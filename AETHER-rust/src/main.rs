#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;

use eframe::egui;
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::Value;
use std::{
    cell::RefCell,
    rc::Rc,
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Deserialize)]
struct Task {
    id: String,
    prompt: String,
    status: String,
    error: Option<String>,
}

#[derive(Deserialize)]
struct State {
    tasks: Vec<Task>,
    mode: String,
    configured: bool,
}

#[derive(Clone, Deserialize)]
struct Dot {
    id: String,
    name: String,
}

#[derive(Clone, Deserialize)]
struct Conversation {
    id: String,
    title: String,
}

#[derive(Deserialize)]
struct Workspace {
    spaces: Vec<Space>,
    dots: Vec<Dot>,
    conversations: Vec<Conversation>,
    setup: Setup,
}

#[derive(Clone, Deserialize)]
struct Space { id: String, name: String, description: String }

#[derive(Deserialize)]
struct Setup {
    missing: Vec<String>,
}

enum ApiMessage {
    Started(Result<(String, Option<server::OwnedServer>), String>),
    Refreshed(Result<(State, Workspace), String>),
    Action(Result<(), String>, bool),
}

struct Client {
    base_url: String,
    token: String,
    prompt: String,
    state: Option<State>,
    workspace: Option<Workspace>,
    selected_thread: Option<String>,
    selected_dot: Option<String>,
    view: String,
    space_name: String,
    page_title: String,
    page_content: String,
    error: Option<String>,
    startup_error: Option<String>,
    start_pending: bool,
    http: reqwest::blocking::Client,
    refresh_at: Instant,
    refresh_pending: bool,
    action_pending: bool,
    tx: Sender<ApiMessage>,
    rx: Receiver<ApiMessage>,
    supervisor: Rc<RefCell<Option<server::OwnedServer>>>,
    next_server_check: Instant,
}

fn request<T: DeserializeOwned>(
    http: &reqwest::blocking::Client,
    base_url: &str,
    token: &str,
    path: &str,
    method: reqwest::Method,
    body: Option<Value>,
) -> Result<T, String> {
    let url = format!("{}{}", base_url.trim_end_matches('/'), path);
    let mut request = http.request(method, url);
    if !token.is_empty() {
        request = request.bearer_auth(token);
    }
    if let Some(json) = body {
        request = request.json(&json);
    }
    let response = request.send().map_err(|e| format!("Could not reach OpenDots: {e}"))?;
    let status = response.status();
    let payload: Value = response.json().unwrap_or(Value::Null);
    if !status.is_success() {
        return Err(payload
            .get("error")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| format!("OpenDots request failed ({status}).")));
    }
    serde_json::from_value(payload)
        .map_err(|e| format!("OpenDots returned an unreadable response: {e}"))
}

impl Client {
    fn refresh(&mut self) {
        if self.refresh_pending || self.start_pending || self.startup_error.is_some() {
            return;
        }
        self.refresh_pending = true;
        self.refresh_at = Instant::now() + Duration::from_secs(4);
        let http = self.http.clone();
        let base_url = self.base_url.clone();
        let token = self.token.clone();
        let tx = self.tx.clone();
        thread::spawn(move || {
            let result = (|| {
                let state = request(
                    &http,
                    &base_url,
                    &token,
                    "/api/state",
                    reqwest::Method::GET,
                    None,
                )?;
                let workspace = request(
                    &http,
                    &base_url,
                    &token,
                    "/api/workspace",
                    reqwest::Method::GET,
                    None,
                )?;
                Ok((state, workspace))
            })();
            let _ = tx.send(ApiMessage::Refreshed(result));
        });
    }

    fn action(&mut self, path: String, body: Value, clear_prompt: bool) {
        if self.action_pending {
            return;
        }
        self.action_pending = true;
        let http = self.http.clone();
        let base_url = self.base_url.clone();
        let token = self.token.clone();
        let tx = self.tx.clone();
        thread::spawn(move || {
            let result = request::<Value>(
                &http,
                &base_url,
                &token,
                &path,
                reqwest::Method::POST,
                Some(body),
            )
            .map(|_| ());
            let _ = tx.send(ApiMessage::Action(result, clear_prompt));
        });
    }

