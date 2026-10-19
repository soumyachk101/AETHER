#if os(macOS)
import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID().uuidString
    var role: String
    var text: String
}

@MainActor
final class ConversationClient: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var sending = false
    @Published var error: String?

    func send(_ text: String, dotId: String, threadId: String, baseURL: URL, token: String?) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(ChatMessage(role: "user", text: text))
        let assistant = ChatMessage(role: "assistant", text: "")
        messages.append(assistant)
        sending = true; error = nil
        defer { sending = false }
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("copilotkit")
            .appendingPathComponent("agent")
            .appendingPathComponent(dotId)
            .appendingPathComponent("run")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let history = messages.dropLast().map { ["id": $0.id, "role": $0.role, "content": $0.text] }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "threadId": threadId,
            "runId": UUID().uuidString,
            "state": NSNull(),
            "messages": history,
            "tools": [],
            "context": [],
            "forwardedProps": [:]
        ])
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            var eventType = "", payload = ""
            for try await line in bytes.lines {
                if line.hasPrefix("event:") { eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("data:") { payload += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                else if line.isEmpty, !payload.isEmpty {
                    if let data = payload.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let type = (event["type"] as? String) ?? eventType
                        let value = (event["delta"] as? String) ?? (event["content"] as? String) ?? ""
                        if type.contains("TEXT_MESSAGE_CONTENT") || type.contains("text_message_content") {
                            if let i = messages.lastIndex(where: { $0.id == assistant.id }) { messages[i].text += value }
                        } else if type.contains("RUN_ERROR") || type.contains("RUN_FAILED") { error = event["message"] as? String ?? "The assistant run failed." }
                    }
                    eventType = ""; payload = ""
                }
            }
            if messages.last?.text.isEmpty == true && error == nil { error = "The run ended without a text response. Earlier messages are available only in this session." }
        } catch { self.error = error.localizedDescription }
    }
}
#endif
