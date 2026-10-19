use std::{
    env, fs::{self, File, OpenOptions}, io::{Read, Write},
    net::{TcpStream, ToSocketAddrs}, path::{Path, PathBuf}, process::{Child, Command, Stdio},
    sync::{Arc, Mutex}, thread, time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub struct OwnedServer { child: Child }

fn log_path() -> Result<PathBuf, String> {
    #[cfg(target_os = "windows")]
    let base = env::var_os("LOCALAPPDATA").map(PathBuf::from).or_else(dirs::data_local_dir);
    #[cfg(not(target_os = "windows"))]
    let base = dirs::data_local_dir();
    base.map(|p| p.join("dibi-aether").join("server.log")).ok_or("Could not determine the AETHER log directory".into())
}

fn log(message: &str) {
    if let Ok(path) = log_path() {
        if let Some(parent) = path.parent() { let _ = fs::create_dir_all(parent); }
        if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
            let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
            let _ = writeln!(f, "[{stamp}] {message}");
        }
    }
}

pub fn record_failure(message: &str) { log(&format!("Startup failure: {message}")); }

fn valid_root(path: &Path) -> bool {
    let package = fs::read_to_string(path.join("package.json")).unwrap_or_default();
    (package.contains("\"name\": \"opendots\"") || package.contains("\"name\":\"opendots\""))
        && (path.join("src/server/index.ts").is_file() || path.join("dist/server/server/index.js").is_file())
}

fn resolve_root() -> Result<PathBuf, String> {
    if let Some(root) = env::var_os("OPENDOTS_ROOT") {
        let p = PathBuf::from(root);
        if valid_root(&p) { return Ok(p); }
        return Err(format!("OPENDOTS_ROOT does not contain the OpenDots package.json: {}", p.display()));
    }
    let mut candidates = Vec::new();
    if let Ok(cwd) = env::current_dir() { candidates.extend(cwd.ancestors().map(Path::to_path_buf)); }
    if let Ok(exe) = env::current_exe() { candidates.extend(exe.ancestors().map(Path::to_path_buf)); }
    for candidate in candidates {
        if valid_root(&candidate) { return Ok(candidate); }
        let app = candidate.join("AETHER-web");
        if valid_root(&app) { return Ok(app); }
    }
    Err("Could not find the OpenDots project. Set OPENDOTS_ROOT to the app directory containing package.json.".into())
}

pub fn owner_token() -> Option<String> {
    if let Ok(token) = env::var("OWNER_TOKEN") {
        if !token.is_empty() { return Some(token); }
    }
    let root = resolve_root().ok()?;
    let contents = fs::read_to_string(root.join(".env")).ok()?;
    for raw_line in contents.lines() {
        let line = raw_line.trim();
        if line.starts_with('#') { continue; }
        let Some((key, raw_value)) = line.split_once('=') else { continue };
        if key.trim() != "OWNER_TOKEN" { continue; }
        let value = raw_value.trim();
        let value = if value.len() >= 2
            && ((value.starts_with('"') && value.ends_with('"'))
                || (value.starts_with('\'') && value.ends_with('\''))) {
            &value[1..value.len() - 1]
        } else {
            value
        };
        if !value.is_empty() { return Some(value.to_string()); }
    }
    None
}

fn ready(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("http://") else { return false };
    let authority = rest.split('/').next().unwrap_or("");
    let addr = if authority.contains(':') { authority.to_string() } else { format!("{authority}:80") };
    let Ok(mut stream) = addr.to_socket_addrs().ok().and_then(|mut a| a.next()).ok_or(())
        .and_then(|a| TcpStream::connect_timeout(&a, Duration::from_millis(500)).map_err(|_| ())) else { return false };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(600)));
    let path = format!("/{}", rest.split_once('/').map(|(_, p)| p).unwrap_or(""));
    if write!(stream, "GET {path} HTTP/1.0\r\nHost: {authority}\r\nConnection: close\r\n\r\n").is_err() { return false; }
    let mut response = [0u8; 32];
    stream.read(&mut response).map(|n| n > 0 && String::from_utf8_lossy(&response[..n]).split_whitespace().nth(1).and_then(|s| s.parse::<u16>().ok()).is_some_and(|s| s < 500)).unwrap_or(false)
}

