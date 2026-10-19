#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;

use eframe::egui;
use serde_json::{json, Value};
use std::{io::{BufRead, BufReader}, sync::{mpsc::{self, Receiver, Sender}, Arc, Mutex}, thread, time::{Duration, Instant, SystemTime, UNIX_EPOCH}};

#[derive(Clone, Copy, PartialEq)]
enum Screen { Home, Dots, Conversations, Spaces, Activity, Memories, Settings, Computer }

struct NativeApp {
    base: String,
    token: Option<String>,
    tx: Sender<(String, Result<Value, String>)>,
    rx: Receiver<(String, Result<Value, String>)>,
    data: Value,
    workspace: Value,
    pages: Value,
    selected_space: String,
    selected_page: String,
    selected_thread: String,
    selected_dot: String,
    screen: Screen,
    error: Option<String>,
    server_error: Option<String>,
    last_refresh: Instant,
    space_name: String,
    space_description: String,
    page_title: String,
    page_content: String,
    page_revision: i64,
    task_prompt: String,
    task_interval: String,
    conversation_title: String,
    chat_draft: String,
    chat_messages: Vec<(String, String)>,
    chat_thread: String,
    chat_busy: bool,
    memory_text: String,
    settings_name: String,
    settings: Value,
    dot_name: String,
    dot_instructions: String,
    dot_space: String,
    dot_research: bool,
    dot_memory: bool,
    dot_apps: bool,
    connections: Value,
    computer: Value,
    connection_name: String,
    connection_url: String,
    connection_token: String,
    computer_url: String,
    computer_text: String,
    computer_path: String,
    computer_command: String,
    selected_memory: String,
    task_search: String,
    selected_task: Value,
    page_dot: String,
    server: Arc<Mutex<Option<server::OwnedServer>>>,
}

fn api_call(base: String, token: Option<String>, method: &str, path: &str, body: Option<Value>) -> Result<Value, String> {
    let client = reqwest::blocking::Client::builder().timeout(Duration::from_secs(45)).build().map_err(|e| e.to_string())?;
    let mut request = match method { "POST" => client.post(format!("{base}/api{path}")), "PATCH" => client.patch(format!("{base}/api{path}")), "PUT" => client.put(format!("{base}/api{path}")), "DELETE" => client.delete(format!("{base}/api{path}")), _ => client.get(format!("{base}/api{path}")) };
    if let Some(token) = token { request = request.bearer_auth(token); }
    if let Some(body) = body { request = request.json(&body); }
    let response = request.send().map_err(|e| format!("Network request failed: {e}"))?;
    let status = response.status();
    let value: Value = response.json().unwrap_or_else(|_| json!({}));
    if !status.is_success() { return Err(value["error"].as_str().unwrap_or("Request failed").to_owned()); }
    Ok(value)
}

impl NativeApp {
    fn new(url: String, server: Option<server::OwnedServer>) -> Self {
        let (tx, rx) = mpsc::channel();
        let app = Self {
            base: url.trim_end_matches('/').to_owned(), token: server::owner_token(), tx, rx,
            data: json!({}), workspace: json!({}), pages: json!([]), selected_space: String::new(), selected_page: String::new(), selected_thread: String::new(), selected_dot: String::new(), screen: Screen::Home, error: None, server_error: None, last_refresh: Instant::now(),
            space_name: String::new(), space_description: String::new(), page_title: String::new(), page_content: String::new(), page_revision: 1, task_prompt: String::new(), task_interval: "86400".into(), conversation_title: "A new thought".into(), chat_draft: String::new(), chat_messages: Vec::new(), chat_thread: String::new(), chat_busy: false, memory_text: String::new(), settings_name: String::new(), settings: json!({}), dot_name: String::new(), dot_instructions: String::new(), dot_space: String::new(), dot_research: true, dot_memory: true, dot_apps: false, connections: json!([]), computer: json!({}), connection_name: String::new(), connection_url: String::new(), connection_token: String::new(), computer_url: String::new(), computer_text: String::new(), computer_path: String::new(), computer_command: String::new(), selected_memory: String::new(), task_search: String::new(), selected_task: Value::Null, page_dot: String::new(), server: Arc::new(Mutex::new(server)),
        };
        app.request("refresh", "GET", "/state", None);
        app.request("workspace", "GET", "/workspace", None);
        app
    }

