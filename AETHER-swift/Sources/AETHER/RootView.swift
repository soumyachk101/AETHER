#if os(macOS)
import SwiftUI
import Combine

private enum Section: String, CaseIterable, Identifiable {
    case home = "Home", dots = "Dots", conversations = "Conversations", pages = "Spaces & Pages", tasks = "Scheduled & Activity", memories = "Memories", settings = "Settings"
    var id: String { rawValue }
    var icon: String { ["Home":"house", "Dots":"sparkles", "Conversations":"bubble.left.and.bubble.right", "Spaces & Pages":"doc.text", "Scheduled & Activity":"clock", "Memories":"brain.head.profile", "Settings":"gearshape"][rawValue] ?? "circle" }
}

@MainActor private final class Workspace: ObservableObject {
    @Published var state: [String: Any] = [:]
    @Published var workspace: [String: Any] = [:]
    @Published var alert: String?
    var base: URL?; var token: String?
    func load(_ server: ServerController) async {
        guard let base = server.serverURL else { return }; self.base = base; token = server.ownerToken
        do {
            state = try await get("/api/state")
            workspace = try await get("/api/workspace")
            if let firstSpace = rows("spaces", from: workspace).first, pageSpace.isEmpty {
                pageSpace = str(firstSpace, "id")
            }
            await loadPages()
        } catch { alert = error.localizedDescription }
    }
    func get(_ path: String) async throws -> [String: Any] { try await request(path, method: "GET") }
    func send(_ path: String, method: String = "POST", body: [String: Any] = [:]) async throws -> [String: Any] { try await request(path, method: method, body: body) }
    private func request(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let base else { throw URLError(.notConnectedToInternet) }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let object = try? JSONSerialization.jsonObject(with: data)
        let result = object as? [String: Any] ?? ["items": object as? [[String: Any]] ?? []]
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw NSError(domain: "AETHER", code: 1, userInfo: [NSLocalizedDescriptionKey: result["error"] as? String ?? "Request failed."]) }
        return result
    }
    func refresh() async { if base != nil { do { state = try await get("/api/state"); workspace = try await get("/api/workspace"); if pageSpace.isEmpty, let firstSpace = rows("spaces", from: workspace).first { pageSpace = str(firstSpace, "id") }; await loadPages() } catch { alert = error.localizedDescription } } }
    private func loadPages() async { for index in rows("spaces", from: workspace).indices { let space = rows("spaces", from: workspace)[index]; if let id = space["id"] as? String, let result = try? await get("/api/spaces/\(id)/pages") { var updated = space; updated["pages"] = result["items"] ?? []; var all = rows("spaces", from: workspace); all[index] = updated; workspace["spaces"] = all } } }
    func rows(_ key: String, from source: [String: Any]) -> [[String: Any]] { source[key] as? [[String: Any]] ?? [] }
    func str(_ row: [String: Any], _ key: String) -> String { row[key] as? String ?? "" }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerController
    @StateObject private var data = Workspace()
    @StateObject private var chat = ConversationClient()
    @State private var section: Section = .home
    @State private var selectedThread = ""
    @State private var selectedDot = ""
    @State private var search = ""
    @State private var draft = ""
    @State private var pageTitle = ""
    @State private var pageContent = ""
    @State private var pageId = ""
    @State private var pageSpace = ""
    @State private var pageRevision = 0
    @State private var composer = ""
    @State private var taskPrompt = ""
    @State private var memoryText = ""

    var body: some View {
        Group {
            if !server.phase.isReady { LaunchView() }
            else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) { AetherMark(size: 36); VStack(alignment: .leading) { Text("AETHER").font(.headline); Text("OpenDots workspace").font(.caption).foregroundStyle(.secondary) } }
                            .padding(.horizontal, 15).padding(.top, 18)
                        ForEach(Section.allCases) { item in
                            Button { section = item } label: { Label(item.rawValue, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6) }
                                .buttonStyle(.plain).padding(.horizontal, 12)
                                .background(section == item ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                        Spacer()
                        Label("Local server connected", systemImage: "circle.fill").font(.caption).foregroundStyle(.secondary).padding(16)
                    }
                    .padding(10).frame(minWidth: 220).background(Color(nsColor: .controlBackgroundColor))
                } detail: {
                    VStack(spacing: 0) {
                        HStack { Text(section.rawValue).font(.system(size: 24, weight: .semibold, design: .rounded)); Spacer(); Button { Task { await data.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh") }
                            .padding(.horizontal, 28).padding(.vertical, 18)
                        Divider()
                        screen.padding(26)
                    }.background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: 980, minHeight: 650)
        .task { await server.start(); await data.load(server) }
        .alert("AETHER", isPresented: Binding(get: { data.alert != nil }, set: { if !$0 { data.alert = nil } })) { Button("OK") {} } message: { Text(data.alert ?? "") }
    }

    @ViewBuilder private var screen: some View {
        switch section {
        case .home: home
        case .dots: listScreen("Your specialist Dots", rows: data.rows("dots", from: data.workspace), name: "name", detail: "instructions")
        case .conversations: conversations
        case .pages: pages
        case .tasks: tasks
        case .memories: memories
        case .settings: settings
        }
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A calm place to think with your Dots.").font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 14) { metric("Dots", data.rows("dots", from: data.workspace).count); metric("Conversations", data.rows("conversations", from: data.workspace).count); metric("Pages", data.rows("spaces", from: data.workspace).count); metric("Scheduled", data.rows("tasks", from: data.state).count) }
            Text("Recent conversations").font(.headline)
            ForEach(Array(data.rows("conversations", from: data.workspace).prefix(6).enumerated()), id: \.offset) { _, row in Button { selectedThread = data.str(row,"id"); selectedDot = data.str(row,"dotId"); section = .conversations } label: { Label(data.str(row,"title"), systemImage: "bubble.left").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) }
            Spacer()
        }
    }
    private func metric(_ label: String, _ count: Int) -> some View { VStack(alignment: .leading, spacing: 6) { Text("\(count)").font(.title.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)) }
    private func emptyState(_ title: String, icon: String, detail: String) -> some View { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 32)).foregroundStyle(.blue.opacity(0.7)); Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    private func listScreen(_ title: String, rows: [[String: Any]], name: String, detail: String) -> some View { VStack(alignment: .leading, spacing: 16) { Text(title).font(.title3); ForEach(Array(rows.enumerated()), id: \.offset) { _, row in VStack(alignment: .leading, spacing: 6) { Text(data.str(row,name)).font(.headline); Text(data.str(row,detail)).foregroundStyle(.secondary).lineLimit(4) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 12)) }; Spacer() } }
    private var conversations: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading) {
                HStack { Text("Threads").font(.headline); Spacer(); Button { Task { await createConversation() } } label: { Image(systemName: "plus") }.help("New conversation") }
                ForEach(Array(data.rows("conversations", from: data.workspace).enumerated()), id: \.offset) { _, row in Button { selectedThread = data.str(row,"id"); selectedDot = data.str(row,"dotId"); chat.messages = [] } label: { VStack(alignment: .leading) { Text(data.str(row,"title")).font(.callout); Text(data.str(row,"dotId")).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(9).background(selectedThread == data.str(row,"id") ? .blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) }
                Spacer()
            }.frame(width: 210)
            Divider()
            VStack(spacing: 12) {
                if selectedThread.isEmpty { emptyState("Choose a conversation", icon: "bubble.left.and.bubble.right", detail: "Start a conversation with one of your Dots.") }
                else {
                    if chat.messages.isEmpty { emptyState("No messages in this session", icon: "text.bubble", detail: "This native client keeps the current session in memory. The server does not expose conversation transcript history.") }
                    ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ForEach(chat.messages) { m in HStack { if m.role == "assistant" { Text(m.text).frame(maxWidth: .infinity, alignment: .leading) } else { Spacer(); Text(m.text).padding(11).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) } } } } }
                    if let error = chat.error { Text(error).foregroundStyle(.red).font(.caption) }
                    HStack { TextField("Message your Dot…", text: $composer, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).onSubmit { send() }; Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(chat.sending || composer.isEmpty) }
                }
            }
        }
    }
    private func send() { let text = composer; composer = ""; Task { if let base = data.base { await chat.send(text, dotId: selectedDot, threadId: selectedThread, baseURL: base, token: data.token) } } }
    private func createConversation() async { let dots = data.rows("dots", from: data.workspace); guard let dot = dots.first else { data.alert = "Create a Dot before starting a conversation."; return }; do { let result = try await data.send("/api/conversations", body: ["dotId": data.str(dot,"id"), "title":"A new thought"]); selectedThread = data.str(result,"id"); selectedDot = data.str(result,"dotId"); await data.refresh() } catch { data.alert = error.localizedDescription } }
    private var pages: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { TextField("Search pages", text: $search).textFieldStyle(.roundedBorder); Picker("Space", selection: $pageSpace) { ForEach(Array(data.rows("spaces", from:data.workspace).enumerated()), id:\.offset) { _, space in Text(data.str(space,"name")).tag(data.str(space,"id")) } }.frame(width:220); Button("New Page") { pageId = ""; pageTitle = "Untitled"; pageContent = "" }.disabled(pageSpace.isEmpty) }
            HStack(alignment: .top, spacing: 14) {
                List { ForEach(Array(data.rows("spaces", from: data.workspace).enumerated()), id: \.offset) { _, space in Section(data.str(space,"name")) { ForEach(Array(filteredPages(space).enumerated()), id: \.offset) { _, p in Button(data.str(p,"title")) { selectPage(p, space: space) }.buttonStyle(.plain) } } } }.frame(width: 260)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Page title", text: $pageTitle).font(.title3)
                    TextField("Markdown content", text: $pageContent, axis: .vertical).textFieldStyle(.roundedBorder).frame(maxHeight: .infinity, alignment: .top)
                    HStack { if !pageId.isEmpty { Button("Delete", role: .destructive) { Task { await deletePage() } } }; Spacer(); Button("Save") { Task { await savePage() } }.buttonStyle(.borderedProminent) }
                }
            }
        }
    }
    private func filteredPages(_ space: [String: Any]) -> [[String: Any]] { let rows = data.rows("pages", from: space); return rows.filter { search.isEmpty || data.str($0,"title").localizedCaseInsensitiveContains(search) } }
    private func selectPage(_ page: [String: Any], space: [String: Any]) { pageId = data.str(page,"id"); pageSpace = data.str(space,"id"); pageTitle = data.str(page,"title"); pageContent = data.str(page,"content"); pageRevision = page["revision"] as? Int ?? 0 }
    private func savePage() async { do { if pageId.isEmpty { let result = try await data.send("/api/spaces/\(pageSpace)/pages", body: ["title":pageTitle,"content":pageContent]); pageId = data.str(result,"id"); pageRevision = result["revision"] as? Int ?? 1 } else { let result = try await data.send("/api/spaces/\(pageSpace)/pages/\(pageId)", method: "PATCH", body: ["title":pageTitle,"content":pageContent,"expectedRevision":pageRevision]); pageRevision = result["revision"] as? Int ?? pageRevision + 1 }; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private func deletePage() async { do { _ = try await data.send("/api/spaces/\(pageSpace)/pages/\(pageId)", method:"DELETE"); pageId = ""; pageTitle = ""; pageContent = ""; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private var tasks: some View { VStack(alignment: .leading, spacing: 12) { HStack { Picker("Conversation", selection: $selectedThread) { Text("Choose a conversation").tag(""); ForEach(Array(data.rows("conversations", from:data.workspace).enumerated()), id:\.offset) { _, thread in Text(data.str(thread,"title")).tag(data.str(thread,"id")) } }.frame(width:250); TextField("Task request", text: $taskPrompt); Button("Schedule") { Task { await createTask() } }.buttonStyle(.borderedProminent).disabled(selectedThread.isEmpty) }; ForEach(Array(data.rows("tasks", from: data.state).enumerated()), id: \.offset) { _, task in HStack { VStack(alignment:.leading) { Text(data.str(task,"prompt")); Text(data.str(task,"status")).font(.caption).foregroundStyle(.secondary) }; Spacer(); ForEach(["run","pause","cancel"], id:\.self) { action in Button(action.capitalized) { Task { await taskAction(task, action) } }.controlSize(.small) } }.padding(12).background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius:10)) }; Spacer() } }
    private func createTask() async { guard !selectedThread.isEmpty else { data.alert = "Select a conversation for this scheduled task."; return }; do { _ = try await data.send("/api/tasks", body:["prompt":taskPrompt,"threadId":selectedThread]); taskPrompt = ""; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private func taskAction(_ task:[String:Any], _ action:String) async { do { _ = try await data.send("/api/tasks/\(data.str(task,"id"))/actions", body:["action":action]); await data.refresh() } catch { data.alert = error.localizedDescription } }
    private var memories: some View { VStack(alignment:.leading, spacing:12) { HStack { TextField("Add a memory", text:$memoryText); Button("Save") { Task { do { _ = try await data.send("/api/memories", body:["text":memoryText]); memoryText = ""; await data.refresh() } catch { data.alert = error.localizedDescription } } }.buttonStyle(.borderedProminent) }; ForEach(Array(data.rows("memories", from:data.state).enumerated()), id:\.offset) { _, m in Text(data.str(m,"text")).frame(maxWidth:.infinity, alignment:.leading).padding(14).background(.blue.opacity(0.06), in:RoundedRectangle(cornerRadius:10)) }; Spacer() } }
    private var settings: some View { VStack(alignment:.leading, spacing:14) { TextField("Workspace name", text: Binding(get:{ (data.state["settings"] as? [String:Any])?["name"] as? String ?? "OpenDots" }, set:{ draft = $0 })).textFieldStyle(.roundedBorder); ForEach([("paused","Pause activity"),("researchAllowed","Allow research"),("memoryAllowed","Allow memory"),("appsAllowed","Allow connected apps")], id:\.0) { key,label in Toggle(label, isOn: Binding(get:{ ((data.state["settings"] as? [String:Any])?[key] as? Bool) ?? false }, set:{ value in Task { do { let updated = try await data.send("/api/settings", method:"PATCH", body:[key:value]); data.state["settings"] = updated } catch { data.alert = error.localizedDescription } } })) }; Button("Save name") { Task { do { data.state["settings"] = try await data.send("/api/settings", method:"PATCH", body:["name":draft]) } catch { data.alert = error.localizedDescription } } }; Text("Configuration: \((data.state["configured"] as? Bool == true) ? "Ready" : "Setup needed") · Mode: \(data.state["mode"] as? String ?? "—")").font(.caption).foregroundStyle(.secondary); Spacer() }.frame(maxWidth:500, alignment:.leading) }
}

struct LogConsole: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No output yet." : text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
