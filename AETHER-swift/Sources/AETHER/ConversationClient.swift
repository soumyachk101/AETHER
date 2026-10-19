import Foundation
import Combine

struct NativeChatMessage: Identifiable, Equatable {
    let id: String
    let role: String
    var text: String

    init(id: String = UUID().uuidString, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

@MainActor
final class NativeConversationClient: ObservableObject {
    @Published private(set) var messages: [NativeChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func load(baseURL: URL, token: String, conversationID: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let url = endpoint(baseURL, path: "/conversations/\(escaped(conversationID))/capture")
            var request = URLRequest(url: url)
            authorize(&request, token: token)
            let (data, response) = try await session.data(for: request)
            try check(response, data: data)
            guard !data.isEmpty, (try JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                messages = []
                return
            }
            let capture = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let text = capture?["text"] as? String, !text.isEmpty {
                messages = [NativeChatMessage(role: "assistant", text: text)]
            } else {
                messages = []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(_ text: String, baseURL: URL, token: String, conversationID: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }
        error = nil
        isStreaming = true
        defer { isStreaming = false }

        let userMessage = NativeChatMessage(role: "user", text: prompt)
        messages.append(userMessage)
        let assistantID = UUID().uuidString
        messages.append(NativeChatMessage(id: assistantID, role: "assistant", text: ""))
        do {
            let path = "/api/copilotkit/agent/\(escaped(conversationID))/run"
            var request = URLRequest(url: endpoint(baseURL, path: path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            authorize(&request, token: token)
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "threadId": conversationID,
                "runId": UUID().uuidString,
                "state": NSNull(),
                "messages": [["id": userMessage.id, "role": "user", "content": prompt]],
                "tools": [],
                "context": [],
                "forwardedProps": [:]
            ])
            let (bytes, response) = try await session.bytes(for: request)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                var body = ""
                for try await line in bytes.lines { body += line }
                throw serverError(status: response.statusCode, body: body)
            }
            var eventName = ""
            for try await line in bytes.lines {
                if line.hasPrefix("event:") { eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("data:") {
                    let raw = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    guard raw != "[DONE]", let data = raw.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let type = event["type"] as? String ?? eventName
                    switch type {
                    case "TEXT_MESSAGE_START":
                        if let id = event["messageId"] as? String { replaceAssistant(id: assistantID, with: id) }
                    case "TEXT_MESSAGE_CONTENT":
                        if let delta = event["delta"] as? String { append(delta, to: assistantID) }
                    case "TEXT_MESSAGE_END", "RUN_FINISHED": break
                    case "RUN_ERROR", "RUN_FAILED":
                        throw NSError(domain: "NativeConversationClient", code: 1, userInfo: [NSLocalizedDescriptionKey: event["message"] as? String ?? "The conversation turn failed."])
                    default: break
                    }
                } else if line.isEmpty { eventName = "" }
            }
            if messages.first(where: { $0.id == assistantID })?.text.isEmpty == true {
                messages.removeAll { $0.id == assistantID }
                throw NSError(domain: "NativeConversationClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "The current turn returned no response."])
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func endpoint(_ baseURL: URL, path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path)
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? value
    }

    private func authorize(_ request: inout URLRequest, token: String) {
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw serverError(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func serverError(status: Int, body: String) -> NSError {
        let message = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String])?["error"]
        return NSError(domain: "NativeConversationClient", code: status, userInfo: [NSLocalizedDescriptionKey: message ?? "Request failed (HTTP \(status))."])
    }

    private func append(_ delta: String, to id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += delta
    }

    private func replaceAssistant(id oldID: String, with newID: String) {
        guard let index = messages.firstIndex(where: { $0.id == oldID }) else { return }
        messages[index] = NativeChatMessage(id: newID, role: "assistant", text: messages[index].text)
    }
}