    fn request(&self, tag: &str, method: &str, path: &str, body: Option<Value>) {
        let tx = self.tx.clone(); let base = self.base.clone(); let token = self.token.clone(); let tag = tag.to_owned(); let method = method.to_owned(); let path = path.to_owned();
        thread::spawn(move || { let result = api_call(base, token, &method, &path, body); let _ = tx.send((tag, result)); });
    }

    fn refresh(&self) { self.request("refresh", "GET", "/state", None); self.request("workspace", "GET", "/workspace", None); }

    fn refresh_pages(&self) {
        if !self.selected_space.is_empty() { self.request("pages", "GET", &format!("/spaces/{}/pages", self.selected_space), None); }
    }

    fn refresh_dot_tools(&self) {
        if !self.selected_dot.is_empty() {
            self.request("connections", "GET", &format!("/dots/{}/connections", self.selected_dot), None);
            self.request("computer", "GET", &format!("/dots/{}/computer", self.selected_dot), None);
        }
    }

    fn poll(&mut self) {
        while let Ok((tag, result)) = self.rx.try_recv() {
            match result {
                Ok(value) => {
                    self.error = None;
                    match tag.as_str() {
                        "refresh" => { self.settings = value["settings"].clone(); self.settings_name = self.settings["name"].as_str().unwrap_or("").to_owned(); self.data = value; }
                        "workspace" => {
                            self.workspace = value;
                            if self.workspace["spaces"].as_array().into_iter().flatten().all(|space| space["id"].as_str() != Some(&self.selected_space)) {
                                self.selected_space = self.workspace["spaces"][0]["id"].as_str().unwrap_or("").to_owned();
                                self.selected_page.clear();
                            }
                            if self.workspace["conversations"].as_array().into_iter().flatten().all(|thread| thread["id"].as_str() != Some(&self.selected_thread)) {
                                self.selected_thread = self.workspace["conversations"][0]["id"].as_str().unwrap_or("").to_owned();
                            }
                            self.refresh_pages();
                            self.refresh_dot_tools();
                        }
                        "connections" => self.connections = value,
                        "computer" => self.computer = value,
                        "connection-added" => { self.connection_name.clear(); self.connection_url.clear(); self.connection_token.clear(); self.refresh_dot_tools(); }
                        "memory-saved" => { self.selected_memory.clear(); self.memory_text.clear(); self.refresh(); }
                        "task-detail" => self.selected_task = value,
                        "pages" => self.pages = value,
                        "page-read" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_title = value["title"].as_str().unwrap_or("").to_owned(); self.page_content = value["content"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(1); }
                        "capture" => self.data["capture"] = value,
                        "page-saved" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(self.page_revision); self.refresh_pages(); }
                        "page-deleted" => { self.selected_page.clear(); self.page_title.clear(); self.page_content.clear(); self.page_revision = 1; self.refresh_pages(); }
                        "conversation-created" => { self.selected_thread = value["id"].as_str().unwrap_or("").to_owned(); self.chat_thread = self.selected_thread.clone(); self.chat_messages.clear(); self.data["capture"] = Value::Null; self.refresh(); }
                        "chat-delta" => { if self.chat_thread == value["threadId"].as_str().unwrap_or("") { if let (Some((role, text)), Some(delta)) = (self.chat_messages.last_mut(), value["delta"].as_str()) { if role == "assistant" { text.push_str(delta); } } } }
                        "chat-done" => self.chat_busy = false,
                        "dot-saved" => { self.selected_dot = value["id"].as_str().unwrap_or("").to_owned(); self.refresh(); }
                        "mutation" => { self.refresh(); if !self.selected_dot.is_empty() { self.refresh_dot_tools(); } },
                        _ => {}
                    }
                }
                Err(message) => { if tag.starts_with("chat-") { self.chat_busy = false; } self.error = Some(message); }
            }
        }
        if self.last_refresh.elapsed() > Duration::from_secs(8) { self.refresh(); self.last_refresh = Instant::now(); }
        if let Ok(mut child) = self.server.lock() { if let Some(message) = server::check_exit(&mut child) { self.server_error = Some(message); } }
    }

    fn mutate(&self, method: &str, path: &str, body: Option<Value>) { self.request("mutation", method, path, body); }
    fn heading(ui: &mut egui::Ui, title: &str, subtitle: &str) { ui.heading(title); ui.label(egui::RichText::new(subtitle).color(egui::Color32::from_rgb(104, 112, 124))); ui.add_space(14.0); }
    fn button(ui: &mut egui::Ui, label: &str) -> egui::Response { ui.add_sized([150.0, 34.0], egui::Button::new(label)) }

    fn render_home(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui, "AETHER", "A calm workspace for your ideas, specialists, and scheduled work.");
        ui.horizontal_wrapped(|ui| {
            for (title, value) in [("Spaces", self.workspace["spaces"].as_array().map_or(0, Vec::len)), ("Conversations", self.workspace["conversations"].as_array().map_or(0, Vec::len)), ("Scheduled tasks", self.data["tasks"].as_array().map_or(0, Vec::len)), ("Memories", self.data["memories"].as_array().map_or(0, Vec::len))] {
                egui::Frame::group(ui.style()).show(ui, |ui| { ui.set_min_width(150.0); ui.label(title); ui.heading(value.to_string()); });
            }
        });
        ui.add_space(20.0); ui.heading("Recent activity");
        for call in self.workspace["calls"].as_array().into_iter().flatten().take(8) { ui.label(format!("{} · {} · {}", call["status"].as_str().unwrap_or("call"), call["startedAt"], call["transcript"].as_str().unwrap_or(""))); }
    }

    fn render_dots(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui, "Specialist Dots", "Set each specialist’s role and workspace permissions.");
        ui.columns(2, |cols| {
            cols[0].horizontal(|ui| {
                if ui.button("New Dot").clicked() {
                    self.selected_dot.clear(); self.dot_name.clear(); self.dot_instructions.clear();
                    self.dot_space = self.workspace["spaces"][0]["id"].as_str().unwrap_or("").to_owned();
                    self.dot_research = true; self.dot_memory = true; self.dot_apps = false;
                }
            });
            egui::ScrollArea::vertical().show(&mut cols[0], |ui| {
                for dot in self.workspace["dots"].as_array().into_iter().flatten() {
                    let id = dot["id"].as_str().unwrap_or("");
                    if ui.selectable_label(self.selected_dot == id, dot["name"].as_str().unwrap_or("Dot")).clicked() {
                        self.selected_dot = id.to_owned();
                        self.dot_name = dot["name"].as_str().unwrap_or("").to_owned();
                        self.dot_instructions = dot["instructions"].as_str().unwrap_or("").to_owned();
                        self.dot_space = dot["spaceId"].as_str().unwrap_or("").to_owned();
                        self.dot_research = dot["researchAllowed"].as_bool().unwrap_or(true);
                        self.dot_memory = dot["memoryAllowed"].as_bool().unwrap_or(true);
                        self.dot_apps = dot["appsAllowed"].as_bool().unwrap_or(false);
                        self.refresh_dot_tools();
                    }
                }
            });
            cols[1].label("Name"); cols[1].text_edit_singleline(&mut self.dot_name);
            cols[1].label("Role instructions"); cols[1].add(egui::TextEdit::multiline(&mut self.dot_instructions).desired_rows(8));
            egui::ComboBox::from_label("Default Space").selected_text(self.workspace["spaces"].as_array().into_iter().flatten().find(|s|s["id"].as_str()==Some(&self.dot_space)).and_then(|s|s["name"].as_str()).unwrap_or("Choose a space")).show_ui(&mut cols[1], |ui| {
                for space in self.workspace["spaces"].as_array().into_iter().flatten() { ui.selectable_value(&mut self.dot_space,space["id"].as_str().unwrap_or("").into(),space["name"].as_str().unwrap_or("Space")); }
            });
            cols[1].checkbox(&mut self.dot_research, "Allow research");
            cols[1].checkbox(&mut self.dot_memory, "Allow memory");
            cols[1].checkbox(&mut self.dot_apps, "Allow connected apps");
            let can_save = !self.dot_name.trim().is_empty() && self.dot_instructions.trim().len() >= 3 && !self.dot_space.is_empty();
            let label = if self.selected_dot.is_empty() { "Create Dot" } else { "Save Dot" };
            if cols[1].add_enabled(can_save, egui::Button::new(label)).clicked() {
                let body = json!({"name":self.dot_name,"instructions":self.dot_instructions,"researchAllowed":self.dot_research,"memoryAllowed":self.dot_memory,"appsAllowed":self.dot_apps,"composioToolkits":[],"spaceId":self.dot_space,"spaceIds":[self.dot_space]});
                if self.selected_dot.is_empty() { self.request("dot-saved","POST","/dots",Some(body)); }
                else { self.request("dot-saved","PUT",&format!("/dots/{}",self.selected_dot),Some(body)); }
            }
            cols[1].separator();
            cols[1].heading("Connected services");
            cols[1].label("Connect an MCP server. Tokens are stored by the server.");
            cols[1].horizontal(|ui| { ui.text_edit_singleline(&mut self.connection_name).hint_text("Name"); ui.text_edit_singleline(&mut self.connection_url).hint_text("https://…"); });
            cols[1].horizontal(|ui| { ui.add(egui::TextEdit::singleline(&mut self.connection_token).password(true).hint_text("Optional token")); if ui.add_enabled(!self.selected_dot.is_empty() && !self.connection_name.trim().is_empty() && !self.connection_url.trim().is_empty(),egui::Button::new("Connect")).clicked() { self.request("connection-added","POST",&format!("/dots/{}/connections",self.selected_dot),Some(json!({"name":self.connection_name,"url":self.connection_url,"token":self.connection_token}))); } });
            for connection in self.connections.as_array().into_iter().flatten() {
                cols[1].horizontal(|ui| { ui.strong(connection["name"].as_str().unwrap_or("Connection")); if ui.button("Refresh tools").clicked() { self.request("connections","POST",&format!("/connections/{}/refresh",connection["id"].as_str().unwrap_or("")),Some(json!({}))); } if ui.button("Remove").clicked() { self.mutate("DELETE",&format!("/connections/{}",connection["id"].as_str().unwrap_or("")),None); } });
                if let Some(message)=connection["error"].as_str() { cols[1].colored_label(egui::Color32::DARK_RED,message); }
                for tool in connection["tools"].as_array().into_iter().flatten() {
                    cols[1].horizontal(|ui| { ui.label(format!("{}{}",tool["title"].as_str().unwrap_or("Tool"),if tool["readOnly"].as_bool().unwrap_or(false){" · read-only"}else{""})); let mut enabled=tool["enabled"].as_bool().unwrap_or(false); if ui.checkbox(&mut enabled,"Enabled").changed() { self.request("connections","PATCH",&format!("/connections/{}/tools/{}",connection["id"].as_str().unwrap_or(""),tool["name"].as_str().unwrap_or("")),Some(json!({"enabled":enabled}))); } let mut approval=tool["requiresApproval"].as_bool().unwrap_or(false); if ui.add_enabled(enabled,egui::Checkbox::new(&mut approval,"Ask first")).changed() { self.request("connections","PATCH",&format!("/connections/{}/tools/{}",connection["id"].as_str().unwrap_or(""),tool["name"].as_str().unwrap_or("")),Some(json!({"requiresApproval":approval}))); } });
                }
            }
            cols[1].separator(); cols[1].heading("Computer");
            cols[1].label(format!("{} · {}",self.computer["state"].as_str().unwrap_or("Loading status"),if self.computer["configured"].as_bool().unwrap_or(false){"configured"}else{"not configured"}));
            cols[1].horizontal(|ui| { if ui.button("Refresh status").clicked(){self.refresh_dot_tools();} if ui.add_enabled(self.computer["configured"].as_bool().unwrap_or(false),egui::Button::new("Start")).clicked(){self.mutate("POST",&format!("/dots/{}/computer/start",self.selected_dot),Some(json!({})));} if ui.button("Stop").clicked(){self.mutate("POST",&format!("/dots/{}/computer/stop",self.selected_dot),Some(json!({})));} if ui.button("Take control").clicked(){self.mutate("POST",&format!("/dots/{}/computer/take",self.selected_dot),Some(json!({})));} if ui.button("Release control").clicked(){self.mutate("POST",&format!("/dots/{}/computer/release",self.selected_dot),Some(json!({})));} });
            ui_computer_actions(self, &mut cols[1]);
        });
    }

    fn render_conversations(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui, "Conversations", "Start a thought with one of your workspace specialists.");
        ui.horizontal(|ui| {
            egui::ComboBox::from_label("Specialist").selected_text(self.workspace["dots"].as_array().into_iter().flatten().find(|d|d["id"].as_str()==Some(&self.selected_dot)).and_then(|d|d["name"].as_str()).unwrap_or("Choose a Dot")).show_ui(ui, |ui| { for dot in self.workspace["dots"].as_array().into_iter().flatten() { ui.selectable_value(&mut self.selected_dot,dot["id"].as_str().unwrap_or("").into(),dot["name"].as_str().unwrap_or("Specialist")); } });
            ui.text_edit_singleline(&mut self.conversation_title);
            if ui.add_enabled(!self.selected_dot.is_empty(), egui::Button::new("Create conversation")).clicked() {
                self.request("conversation-created", "POST", "/conversations", Some(json!({"dotId":self.selected_dot,"title":self.conversation_title})));
            }
        });
        ui.add_space(12.0);
        for thread in self.workspace["conversations"].as_array().into_iter().flatten() {
            let id = thread["id"].as_str().unwrap_or("");
            if ui.selectable_label(self.selected_thread == id, format!("{}  ·  {}", thread["title"].as_str().unwrap_or("Conversation"), id)).clicked() { self.selected_thread = id.to_owned(); self.chat_thread = id.to_owned(); self.chat_messages.clear(); self.data["capture"] = Value::Null; self.request("capture", "GET", &format!("/conversations/{id}/capture"), None); }
        }
        if !self.data["capture"].is_null() { ui.separator(); ui.heading("Captured result"); ui.label(self.data["capture"].to_string()); }
        for call in self.workspace["calls"].as_array().into_iter().flatten() { ui.label(format!("Call {} — {}", call["status"], call["transcript"].as_str().unwrap_or(""))); }
        if !self.selected_thread.is_empty() {
            ui.separator();
            ui.heading("Chat");
            egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
                for (role, text) in &self.chat_messages {
                    ui.horizontal_wrapped(|ui| {
                        ui.label(egui::RichText::new(if role == "assistant" { "AETHER" } else { "You" }).strong());
                        ui.label(text);
                    });
                    ui.add_space(8.0);
                }
            });
            ui.add(egui::TextEdit::multiline(&mut self.chat_draft).desired_rows(2).hint_text("Message your Dot…"));
            if ui.add_enabled(!self.chat_busy && !self.chat_draft.trim().is_empty(), egui::Button::new(if self.chat_busy { "Thinking…" } else { "Send" })).clicked() { self.send_chat(); }
        }
    }

    fn send_chat(&mut self) {
        let text = self.chat_draft.trim().to_owned();
        if text.is_empty() || self.chat_busy { return; }
        let Some(dot_id) = self.workspace["conversations"].as_array().into_iter().flatten()
            .find(|thread| thread["id"].as_str() == Some(&self.selected_thread))
            .and_then(|thread| thread["dotId"].as_str()).map(str::to_owned) else {
                self.error = Some("The selected conversation has no specialist Dot.".into());
                return;
            };
        let thread_id = self.selected_thread.clone();
        let tx = self.tx.clone();
        let base = self.base.clone();
        let token = self.token.clone();
        self.chat_draft.clear();
        self.chat_messages.push(("user".into(), text));
        self.chat_messages.push(("assistant".into(), String::new()));
        self.chat_thread = thread_id.clone();
        self.chat_busy = true;
        self.error = None;
        let messages = self.chat_messages.iter().take(self.chat_messages.len().saturating_sub(1)).enumerate()
            .map(|(index, (role, content))| json!({"id":format!("aether-{index}"),"role":role,"content":content})).collect::<Vec<_>>();
        thread::spawn(move || {
            let result = (|| -> Result<(), String> {
                let client = reqwest::blocking::Client::builder().timeout(Duration::from_secs(300)).build().map_err(|e| e.to_string())?;
                let url = format!("{base}/api/copilotkit/agent/{dot_id}/run");
                let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
                let mut request = client.post(url).header("Accept", "text/event-stream");
                if let Some(token) = token { request = request.bearer_auth(token); }
                let response = request.json(&json!({"threadId":thread_id.clone(),"runId":format!("aether-{now}"),"state":Value::Null,"messages":messages,"tools":[],"context":[],"forwardedProps":{}}))
                    .send().map_err(|e| format!("Chat request failed: {e}"))?;
                let status = response.status();
                if !status.is_success() {
                    let body = response.json::<Value>().unwrap_or_else(|_| json!({}));
                    return Err(body["error"].as_str().unwrap_or("The assistant run failed.").to_owned());
                }
                let mut reader = BufReader::new(response);
                let mut line = String::new();
                let mut event_type = String::new();
                let mut payload = String::new();
                let mut got_text = false;
                loop {
                    line.clear();
                    if reader.read_line(&mut line).map_err(|e| e.to_string())? == 0 { break; }
                    let line = line.trim_end_matches(&['\r', '\n'][..]);
                    if let Some(value) = line.strip_prefix("event:") { event_type = value.trim().to_owned(); }
                    else if let Some(value) = line.strip_prefix("data:") { if !payload.is_empty() { payload.push('\n'); } payload.push_str(value.trim_start()); }
                    else if line.is_empty() && !payload.is_empty() {
                        if let Ok(event) = serde_json::from_str::<Value>(&payload) {
                            let kind = event["type"].as_str().unwrap_or(&event_type);
                            if kind.contains("RUN_ERROR") || kind.contains("RUN_FAILED") || kind.contains("run_error") {
                                return Err(event["message"].as_str().unwrap_or("The assistant run failed.").to_owned());
                            }
                            if kind.contains("TEXT_MESSAGE_CONTENT") || kind.contains("text_message_content") {
                                if let Some(delta) = event["delta"].as_str().or_else(|| event["content"].as_str()) {
                                    got_text |= !delta.is_empty();
                                    let _ = tx.send(("chat-delta".into(), Ok(json!({"threadId":thread_id.clone(),"delta":delta}))));
                                }
                            }
                        }
                        event_type.clear(); payload.clear();
                    }
                }
                if !got_text { return Err("The run ended without a text response.".into()); }
                Ok(())
            })();
            match result {
                Ok(()) => { let _ = tx.send(("chat-done".into(), Ok(json!({})))); }
                Err(message) => { let _ = tx.send(("chat-error".into(), Err(message))); }
            }
        });
    }

    fn render_spaces(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui, "Spaces & Pages", "Organize notes and working documents in shared spaces.");
        ui.horizontal(|ui| { ui.text_edit_singleline(&mut self.space_name); ui.text_edit_singleline(&mut self.space_description); if Self::button(ui, "Create space").clicked() { self.mutate("POST", "/spaces", Some(json!({"name":self.space_name,"description":self.space_description}))); self.space_name.clear(); } });
        ui.horizontal(|ui| {
            egui::ComboBox::from_label("Space").selected_text(self.workspace["spaces"].as_array().into_iter().flatten().find(|s| s["id"].as_str()==Some(&self.selected_space)).and_then(|s|s["name"].as_str()).unwrap_or("Choose a space")).show_ui(ui, |ui| {
                for space in self.workspace["spaces"].as_array().into_iter().flatten() { let id=space["id"].as_str().unwrap_or(""); if ui.selectable_value(&mut self.selected_space,id.to_owned(),space["name"].as_str().unwrap_or("Space")).clicked() { self.selected_page.clear(); self.refresh_pages(); } }
            });
            if Self::button(ui,"New page").clicked() { self.selected_page.clear(); self.page_title.clear(); self.page_content.clear(); self.page_revision=1; }
        });
        ui.columns(2, |cols| {
            egui::ScrollArea::vertical().show(&mut cols[0], |ui| { for page in self.pages.as_array().into_iter().flatten() { let id=page["id"].as_str().unwrap_or(""); if ui.selectable_label(self.selected_page==id,page["title"].as_str().unwrap_or("Untitled")).clicked() { self.request("page-read","GET",&format!("/spaces/{}/pages/{id}",self.selected_space),None); } } });
            cols[1].label("Title"); cols[1].text_edit_singleline(&mut self.page_title); cols[1].label("Markdown"); cols[1].add(egui::TextEdit::multiline(&mut self.page_content).desired_rows(18).desired_width(f32::INFINITY));
            cols[1].horizontal(|ui| {
                if ui.add_enabled(!self.selected_space.is_empty() && !self.page_title.trim().is_empty(), egui::Button::new("Save page")).clicked() { let (method,path,body)=if self.selected_page.is_empty() { ("POST",format!("/spaces/{}/pages",self.selected_space),json!({"title":self.page_title,"content":self.page_content})) } else { ("PATCH",format!("/spaces/{}/pages/{}",self.selected_space,self.selected_page),json!({"title":self.page_title,"content":self.page_content,"expectedRevision":self.page_revision})) }; self.request("page-saved",method,&path,Some(body)); }
                if !self.selected_page.is_empty() && ui.button("Delete page").clicked() { self.request("page-deleted","DELETE",&format!("/spaces/{}/pages/{}",self.selected_space,self.selected_page),None); }
            });
        });
    }

    fn render_activity(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui,"Scheduled & Activity","Review scheduled research and recent results.");
        ui.label("New scheduled task"); ui.add(egui::TextEdit::multiline(&mut self.task_prompt).desired_rows(3));
        ui.horizontal(|ui| {
            egui::ComboBox::from_label("Conversation").selected_text(self.workspace["conversations"].as_array().into_iter().flatten().find(|c|c["id"].as_str()==Some(&self.selected_thread)).and_then(|c|c["title"].as_str()).unwrap_or("Select conversation")).show_ui(ui,|ui| { for c in self.workspace["conversations"].as_array().into_iter().flatten() { if ui.selectable_value(&mut self.selected_thread,c["id"].as_str().unwrap_or("").into(),c["title"].as_str().unwrap_or("Conversation")).clicked() {} } });
            ui.label("Repeat seconds (blank for once)"); ui.text_edit_singleline(&mut self.task_interval);
            let can_create = !self.selected_thread.is_empty() && self.task_prompt.trim().len() >= 3;
            if ui.add_enabled(can_create, egui::Button::new("Create task")).clicked() { let interval=self.task_interval.trim().parse::<i64>().ok(); self.mutate("POST","/tasks",Some(json!({"prompt":self.task_prompt,"intervalSeconds":interval,"threadId":self.selected_thread}))); }
        });
        for task in self.data["tasks"].as_array().into_iter().flatten() { ui.separator(); ui.horizontal(|ui| { ui.vertical(|ui| { ui.label(task["prompt"].as_str().unwrap_or("")); ui.label(format!("{} · {}",task["status"],task["id"])); }); for action in ["run","pause","cancel"] { if ui.button(action).clicked() { self.mutate("POST",&format!("/tasks/{}/actions",task["id"].as_str().unwrap_or("")),Some(json!({"action":action}))); } } }); }
        for call in self.workspace["calls"].as_array().into_iter().flatten() { ui.label(format!("{} · {}",call["status"],call["transcript"].as_str().unwrap_or(""))); }
    }

    fn render_memories(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui,"Memories","Keep useful context available across your workspace."); ui.horizontal(|ui| { ui.text_edit_singleline(&mut self.memory_text); if Self::button(ui,"Save memory").clicked() { self.mutate("POST","/memories",Some(json!({"text":self.memory_text}))); self.memory_text.clear(); } });
        for memory in self.data["memories"].as_array().into_iter().flatten() { ui.horizontal(|ui| { ui.label(memory["text"].as_str().unwrap_or("")); if ui.button("Delete").clicked() { self.mutate("DELETE",&format!("/memories/{}",memory["id"].as_str().unwrap_or("")),None); } }); }
    }

    fn render_settings(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui,"Settings","Set the name and permissions for this workspace."); ui.label("Workspace name"); ui.text_edit_singleline(&mut self.settings_name);
        for key in ["paused","researchAllowed","memoryAllowed","appsAllowed"] { let mut value=self.settings[key].as_bool().unwrap_or(false); let label=match key { "paused"=>"Pause all Dots", "researchAllowed"=>"Allow research", "memoryAllowed"=>"Allow memory", _=>"Allow connected apps" }; if ui.checkbox(&mut value,label).changed() { self.settings[key]=json!(value); self.mutate("PATCH","/settings",Some(json!({key:value}))); } }
        if Self::button(ui,"Save workspace name").clicked() { self.mutate("PATCH","/settings",Some(json!({"name":self.settings_name}))); }
        ui.separator(); ui.label(format!("API mode: {}",self.data["mode"].as_str().unwrap_or("unknown"))); ui.label(format!("Server: {}",self.base));
    }
}