    fn receive_updates(&mut self) {
        while let Ok(message) = self.rx.try_recv() {
            match message {
                ApiMessage::Started(result) => {
                    self.start_pending = false;
                    match result {
                        Ok((url, owned_server)) => {
                            self.base_url = url;
                            *self.supervisor.borrow_mut() = owned_server;
                            self.refresh_at = Instant::now();
                        }
                        Err(error) => {
                            self.startup_error = Some(error.clone());
                            self.error = Some(error);
                        }
                    }
                }
                ApiMessage::Refreshed(result) => {
                    self.refresh_pending = false;
                    match result {
                        Ok((state, workspace)) => {
                            if self.selected_thread.as_ref().map_or(true, |id| {
                                !workspace.conversations.iter().any(|conversation| &conversation.id == id)
                            }) {
                                self.selected_thread = workspace.conversations.first().map(|c| c.id.clone());
                            }
                            if self.selected_dot.as_ref().map_or(true, |id| {
                                !workspace.dots.iter().any(|dot| &dot.id == id)
                            }) {
                                self.selected_dot = workspace.dots.first().map(|dot| dot.id.clone());
                            }
                            self.state = Some(state);
                            self.workspace = Some(workspace);
                            self.error = None;
                        }
                        Err(error) => self.error = Some(error),
                    }
                }
                ApiMessage::Action(result, clear_prompt) => {
                    self.action_pending = false;
                    match result {
                        Ok(()) => {
                            self.error = None;
                            if clear_prompt {
                                self.prompt.clear();
                            }
                            self.refresh();
                        }
                        Err(error) => self.error = Some(error),
                    }
                }
            }
        }
    }
}

