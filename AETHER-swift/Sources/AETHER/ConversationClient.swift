#if os(macOS)
import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID().uuidString
    var role: String
    var text: String
    var tool: String? = nil
    var arguments: [String: AnyCodable]? = nil
    var result: String? = nil
    var rawToolArguments = ""
    var toolCallId: String? = nil
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
        guard !sending else { return }
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
        let history = messages.dropLast().filter { $0.role == "user" || $0.role == "assistant" }.map { ["id": $0.id, "role": $0.role, "content": $0.text] as [String: Any] }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "agentId": dotId,
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
            guard let http = response as? HTTPURLResponse else { throw NSError(domain: "AETHER", code: 1, userInfo: [NSLocalizedDescriptionKey: "The runtime returned an invalid response."]) }
            guard (200..<300).contains(http.statusCode) else {
                var body = Data()
                for try await byte in bytes { body.append(byte) }
                let responseObject = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                let message = responseObject?["error"] as? String ?? responseObject?["message"] as? String
                throw NSError(domain: "AETHER", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message ?? "The runtime request failed (\(http.statusCode))."])
            }
            var eventType = "", dataLines: [String] = []
            for try await line in bytes.lines {
                if line.isEmpty {
                    consume(eventType: eventType, dataLines: dataLines, assistantId: assistant.id)
                    eventType = ""; dataLines = []
                } else if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let value = String(line.dropFirst(5))
                    dataLines.append(value.hasPrefix(" ") ? String(value.dropFirst()) : value)
                }
            }
            if !dataLines.isEmpty || !eventType.isEmpty {
                self.error = "The runtime stream ended before the final event was complete."
            } else if messages.first(where: { $0.id == assistant.id })?.text.isEmpty == true && error == nil {
                self.error = "The current turn returned no response. Check the runtime connection and retry."
            }
        } catch {
            if (error as? URLError)?.code != .cancelled {
                self.error = error.localizedDescription
            }
        }
    }

    private func consume(eventType: String, dataLines: [String], assistantId: String) {
        guard !dataLines.isEmpty,
              let data = dataLines.joined(separator: "\n").data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = (event["type"] as? String) ?? eventType
        func string(_ key: String) -> String? { event[key] as? String }
        func toolIndex(_ id: String?) -> Int? {
            guard let id else { return nil }
            return messages.firstIndex(where: { $0.toolCallId == id })
        }
        switch type {
        case "TEXT_MESSAGE_START":
            guard string("role") == "assistant", let id = string("messageId") else { return }
            if !messages.contains(where: { $0.id == id }) { messages.append(ChatMessage(id: id, role: "assistant", text: "")) }
        case "TEXT_MESSAGE_CONTENT":
            guard let id = string("messageId"), let delta = string("delta"),
                  let i = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }) else { return }
            messages[i].text += delta
        case "TOOL_CALL_START":
            guard let id = string("toolCallId"), !id.isEmpty else { return }
            if let i = toolIndex(id) { messages[i].tool = string("toolCallName") ?? messages[i].tool }
            else { messages.append(ChatMessage(id: UUID().uuidString, role: "tool", text: "", tool: string("toolCallName"), toolCallId: id)) }
        case "TOOL_CALL_ARGS":
            guard let id = string("toolCallId"), let delta = string("delta"), let i = toolIndex(id) else { return }
            messages[i].rawToolArguments += delta
        case "TOOL_CALL_END":
            guard let i = toolIndex(string("toolCallId")),
                  let data = messages[i].rawToolArguments.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            messages[i].arguments = args.mapValues(AnyCodable.init)
        case "TOOL_CALL_RESULT":
            guard let i = toolIndex(string("toolCallId")) else { return }
            if let content = event["content"] { messages[i].result = String(describing: content) }
            else if let result = event["result"] { messages[i].result = String(describing: result) }
        case "RUN_ERROR", "RUN_FAILED":
            error = string("message") ?? "The assistant run failed."
        default: break
        }
        _ = assistantId
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