fn stream_output<R: Read + Send + 'static>(mut input: R, label: &'static str, log_file: Arc<Mutex<File>>) {
    thread::spawn(move || {
        let mut buf = [0u8; 2048];
        loop { match input.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => { let text = String::from_utf8_lossy(&buf[..n]); if let Ok(mut f) = log_file.lock() { let _ = writeln!(f, "[{label}] {text}"); } }
        }}
    });
}

pub fn launch() -> Result<(String, Option<OwnedServer>), String> {
    let attach = env::var("AETHER_URL").or_else(|_| env::var("OPENDOTS_URL")).ok();
    let port = env::var("AETHER_PORT").or_else(|_| env::var("PORT")).unwrap_or_else(|_| "4310".into());
    let url = attach.unwrap_or_else(|| format!("http://127.0.0.1:{port}/"));
    if !url.starts_with("http://") { return Err("AETHER_URL must use http:// for local server health checks".into()); }
    if env::var("AETHER_URL").is_ok() || env::var("OPENDOTS_URL").is_ok() {
        log(&format!("Attaching to the OpenDots API at {url}"));
        return wait_for(url, None);
    }
    let root = resolve_root()?;
    let entry = root.join("dist/server/server/index.js");
    if !entry.is_file() || !root.join("node_modules").is_dir() { return Err(format!("OpenDots is not built in {}. Run npm ci and npm run build.", root.display())); }
    let path = log_path()?;
    if let Some(parent) = path.parent() { fs::create_dir_all(parent).map_err(|e| format!("Could not create log directory: {e}"))?; }
    let file = OpenOptions::new().create(true).append(true).open(path).map_err(|e| format!("Could not open AETHER log: {e}"))?;
    log(&format!("Starting OpenDots from {} on port {port}", root.display()));
    let mut command = Command::new("node");
    command.args(["--env-file-if-exists=.env", "dist/server/server/index.js"]).current_dir(&root)
        .env("HOST", "127.0.0.1").env("PORT", &port).stdout(Stdio::piped()).stderr(Stdio::piped());
    if let Ok(token) = env::var("OWNER_TOKEN") { command.env("OWNER_TOKEN", token); }
    let mut child = command.spawn().map_err(|e| format!("Could not start Node.js: {e}. Confirm node is on PATH.").tap_log())?;
    let shared = Arc::new(Mutex::new(file));
    if let Some(out) = child.stdout.take() { stream_output(out, "stdout", shared.clone()); }
    if let Some(err) = child.stderr.take() { stream_output(err, "stderr", shared); }
    wait_for(url, Some(OwnedServer { child }))
}

trait LogError { fn tap_log(self) -> Self; }
impl LogError for String { fn tap_log(self) -> Self { log(&self); self } }

fn wait_for(url: String, mut owned: Option<OwnedServer>) -> Result<(String, Option<OwnedServer>), String> {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if ready(&url) { log(&format!("Server ready at {url}")); return Ok((url, owned)); }
        if let Some(server) = owned.as_mut() {
            if let Ok(Some(status)) = server.child.try_wait() { return Err(format!("OpenDots server exited during startup ({status}). See the AETHER server log.")); }
        }
        thread::sleep(Duration::from_millis(250));
    }
    stop(&mut owned);
    Err(format!("Timed out waiting for OpenDots at {url}. See the AETHER server log."))
}

pub fn stop(server: &mut Option<OwnedServer>) {
    if let Some(s) = server.as_mut() {
        let _ = s.child.kill();
        let _ = s.child.wait();
        log("Stopped the OpenDots child process");
    }
    *server = None;
}

pub fn check_exit(server: &mut Option<OwnedServer>) -> Option<String> {
    let child = &mut server.as_mut()?.child;
    match child.try_wait() {
        Ok(Some(status)) => {
            let message = format!("The OpenDots server exited unexpectedly ({status}). See the AETHER server log.");
            log(&message);
            server.take();
            Some(message)
        }
        Err(error) => { let message = format!("Could not monitor the OpenDots server: {error}"); log(&message); server.take(); Some(message) }
        Ok(None) => None,
    }
}