impl eframe::App for Client {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.receive_updates();
        if Instant::now() >= self.next_server_check {
            self.next_server_check = Instant::now() + Duration::from_secs(1);
            if let Some(message) = server::check_exit(&mut self.supervisor.borrow_mut()) {
                self.error = Some(message);
            }
        }
        if !self.start_pending && !self.refresh_pending && Instant::now() >= self.refresh_at {
            self.refresh();
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("OpenDots");
            ui.label("Your workspace");
            ui.separator();
            if self.start_pending {
                ui.spinner();
                ui.label("Starting the OpenDots server…");
                ctx.request_repaint_after(Duration::from_millis(100));
                return;
            }
            if let Some(message) = &self.startup_error {
                ui.colored_label(egui::Color32::LIGHT_RED, format!("Could not start OpenDots: {message}"));
                ui.label("Check the AETHER server log and confirm Node.js and the built app are available.");
                return;
            }
            ui.horizontal(|ui| {
                ui.label("Server");
                ui.monospace(&self.base_url);
                if ui.add_enabled(!self.refresh_pending, egui::Button::new("Refresh")).clicked() {
                    self.refresh();
                }
            });
            if let Some(message) = &self.error {
                ui.colored_label(egui::Color32::LIGHT_RED, message);
            }
            if self.state.is_none() {
                ui.add_space(20.0);
                if self.refresh_pending {
                    ui.spinner();
                    ui.label("Connecting to OpenDots…");
                }
                ui.label("Owner token");
                ui.add(egui::TextEdit::singleline(&mut self.token).password(true).hint_text("Paste your owner access token"));
                if ui.add_enabled(!self.refresh_pending, egui::Button::new("Connect")).clicked() {
                    self.refresh();
                }
                ctx.request_repaint_after(Duration::from_millis(100));
                return;
            }

            let configured = self.state.as_ref().is_some_and(|state| state.configured);
            ui.horizontal(|ui| {
                for (label, view) in [("Chat", "chat"), ("Spaces & Pages", "spaces"), ("Tasks", "tasks"), ("Settings", "settings")] {
                    if ui.selectable_label(self.view == view, label).clicked() { self.view = view.into(); }
                }
            });
            ui.separator();
            if self.view == "spaces" {
                ui.heading("Spaces");
                if let Some(w) = &self.workspace {
                    for space in &w.spaces { ui.group(|ui| { ui.strong(&space.name); ui.label(&space.description); }); }
                }
                ui.horizontal(|ui| {
                    ui.add(egui::TextEdit::singleline(&mut self.space_name).hint_text("Space name"));
                    if ui.add_enabled(!self.action_pending && !self.space_name.trim().is_empty(), egui::Button::new("Create Space")).clicked() {
                        self.action("/api/spaces".into(), serde_json::json!({"name": self.space_name.trim(), "description": ""}), false);
                        self.space_name.clear();
                    }
                });
                let first_space = self.workspace.as_ref().and_then(|w| w.spaces.first()).map(|s| (s.id.clone(), s.name.clone()));
                if let Some((space_id, space_name)) = first_space {
                    ui.separator(); ui.heading(format!("Pages · {}", space_name));
                    ui.add(egui::TextEdit::singleline(&mut self.page_title).hint_text("Page title"));
                    ui.add(egui::TextEdit::multiline(&mut self.page_content).desired_rows(8).hint_text("Write a page…"));
                    if ui.add_enabled(!self.action_pending && !self.page_title.trim().is_empty(), egui::Button::new("Create page in this Space")).clicked() {
                        self.action(format!("/api/spaces/{}/pages", space_id), serde_json::json!({"title": self.page_title.trim(), "content": self.page_content, "parentId": null}), false);
                        self.page_title.clear(); self.page_content.clear();
                    }
                }
                ctx.request_repaint_after(Duration::from_millis(250)); return;
            }
            if self.view == "settings" {
                ui.heading("Settings");
                ui.label("Workspace settings are available through the server API; native editing is not wired yet.");
                ui.label("Conversation transcripts and live chat streaming are not exposed by the current native client.");
                return;
            }
            let missing = self.workspace.as_ref().map(|workspace| workspace.setup.missing.clone()).unwrap_or_default();
            let workspace = self.workspace.as_ref().map(|workspace| (
                workspace.dots.clone(),
                workspace.conversations.clone(),
            ));
            ui.label(format!("Mode: {} · {}", self.state.as_ref().map(|state| state.mode.as_str()).unwrap_or("unknown"), if configured { "configured" } else { "setup needed" }));
            ui.add_space(12.0);
            ui.heading("New task");
            if !missing.is_empty() {
                ui.label(format!("Complete OpenDots setup first: {}", missing.join(", ")));
            } else if let Some((dots, conversations)) = workspace {
                if !conversations.is_empty() {
                    let selected = self.selected_thread.clone().unwrap_or_default();
                    egui::ComboBox::from_label("Conversation")
                        .selected_text(conversations.iter().find(|c| c.id == selected).map(|c| c.title.as_str()).unwrap_or("Choose a conversation"))
                        .show_ui(ui, |ui| {
                            for conversation in &conversations {
                                ui.selectable_value(&mut self.selected_thread, Some(conversation.id.clone()), &conversation.title);
                            }
                        });
                }
                if !dots.is_empty() {
                    egui::ComboBox::from_label("Dot")
                        .selected_text(dots.iter().find(|dot| Some(&dot.id) == self.selected_dot.as_ref()).map(|dot| dot.name.as_str()).unwrap_or("Choose a Dot"))
                        .show_ui(ui, |ui| {
                            for dot in &dots {
                                ui.selectable_value(&mut self.selected_dot, Some(dot.id.clone()), &dot.name);
                            }
                        });
                    if ui.add_enabled(!self.action_pending, egui::Button::new("New conversation")).clicked() {
                        if let Some(dot_id) = self.selected_dot.clone() {
                            self.action("/api/conversations".into(), serde_json::json!({"dotId": dot_id, "title": "A new thought"}), false);
                        }
                    }
                }
                if conversations.is_empty() && dots.is_empty() {
                    ui.label("Create a Dot in OpenDots before starting a conversation.");
                }
            }
            ui.add(egui::TextEdit::multiline(&mut self.prompt).desired_rows(3).hint_text("What should OpenDots work on?"));
            let can_create = configured && missing.is_empty() && self.selected_thread.is_some();
            if ui.add_enabled(can_create && !self.action_pending && self.prompt.trim().len() >= 3, egui::Button::new("Create task")).clicked() {
                let prompt = self.prompt.trim().to_owned();
                let thread_id = self.selected_thread.clone().unwrap_or_default();
                self.action("/api/tasks".into(), serde_json::json!({"prompt": prompt, "threadId": thread_id}), true);
            }
            if !can_create {
                ui.small("Complete setup and select a conversation before creating a task.");
            }
            ui.add_space(16.0);
            ui.heading("Tasks");
            egui::ScrollArea::vertical().show(ui, |ui| {
                let tasks = self.state.as_ref().map(|state| state.tasks.clone()).unwrap_or_default();
                if tasks.is_empty() { ui.label("No tasks yet."); }
                for task in tasks {
                    ui.group(|ui| {
                        ui.strong(&task.prompt);
                        ui.label(format!("{} · {}", task.status, task.id));
                        if let Some(error) = task.error.as_deref() { ui.colored_label(egui::Color32::LIGHT_RED, error); }
                        ui.horizontal(|ui| {
                            for (label, action) in [("Run", "run"), ("Pause", "pause"), ("Cancel", "cancel")] {
                                if ui.add_enabled(!self.action_pending, egui::Button::new(label)).clicked() {
                                    self.action(format!("/api/tasks/{}/actions", task.id), serde_json::json!({"action": action}), false);
                                }
                            }
                        });
                    });
                }
            });
            ctx.request_repaint_after(Duration::from_millis(250));
        });
    }
}

