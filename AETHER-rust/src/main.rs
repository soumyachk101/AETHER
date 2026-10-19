#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;

use eframe::egui;
use serde::Deserialize;
use std::{cell::RefCell, rc::Rc, time::{Duration, Instant}};

#[derive(Clone, Deserialize)]
struct Task { id: String, prompt: String, status: String, error: Option<String> }
#[derive(Deserialize)]
struct State { tasks: Vec<Task>, mode: String, configured: bool }
#[derive(Clone, Deserialize)]
struct Dot { id: String, name: String }
#[derive(Clone, Deserialize)]
struct Conversation { id: String, title: String }
#[derive(Deserialize)]
struct Workspace { dots: Vec<Dot>, conversations: Vec<Conversation>, setup: Setup }
#[derive(Deserialize)]
struct Setup { missing: Vec<String> }

struct Client {
    base_url: String,
    token: String,
    prompt: String,
    state: Option<State>,
    workspace: Option<Workspace>,
    selected_thread: Option<String>,
    error: Option<String>,
    startup_error: Option<String>,
    client: reqwest::blocking::Client,
    refresh_at: Instant,
    supervisor: Rc<RefCell<Option<server::OwnedServer>>>,
    next_server_check: Instant,
}

impl Client {
    fn request(&self, path: &str, method: reqwest::Method, body: Option<serde_json::Value>) -> Result<reqwest::blocking::Response, String> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let mut request = self.client.request(method, url);
        if !self.token.is_empty() { request = request.bearer_auth(&self.token); }
        if let Some(json) = body { request = request.json(&json); }
        request.send().map_err(|e| format!("Could not reach OpenDots: {e}"))
    }

    fn refresh(&mut self) {
        self.refresh_at = Instant::now() + Duration::from_secs(4);
        match self.request("/api/state", reqwest::Method::GET, None) {
            Ok(response) if response.status().is_success() => match response.json::<State>() {
                Ok(state) => { self.state = Some(state); self.error = None; }
                Err(e) => self.error = Some(format!("OpenDots returned an unreadable response: {e}")),
            },
            Ok(response) => {
                let status = response.status();
                let detail = response.json::<serde_json::Value>().ok().and_then(|v| v["error"].as_str().map(str::to_owned));
                self.error = Some(detail.unwrap_or_else(|| format!("OpenDots request failed ({status}).")));
            }
            Err(error) => self.error = Some(error),
        }
        match self.request("/api/workspace", reqwest::Method::GET, None) {
            Ok(response) if response.status().is_success() => match response.json::<Workspace>() {
                Ok(workspace) => {
                    if self.selected_thread.as_ref().is_none_or(|id| !workspace.conversations.iter().any(|c| &c.id == id)) {
                        self.selected_thread = workspace.conversations.first().map(|c| c.id.clone());
                    }
                    self.workspace = Some(workspace);
                }
                Err(e) => self.error = Some(format!("OpenDots returned an unreadable workspace response: {e}")),
            },
            Ok(response) => self.error = Some(format!("Could not load workspace ({}).", response.status())),
            Err(error) => self.error = Some(error),
        }
    }

    fn action(&mut self, path: &str, body: serde_json::Value) {
        match self.request(path, reqwest::Method::POST, Some(body)) {
            Ok(response) if response.status().is_success() => { self.error = None; self.refresh(); }
            Ok(response) => {
                let status = response.status();
                self.error = Some(response.json::<serde_json::Value>().ok().and_then(|v| v["error"].as_str().map(str::to_owned)).unwrap_or_else(|| format!("OpenDots request failed ({status}).")));
            }
            Err(error) => self.error = Some(error),
        }
    }
}

