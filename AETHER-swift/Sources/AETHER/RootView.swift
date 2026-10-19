import SwiftUI

@MainActor
final class OpenDotsClient: ObservableObject {
    @Published var tasks: [[String: Any]] = []
    @Published var loading = false
    @Published var error: String?
    @Published var prompt = ""
    @Published var token: String

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
            error = nil
        } catch { error = error.localizedDescription }
    }

    func createTask() async {
        guard let url = server.serverURL else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { error = "Enter a request with at least 3 characters."; return }
        loading = true
        defer { loading = false }
        do {
            _ = try await request(url: url, path: "/api/tasks", method: "POST", body: ["prompt": text])
            prompt = ""
            await refresh()
        } catch { error = error.localizedDescription }
    }

    func act(_ id: String, action: String) async {
        guard let url = server.serverURL else { return }
        loading = true
        defer { loading = false }
        do {
            _ = try await request(url: url, path: "/api/tasks/\(id)/actions", method: "POST", body: ["action": action])
            await refresh()
        } catch { error = error.localizedDescription }
    }

    private func request(url: URL, path: String, method: String = "GET", body: [String: String]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: path, relativeTo: url)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        UserDefaults.standard.set(token, forKey: "openDotsOwnerToken")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError("The server returned an invalid response.") }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw ServerError(payload["error"] as? String ?? "Request failed (HTTP \(http.statusCode)).")
        }
        return payload
    }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerController
    @StateObject private var client: OpenDotsClient

    init(server: ServerController) { _client = StateObject(wrappedValue: OpenDotsClient(server: server)) }

    var body: some View {
        Group {
            if server.phase.isReady {
                clientView
            } else {
                LaunchView()
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .task { await server.start() }
        .onChange(of: server.generation) { _ in Task { await client.refresh() } }
    }

    private var clientView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AetherMark(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenDots").font(.title2.weight(.semibold))
                    Text(server.serverURL?.absoluteString ?? "Local server").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await client.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(client.loading)
                Button("Restart Server") { Task { await server.restart() } }
            }
            if !client.token.isEmpty { EmptyView() }
            GroupBox("Owner access token") {
                SecureField("Bearer token (if required)", text: $client.token)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = client.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
            }
            GroupBox("New request") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $client.prompt).frame(minHeight: 70)
                    Button { Task { await client.createTask() } } label: {
                        if client.loading { ProgressView().controlSize(.small) } else { Label("Add request", systemImage: "paperplane") }
                    }.buttonStyle(.borderedProminent).disabled(client.loading)
                }.padding(4)
            }
            Text("Requests").font(.headline)
            if client.loading && client.tasks.isEmpty { ProgressView("Loading OpenDots…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if client.tasks.isEmpty { ContentUnavailableView("No requests yet", systemImage: "tray", description: Text("Add a request above to create a task.")) }
            else {
                List(client.tasks, id: \.id) { task in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task["prompt"] as? String ?? "Request").lineLimit(3)
                            Text(task["status"] as? String ?? "unknown").font(.caption).foregroundStyle(.secondary)
                            if let message = task["error"] as? String, !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
                        }
                        Spacer()
                        let status = task["status"] as? String ?? ""
                        let id = task["id"] as? String ?? ""
                        if status == "paused" || status == "cancelled" || status == "failed" {
                            Button("Run") { Task { await client.act(id, action: "run") } }
                        } else if status != "completed" {
                            Button("Pause") { Task { await client.act(id, action: "pause") } }
                        }
                    }.padding(.vertical, 4)
                }
            }
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Connected to OpenDots API").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Server Log…") { server.revealLog() }
            }
        }
        .padding(20)
        .task { await client.refresh() }
    }
}

struct LaunchView: View {
    @EnvironmentObject private var server: ServerController
    var body: some View {
        VStack(spacing: 18) {
            AetherMark(size: 72)
            Text("OpenDots").font(.largeTitle.weight(.semibold))
            if server.phase.isBusy { ProgressView(server.statusText) }
            else if let message = server.phase.failedMessage {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                HStack {
                    Button("Retry") { Task { await server.start() } }
                    Button("Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                    Button("Server Log…") { server.revealLog() }
                }
                LogConsole(text: server.logs)
            } else { Text(server.statusText).foregroundStyle(.secondary) }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AetherMark: View {
    var size: CGFloat = 64
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct LogConsole: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No output yet." : text)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.frame(maxHeight: 220).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
