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
    var decision: Bool? = nil
    var actionError: String? = nil
    var parentAssistantId: String? = nil
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

    func send(_ text: String, dotId: String, threadId: String, baseURL: URL, token: String?) async -> Bool {
        guard !sending else { return false }
        sending = true
        error = nil
        defer { sending = false }

        let pageContext: [String: Any]
        do {
            pageContext = try await api("/api/conversations/\(threadId)/page-context", baseURL: baseURL, token: token)
        } catch {
            self.error = "Conversation context could not load. Retry before sending your message."
            return false
        }
        var content = text
        if let pageId = pageContext["id"] as? String,
           let spaceId = pageContext["spaceId"] as? String,
           let title = pageContext["title"] as? String {
            let cleanTitle = title.filter { !"[]\\\r\n".contains($0) }
            content = "From [\(cleanTitle)](/#/spaces/\(spaceId)/pages/\(pageId)):\n\n\(text)"
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ChatMessage(role: "user", text: content))
            messages.append(ChatMessage(role: "assistant", text: ""))
        }
        guard let assistant = messages.last(where: { $0.role == "assistant" }) else { return false }
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
        let history = runHistory(excludingAssistantId: assistant.id)
        let tools: [[String: Any]] = [
            ["name": "review_space_page", "description": "Present a Markdown draft for human review before saving it into an authorized Space. The user can approve and save, or decline. Do not create the page yourself after this tool: its approved result includes the saved page URL. Call once, then wait for the review result.", "parameters": ["type": "object", "properties": ["title": ["type": "string", "minLength": 1, "maxLength": 160], "content": ["type": "string", "minLength": 1, "maxLength": 20000], "spaceId": ["type": "string", "minLength": 1]], "required": ["title", "content", "spaceId"], "additionalProperties": false]],
            ["name": "request_connection_action", "description": "Ask the owner to approve a connected-service action that changes something (sends, creates, updates, deletes). Use only after a connection tool returned approval_required. Pass its approvalId and a one-sentence summary of the effect. Call once, then wait: the result contains the service response if approved.", "parameters": ["type": "object", "properties": ["approvalId": ["type": "string", "minLength": 1, "maxLength": 64], "summary": ["type": "string", "minLength": 1, "maxLength": 500]], "required": ["approvalId", "summary"], "additionalProperties": false]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "agentId": dotId,
            "threadId": threadId,
            "runId": UUID().uuidString,
            "state": NSNull(),
            "messages": history,
            "tools": tools,
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
            } else if let latestAssistant = messages.last(where: { $0.role == "assistant" }),
                      latestAssistant.text.isEmpty,
                      !messages.contains(where: { $0.role == "tool" && $0.parentAssistantId == latestAssistant.id && $0.tool != nil }),
                      error == nil {
                self.error = "The current turn returned no response. Check the runtime connection and retry."
            }
        } catch {
            if (error as? URLError)?.code != .cancelled {
                self.error = error.localizedDescription
            }
        }
        return error == nil
    }

    private func runHistory(excludingAssistantId: String) -> [[String: Any]] {
        messages.compactMap { message in
            if message.role == "tool" {
                if message.tool != nil { return nil }
                guard let callId = message.toolCallId else { return nil }
                return ["id": message.id, "role": "tool", "toolCallId": callId, "content": message.result ?? ""]
            }
            guard message.role == "user" || message.role == "assistant" else { return nil }
            if message.role == "assistant", message.id == excludingAssistantId { return nil }
            var item: [String: Any] = ["id": message.id, "role": message.role, "content": message.text]
            let calls = messages.filter { $0.role == "tool" && $0.parentAssistantId == message.id && $0.tool != nil }
            if !calls.isEmpty { item["toolCalls"] = calls.compactMap { call in
                guard let id = call.toolCallId, let name = call.tool,
                      let data = try? JSONSerialization.data(withJSONObject: call.arguments?.mapValues { $0.value } ?? [:]),
                      let arguments = String(data: data, encoding: .utf8) else { return nil }
                return ["id": id, "type": "function", "function": ["name": name, "arguments": arguments]] as [String: Any]
            } }
            return item
        }
    }

    func decideTool(_ messageId: String, approve: Bool, dotId: String, threadId: String, baseURL: URL, token: String?) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }), let tool = messages[index].tool, let callId = messages[index].toolCallId else { return }
        do {
            var result: [String: Any]
            let args = messages[index].arguments?.mapValues { $0.value } ?? [:]
            if !approve {
                result = ["approved": false, "message": tool == "review_space_page" ? "The owner declined this draft. Do not save it." : "The owner declined this action. Do not perform it or try another way."]
            } else if tool == "review_space_page" {
                var payload = args; payload["toolCallId"] = callId
                result = try await api("/api/conversations/\(threadId)/reviewed-page", method: "POST", body: payload, baseURL: baseURL, token: token)
                result = ["approved": true, "pageId": result["id"] ?? "", "spaceId": result["spaceId"] ?? "", "url": "/#/spaces/\(result["spaceId"] ?? "")/pages/\(result["id"] ?? "")"]
            } else {
                guard let approvalId = args["approvalId"] as? String else { throw NSError(domain: "AETHER", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing approval ID."]) }
                result = try await api("/api/conversations/\(threadId)/connection-actions", method: "POST", body: ["toolCallId": callId, "approvalId": approvalId], baseURL: baseURL, token: token)
                result["approved"] = true
            }
            messages[index].decision = approve
            messages[index].result = String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)
            let toolResult = ChatMessage(role: "tool", text: "", result: messages[index].result, toolCallId: callId)
            messages.append(toolResult)
            messages.append(ChatMessage(role: "assistant", text: ""))
            _ = await send("", dotId: dotId, threadId: threadId, baseURL: baseURL, token: token)
        } catch { messages[index].actionError = error.localizedDescription }
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
            if let i = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[i].id = id
            } else if !messages.contains(where: { $0.id == id }) {
                messages.append(ChatMessage(id: id, role: "assistant", text: ""))
            }
        case "TEXT_MESSAGE_CONTENT":
            guard let id = string("messageId"), let delta = string("delta"),
                  let i = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }) else { return }
            messages[i].text += delta
        case "TOOL_CALL_START":
            guard let id = string("toolCallId"), !id.isEmpty else { return }
            if let i = toolIndex(id) { messages[i].tool = string("toolCallName") ?? messages[i].tool }
            else {
                let parentId = messages.last(where: { $0.role == "assistant" })?.id ?? assistantId
                messages.append(ChatMessage(id: UUID().uuidString, role: "tool", text: "", tool: string("toolCallName"), toolCallId: id, parentAssistantId: parentId))
            }
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
