import SwiftUI

private enum ClientSection: Hashable { case home, chat, tasks, memories, space(String), page(String, String), dot(String), settings }

@MainActor
final class OpenDotsClient: ObservableObject {
    @Published var tasks: [[String: Any]] = []
    @Published var conversations: [[String: Any]] = []
    @Published var dots: [[String: Any]] = []
    @Published var spaces: [[String: Any]] = []
    @Published var memories: [[String: Any]] = []
    @Published var settings: [String: Any] = [:]
    @Published var setupMissing: [String] = []
    @Published var selectedConversation = ""
    @Published var selectedDot = ""
    @Published var selectedSpace = ""
    @Published var pages: [[String: Any]] = []
    @Published var selectedPage = ""
    @Published var loading = false
    @Published var error: String?
    @Published var prompt = ""
    @Published var token: String
    @Published var draftTitle = ""
    @Published var draftContent = ""
    @Published var spaceName = ""
    @Published var dotName = ""
    @Published var dotInstructions = ""
    @Published var search = ""

    private let server: ServerController
    init(server: ServerController) {
        self.server = server
        token = UserDefaults.standard.string(forKey: "openDotsOwnerToken") ?? server.ownerToken ?? ""
    }

    func refresh() async {
        guard let url = server.serverURL else { return }
        loading = true
        defer { loading = false }
        do {
            let state = try await request(url: url, path: "/api/state")
            tasks = state["tasks"] as? [[String: Any]] ?? []
            memories = state["memories"] as? [[String: Any]] ?? []
            settings = state["settings"] as? [String: Any] ?? [:]
            let workspace = try await request(url: url, path: "/api/workspace")
            conversations = workspace["conversations"] as? [[String: Any]] ?? []
            dots = workspace["dots"] as? [[String: Any]] ?? []
            spaces = workspace["spaces"] as? [[String: Any]] ?? []
            setupMissing = (workspace["setup"] as? [String: Any])?["missing"] as? [String] ?? []
            if !conversations.contains(where: { ($0["id"] as? String) == selectedConversation }) { selectedConversation = conversations.first?["id"] as? String ?? "" }
            if !dots.contains(where: { ($0["id"] as? String) == selectedDot }) { selectedDot = dots.first?["id"] as? String ?? "" }
            if !spaces.contains(where: { ($0["id"] as? String) == selectedSpace }) { selectedSpace = spaces.first?["id"] as? String ?? "" }
            if !selectedSpace.isEmpty { await loadPages() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func loadPages() async {
        guard let url = server.serverURL, !selectedSpace.isEmpty else { pages = []; return }
        do {
            pages = try await requestArray(url: url, path: "/api/spaces/\(selectedSpace)/pages")
            if !pages.contains(where: { ($0["id"] as? String) == selectedPage }) { selectedPage = "" }
        } catch { self.error = error.localizedDescription }
    }
    func createConversation() async {
        guard let url = server.serverURL, !selectedDot.isEmpty else { error = "Create a Dot before starting a conversation."; return }
        do {
            let result = try await request(url: url, path: "/api/conversations", method: "POST", body: ["dotId": selectedDot, "title": "A new thought"])
            selectedConversation = result["id"] as? String ?? ""
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func createTask() async {
        guard let url = server.serverURL else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { error = "Enter a request with at least 3 characters."; return }
        do {
            _ = try await request(url: url, path: "/api/tasks", method: "POST", body: ["prompt": text, "threadId": selectedConversation])
            prompt = ""; await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func taskAction(_ id: String, _ action: String) async {
        guard let url = server.serverURL else { return }
        do { _ = try await request(url: url, path: "/api/tasks/\(id)/actions", method: "POST", body: ["action": action]); await refresh() }
        catch { error = error.localizedDescription }
    }
    func createSpace() async {
        guard let url = server.serverURL, !spaceName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do { let item = try await request(url: url, path: "/api/spaces", method: "POST", body: ["name": spaceName, "description": ""]); selectedSpace = item["id"] as? String ?? ""; spaceName = ""; await refresh() }
        catch { error = error.localizedDescription }
    }
    func createDot() async {
        guard let url = server.serverURL, !selectedSpace.isEmpty else { error = "Create a Space first."; return }
        do {
            let item = try await request(url: url, path: "/api/dots", method: "POST", body: ["spaceId": selectedSpace, "name": dotName, "instructions": dotInstructions, "researchAllowed": true, "memoryAllowed": true, "appsAllowed": false, "composioToolkits": []])
            selectedDot = item["id"] as? String ?? ""; dotName = ""; dotInstructions = ""; await refresh()
        } catch { error = error.localizedDescription }
    }
    func savePage() async {
        guard let url = server.serverURL, !selectedSpace.isEmpty else { return }
        do {
            if selectedPage.isEmpty {
                let p = try await request(url: url, path: "/api/spaces/\(selectedSpace)/pages", method: "POST", body: ["title": draftTitle.isEmpty ? "Untitled" : draftTitle, "content": draftContent, "parentId": NSNull()])
                selectedPage = p["id"] as? String ?? ""
            } else {
                let current = pages.first(where: { ($0["id"] as? String) == selectedPage }) ?? [:]
                _ = try await request(url: url, path: "/api/spaces/\(selectedSpace)/pages/\(selectedPage)", method: "PATCH", body: ["title": draftTitle, "content": draftContent, "expectedRevision": current["revision"] as? Int ?? 1])
            }
            await loadPages()
        } catch { error = error.localizedDescription }
    }
    func openPage(_ id: String) {
        guard let url = server.serverURL else { return }
        selectedPage = id
        Task {
            do {
                let p = try await request(url: url, path: "/api/spaces/\(selectedSpace)/pages/\(id)")
                draftTitle = p["title"] as? String ?? ""
                draftContent = p["content"] as? String ?? ""
            } catch { self.error = error.localizedDescription }
        }
    }
    func createBlankPage() { selectedPage = ""; draftTitle = ""; draftContent = "" }
    func updateSetting(_ key: String, _ value: Any) async {
        guard let url = server.serverURL else { return }
        do { _ = try await request(url: url, path: "/api/settings", method: "PATCH", body: [key: value]); await refresh() }
        catch { error = error.localizedDescription }
    }

    private func request(_ url: URL, path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: path, relativeTo: url)!)
        req.httpMethod = method; req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        UserDefaults.standard.set(token, forKey: "openDotsOwnerToken")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ServerError("The server returned an invalid response.") }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else { throw ServerError(payload["error"] as? String ?? "Request failed (HTTP \(http.statusCode)).") }
        return payload
    }
    private func requestArray(url: URL, path: String) async throws -> [[String: Any]] {
        var req = URLRequest(url: URL(string: path, relativeTo: url)!); req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ServerError("Could not load pages.") }
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerController
    @StateObject private var client: OpenDotsClient
    @State private var selection: ClientSection = .home
    @State private var showNewSpace = false
    @State private var showNewDot = false
    init(server: ServerController) { _client = StateObject(wrappedValue: OpenDotsClient(server: server)) }
    var body: some View {
        Group { if server.phase.isReady { appView } else { LaunchView() } }
            .frame(minWidth: 940, minHeight: 620)
            .task { await server.start() }
            .onChange(of: server.generation) { _ in Task { await client.refresh() } }
    }
    private var appView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("OpenDots", systemImage: "circle.grid.2x2.fill").font(.headline).tag(ClientSection.home)
                Section("WORKSPACE") {
                    Label("New chat", systemImage: "plus.bubble").tag(ClientSection.chat)
                    ForEach(client.dots.indices, id: \.self) { index in
                        let dot = client.dots[index] Label(dot["name"] as? String ?? "Dot", systemImage: "sparkle").tag(ClientSection.dot(dot["id"] as? String ?? "")) }
                }
                Section {
                    ForEach(client.spaces.indices, id: \.self) { index in
                        let space = client.spaces[index]
                        Label(space["name"] as? String ?? "Space", systemImage: "folder").tag(ClientSection.space(space["id"] as? String ?? ""))
                    }
                    Button { showNewSpace = true } label: { Label("Add Space", systemImage: "plus") }.buttonStyle(.plain)
                } header: { Text("SPACES").overlay(alignment: .trailing) { Button { showNewSpace = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) } }
                Section("RECENT CONVERSATIONS") {
                    ForEach(client.conversations.indices, id: \.self) { index in
                        let item = client.conversations[index]
                        Label(item["title"] as? String ?? "Conversation", systemImage: "bubble.left").tag(ClientSection.chat)
                            .contextMenu { Button("Open") { client.selectedConversation = item["id"] as? String ?? ""; selection = .chat } }
                    }
                    if !client.dots.isEmpty { Button { showNewDot = true } label: { Label("Create Dot", systemImage: "plus") }.buttonStyle(.plain) }
                }
                Section("LIBRARY") {
                    Label("Scheduled & activity", systemImage: "clock").tag(ClientSection.tasks)
                    Label("Memories", systemImage: "book.closed").tag(ClientSection.memories)
                }
                Section { Label("Settings & setup", systemImage: "gearshape").tag(ClientSection.settings) }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) { Circle().fill(.green).frame(width: 8, height: 8); Text("Local server connected").font(.caption).foregroundStyle(.secondary); Spacer(); Button { server.revealLog() } label: { Image(systemName: "doc.text.magnifyingglass") }.help("Server log") }
                    .padding(12).background(.bar)
            }
            .toolbar { ToolbarItem { Button { Task { await client.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(client.loading) } }
        } detail: { detailView }
        .tint(Color(red: 0.38, green: 0.45, blue: 0.73))
        .alert("New Space", isPresented: $showNewSpace) { TextField("Space name", text: $client.spaceName); Button("Cancel", role: .cancel) {}; Button("Create") { Task { await client.createSpace() } } } message: { Text("Create a place for pages and specialists.") }
        .sheet(isPresented: $showNewDot) { dotForm }
        .onChange(of: selection) { next in
            switch next {
            case .space(let id): client.selectedSpace = id; Task { await client.loadPages() }
            case .page(let space, let page): client.selectedSpace = space; if !page.isEmpty { client.openPage(page) }
            case .dot(let id): client.selectedDot = id
            default: break
            }
        }
        .task { await client.refresh() }
    }
    @ViewBuilder private var detailView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(sectionTitle).font(.title2.weight(.semibold)); Text(server.serverURL?.host ?? "OpenDots workspace").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if selection == .tasks { Button { Task { await client.updateSetting("paused", !(client.settings["paused"] as? Bool ?? false)) } } label: { Label((client.settings["paused"] as? Bool ?? false) ? "Resume all" : "Pause all", systemImage: (client.settings["paused"] as? Bool ?? false) ? "play.fill" : "pause.fill") } }
                Button { Task { await client.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }.padding(.horizontal, 24).padding(.vertical, 17).background(Color(red: 0.985, green: 0.98, blue: 0.97))
            Divider()
            if let error = client.error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
            Group {
                switch selection {
                case .home: homeScreen
                case .chat: chatScreen
                case .tasks: tasksScreen
                case .memories: memoriesScreen
                case .space: pagesScreen
                case .page: pageEditor
                case .dot(let id): dotScreen(id)
                case .settings: settingsScreen
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color(red: 0.98, green: 0.976, blue: 0.96))
    }
    private var sectionTitle: String {
        switch selection { case .home: "Your workspace"; case .chat: "Conversations"; case .tasks: "Scheduled & activity"; case .memories: "Memories"; case .space: client.spaces.first(where: { ($0["id"] as? String) == client.selectedSpace })?["name"] as? String ?? "Space"; case .page: client.draftTitle.isEmpty ? "Page" : client.draftTitle; case .dot(let id): client.dots.first(where: { ($0["id"] as? String) == id })?["name"] as? String ?? "Dot"; case .settings: "Settings & setup" }
    }
    private var homeScreen: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) { Text("A little room for your ideas.").font(.largeTitle.weight(.medium)); Text("Choose a Dot to start a conversation, or organize your work in Spaces.").foregroundStyle(.secondary) }
            HStack { summaryCard("Dots", value: "\(client.dots.count)", icon: "sparkle"); summaryCard("Spaces", value: "\(client.spaces.count)", icon: "folder"); summaryCard("Conversations", value: "\(client.conversations.count)", icon: "bubble.left") }
            HStack { Button { selection = .chat; Task { await client.createConversation() } } label: { Label("New conversation", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(client.setupMissing.count > 0 || client.dots.isEmpty); Button { showNewSpace = true } label: { Label("New Space", systemImage: "folder.badge.plus") }.buttonStyle(.bordered) }
            if !client.setupMissing.isEmpty { Label("Finish setup to enable conversations: \(client.setupMissing.joined(separator: ", "))", systemImage: "info.circle").foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12)) }
            Text("RECENT CONVERSATIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(client.conversations.prefix(6).indices, id: \.self) { index in
                let item = client.conversations[index] Button { client.selectedConversation = item["id"] as? String ?? ""; if let id = item["dotId"] as? String { client.selectedDot = id }; selection = .chat } label: { HStack { Image(systemName: "bubble.left").foregroundStyle(.indigo); Text(item["title"] as? String ?? "Conversation"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
        }.padding(28).frame(maxWidth: 900, alignment: .leading) }
    }
    private func summaryCard(_ title: String, value: String, icon: String) -> some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(.indigo); Text(value).font(.title.weight(.semibold)); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12)) }
    private var chatScreen: some View {
        VStack(spacing: 0) {
            if client.conversations.isEmpty {
                ContentUnavailableView("Start a conversation", systemImage: "bubble.left.and.bubble.right", description: Text(client.setupMissing.isEmpty ? "Choose a Dot and create a conversation." : "Set up chat services to start a conversation."))
            } else {
                HStack { Picker("Conversation", selection: $client.selectedConversation) { ForEach(client.conversations.indices, id: \.self) { index in
                        let item = client.conversations[index] Text(item["title"] as? String ?? "Conversation").tag(item["id"] as? String ?? "") } }.frame(maxWidth: 300); Picker("Dot", selection: $client.selectedDot) { ForEach(client.dots.indices, id: \.self) { index in let item = client.dots[index]; Text(item["name"] as? String ?? "Dot").tag(item["id"] as? String ?? "") } }.frame(maxWidth: 200); Spacer(); Button { Task { await client.createConversation() } } label: { Label("New", systemImage: "plus") }.disabled(client.setupMissing.count > 0) }.padding(18)
                Spacer()
                VStack(spacing: 12) { Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle).foregroundStyle(.indigo.opacity(0.7)); Text("Your conversation is ready").font(.title3.weight(.medium)); Text("Message streaming is provided by the web client's CopilotKit runtime and is not exposed as a plain JSON endpoint.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 480); Text("Use OpenDots web to send and read messages in this thread.").font(.caption).foregroundStyle(.secondary) }.padding(28)
                Spacer()
                if !client.setupMissing.isEmpty { Text("Setup required: \(client.setupMissing.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).padding() }
            }
        }
    }
    private var tasksScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Picker("Conversation", selection: $client.selectedConversation) { ForEach(client.conversations.indices, id: \.self) { index in
                        let item = client.conversations[index] Text(item["title"] as? String ?? "Conversation").tag(item["id"] as? String ?? "") } }.frame(maxWidth: 260); Spacer() }
            HStack { TextField("Add a scheduled or research request…", text: $client.prompt, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder); Button { Task { await client.createTask() } } label: { Label("Add request", systemImage: "paperplane") }.buttonStyle(.borderedProminent).disabled(client.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || client.selectedConversation.isEmpty) }
            if client.tasks.isEmpty { ContentUnavailableView("No activity yet", systemImage: "tray", description: Text("Requests and scheduled work will appear here.")) }
            else { ForEach(client.tasks.indices, id: \.self) { index in
                let task = client.tasks[index] HStack(alignment: .top) { VStack(alignment: .leading, spacing: 6) { Text(task["prompt"] as? String ?? "Request").lineLimit(3); Text(task["status"] as? String ?? "unknown").font(.caption).foregroundStyle(.secondary); if let error = task["error"] as? String, !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) } }; Spacer(); taskButtons(task) }.padding(.vertical, 5) }.listStyle(.inset) }
        }.padding(22)
    }
    @ViewBuilder private func taskButtons(_ task: [String: Any]) -> some View { let status = task["status"] as? String ?? ""; let id = task["id"] as? String ?? ""; if ["paused", "cancelled", "failed", "interrupted"].contains(status) { Button("Run") { Task { await client.taskAction(id, "run") } } } else if status != "completed" { Button("Pause") { Task { await client.taskAction(id, "pause") } } } }
    private var memoriesScreen: some View { ForEach(client.memories.indices, id: \.self) { index in
        let item = client.memories[index] VStack(alignment: .leading, spacing: 6) { Text(item["text"] as? String ?? ""); Text(Date(timeIntervalSince1970: (item["createdAt"] as? Double ?? 0) / 1000), style: .date).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 5) }.overlay { if client.memories.isEmpty { ContentUnavailableView("No memories yet", systemImage: "book.closed", description: Text("Useful notes saved by your workspace will appear here.")) } } }
    private var pagesScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { TextField("Search pages", text: $client.search).textFieldStyle(.roundedBorder).frame(maxWidth: 350); Spacer(); Button { client.createBlankPage(); selection = .page(client.selectedSpace, "") } label: { Label("New page", systemImage: "plus") }.buttonStyle(.borderedProminent) }
            if client.pages.isEmpty { ContentUnavailableView("No pages yet", systemImage: "doc.text", description: Text("Create a page to start organizing this Space.")) }
            else { List(client.pages.filter { client.search.isEmpty || (($0["title"] as? String ?? "") + " " + ($0["content"] as? String ?? "")).localizedCaseInsensitiveContains(client.search) }, id: \.self) { index in
                let page = client.pages[index] Button { client.openPage(page["id"] as? String ?? ""); selection = .page(client.selectedSpace, page["id"] as? String ?? "") } label: { VStack(alignment: .leading, spacing: 5) { Text(page["title"] as? String ?? "Untitled").font(.headline); Text((page["content"] as? String ?? "").prefix(150)).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 4) }.buttonStyle(.plain) } }
        }.padding(24).task { await client.loadPages() }
    }
    private var pageEditor: some View { VStack(alignment: .leading, spacing: 12) { TextField("Page title", text: $client.draftTitle).font(.title2).textFieldStyle(.plain); TextEditor(text: $client.draftContent).font(.body).scrollContentBackground(.hidden).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)); HStack { Text("Markdown content").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save page") { Task { await client.savePage() } }.buttonStyle(.borderedProminent) } }.padding(24) }
    private func dotScreen(_ id: String) -> some View { let dot = client.dots.first(where: { ($0["id"] as? String) == id }) ?? [:]; return ScrollView { VStack(alignment: .leading, spacing: 16) { Text(dot["instructions"] as? String ?? "A workspace specialist.").foregroundStyle(.secondary); LabeledContent("Accessible Spaces", value: client.spaces.filter { space in (dot["spaceIds"] as? [String] ?? [dot["spaceId"] as? String ?? ""]).contains(space["id"] as? String ?? "") }.compactMap { $0["name"] as? String }.joined(separator: ", ")); Button { Task { client.selectedDot = id; selection = .chat; await client.createConversation() } } label: { Label("Start conversation", systemImage: "plus.bubble") }.buttonStyle(.borderedProminent); Text("Dot settings and tool permissions can be managed in OpenDots web.").font(.caption).foregroundStyle(.secondary) }.padding(28).frame(maxWidth: 720, alignment: .leading) } }
    private var settingsScreen: some View { Form {
        Section("Workspace settings") { LabeledContent("Name", value: client.settings["name"] as? String ?? "OpenDots"); Toggle("Pause all Dots", isOn: Binding(get: { client.settings["paused"] as? Bool ?? false }, set: { value in Task { await client.updateSetting("paused", value) } })); Toggle("Allow research", isOn: Binding(get: { client.settings["researchAllowed"] as? Bool ?? false }, set: { value in Task { await client.updateSetting("researchAllowed", value) } })); Toggle("Allow memory", isOn: Binding(get: { client.settings["memoryAllowed"] as? Bool ?? false }, set: { value in Task { await client.updateSetting("memoryAllowed", value) } })); Toggle("Allow connected apps", isOn: Binding(get: { client.settings["appsAllowed"] as? Bool ?? false }, set: { value in Task { await client.updateSetting("appsAllowed", value) } })) }
        Section("API access") { SecureField("Owner access token", text: $client.token); Text("Token is stored in this Mac user's preferences and sent only to the configured local server.").font(.caption).foregroundStyle(.secondary); Text("Setup missing: \(client.setupMissing.isEmpty ? "None" : client.setupMissing.joined(separator: ", "))").font(.caption) }
        Section("Local server") { LabeledContent("Address", value: server.serverURL?.absoluteString ?? "Not connected"); LabeledContent("Status", value: server.statusText); HStack { Button("Restart Server") { Task { await server.restart() } }; Button("Reveal Server Log") { server.revealLog() } } }
    }.formStyle(.grouped).padding(20).frame(maxWidth: 760, maxHeight: .infinity) }
    private var dotForm: some View { VStack(alignment: .leading, spacing: 14) { Text("Create a Dot").font(.title2.weight(.semibold)); TextField("Name", text: $client.dotName); TextField("Role instructions", text: $client.dotInstructions, axis: .vertical).lineLimit(4...8); Picker("Default Space", selection: $client.selectedSpace) { ForEach(client.spaces.indices, id: \.self) { index in let item = client.spaces[index]; Text(item["name"] as? String ?? "Space").tag($0["id"] as? String ?? "") } }; HStack { Spacer(); Button("Cancel") { showNewDot = false }; Button("Create Dot") { Task { await client.createDot(); showNewDot = false } }.buttonStyle(.borderedProminent).disabled(client.dotName.isEmpty || client.dotInstructions.count < 3) } }.padding(24).frame(width: 430) }
}

struct LaunchView: View {
    @EnvironmentObject private var server: ServerController
    var body: some View { VStack(spacing: 18) { AetherMark(size: 72); Text("OpenDots").font(.largeTitle.weight(.semibold)); if server.phase.isBusy { ProgressView(server.statusText) } else if let message = server.phase.failedMessage { Text(message).foregroundStyle(.red).multilineTextAlignment(.center); HStack { Button("Retry") { Task { await server.start() } }; Button("Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }; Button("Server Log…") { server.revealLog() } }; LogConsole(text: server.logs) } else { Text(server.statusText).foregroundStyle(.secondary) } }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
struct AetherMark: View {
    var size: CGFloat = 64
    var body: some View { Image(systemName: "sparkles").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.25)) }
}