fn main() {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("OpenDots")
            .with_inner_size([1000.0, 760.0])
            .with_min_inner_size([700.0, 520.0]),
        ..Default::default()
    };
    let supervisor = Rc::new(RefCell::new(None));
    let app_supervisor = supervisor.clone();
    let (tx, rx) = mpsc::channel();
    let startup_tx = tx.clone();
    thread::spawn(move || {
        let result = server::launch();
        if let Err(error) = &result {
            server::record_failure(error);
        }
        if let Err(error) = startup_tx.send(ApiMessage::Started(result)) {
            if let ApiMessage::Started(Ok((_url, mut owned_server))) = error.0 {
                server::stop(&mut owned_server);
            }
        }
    });
    let result = eframe::run_native(
        "OpenDots",
        options,
        Box::new(move |_cc| {
            Ok(Box::new(Client {
                base_url: String::new(),
                token: server::owner_token().unwrap_or_default(),
                prompt: String::new(),
                state: None,
                workspace: None,
                selected_thread: None,
                selected_dot: None,
                view: "chat".into(),
                space_name: String::new(),
                page_title: String::new(),
                page_content: String::new(),
                error: None,
                startup_error: None,
                start_pending: true,
                http: reqwest::blocking::Client::builder()
                    .timeout(Duration::from_secs(15))
                    .build()
                    .expect("build HTTP client"),
                refresh_at: Instant::now(),
                refresh_pending: false,
                action_pending: false,
                tx,
                rx,
                supervisor: app_supervisor,
                next_server_check: Instant::now(),
            }))
        }),
    );
    if let Err(error) = result {
        server::record_failure(&format!("Native UI startup failed: {error}"));
        eprintln!("AETHER: native UI startup failed: {error}");
    }
    server::stop(&mut supervisor.borrow_mut());
}