impl eframe::App for NativeApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll();
        let bg=egui::Color32::from_rgb(248,246,241); let blue=egui::Color32::from_rgb(62,105,160);
        let mut style=(*ctx.style()).clone(); style.visuals.window_fill=bg; style.visuals.panel_fill=bg; style.visuals.widgets.active.bg_fill=blue; style.visuals.selection.bg_fill=blue; ctx.set_style(style);
        egui::SidePanel::left("navigation").exact_width(220.0).frame(egui::Frame::side_top_panel(&ctx.style()).fill(egui::Color32::from_rgb(239,236,229))).show(ctx,|ui| {
            ui.add_space(14.0); ui.heading("AETHER"); ui.label("OpenDots workspace"); ui.add_space(24.0);
            for (label,screen) in [("Home",Screen::Home),("Dots",Screen::Dots),("Conversations",Screen::Conversations),("Spaces & Pages",Screen::Spaces),("Scheduled & Activity",Screen::Activity),("Memories",Screen::Memories),("Settings",Screen::Settings)] { if ui.selectable_label(self.screen==screen,label).clicked() { self.screen=screen; } }
            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT),|ui| { ui.label(if self.server_error.is_some(){"Server stopped"}else{"Local server connected"}); });
        });
        egui::CentralPanel::default().show(ctx,|ui| {
            egui::ScrollArea::vertical().show(ui,|ui| {
                if let Some(message)=&self.server_error { ui.colored_label(egui::Color32::DARK_RED,message); }
                if let Some(message)=&self.error { ui.colored_label(egui::Color32::DARK_RED,message); }
                match self.screen { Screen::Home=>self.render_home(ui), Screen::Dots=>self.render_dots(ui), Screen::Conversations=>self.render_conversations(ui), Screen::Spaces=>self.render_spaces(ui), Screen::Activity=>self.render_activity(ui), Screen::Memories=>self.render_memories(ui), Screen::Settings=>self.render_settings(ui) }
            });
        });
        ctx.request_repaint_after(Duration::from_millis(250));
    }
    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) { if let Ok(mut child)=self.server.lock() { server::stop(&mut child); } }
}

fn main() {
    let (url, child, failure) = match server::launch() { Ok((url, child)) => (url, child, None), Err(e) => { server::record_failure(&e); ("http://127.0.0.1:4310".into(), None, Some(e)) } };
    let options=eframe::NativeOptions { viewport:egui::ViewportBuilder::default().with_title("AETHER").with_inner_size([1280.0,840.0]).with_min_inner_size([940.0,620.0]), ..Default::default() };
    let result=eframe::run_native("AETHER",options,Box::new(move |_cc| { let mut app=NativeApp::new(url,child); app.server_error=failure; Ok(Box::new(app)) }));
    if let Err(error)=result { eprintln!("AETHER: could not create native window: {error}"); }
}