impl eframe::App for Client {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if Instant::now() >= self.next_server_check {
            self.next_server_check = Instant::now() + Duration::from_secs(1);
            if let Some(message) = server::check_exit(&mut self.supervisor.borrow_mut()) { self.error = Some(message); }
        }
        if self.state.is_none() && self.startup_error.is_none() || Instant::now() >= self.refresh_at {
            self.refresh();
        }
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("OpenDots");
            ui.label("Your local workspace");
            ui.separator();
            if let Some(message) = &self.startup_error {
                ui.colored_label(egui::Color32::LIGHT_RED, format!("Could not start OpenDots: {message}"));
                ui.label("Check the AETHER server log and confirm Node.js and the built app are available.");
                return;
            }
            ui.horizontal(|ui| {
                ui.label("Server");
                ui.monospace(&self.base_url);
                if ui.button("Refresh").clicked() { self.refresh(); }
            });
            if let Some(message) = &self.error {
                ui.colored_label(egui::Color32::LIGHT_RED, message);
            }
            if self.state.is_none() {
                ui.add_space(20.0);
                ui.spinner();
                ui.label("Connecting to OpenDots…");
                ui.label("Owner token");
                ui.add(egui::TextEdit::singleline(&mut self.token).password(true).hint_text("Paste your owner access token"));
                if ui.button("Connect").clicked() { self.refresh(); }
                ctx.request_repaint_after(Duration::from_millis(250));
                return;
            }
            let state = self.state.as_ref().unwrap();
            ui.label(format!("Mode: {} · {}", state.mode, if state.configured { "configured" } else { "setup needed" }));
            ui.add_space(12.0);
            ui.heading("New task");
            if let Some(workspace) = self.workspace.clone() {
                if workspace.setup.missing.is_empty() && !workspace.conversations.is_empty() {
                    let selected = self.selected_thread.clone().unwrap_or_default();
                    egui::ComboBox::from_label("Conversation").selected_text(workspace.conversations.iter().find(|c| c.id == selected).map(|c| c.title.as_str()).unwrap_or("Choose a conversation")).show_ui(ui, |ui| {
                        for conversation in &workspace.conversations {
                            ui.selectable_value(&mut self.selected_thread, Some(conversation.id.clone()), &conversation.title);
                        }
                    });
                } else if workspace.setup.missing.is_empty() {
                    ui.label("Create a conversation to enable scheduled tasks.");
                    if let Some(dot) = workspace.dots.first() {
                        if ui.button(format!("Create conversation with {}", dot.name)).clicked() {
                            self.action("/api/conversations", serde_json::json!({"dotId": dot.id, "title":"A new thought"}));
                        }
                    }
                } else {
                    ui.label(format!("Setup required: {}", workspace.setup.missing.join(", ")));
                }
            }
            ui.add(egui::TextEdit::multiline(&mut self.prompt).desired_rows(3).hint_text("What should OpenDots work on?"));
            let can_create = self.state.as_ref().is_some_and(|s| s.configured) && self.selected_thread.is_some();
            if ui.add_enabled(can_create && self.prompt.trim().len() >= 3, egui::Button::new("Create task")).clicked() {
                let prompt = self.prompt.trim().to_owned();
                self.action("/api/tasks", serde_json::json!({"prompt": prompt, "threadId": self.selected_thread}));
                if self.error.is_none() { self.prompt.clear(); }
            }
            if !can_create { ui.small("Complete OpenDots setup before creating tasks."); }
            ui.add_space(16.0);
            ui.heading("Tasks");
            egui::ScrollArea::vertical().show(ui, |ui| {
                let tasks = self.state.as_ref().map(|s| s.tasks.clone()).unwrap_or_default();
                if tasks.is_empty() { ui.label("No tasks yet."); }
                for task in tasks {
                    ui.group(|ui| {
                        ui.strong(&task.prompt);
                        ui.label(format!("{} · {}", task.status, task.id));
                        if let Some(error) = task.error.as_deref() { ui.colored_label(egui::Color32::LIGHT_RED, error); }
                        ui.horizontal(|ui| {
                            if ui.button("Run").clicked() { self.action(&format!("/api/tasks/{}/actions", task.id), serde_json::json!({"action":"run"})); }
                            if ui.button("Pause").clicked() { self.action(&format!("/api/tasks/{}/actions", task.id), serde_json::json!({"action":"pause"})); }
                            if ui.button("Cancel").clicked() { self.action(&format!("/api/tasks/{}/actions", task.id), serde_json::json!({"action":"cancel"})); }
                        });
                    });
                }
            });
            ctx.request_repaint_after(Duration::from_millis(500));
        });
    }
}

fn main() {
    let (url, supervisor, failure) = match server::launch() {
        Ok((url, child)) => (url, child, None),
        Err(e) => { server::record_failure(&e); ("http://127.0.0.1:4310".to_owned(), None, Some(e)) }
    };
    let options = eframe::NativeOptions { viewport: egui::ViewportBuilder::default().with_title("OpenDots").with_inner_size([1000.0, 760.0]).with_min_inner_size([700.0, 520.0]), ..Default::default() };
    let supervisor = Rc::new(RefCell::new(supervisor));
    let app_supervisor = supervisor.clone();
    let result = eframe::run_native("OpenDots", options, Box::new(move |_cc| Ok(Box::new(Client {
        base_url: url, token: server::owner_token().unwrap_or_default(), prompt: String::new(), state: None,
        error: None, startup_error: failure, workspace: None, selected_thread: None, client: reqwest::blocking::Client::new(), refresh_at: Instant::now(),
        supervisor: app_supervisor, next_server_check: Instant::now(),
    }))));
    if let Err(e) = result { server::record_failure(&format!("Native UI startup failed: {e}")); eprintln!("AETHER: native UI startup failed: {e}"); }
    server::stop(&mut supervisor.borrow_mut());
}
