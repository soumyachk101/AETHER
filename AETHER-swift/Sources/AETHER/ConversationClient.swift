#if os(macOS)
import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID().uuidString
    var role: String
    var text: String
    var tool: String? = nil
    var arguments: [String: AnyCodable]? = nil
    var result: String? = nil
}

struct AnyCodable: Codable { let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); value = (try? c.decode(String.self)) ?? (try? c.decode(Double.self)) ?? (try? c.decode(Bool.self)) ?? NSNull() }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); if let v = value as? String { try c.encode(v) } else if let v = value as? Double { try c.encode(v) } else if let v = value as? Bool { try c.encode(v) } else { try c.encodeNil() } }
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
        let history = messages.dropLast().map { ["id": $0.id, "role": $0.role, "content": $0.text] as [String: Any] }
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
                        } else if type.contains("TOOL_CALL") || type.contains("tool_call") {
                            let name = event["toolName"] as? String ?? event["name"] as? String ?? ""
                            let id = event["toolCallId"] as? String ?? event["toolCallID"] as? String ?? UUID().uuidString
                            let args = (event["args"] as? [String: Any]) ?? (event["arguments"] as? [String: Any]) ?? [:]
                            if !name.isEmpty, !messages.contains(where: { $0.id == id }) { messages.append(ChatMessage(id: id, role: "tool", text: "", tool: name, arguments: args.mapValues(AnyCodable.init))) }
                        } else if type.contains("TOOL_RESULT") || type.contains("tool_result") {
                            let id = event["toolCallId"] as? String ?? event["toolCallID"] as? String ?? ""
                            if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].result = String(describing: event["content"] ?? event["result"] ?? "") }
                        } else if type.contains("RUN_ERROR") || type.contains("RUN_FAILED") { error = event["message"] as? String ?? "The assistant run failed." }
                    }
                    eventType = ""; payload = ""
                }
            }
            if messages.last?.text.isEmpty == true && error == nil { error = "The run ended without a text response. Earlier messages are available only in this session." }
        } catch { self.error = error.localizedDescription }
    }

    func api(_ path: String, method: String = "GET", body: [String: Any]? = nil, baseURL: URL, token: String?) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = try? JSONSerialization.jsonObject(with: data); let value = object as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw NSError(domain: "AETHER", code: 1, userInfo: [NSLocalizedDescriptionKey: value["error"] as? String ?? "Request failed."]) }
        return value
    }
}
#endif
