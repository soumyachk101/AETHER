#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;
mod voice;

use eframe::egui;
use serde_json::{json, Value};
use std::{collections::HashMap, io::{BufRead, BufReader}, sync::{mpsc::{self, Receiver, Sender}, Arc, Mutex}, thread, time::{Duration, Instant, SystemTime, UNIX_EPOCH}};

#[derive(Clone, Copy, PartialEq)]
#[allow(dead_code)]
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
    computer_screen: Value,
    chat_tools: Vec<Value>,
    computer_path: String,
    computer_command: String,
    selected_memory: String,
    task_search: String,
    selected_task: Value,
    expanded_spaces: HashMap<String, bool>,
    pages_by_space: HashMap<String, Value>,
    page_dot: String,
    page_context: Value,
    page_search: String,
    page_sort_name: bool,
    page_list_view: bool,
    page_parent: String,
    voice_state: Value,
    voice_commands: tokio::sync::mpsc::UnboundedSender<voice::Command>,
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
        let token=server::owner_token();
        let voice_commands=voice::start_worker(url.trim_end_matches('/').to_owned(),token.clone(),tx.clone());
        let app = Self {
            base: url.trim_end_matches('/').to_owned(), token, tx, rx,
            data: json!({}), workspace: json!({}), pages: json!([]), selected_space: String::new(), selected_page: String::new(), selected_thread: String::new(), selected_dot: String::new(), screen: Screen::Home, error: None, server_error: None, last_refresh: Instant::now(),
            space_name: String::new(), space_description: String::new(), page_title: String::new(), page_content: String::new(), page_revision: 1, task_prompt: String::new(), task_interval: "86400".into(), conversation_title: "A new thought".into(), chat_draft: String::new(), chat_messages: Vec::new(), chat_thread: String::new(), chat_busy: false, memory_text: String::new(), settings_name: String::new(), settings: json!({}), dot_name: String::new(), dot_instructions: String::new(), dot_space: String::new(), dot_research: true, dot_memory: true, dot_apps: false, connections: json!([]), computer: json!({}), connection_name: String::new(), connection_url: String::new(), connection_token: String::new(), computer_url: String::new(), computer_text: String::new(), computer_screen: Value::Null, chat_tools: Vec::new(), computer_path: String::new(), computer_command: String::new(), selected_memory: String::new(), task_search: String::new(), selected_task: Value::Null, expanded_spaces: HashMap::new(), pages_by_space: HashMap::new(), page_dot: String::new(), page_context: Value::Null, page_search: String::new(), page_sort_name: false, page_list_view: false, page_parent: String::new(), voice_state: json!({"status":"idle","phase":"listening"}), voice_commands, server: Arc::new(Mutex::new(server)),
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
        if !self.selected_space.is_empty() {
            let space_id = self.selected_space.clone();
            self.request(&format!("pages:{space_id}"), "GET", &format!("/spaces/{space_id}/pages"), None);
        }
    }

    fn refresh_dot_tools(&self) {
        if !self.selected_dot.is_empty() {
            self.request("connections", "GET", &format!("/dots/{}/connections", self.selected_dot), None);
            self.request("computer", "GET", &format!("/dots/{}/computer", self.selected_dot), None);
        }
    }

    fn select_thread(&mut self, id: &str, dot_id: &str) {
        self.selected_thread=id.to_owned(); self.selected_dot=dot_id.to_owned(); self.chat_thread=id.to_owned();
        self.chat_messages.clear(); self.chat_tools.clear(); self.page_context=Value::Null; self.data["capture"]=Value::Null;
        self.request(&format!("capture:{id}"),"GET",&format!("/conversations/{id}/capture"),None);
        self.request(&format!("page-context:{id}"),"GET",&format!("/conversations/{id}/page-context"),None);
        self.request(&format!("chat-history:{id}"),"GET",&format!("/copilotkit/threads/{id}/messages?agentId={dot_id}"),None);
        self.refresh_dot_tools();
    }

    fn apply_chat_history(&mut self, value: Value) {
        let messages = value["messages"].as_array().or_else(|| value.as_array());
        if let Some(messages) = messages {
            self.chat_messages = messages.iter().filter_map(|message| {
                let role = message["role"].as_str()?;
                if role != "user" && role != "assistant" { return None; }
                let content = message["content"].as_str().map(str::to_owned).or_else(|| message["content"].as_array().map(|parts| parts.iter().filter_map(|part| part["text"].as_str()).collect::<Vec<_>>().join("")))?;
                (!content.trim().is_empty()).then(|| (role.to_owned(), content))
            }).collect();
        }
    }

    fn poll(&mut self) {
        while let Ok((tag, result)) = self.rx.try_recv() {
            match result {
                Ok(value) => {
                    self.error = None;
                    if let Some(space_id) = tag.strip_prefix("pages:") {
                        self.pages_by_space.insert(space_id.to_owned(), value.clone());
                        if self.selected_space == space_id { self.pages = value; }
                        continue;
                    }
                    if let Some(thread_id) = tag.strip_prefix("capture:") {
                        if self.selected_thread == thread_id { self.data["capture"] = value; }
                        continue;
                    }
                    if let Some(thread_id) = tag.strip_prefix("page-context:") {
                        if self.selected_thread == thread_id { self.page_context = value; }
                        continue;
                    }
                    if let Some(thread_id) = tag.strip_prefix("chat-history:") {
                        if self.selected_thread == thread_id { self.apply_chat_history(value); }
                        continue;
                    }
                    if let Some(call_id) = tag.strip_prefix("page-review:") {
                        if let Some(call) = self.chat_tools.iter_mut().find(|tool| tool["toolCallId"].as_str() == Some(call_id)) { call["result"] = json!(format!("Page saved: {}", value["title"].as_str().unwrap_or("page"))); }
                        self.refresh();
                        continue;
                    }
                    if let Some(call_id) = tag.strip_prefix("connection-run:") {
                        if let Some(call) = self.chat_tools.iter_mut().find(|tool| tool["toolCallId"].as_str() == Some(call_id)) { call["result"] = value.clone(); }
                        continue;
                    }
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
                        "connections" => {
                            if let Some(items) = value.as_array() {
                                self.connections = Value::Array(items.clone());
                            } else if let (Some(id), Some(items)) = (value["id"].as_str(), self.connections.as_array_mut()) {
                                if let Some(index) = items.iter().position(|item| item["id"].as_str() == Some(id)) { items[index] = value; }
                            }
                        }
                        "computer" => self.computer = value,
                        "computer-action" => { self.computer_text = value.to_string(); if value["base64"].is_string() { self.computer_screen = value; } },
                        "chat-tool" => { self.chat_tools.push(value); }
                        "chat-tool-result-event" | "chat-tool-action-result" => {
                            if let Some(call) = self.chat_tools.iter_mut().find(|tool| tool["toolCallId"].as_str() == value["toolCallId"].as_str()) {
                                call["result"] = value["content"].clone().as_str().map(|s| json!(s)).unwrap_or_else(|| value["result"].clone());
                            }
                        }
                        "connection-added" => { self.connection_name.clear(); self.connection_url.clear(); self.connection_token.clear(); self.refresh_dot_tools(); }
                        "memory-saved" => { self.selected_memory.clear(); self.memory_text.clear(); self.refresh(); }
                        "task-detail" => self.selected_task = value,
                        "page-read" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_title = value["title"].as_str().unwrap_or("").to_owned(); self.page_content = value["content"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(1); }
                        "voice" => self.voice_state = value,
                        "page-saved" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(self.page_revision); self.refresh_pages(); }
                        "page-deleted" => { self.selected_page.clear(); self.page_title.clear(); self.page_content.clear(); self.page_revision = 1; self.refresh_pages(); }
                        "page-conversation" => { let thread_id=value["id"].as_str().unwrap_or("").to_owned(); let dot_id=value["dotId"].as_str().unwrap_or(&self.selected_dot).to_owned(); self.select_thread(&thread_id,&dot_id); self.screen=Screen::Conversations; self.refresh(); }
                        "conversation-page" => { self.selected_space=value["spaceId"].as_str().unwrap_or("").into(); self.selected_page=value["id"].as_str().unwrap_or("").into(); self.screen=Screen::Spaces; self.request("page-read","GET",&format!("/spaces/{}/pages/{}",self.selected_space,self.selected_page),None); self.refresh_pages(); }
                        "conversation-created" => { let thread_id=value["id"].as_str().unwrap_or("").to_owned(); let dot_id=value["dotId"].as_str().unwrap_or(&self.selected_dot).to_owned(); self.select_thread(&thread_id,&dot_id); self.refresh(); }
                        "chat-delta" => { if self.chat_thread == value["threadId"].as_str().unwrap_or("") { if let (Some((role, text)), Some(delta)) = (self.chat_messages.last_mut(), value["delta"].as_str()) { if role == "assistant" { text.push_str(delta); } } } }
                        "chat-done" => self.chat_busy = false,
                        "chat-tool-result" => { self.chat_messages.push(("assistant".into(),format!("Page review result: {}",value))); self.refresh(); }
                        "connection-approval" => self.chat_messages.push(("assistant".into(),format!("Approval details: {}",value))),
                        "connection-run" => self.chat_messages.push(("assistant".into(),format!("Connected service result: {}",value))),
                        "dot-saved" => { self.selected_dot = value["id"].as_str().unwrap_or("").to_owned(); self.refresh(); }
                        "mutation" => { self.refresh(); if !self.selected_dot.is_empty() { self.refresh_dot_tools(); } },
                        _ => {}
                    }
                }
                Err(message) => { if tag.starts_with("chat-") { self.chat_busy = false; } self.error = Some(message); }
            }
        }
        if self.last_refresh.elapsed() > Duration::from_secs(8) { self.refresh(); if !self.selected_thread.is_empty(){let id=self.selected_thread.clone();self.request(&format!("capture:{id}"),"GET",&format!("/conversations/{id}/capture"),None);} self.last_refresh = Instant::now(); }
        if let Ok(mut child) = self.server.lock() { if let Some(message) = server::check_exit(&mut child) { self.server_error = Some(message); } }
    }

    fn mutate(&self, method: &str, path: &str, body: Option<Value>) { self.request("mutation", method, path, body); }
    fn heading(ui: &mut egui::Ui, title: &str, subtitle: &str) { ui.add_space(10.0); ui.label(egui::RichText::new(title).size(25.0).strong().color(egui::Color32::from_rgb(35,36,39))); ui.add_space(3.0); ui.label(egui::RichText::new(subtitle).size(13.0).color(egui::Color32::from_rgb(112,112,118))); ui.add_space(18.0); }
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
            cols[1].horizontal(|ui| { ui.add(egui::TextEdit::singleline(&mut self.connection_name).hint_text("Name")); ui.add(egui::TextEdit::singleline(&mut self.connection_url).hint_text("https://…")); });
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
            if ui.add_enabled(!self.selected_dot.is_empty() && self.workspace["setup"]["missing"].as_array().is_some_and(Vec::is_empty), egui::Button::new("Create conversation")).clicked() {
                self.request("conversation-created", "POST", "/conversations", Some(json!({"dotId":self.selected_dot,"title":self.conversation_title})));
            }
        });
        ui.add_space(12.0);
        let conversations = self.workspace["conversations"].as_array().cloned().unwrap_or_default();
        for thread in &conversations {
            let id = thread["id"].as_str().unwrap_or("");
            if ui.selectable_label(self.selected_thread == id, format!("{}  ·  {}", thread["title"].as_str().unwrap_or("Conversation"), thread["dotId"].as_str().unwrap_or(""))).clicked() { self.select_thread(id,thread["dotId"].as_str().unwrap_or("")); }
        }
        if !self.data["capture"].is_null() { ui.separator(); ui.heading("Captured result"); ui.label(self.data["capture"].to_string()); }
        for call in self.workspace["calls"].as_array().into_iter().flatten().filter(|call| call["threadId"].as_str()==Some(&self.selected_thread)) { ui.label(format!("Call {} — {}", call["status"], call["transcript"].as_str().unwrap_or(""))); }
        ui.separator();
        ui.heading("Voice call");
        let paused = self.settings["paused"].as_bool().unwrap_or(false);
        if paused { ui.label(egui::RichText::new("All Dots are paused. Resume the workspace to start a chat or voice call.").color(egui::Color32::from_rgb(120, 105, 70))); }
        let voice_status = self.voice_state["status"].as_str().unwrap_or("idle");
        if voice_status == "idle" {
            if ui.add_enabled(!paused && !self.selected_thread.is_empty(),egui::Button::new("Start voice call")).clicked() {
                let _ = self.voice_commands.send(voice::Command::Start { thread_id:self.selected_thread.clone(), anchor:None });
            }
        } else {
            ui.label(format!("{} · {} · {:02}:{:02}",voice_status,self.voice_state["phase"].as_str().unwrap_or("listening"),self.voice_state["elapsed"].as_u64().unwrap_or(0)/60,self.voice_state["elapsed"].as_u64().unwrap_or(0)%60));
            ui.horizontal(|ui| {
                let muted=self.voice_state["muted"].as_bool().unwrap_or(false);
                if ui.button(if muted{"Unmute microphone"}else{"Mute microphone"}).clicked(){let _=self.voice_commands.send(voice::Command::Mute(!muted));}
                let speaker_muted=self.voice_state["speakerMuted"].as_bool().unwrap_or(false);
                if ui.button(if speaker_muted{"Unmute speaker"}else{"Mute speaker"}).clicked(){let _=self.voice_commands.send(voice::Command::SpeakerMute(!speaker_muted));}
                if ui.button("End call").clicked(){let _=self.voice_commands.send(voice::Command::End);}
            });
            if let Some(caption)=self.voice_state["userCaption"].as_str().filter(|value|!value.is_empty()){ui.label(format!("You: {caption}"));}
            if let Some(caption)=self.voice_state["caption"].as_str().filter(|value|!value.is_empty()){ui.label(format!("Dot: {caption}"));}
        }
        if let Some(error)=self.voice_state["error"].as_str().filter(|value|!value.is_empty()){ui.colored_label(egui::Color32::from_rgb(180,65,58),error);}
        if !self.selected_thread.is_empty() {
            ui.separator();
            ui.heading("Chat");
            if !self.page_context.is_null(){ui.label(format!("Working on page: {}",self.page_context["title"].as_str().unwrap_or("Page")));}
            ui.horizontal(|ui|{ui.text_edit_singleline(&mut self.conversation_title);if ui.add_enabled(!self.chat_busy,egui::Button::new("Save conversation as page")).clicked(){self.request("conversation-page","POST",&format!("/conversations/{}/page",self.selected_thread),Some(json!({"title":self.conversation_title,"parentId":Value::Null})));}});
            for tool in self.chat_tools.clone() { ui.group(|ui| { let name=tool["name"].as_str().unwrap_or("Tool"); let call_id=tool["toolCallId"].as_str().unwrap_or(""); let args=&tool["args"]; ui.strong(name); ui.label(args.to_string()); if let Some(result)=tool["result"].as_str(){ui.label(result);}
                if name=="review_space_page" { ui.label("Page draft review"); if ui.add_enabled(tool["result"].is_null(),egui::Button::new("Approve and save page")).clicked(){ self.request(&format!("page-review:{call_id}"),"POST",&format!("/conversations/{}/reviewed-page",self.selected_thread),Some(json!({"toolCallId":call_id,"title":args["title"],"content":args["content"],"spaceId":args["spaceId"]}))); } if tool["result"].is_null() && ui.button("Decline draft").clicked(){ if let Some(call)=self.chat_tools.iter_mut().find(|item|item["toolCallId"].as_str()==Some(call_id)){call["result"]=json!("Declined by owner");} } }
                if name=="request_connection_action" { let approval=args["approvalId"].as_str().unwrap_or(""); if ui.button("Review connected action").clicked(){self.request("connection-approval","GET",&format!("/conversations/{}/connection-approvals/{}",self.selected_thread,approval),None);} if ui.add_enabled(tool["result"].is_null(),egui::Button::new("Approve and run")).clicked(){self.request(&format!("connection-run:{call_id}"),"POST",&format!("/conversations/{}/connection-actions",self.selected_thread),Some(json!({"toolCallId":call_id,"approvalId":approval})));} }
            }); }
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
            if ui.add_enabled(!paused && !self.chat_busy && !self.chat_draft.trim().is_empty(), egui::Button::new(if self.chat_busy { "Thinking…" } else { "Send" })).clicked() { self.send_chat(); }
        }
    }

    fn send_chat(&mut self) {
        let text = self.chat_draft.trim().to_owned();
        if text.is_empty() || self.chat_busy || self.settings["paused"].as_bool().unwrap_or(false) { return; }
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
            .map(|(index, (role, content))| {let content=if role=="user"&&!self.page_context.is_null(){format!("From [{}](/#/spaces/{}/pages/{}):\n\n{}",self.page_context["title"].as_str().unwrap_or("Page"),self.page_context["spaceId"].as_str().unwrap_or(""),self.page_context["id"].as_str().unwrap_or(""),content)}else{content.clone()};json!({"id":format!("aether-{index}"),"role":role,"content":content})}).collect::<Vec<_>>();
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
                let mut tool_names = HashMap::<String, String>::new();
                let mut tool_arguments = HashMap::<String, String>::new();
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
                            let id=event["toolCallId"].as_str().or_else(||event["toolCallID"].as_str()).unwrap_or("").to_owned();
                            match kind {
                                "TOOL_CALL_START" | "tool_call_start" => {
                                    if !id.is_empty() { if let Some(name)=event["toolCallName"].as_str().or_else(||event["toolName"].as_str()).or_else(||event["name"].as_str()) { tool_names.insert(id.clone(),name.to_owned()); } tool_arguments.insert(id, String::new()); }
                                }
                                "TOOL_CALL_ARGS" | "tool_call_args" => {
                                    if !id.is_empty() { tool_arguments.entry(id).or_default().push_str(event["delta"].as_str().unwrap_or("")); }
                                }
                                "TOOL_CALL_END" | "tool_call_end" => {
                                    if let Some(name)=tool_names.remove(&id) {
                                        let args=tool_arguments.remove(&id).and_then(|raw|serde_json::from_str::<Value>(&raw).ok()).unwrap_or_else(||json!({}));
                                        let _=tx.send(("chat-tool".into(),Ok(json!({"name":name,"args":args,"toolCallId":id,"event":event}))));
                                    }
                                }
                                "TOOL_CALL_RESULT" | "tool_call_result" => {
                                    let _=tx.send(("chat-tool-result-event".into(),Ok(json!({"toolCallId":id,"content":event["content"]}))));
                                }
                                _ => {}
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
        ui.horizontal(|ui| { ui.text_edit_singleline(&mut self.space_name).on_hover_text("Space name"); ui.text_edit_singleline(&mut self.space_description).on_hover_text("Description"); if Self::button(ui, "Create space").clicked() { self.mutate("POST", "/spaces", Some(json!({"name":self.space_name,"description":self.space_description}))); self.space_name.clear(); } });
        ui.horizontal(|ui| {
            egui::ComboBox::from_label("Space").selected_text(self.workspace["spaces"].as_array().into_iter().flatten().find(|s| s["id"].as_str()==Some(&self.selected_space)).and_then(|s|s["name"].as_str()).unwrap_or("Choose a space")).show_ui(ui, |ui| {
                for space in self.workspace["spaces"].as_array().into_iter().flatten() { let id=space["id"].as_str().unwrap_or(""); if ui.selectable_value(&mut self.selected_space,id.to_owned(),space["name"].as_str().unwrap_or("Space")).clicked() { self.selected_page.clear(); self.refresh_pages(); } }
            });
            if Self::button(ui,"New page").clicked() { self.selected_page.clear(); self.page_title="Untitled page".into(); self.page_content.clear(); self.page_revision=1; self.page_parent.clear(); }
        });
        if self.selected_page.is_empty() {
            ui.horizontal(|ui| {
                ui.add(egui::TextEdit::singleline(&mut self.page_search).hint_text("Search pages"));
                egui::ComboBox::from_id_salt("page-sort").selected_text(if self.page_sort_name {"Name A–Z"} else {"Recently edited"}).show_ui(ui, |ui| { ui.selectable_value(&mut self.page_sort_name,false,"Recently edited"); ui.selectable_value(&mut self.page_sort_name,true,"Name A–Z"); });
                ui.selectable_value(&mut self.page_list_view,false,"Grid"); ui.selectable_value(&mut self.page_list_view,true,"List");
                ui.label(format!("{} pages",self.pages.as_array().map_or(0,Vec::len)));
            });
        }
        ui.columns(2, |cols| {
            let mut library_pages=self.pages.as_array().cloned().unwrap_or_default();
            library_pages.retain(|page| format!("{} {}",page["title"].as_str().unwrap_or(""),page["content"].as_str().unwrap_or("")).to_lowercase().contains(&self.page_search.to_lowercase()));
            if self.page_sort_name { library_pages.sort_by(|a,b|a["title"].as_str().unwrap_or("").to_lowercase().cmp(&b["title"].as_str().unwrap_or("").to_lowercase())); } else { library_pages.sort_by(|a,b|b["updatedAt"].as_i64().unwrap_or(0).cmp(&a["updatedAt"].as_i64().unwrap_or(0))); }
            egui::ScrollArea::vertical().show(&mut cols[0], |ui| { for page in &library_pages { let id=page["id"].as_str().unwrap_or(""); let title=page["title"].as_str().unwrap_or("Untitled"); let excerpt=page["content"].as_str().unwrap_or("").lines().map(str::trim).find(|line|!line.is_empty()&&!line.starts_with('#')).unwrap_or("An empty page, ready to write."); let label=if self.page_list_view {format!("▤  {title}   ·   {}",excerpt.chars().take(90).collect::<String>())}else{format!("▤  {title}\n{}",excerpt.chars().take(120).collect::<String>())}; if ui.selectable_label(self.selected_page==id,label).clicked() { self.request("page-read","GET",&format!("/spaces/{}/pages/{id}",self.selected_space),None); } } });
            if library_pages.is_empty(){cols[0].label(if self.page_search.is_empty(){"No pages yet. Create a page to start organizing this Space."}else{"No matching pages. Try a different title or phrase."}); if self.page_search.is_empty() && cols[0].button("＋  New page").clicked(){self.selected_page.clear();self.page_title="Untitled page".into();self.page_content.clear();self.page_parent.clear();} }
            egui::ComboBox::from_label("Open with specialist").selected_text(self.workspace["dots"].as_array().into_iter().flatten().find(|d|d["id"].as_str()==Some(&self.page_dot)).and_then(|d|d["name"].as_str()).unwrap_or("Choose a Dot")).show_ui(&mut cols[0],|ui|{for dot in self.workspace["dots"].as_array().into_iter().flatten(){ui.selectable_value(&mut self.page_dot,dot["id"].as_str().unwrap_or("").into(),dot["name"].as_str().unwrap_or("Dot"));}});
            if cols[0].add_enabled(!self.selected_page.is_empty()&&!self.page_dot.is_empty(),egui::Button::new("Discuss this page")).clicked(){self.request("page-conversation","POST",&format!("/spaces/{}/pages/{}/conversation",self.selected_space,self.selected_page),Some(json!({"dotId":self.page_dot})));}
            cols[1].label("Title"); cols[1].text_edit_singleline(&mut self.page_title);
            if self.selected_page.is_empty() { egui::ComboBox::from_label("Parent page").selected_text(if self.page_parent.is_empty(){"Space root"}else{self.pages.as_array().into_iter().flatten().find(|p|p["id"].as_str()==Some(&self.page_parent)).and_then(|p|p["title"].as_str()).unwrap_or("Choose parent")}).show_ui(&mut cols[1],|ui|{ui.selectable_value(&mut self.page_parent,String::new(),"Space root");for p in self.pages.as_array().into_iter().flatten(){ui.selectable_value(&mut self.page_parent,p["id"].as_str().unwrap_or("").into(),p["title"].as_str().unwrap_or("Untitled"));}}); }
            cols[1].label("Markdown"); cols[1].add(egui::TextEdit::multiline(&mut self.page_content).desired_rows(18).desired_width(f32::INFINITY));
            cols[1].horizontal(|ui| {
                if ui.add_enabled(!self.selected_space.is_empty() && !self.page_title.trim().is_empty(), egui::Button::new("Save page")).clicked() { let (method,path,body)=if self.selected_page.is_empty() { ("POST",format!("/spaces/{}/pages",self.selected_space),json!({"title":self.page_title,"content":self.page_content,"parentId":if self.page_parent.is_empty(){Value::Null}else{json!(self.page_parent)}})) } else { ("PATCH",format!("/spaces/{}/pages/{}",self.selected_space,self.selected_page),json!({"title":self.page_title,"content":self.page_content,"expectedRevision":self.page_revision})) }; self.request("page-saved",method,&path,Some(body)); }
                if !self.selected_page.is_empty() && ui.button("New subpage").clicked() { self.page_parent=self.selected_page.clone(); self.selected_page.clear(); self.page_title="Untitled page".into(); self.page_content.clear(); }
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
        ui.horizontal(|ui| { ui.label("Find task"); ui.text_edit_singleline(&mut self.task_search); });
        let tasks=self.data["tasks"].as_array().cloned().unwrap_or_default();
        if tasks.is_empty(){ui.label("No scheduled activity yet. Schedule a turn from a conversation.");}
        let task_search = self.task_search.to_lowercase();
        for task in tasks.iter().filter(|task|task["prompt"].as_str().unwrap_or("").to_lowercase().contains(&task_search)) { ui.separator(); ui.horizontal(|ui| { ui.vertical(|ui| { ui.label(task["prompt"].as_str().unwrap_or("")); ui.label(format!("{} · {}",task["status"],task["id"])); if let Some(error)=task["error"].as_str(){ui.colored_label(egui::Color32::DARK_RED,error);} }); for action in ["run","pause","cancel"] { if ui.button(action).clicked() { self.mutate("POST",&format!("/tasks/{}/actions",task["id"].as_str().unwrap_or("")),Some(json!({"action":action}))); } } if ui.button("Details").clicked(){self.request("task-detail","GET",&format!("/tasks/{}",task["id"].as_str().unwrap_or("")),None);} }); ui.horizontal(|ui| { ui.label("Repeat seconds (60–31536000; blank runs once)");ui.text_edit_singleline(&mut self.task_interval);if ui.button("Save schedule").clicked(){let interval=self.task_interval.trim().parse::<i64>().ok().filter(|n|*n>=60).map_or(Value::Null,|n|json!(n));self.mutate("PUT",&format!("/tasks/{}/schedule",task["id"].as_str().unwrap_or("")),Some(json!({"intervalSeconds":interval})));} }); }
        if !self.selected_task.is_null(){ui.separator();ui.heading("Task detail");ui.label(self.selected_task["task"]["prompt"].as_str().unwrap_or(""));for event in self.selected_task["events"].as_array().into_iter().flatten(){ui.label(event["text"].as_str().unwrap_or(""));}ui.label(format!("{} saved runs",self.selected_task["runs"].as_array().map_or(0,Vec::len)));}
        for call in self.workspace["calls"].as_array().into_iter().flatten() { ui.label(format!("{} · {}",call["status"],call["transcript"].as_str().unwrap_or(""))); }
    }

    fn render_memories(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui,"Memories","Preferences you choose to share with your Dots."); ui.horizontal(|ui| { ui.text_edit_singleline(&mut self.memory_text); if Self::button(ui,if self.selected_memory.is_empty(){"Add memory"}else{"Save memory"}).clicked() { let (method,path)=if self.selected_memory.is_empty(){("POST","/memories".to_owned())}else{("PUT",format!("/memories/{}",self.selected_memory))}; self.request("memory-saved",method,&path,Some(json!({"text":self.memory_text}))); } });
        let memories=self.data["memories"].as_array().cloned().unwrap_or_default(); if memories.is_empty(){ui.label("A little context goes a long way. Add a preference you want your Dots to remember.");}
        for memory in memories { ui.group(|ui| {ui.label(memory["text"].as_str().unwrap_or(""));ui.label(if self.settings["memoryAllowed"].as_bool().unwrap_or(false){"Available to permitted Dots"}else{"Memory use disabled"});ui.horizontal(|ui|{if ui.button("Edit").clicked(){self.selected_memory=memory["id"].as_str().unwrap_or("").into();self.memory_text=memory["text"].as_str().unwrap_or("").into();}if ui.button("Delete").clicked(){self.mutate("DELETE",&format!("/memories/{}",memory["id"].as_str().unwrap_or("")),None);}})}); }
    }

    fn render_settings(&mut self, ui: &mut egui::Ui) {
        Self::heading(ui,"Settings","Set the name and permissions for this workspace."); ui.label("Workspace name"); ui.text_edit_singleline(&mut self.settings_name);
        for key in ["paused","researchAllowed","memoryAllowed","appsAllowed"] { let mut value=self.settings[key].as_bool().unwrap_or(false); let label=match key { "paused"=>"Pause all Dots", "researchAllowed"=>"Allow research", "memoryAllowed"=>"Allow memory", _=>"Allow connected apps" }; if ui.checkbox(&mut value,label).changed() { self.settings[key]=json!(value); self.mutate("PATCH","/settings",Some(json!({key:value}))); } }
        if Self::button(ui,"Save workspace name").clicked() { self.mutate("PATCH","/settings",Some(json!({"name":self.settings_name}))); }
        ui.separator(); ui.label(format!("API mode: {}",self.data["mode"].as_str().unwrap_or("unknown"))); ui.label(format!("Server: {}",self.base));
    }
}

#[allow(dead_code)]
fn decode_base64(input:&str)->Result<Vec<u8>,String>{ use std::process::{Command,Stdio}; use std::io::Write; let mut child=Command::new("base64").arg("-d").stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().map_err(|e|e.to_string())?; child.stdin.take().ok_or("stdin")?.write_all(input.as_bytes()).map_err(|e|e.to_string())?; let out=child.wait_with_output().map_err(|e|e.to_string())?; if out.status.success(){Ok(out.stdout)}else{Err("invalid base64".into())}}

fn ui_computer_actions(app: &mut NativeApp, ui: &mut egui::Ui) {
    if app.selected_dot.is_empty() { ui.label("Choose a Dot to manage its computer."); return; }
    let base=format!("/dots/{}/computer",app.selected_dot);
    let permissions=app.computer["permissions"].clone();
    ui.label(format!("Control: {}",app.computer["control"]["holder"].as_str().unwrap_or("unknown")));
    for (key,label) in [("enabled","Enable computer tools"),("browser","Browser"),("files","Files"),("shell","Terminal")] {
        let mut value=permissions[key].as_bool().unwrap_or(false);
        if ui.checkbox(&mut value,label).changed(){
            let mut body=json!({"enabled":permissions["enabled"].as_bool().unwrap_or(false),"browser":permissions["browser"].as_bool().unwrap_or(false),"files":permissions["files"].as_bool().unwrap_or(false),"shell":permissions["shell"].as_bool().unwrap_or(false)});
            body[key]=json!(value);
            app.request("computer","PATCH",&format!("{base}/permissions"),Some(body));
        }
    }
    ui.horizontal(|ui| {
        if ui.button("Refresh").clicked(){app.request("computer","GET",&base,None);}
        if ui.button("Start").clicked(){app.request("computer","POST",&format!("{base}/start"),Some(json!({})));}
        if ui.button("Stop").clicked(){app.request("computer","POST",&format!("{base}/stop"),Some(json!({})));}
        if ui.add_enabled(app.computer["control"]["requested"].as_bool().unwrap_or(false) || app.computer["control"]["holder"].as_str()==Some("bot"),egui::Button::new("Take control")).clicked(){app.request("computer","POST",&format!("{base}/take"),Some(json!({})));}
        if ui.button("Release control").clicked(){app.request("computer","POST",&format!("{base}/release"),Some(json!({})));}
    });
    if !app.computer["error"].is_null(){ui.colored_label(egui::Color32::DARK_RED,app.computer["error"].as_str().unwrap_or("Computer error"));}
    if app.computer["state"].as_str()==Some("not_configured"){ui.label("No computer service is configured on the server.");}
    ui.separator();ui.heading("Browser");
    ui.horizontal(|ui|{ui.add(egui::TextEdit::singleline(&mut app.computer_url).hint_text("https://example.com"));if ui.add_enabled(app.computer["state"].as_str()==Some("running") && app.computer["permissions"]["enabled"].as_bool()==Some(true) && app.computer["permissions"]["browser"].as_bool()==Some(true),egui::Button::new("Navigate")).clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"navigate","input":{"url":app.computer_url}})));}if ui.add_enabled(app.computer["state"].as_str()==Some("running") && app.computer["permissions"]["enabled"].as_bool()==Some(true) && app.computer["permissions"]["browser"].as_bool()==Some(true),egui::Button::new("Read page")).clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"read","input":{}})));}});
    if app.computer["state"].as_str()==Some("running") && app.computer["permissions"]["enabled"].as_bool()==Some(true) && app.computer["permissions"]["browser"].as_bool()==Some(true) { if ui.button("Capture screenshot").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"screenshot","input":{}})));} }
    if let Some(encoded)=app.computer_screen["base64"].as_str(){ if let Ok(bytes)=base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded).map_err(|e|e.to_string()){ if let Ok(image)=image::load_from_memory(&bytes){let rgba=image.to_rgba8();let size=[rgba.width() as usize,rgba.height() as usize];let texture=ui.ctx().load_texture("computer-screen",egui::ColorImage::from_rgba_unmultiplied(size,&rgba),Default::default());ui.image((texture.id(),egui::vec2(600.0,400.0)));} } }
    ui.separator();ui.heading("Files");ui.horizontal(|ui|{ui.add(egui::TextEdit::singleline(&mut app.computer_path).hint_text("Relative path"));if ui.button("List directory").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"files_list","input":{"path":app.computer_path}})));}if ui.button("Read file").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"files_read","input":{"path":app.computer_path}})));}});
    ui.horizontal(|ui|{if ui.button("Snapshot").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"snapshot","input":{}})));} if ui.button("Browser back").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"key","input":{"key":"Alt+Left"}})));} });
    ui.separator();ui.heading("Human browser control");ui.label("Take control on the computer service before these actions are accepted.");ui.horizontal(|ui|{ui.add(egui::TextEdit::singleline(&mut app.computer_text).hint_text("Text to type"));if ui.button("Type").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"human_type","input":{"text":app.computer_text}})));}if ui.button("Enter").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"human_key","input":{"key":"Enter"}})));}});
    ui.separator();ui.heading("Terminal");ui.horizontal(|ui|{ui.text_edit_singleline(&mut app.computer_command);if ui.button("Run command").clicked(){app.request("computer-action","POST",&format!("{base}/actions"),Some(json!({"action":"exec","input":{"command":app.computer_command,"timeoutMs":30000}})));}});
    if !app.computer_text.is_empty(){ui.separator();ui.heading("Action result");egui::ScrollArea::vertical().max_height(180.0).show(ui,|ui|{ui.label(&app.computer_text);});}
    if let Some(audit)=app.computer["audit"].as_array(){for entry in audit.iter().rev().take(6){ui.label(format!("{} · {} · {}",entry["action"],entry["actor"],entry["outcome"]));}}
}

