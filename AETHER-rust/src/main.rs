#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;

use eframe::egui;
use serde_json::{json, Value};
use std::{sync::{mpsc::{self, Receiver, Sender}, Arc, Mutex}, thread, time::{Duration, Instant}};

#[derive(Clone, Copy, PartialEq)]
enum Screen { Home, Conversations, Spaces, Activity, Memories, Settings }

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
    memory_text: String,
    settings_name: String,
    settings: Value,
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
            space_name: String::new(), space_description: String::new(), page_title: String::new(), page_content: String::new(), page_revision: 1, task_prompt: String::new(), task_interval: "86400".into(), conversation_title: "A new thought".into(), memory_text: String::new(), settings_name: String::new(), settings: json!({}), server: Arc::new(Mutex::new(server)),
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
                        }
                        "pages" => self.pages = value,
                        "page-read" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_title = value["title"].as_str().unwrap_or("").to_owned(); self.page_content = value["content"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(1); }
                        "capture" => self.data["capture"] = value,
                        "page-saved" => { self.selected_page = value["id"].as_str().unwrap_or("").to_owned(); self.page_revision = value["revision"].as_i64().unwrap_or(self.page_revision); self.refresh_pages(); }
                        "page-deleted" => { self.selected_page.clear(); self.page_title.clear(); self.page_content.clear(); self.page_revision = 1; self.refresh_pages(); }
                        "conversation-created" => { self.selected_thread = value["id"].as_str().unwrap_or("").to_owned(); self.data["capture"] = Value::Null; self.refresh(); }
                        "mutation" => self.refresh(),
                        _ => {}
                    }
                }
                Err(message) => self.error = Some(message),
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
            if ui.selectable_label(self.selected_thread == id, format!("{}  ·  {}", thread["title"].as_str().unwrap_or("Conversation"), id)).clicked() { self.selected_thread = id.to_owned(); self.data["capture"] = Value::Null; self.request("capture", "GET", &format!("/conversations/{id}/capture"), None); }
        }
        if !self.data["capture"].is_null() { ui.separator(); ui.heading("Captured result"); ui.label(self.data["capture"].to_string()); }
        for call in self.workspace["calls"].as_array().into_iter().flatten() { ui.label(format!("Call {} — {}", call["status"], call["transcript"].as_str().unwrap_or(""))); }
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
            for (label,screen) in [("Home",Screen::Home),("Conversations",Screen::Conversations),("Spaces & Pages",Screen::Spaces),("Scheduled & Activity",Screen::Activity),("Memories",Screen::Memories),("Settings",Screen::Settings)] { if ui.selectable_label(self.screen==screen,label).clicked() { self.screen=screen; } }
            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT),|ui| { ui.label(if self.server_error.is_some(){"Server stopped"}else{"Local server connected"}); });
        });
        egui::CentralPanel::default().show(ctx,|ui| {
            egui::ScrollArea::vertical().show(ui,|ui| {
                if let Some(message)=&self.server_error { ui.colored_label(egui::Color32::DARK_RED,message); }
                if let Some(message)=&self.error { ui.colored_label(egui::Color32::DARK_RED,message); }
                match self.screen { Screen::Home=>self.render_home(ui), Screen::Conversations=>self.render_conversations(ui), Screen::Spaces=>self.render_spaces(ui), Screen::Activity=>self.render_activity(ui), Screen::Memories=>self.render_memories(ui), Screen::Settings=>self.render_settings(ui) }
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
