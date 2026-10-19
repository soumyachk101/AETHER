#if os(macOS)
import SwiftUI
import Combine

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case home = "Home", dots = "Dots", conversations = "Conversations", pages = "Spaces & Pages", tasks = "Scheduled & Activity", memories = "Memories", connections = "Connected services", computer = "Computer", settings = "Settings"
    var id: String { rawValue }
    var icon: String { ["Home":"house", "Dots":"sparkles", "Conversations":"bubble.left.and.bubble.right", "Spaces & Pages":"doc.text", "Scheduled & Activity":"clock", "Memories":"brain.head.profile", "Connected services":"link", "Computer":"desktopcomputer", "Settings":"gearshape"][rawValue] ?? "circle" }
}

@MainActor private final class Workspace: ObservableObject {
    @Published var state: [String: Any] = [:]
    @Published var workspace: [String: Any] = [:]
    @Published var alert: String?
    @Published var connections: [[String: Any]] = []
    @Published var computer: [String: Any] = [:]
    var base: URL?; var token: String?
    func load(_ server: ServerController) async {
        guard let base = server.serverURL else { return }; self.base = base; token = server.ownerToken
        do {
            state = try await get("/api/state")
            workspace = try await get("/api/workspace")
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
    func refresh() async { if base != nil { do { state = try await get("/api/state"); workspace = try await get("/api/workspace"); await loadPages() } catch { alert = error.localizedDescription } } }
    private func loadPages() async { for index in rows("spaces", from: workspace).indices { let space = rows("spaces", from: workspace)[index]; if let id = space["id"] as? String, let result = try? await get("/api/spaces/\(id)/pages") { var updated = space; updated["pages"] = result["items"] ?? []; var all = rows("spaces", from: workspace); all[index] = updated; workspace["spaces"] = all } } }
    func rows(_ key: String, from source: [String: Any]) -> [[String: Any]] { source[key] as? [[String: Any]] ?? [] }
    func str(_ row: [String: Any], _ key: String) -> String { row[key] as? String ?? "" }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerController
    @StateObject private var data = Workspace()
    @StateObject private var chat = ConversationClient()
    @State private var section: WorkspaceSection = .home
    @State private var selectedThread = ""
    @State private var selectedDot = ""
    @State private var search = ""
    @State private var draft = ""
    @State private var pageTitle = ""
    @State private var pageContent = ""
    @State private var pageId = ""
    @State private var pageSpace = ""
    @State private var pageRevision = 0
    @State private var newSpaceName = ""
    @State private var dotName = ""
    @State private var dotInstructions = ""
    @State private var dotSpace = ""
    @State private var dotResearchAllowed = true
    @State private var dotMemoryAllowed = true
    @State private var dotAppsAllowed = false
    @State private var composer = ""
    @State private var taskPrompt = ""
    @State private var memoryText = ""
    @State private var editingMemoryID = ""
    @State private var editingMemoryText = ""

    var body: some View {
        Group {
            if !server.phase.isReady { LaunchView() }
            else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) { AetherMark(size: 36); VStack(alignment: .leading) { Text("AETHER").font(.headline); Text("OpenDots workspace").font(.caption).foregroundStyle(.secondary) } }
                            .padding(.horizontal, 15).padding(.top, 18)
                        ForEach(WorkspaceSection.allCases) { item in
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
        .task {
            await server.start()
            await data.load(server)
            if pageSpace.isEmpty, let firstSpace = data.rows("spaces", from: data.workspace).first {
                pageSpace = data.str(firstSpace, "id")
            }
        }
        .alert("AETHER", isPresented: Binding(get: { data.alert != nil }, set: { if !$0 { data.alert = nil } })) { Button("OK") {} } message: { Text(data.alert ?? "") }
    }

    @ViewBuilder private var screen: some View {
        switch section {
        case .home: home
        case .dots: dots
        case .conversations: conversations
        case .pages: pages
        case .tasks: tasks
        case .memories: memories
        case .connections: connectionsView
        case .computer: computerView
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
    private var dots: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Specialists").font(.headline); Spacer(); Button("New") { resetDotForm() } }
                ForEach(Array(data.rows("dots", from: data.workspace).enumerated()), id: \.offset) { _, dot in
                    let id = data.str(dot, "id")
                    Button {
                        selectedDot = id
                        dotName = data.str(dot, "name")
                        dotInstructions = data.str(dot, "instructions")
                        dotSpace = data.str(dot, "spaceId")
                        dotResearchAllowed = dot["researchAllowed"] as? Bool ?? true
                        dotMemoryAllowed = dot["memoryAllowed"] as? Bool ?? true
                        dotAppsAllowed = dot["appsAllowed"] as? Bool ?? false
                    } label: {
                        Text(data.str(dot, "name")).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(selectedDot == id ? .blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.frame(width: 190)
            Divider()
            Form {
                TextField("Name", text: $dotName)
                TextField("Role instructions", text: $dotInstructions, axis: .vertical).lineLimit(4...10)
                Picker("Default Space", selection: $dotSpace) {
                    ForEach(Array(data.rows("spaces", from: data.workspace).enumerated()), id: \.offset) { _, space in
                        Text(data.str(space, "name")).tag(data.str(space, "id"))
                    }
                }
                Toggle("Allow research", isOn: $dotResearchAllowed)
                Toggle("Allow memory", isOn: $dotMemoryAllowed)
                Toggle("Allow connected apps", isOn: $dotAppsAllowed)
                HStack {
                    Spacer()
                    Button(selectedDot.isEmpty ? "Create Dot" : "Save Dot") { Task { await saveDot() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(dotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dotInstructions.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || dotSpace.isEmpty)
                }
            }.formStyle(.grouped)
        }
    }
    private func resetDotForm() {
        selectedDot = ""; dotName = ""; dotInstructions = ""
        dotSpace = data.str(data.rows("spaces", from: data.workspace).first ?? [:], "id")
        dotResearchAllowed = true; dotMemoryAllowed = true; dotAppsAllowed = false
    }
    private func saveDot() async {
        let body: [String: Any] = ["name":dotName, "instructions":dotInstructions, "researchAllowed":dotResearchAllowed, "memoryAllowed":dotMemoryAllowed, "appsAllowed":dotAppsAllowed, "composioToolkits":[], "spaceId":dotSpace, "spaceIds":[dotSpace]]
        do {
            let path = selectedDot.isEmpty ? "/api/dots" : "/api/dots/\(selectedDot)"
            let result = try await data.send(path, method: selectedDot.isEmpty ? "POST" : "PUT", body: body)
            selectedDot = data.str(result, "id"); await data.refresh()
        } catch { data.alert = error.localizedDescription }
    }
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
            HStack {
                TextField("New Space", text: $newSpaceName).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Button("Create Space") { Task { await createSpace() } }
                    .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(alignment: .top, spacing: 14) {
                List {
                    ForEach(Array(data.rows("spaces", from: data.workspace).enumerated()), id: \.offset) { _, space in
                        SwiftUI.Section(data.str(space, "name")) {
                            ForEach(Array(filteredPages(space).enumerated()), id: \.offset) { _, page in
                                Button(data.str(page, "title")) { selectPage(page, space: space) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: 260)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Page title", text: $pageTitle).font(.title3)
                    TextField("Markdown content", text: $pageContent, axis: .vertical).textFieldStyle(.roundedBorder).frame(maxHeight: .infinity, alignment: .top)
                    HStack { if !pageId.isEmpty { Button("Delete", role: .destructive) { Task { await deletePage() } } }; Spacer(); Button("Save") { Task { await savePage() } }.buttonStyle(.borderedProminent) }
                }
            }
        }
    }
    private func filteredPages(_ space: [String: Any]) -> [[String: Any]] { let rows = data.rows("pages", from: space); return rows.filter { search.isEmpty || data.str($0,"title").localizedCaseInsensitiveContains(search) } }
    private func createSpace() async {
        do {
            let result = try await data.send("/api/spaces", body: ["name": newSpaceName, "description": ""])
            pageSpace = data.str(result, "id"); newSpaceName = ""; await data.refresh()
        } catch { data.alert = error.localizedDescription }
    }
    private func selectPage(_ page: [String: Any], space: [String: Any]) { pageId = data.str(page,"id"); pageSpace = data.str(space,"id"); pageTitle = data.str(page,"title"); pageContent = data.str(page,"content"); pageRevision = page["revision"] as? Int ?? 0 }
    private func savePage() async { do { if pageId.isEmpty { let result = try await data.send("/api/spaces/\(pageSpace)/pages", body: ["title":pageTitle,"content":pageContent]); pageId = data.str(result,"id"); pageRevision = result["revision"] as? Int ?? 1 } else { let result = try await data.send("/api/spaces/\(pageSpace)/pages/\(pageId)", method: "PATCH", body: ["title":pageTitle,"content":pageContent,"expectedRevision":pageRevision]); pageRevision = result["revision"] as? Int ?? pageRevision + 1 }; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private func deletePage() async { do { _ = try await data.send("/api/spaces/\(pageSpace)/pages/\(pageId)", method:"DELETE"); pageId = ""; pageTitle = ""; pageContent = ""; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private var tasks: some View { VStack(alignment: .leading, spacing: 12) { HStack { Picker("Conversation", selection: $selectedThread) { Text("Choose a conversation").tag(""); ForEach(Array(data.rows("conversations", from:data.workspace).enumerated()), id:\.offset) { _, thread in Text(data.str(thread,"title")).tag(data.str(thread,"id")) } }.frame(width:250); TextField("Task request", text: $taskPrompt); Button("Schedule") { Task { await createTask() } }.buttonStyle(.borderedProminent).disabled(selectedThread.isEmpty) }; ForEach(Array(data.rows("tasks", from: data.state).enumerated()), id: \.offset) { _, task in HStack { VStack(alignment:.leading) { Text(data.str(task,"prompt")); Text(data.str(task,"status")).font(.caption).foregroundStyle(.secondary) }; Spacer(); ForEach(["run","pause","cancel"], id:\.self) { action in Button(action.capitalized) { Task { await taskAction(task, action) } }.controlSize(.small) } }.padding(12).background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius:10)) }; Spacer() } }
    private func createTask() async { guard !selectedThread.isEmpty else { data.alert = "Select a conversation for this scheduled task."; return }; do { _ = try await data.send("/api/tasks", body:["prompt":taskPrompt,"threadId":selectedThread]); taskPrompt = ""; await data.refresh() } catch { data.alert = error.localizedDescription } }
    private func taskAction(_ task:[String:Any], _ action:String) async { do { _ = try await data.send("/api/tasks/\(data.str(task,"id"))/actions", body:["action":action]); await data.refresh() } catch { data.alert = error.localizedDescription } }
    private var memories: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Add a memory", text: $memoryText)
                Button("Save") {
                    Task {
                        do { _ = try await data.send("/api/memories", body: ["text": memoryText]); memoryText = ""; await data.refresh() }
                        catch { data.alert = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent)
            }
            ForEach(Array(data.rows("memories", from: data.state).enumerated()), id: \.offset) { _, memory in
                let id = data.str(memory, "id")
                HStack {
                    if editingMemoryID == id {
                        TextField("Memory", text: $editingMemoryText)
                        Button("Save") {
                            Task {
                                do { _ = try await data.send("/api/memories/\(id)", method: "PUT", body: ["text": editingMemoryText]); editingMemoryID = ""; await data.refresh() }
                                catch { data.alert = error.localizedDescription }
                            }
                        }
                    } else {
                        Text(data.str(memory, "text")).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Edit") { editingMemoryID = id; editingMemoryText = data.str(memory, "text") }
                        Button("Delete", role: .destructive) {
                            Task {
                                do { _ = try await data.send("/api/memories/\(id)", method: "DELETE"); await data.refresh() }
                                catch { data.alert = error.localizedDescription }
                            }
                        }
                    }
                }
                .padding(14)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }
    }
    private var settings: some View { VStack(alignment:.leading, spacing:14) { TextField("Workspace name", text: Binding(get:{ (data.state["settings"] as? [String:Any])?["name"] as? String ?? "OpenDots" }, set:{ draft = $0 })).textFieldStyle(.roundedBorder); ForEach([("paused","Pause activity"),("researchAllowed","Allow research"),("memoryAllowed","Allow memory"),("appsAllowed","Allow connected apps")], id:\.0) { key,label in Toggle(label, isOn: Binding(get:{ ((data.state["settings"] as? [String:Any])?[key] as? Bool) ?? false }, set:{ value in Task { do { let updated = try await data.send("/api/settings", method:"PATCH", body:[key:value]); data.state["settings"] = updated } catch { data.alert = error.localizedDescription } } })) }; Button("Save name") { Task { do { data.state["settings"] = try await data.send("/api/settings", method:"PATCH", body:["name":draft]) } catch { data.alert = error.localizedDescription } } }; Text("Configuration: \((data.state["configured"] as? Bool == true) ? "Ready" : "Setup needed") · Mode: \(data.state["mode"] as? String ?? "—")").font(.caption).foregroundStyle(.secondary); Spacer() }.frame(maxWidth:500, alignment:.leading) }

    private var connectionsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connected services").font(.title3)
            Picker("Dot", selection: $selectedDot) { ForEach(Array(data.rows("dots", from: data.workspace).enumerated()), id: \.offset) { _, dot in Text(data.str(dot,"name")).tag(data.str(dot,"id")) } }
                .onChange(of: selectedDot) { _ in Task { await loadConnections() } }
            HStack { TextField("Service name", text: $draft); TextField("MCP server URL", text: $composer); SecureField("Bearer token (optional)", text: $memoryText); Button("Connect") { Task { do { let c = try await data.send("/api/dots/\(selectedDot)/connections", body:["name":draft,"url":composer,"token":memoryText]); data.connections.append(c); draft = ""; composer = ""; memoryText = "" } catch { data.alert = error.localizedDescription } } }.disabled(selectedDot.isEmpty || draft.isEmpty || composer.isEmpty) }
            if data.connections.isEmpty { emptyState("No connected services", icon: "link", detail: "Connect an MCP server to give this Dot additional tools.") }
            List { ForEach(Array(data.connections.enumerated()), id: \.offset) { _, connection in VStack(alignment: .leading, spacing: 8) { HStack { Text(data.str(connection,"name")).font(.headline); Spacer(); Button("Refresh tools") { Task { do { let next = try await data.send("/api/connections/\(data.str(connection,"id"))/refresh"); replaceConnection(next) } catch { data.alert = error.localizedDescription } } }; Button("Remove", role: .destructive) { Task { do { _ = try await data.send("/api/connections/\(data.str(connection,"id"))", method:"DELETE"); data.connections.removeAll { data.str($0,"id") == data.str(connection,"id") } } catch { data.alert = error.localizedDescription } } } }; ForEach(Array((connection["tools"] as? [[String:Any]] ?? []).enumerated()), id: \.offset) { _, tool in HStack { Toggle(data.str(tool,"title"), isOn: Binding(get:{ tool["enabled"] as? Bool ?? false }, set:{ enabled in Task { do { let next = try await data.send("/api/connections/\(data.str(connection,"id"))/tools/\(data.str(tool,"name"))", method:"PATCH", body:["enabled":enabled]); replaceConnection(next) } catch { data.alert = error.localizedDescription } } })).toggleStyle(.checkbox); Toggle("Ask first", isOn: Binding(get:{ tool["requiresApproval"] as? Bool ?? true }, set:{ enabled in Task { do { let next = try await data.send("/api/connections/\(data.str(connection,"id"))/tools/\(data.str(tool,"name"))", method:"PATCH", body:["requiresApproval":enabled]); replaceConnection(next) } catch { data.alert = error.localizedDescription } } })).toggleStyle(.checkbox).disabled(!(tool["enabled"] as? Bool ?? false)) } } } } }
            Text("Voice calls are unavailable in this native client: the server requires a WebRTC SDP offer, and this project has no native WebRTC implementation.").font(.caption).foregroundStyle(.secondary)
        }.task { await loadConnections() }
    }
    private func loadConnections() async { guard !selectedDot.isEmpty else { return }; do { let result = try await data.get("/api/dots/\(selectedDot)/connections"); data.connections = result["items"] as? [[String:Any]] ?? [] } catch { data.alert = error.localizedDescription } }
    private func replaceConnection(_ connection: [String:Any]) { let id = data.str(connection,"id"); if let i = data.connections.firstIndex(where: { data.str($0,"id") == id }) { data.connections[i] = connection } }
    private var computerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Dot", selection: $selectedDot) { ForEach(Array(data.rows("dots", from: data.workspace).enumerated()), id: \.offset) { _, dot in Text(data.str(dot,"name")).tag(data.str(dot,"id")) } }
            HStack { Text("Computer: \(data.str(data.computer,"state").replacingOccurrences(of:"_", with:" "))"); Spacer(); Button("Refresh") { Task { await loadComputer() } }; Button("Start") { Task { await computerAction("start") } }; Button("Stop") { Task { await computerAction("stop") } } }
            if data.computer["configured"] as? Bool == false { emptyState("Computer service not configured", icon:"desktopcomputer", detail:"Configure the server’s computer service URL and token, then restart the server.") }
            Form { Toggle("Enable computer", isOn: Binding(get:{ (data.computer["permissions"] as? [String:Any])?["enabled"] as? Bool ?? false }, set:{ v in Task { await setComputerPermission("enabled", v) } })); Toggle("Browser", isOn: Binding(get:{ (data.computer["permissions"] as? [String:Any])?["browser"] as? Bool ?? false }, set:{ v in Task { await setComputerPermission("browser", v) } })); Toggle("Files", isOn: Binding(get:{ (data.computer["permissions"] as? [String:Any])?["files"] as? Bool ?? false }, set:{ v in Task { await setComputerPermission("files", v) } })); Toggle("Terminal", isOn: Binding(get:{ (data.computer["permissions"] as? [String:Any])?["shell"] as? Bool ?? false }, set:{ v in Task { await setComputerPermission("shell", v) } })) }.formStyle(.grouped)
            Text("Computer actions can be managed through chat when enabled. Human screen control and live browser interaction are not implemented in this client.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.task { await loadComputer() }.onChange(of: selectedDot) { _ in Task { await loadComputer() } }
    }
    private func loadComputer() async { guard !selectedDot.isEmpty else { return }; do { data.computer = try await data.get("/api/dots/\(selectedDot)/computer") } catch { data.alert = error.localizedDescription } }
    private func computerAction(_ action: String) async { do { data.computer = try await data.send("/api/dots/\(selectedDot)/computer/\(action)"); } catch { data.alert = error.localizedDescription } }
    private func setComputerPermission(_ key: String, _ value: Bool) async { do { data.computer = try await data.send("/api/dots/\(selectedDot)/computer/permissions", method:"PATCH", body:[key:value]) } catch { data.alert = error.localizedDescription } }
}

private struct LaunchView: View {
    @EnvironmentObject private var server: ServerController

    var body: some View {
        VStack(spacing: 18) {
            AetherMark(size: 72)
            Text("AETHER").font(.largeTitle.weight(.semibold))
            if server.phase.isBusy {
                ProgressView(server.statusText)
            } else if let message = server.phase.failedMessage {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                HStack {
                    Button("Retry") { Task { await server.start() } }
                    Button("Reveal Log") { server.revealLog() }
                }
                LogConsole(text: server.logs).frame(maxWidth: 720, maxHeight: 220)
            } else {
                Text(server.statusText).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AetherMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.25)
            )
    }
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