impl eframe::App for NativeApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll();
        let bg=egui::Color32::from_rgb(255,255,255); let blue=egui::Color32::from_rgb(238,239,247);
        let mut style=(*ctx.style()).clone(); style.visuals.window_fill=bg; style.visuals.panel_fill=bg; style.visuals.widgets.active.bg_fill=blue; style.visuals.selection.bg_fill=blue; style.visuals.widgets.hovered.bg_fill=egui::Color32::from_rgb(245,245,247); style.spacing.item_spacing=egui::vec2(8.0,7.0); style.visuals.widgets.inactive.fg_stroke.color=egui::Color32::from_rgb(76,78,86); ctx.set_style(style);
        egui::TopBottomPanel::top("topbar").frame(egui::Frame::NONE.fill(egui::Color32::WHITE).inner_margin(egui::Margin::symmetric(22,14))).show(ctx,|ui|{ui.horizontal(|ui|{let crumb=match self.screen{Screen::Spaces=>self.workspace["spaces"].as_array().into_iter().flatten().find(|s|s["id"].as_str()==Some(&self.selected_space)).and_then(|s|s["name"].as_str()).unwrap_or("Spaces"),Screen::Activity=>"Activity",Screen::Memories=>"Memories",Screen::Dots=>"Dots & services",Screen::Settings=>"Settings",Screen::Computer=>"Computer",Screen::Home=>"Home",Screen::Conversations=>self.workspace["dots"].as_array().into_iter().flatten().find(|d|d["id"].as_str()==Some(&self.selected_dot)).and_then(|d|d["name"].as_str()).unwrap_or("Conversations")};ui.label(egui::RichText::new("Workspace").color(egui::Color32::GRAY));ui.label("/");ui.strong(crumb);ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui|{ui.label(egui::RichText::new("AETHER  ·  LOCAL").small().color(egui::Color32::GRAY));if ui.button(if self.settings["paused"].as_bool().unwrap_or(false){"▶ Resume all Dots"}else{"Ⅱ Pause all Dots"}).clicked(){let paused=!self.settings["paused"].as_bool().unwrap_or(false);self.settings["paused"]=json!(paused);if paused{let _=self.voice_commands.send(voice::Command::End);}self.mutate("PATCH","/settings",Some(json!({"paused":paused})));}});});});
        egui::SidePanel::left("rail").exact_width(52.0).frame(egui::Frame::side_top_panel(&ctx.style()).fill(egui::Color32::from_rgb(245,245,245))).show(ctx,|ui| {
            ui.add_space(8.0);
            if ui.add_sized([36.0,38.0],egui::Button::new(egui::RichText::new("o·").size(24.0).strong())).clicked(){self.screen=Screen::Conversations;}
            ui.add_space(8.0);
            if ui.add_sized([36.0,34.0],egui::Button::new("＋")).clicked(){self.screen=Screen::Conversations;self.conversation_title="A new thought".into();}
            if ui.add_sized([36.0,34.0],egui::Button::new("▱")).clicked(){self.screen=Screen::Spaces;}
            if ui.add_sized([36.0,34.0],egui::Button::new("◷")).clicked(){self.screen=Screen::Activity;}
            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center),|ui|{if ui.add_sized([36.0,34.0],egui::Button::new("⚙")).clicked(){self.screen=Screen::Settings;}});
        });
        let sidebar_spaces = self.workspace["spaces"].as_array().cloned().unwrap_or_default();
        let sidebar_dots = self.workspace["dots"].as_array().cloned().unwrap_or_default();
        let sidebar_conversations = self.workspace["conversations"].as_array().cloned().unwrap_or_default();
        egui::SidePanel::left("navigation").exact_width(226.0).frame(egui::Frame::side_top_panel(&ctx.style()).fill(egui::Color32::from_rgb(249,249,249)).inner_margin(egui::Margin::same(12))).show(ctx,|ui|{
            ui.add_space(8.0); ui.horizontal(|ui|{ui.label(egui::RichText::new("⠿  OpenDots").size(17.0).strong());}); ui.add_space(14.0);
            if ui.add_sized([ui.available_width(),34.0],egui::Button::new("＋   New chat")).clicked(){self.screen=Screen::Conversations;self.conversation_title="A new thought".into();}
            ui.add_space(14.0);
            ui.horizontal(|ui|{ui.label(egui::RichText::new("DOTS").size(11.0).color(egui::Color32::GRAY));ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui|{if ui.small_button("＋").clicked(){self.screen=Screen::Dots;self.selected_dot.clear();self.dot_name.clear();self.dot_instructions.clear();}});});
            for dot in &sidebar_dots{let id=dot["id"].as_str().unwrap_or("");let active=self.selected_dot==id&&self.screen==Screen::Conversations;if ui.add_sized([ui.available_width(),32.0],egui::SelectableLabel::new(active,format!("◉   {}",dot["name"].as_str().unwrap_or("Dot")))).clicked(){if let Some(thread)=sidebar_conversations.iter().find(|t|t["dotId"].as_str()==Some(id)){self.select_thread(thread["id"].as_str().unwrap_or(""),id);}else{self.selected_dot=id.into();}self.screen=Screen::Conversations;}}
            ui.add_space(10.0);ui.horizontal(|ui|{ui.label(egui::RichText::new("SPACES").size(11.0).color(egui::Color32::GRAY));ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui|{if ui.small_button("＋").clicked(){self.screen=Screen::Spaces;}});});
            for space in &sidebar_spaces{let id=space["id"].as_str().unwrap_or("").to_owned();let expanded=*self.expanded_spaces.get(&id).unwrap_or(&false);ui.horizontal(|ui|{if ui.small_button(if expanded{"⌄"}else{"›"}).clicked(){self.expanded_spaces.insert(id.clone(),!expanded);if !expanded{self.selected_space=id.clone();self.refresh_pages();}}let active=self.selected_space==id&&self.screen==Screen::Spaces&&self.selected_page.is_empty();if ui.add_sized([ui.available_width(),28.0],egui::SelectableLabel::new(active,format!("▱  {}",space["name"].as_str().unwrap_or("Space")))).clicked(){self.selected_space=id.clone();self.selected_page.clear();self.screen=Screen::Spaces;self.refresh_pages();}});
                if expanded{let page_items=self.pages_by_space.get(&id).and_then(Value::as_array).cloned().unwrap_or_default();for page in page_items.iter(){let pid=page["id"].as_str().unwrap_or("");let depth=page_items.iter().filter(|p|p["id"].as_str()==page["parentId"].as_str()).count().min(3);let active=self.selected_page==pid&&self.screen==Screen::Spaces;if ui.add_sized([ui.available_width(),26.0],egui::SelectableLabel::new(active,format!("{}▤  {}","  ".repeat(depth+1),page["title"].as_str().unwrap_or("Untitled")))).clicked(){self.selected_space=id.clone();self.screen=Screen::Spaces;self.request("page-read","GET",&format!("/spaces/{id}/pages/{pid}"),None);}}if page_items.is_empty(){ui.indent(format!("empty-{id}"),|ui|{ui.label(egui::RichText::new("No pages yet").small().weak());});}}
            }
            ui.add_space(8.0);ui.separator();ui.horizontal(|ui|{ui.label(egui::RichText::new("RECENT CHATS").size(11.0).color(egui::Color32::GRAY));ui.with_layout(egui::Layout::right_to_left(egui::Align::Center),|ui|{if ui.small_button("＋").clicked(){self.screen=Screen::Conversations;self.conversation_title="A new thought".into();}});});
            egui::ScrollArea::vertical().id_salt("recent-chats").show(ui,|ui|{for thread in &sidebar_conversations{let id=thread["id"].as_str().unwrap_or("");let active=self.selected_thread==id&&self.screen==Screen::Conversations;if ui.add_sized([ui.available_width(),34.0],egui::SelectableLabel::new(active,format!("◌  {}",thread["title"].as_str().unwrap_or("Conversation")))).clicked(){self.select_thread(id,thread["dotId"].as_str().unwrap_or(""));self.screen=Screen::Conversations;}}});
            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT),|ui|{ui.separator();for (label,screen,count) in [("Settings & setup",Screen::Settings,0),("Memories",Screen::Memories,self.data["memories"].as_array().map_or(0,Vec::len)),("Scheduled & activity",Screen::Activity,self.data["tasks"].as_array().map_or(0,Vec::len)),("Dots & services",Screen::Dots,0)]{let suffix=if count>0{format!("  {count}")}else{String::new()};if ui.add_sized([ui.available_width(),30.0],egui::SelectableLabel::new(self.screen==screen,format!("{}{}",label,suffix))).clicked(){self.screen=screen;if screen==Screen::Dots{self.refresh_dot_tools();}}}ui.add_space(4.0);ui.label(egui::RichText::new(if self.server_error.is_some(){"●  Server stopped"}else{"●  Local server connected"}).small().color(egui::Color32::from_rgb(125,145,128)));});
        });
        egui::CentralPanel::default().frame(egui::Frame::NONE.fill(egui::Color32::WHITE).inner_margin(egui::Margin::symmetric(26,18))).show(ctx,|ui| {
            egui::ScrollArea::vertical().show(ui,|ui| {
                if let Some(message)=&self.server_error { ui.colored_label(egui::Color32::DARK_RED,message); }
                if let Some(message)=&self.error { ui.colored_label(egui::Color32::DARK_RED,message); }
                match self.screen { Screen::Home=>self.render_home(ui), Screen::Dots=>self.render_dots(ui), Screen::Conversations=>self.render_conversations(ui), Screen::Spaces=>self.render_spaces(ui), Screen::Activity=>self.render_activity(ui), Screen::Memories=>self.render_memories(ui), Screen::Settings=>self.render_settings(ui), Screen::Computer=>{Self::heading(ui,"Computer","Control the selected Dot’s server hosted computer.");ui.label(format!("{}",self.computer["state"].as_str().unwrap_or("Loading status")));ui_computer_actions(self,ui);} }
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
