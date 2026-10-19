#if os(macOS)
import Foundation
import Combine
import WebRTC

@MainActor
final class VoiceClient: NSObject, ObservableObject {
    @Published private(set) var status = "idle"
    @Published private(set) var error: String?
    @Published private(set) var muted = false
    @Published private(set) var speakerMuted = false
    @Published private(set) var phase = "listening"
    @Published private(set) var caption = ""
    @Published private(set) var userCaption = ""
    @Published private(set) var elapsed = 0

    private var baseURL: URL?
    private var token: String?
    private var anchorMessageId: String?
    private var peer: RTCPeerConnection?
    private var factory: RTCPeerConnectionFactory?
    private var channel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var remoteAudioTrack: RTCAudioTrack?
    private var callId: String?
    private var transcript: [String] = []
    private var pollTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?

    func start(threadId: String, baseURL: URL, token: String?, anchorMessageId: String?) async {
        guard status == "idle" else { return }
        self.baseURL = baseURL; self.token = token; self.anchorMessageId = anchorMessageId
        status = "connecting"; error = nil; muted = false; speakerMuted = false
        phase = "listening"; caption = ""; userCaption = ""; transcript = []; elapsed = 0
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
                self.factory = factory
                let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
                let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
                    continuation.resume(throwing: URLError(.cannotCreateFile)); return
                }
                peer = pc
                let source = factory.audioSource(with: constraints)
                let track = factory.audioTrack(with: source, trackId: "aether-mic")
                audioTrack = track; pc.add(track, streamIds: ["aether-audio"])
                let channel = pc.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration())
                self.channel = channel; channel?.delegate = self
                pc.offer(for: constraints) { [weak self] offer, error in
                    guard let self, let offer, error == nil else {
                        continuation.resume(throwing: error ?? URLError(.cannotCreateFile)); return
                    }
                    pc.setLocalDescription(offer) { setError in
                        guard setError == nil else { continuation.resume(throwing: setError!); return }
                        Task { @MainActor in
                            do {
                                let response = try await self.api("/api/voice/calls", method: "POST", body: ["threadId": threadId, "sdp": offer.sdp])
                                guard let id = response["id"] as? String, let sdp = response["sdp"] as? String else { throw URLError(.cannotParseResponse) }
                                self.callId = id
                                pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { remoteError in
                                    if let remoteError { continuation.resume(throwing: remoteError) }
                                    else { continuation.resume() }
                                }
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                }
            }
            pollTask = Task { await pollStatus() }
            limitTask = Task { try? await Task.sleep(for: .seconds(900)); if !Task.isCancelled { await end() } }
        } catch {
            self.error = error.localizedDescription
            if let callId { try? await finishCall(id: callId) }
            cleanup(); status = "idle"
        }
    }

    func toggleMute() { muted.toggle(); audioTrack?.isEnabled = !muted }
    func toggleSpeaker() { speakerMuted.toggle(); remoteAudioTrack?.isEnabled = !speakerMuted }

    func end() async {
        guard status != "idle", status != "ending" else { return }
        status = "ending"; pollTask?.cancel(); limitTask?.cancel(); durationTask?.cancel(); disconnectTask?.cancel()
        audioTrack?.isEnabled = false
        if let id = callId {
            do { try await finishCall(id: id) }
            catch { self.error = "Call ended, but its receipt could not be saved: \(error.localizedDescription)" }
        }
        cleanup(); status = "idle"
    }

    private func finishCall(id: String) async throws {
        _ = try await api("/api/voice/calls/\(id)/end", method: "POST", body: ["transcript": transcript.joined(separator: "\n").prefix(20000).description, "anchorMessageId": anchorMessageId as Any? ?? NSNull()])
    }

    private func pollStatus() async {
        var failures = 0
        while !Task.isCancelled, status == "connecting" || status == "active" {
            try? await Task.sleep(for: .seconds(2)); guard let id = callId else { continue }
            do { let value = try await api("/api/voice/calls/\(id)"); failures = 0; if value["endedAt"] is Int && !(value["endedAt"] is NSNull) { await end(); return } }
            catch { failures += 1; if failures >= 3 { self.error = "Call control connection was lost."; await end(); return } }
        }
    }

    private func api(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw NSError(domain: "AETHER", code: 1, userInfo: [NSLocalizedDescriptionKey: value["error"] as? String ?? "Request failed."]) }
        return value
    }

    private func cleanup() {
        pollTask?.cancel(); limitTask?.cancel(); durationTask?.cancel(); disconnectTask?.cancel()
        channel?.delegate = nil; channel?.close(); peer?.close()
        channel = nil; peer = nil; factory = nil; audioTrack = nil; remoteAudioTrack = nil; callId = nil
    }

    private func receive(_ text: String) {
        guard let data = text.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = event["type"] as? String else { return }
        switch type {
        case "input_audio_buffer.speech_started": phase = "listening"; caption = ""
        case "response.created": phase = "thinking"; caption = ""
        case "output_audio_buffer.stopped": phase = "listening"
        case "response.output_audio_transcript.delta": phase = "speaking"; caption += event["delta"] as? String ?? ""
        case "conversation.item.input_audio_transcription.completed":
            if let value = event["transcript"] as? String { transcript.append("You: \(value)"); userCaption = value }
        case "response.output_audio_transcript.done": if let value = event["transcript"] as? String { transcript.append("Dot: \(value)") }
        case "error": error = "The voice provider reported a session error. End the call and retry."
        case "response.function_call_arguments.done": Task { await handleCompute(event) }
        default: break
        }
    }

    private func handleCompute(_ event: [String: Any]) async {
        guard event["name"] as? String == "ask_compute", let call = event["call_id"] as? String, let id = callId,
              let arguments = event["arguments"] as? String, let bytes = arguments.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let request = args["request"] as? String else { return }
        phase = "thinking"; var output = ""
        do { output = try await api("/api/voice/calls/\(id)/compute", method: "POST", body: ["toolCallId": call, "request": request, "transcript": String(transcript.joined(separator: "\n").suffix(12000))])["text"] as? String ?? "" }
        catch { output = "Compute failed: \(error.localizedDescription)" }
        guard let channel, channel.readyState == .open else { return }
        for value in [["type":"conversation.item.create", "item":["type":"function_call_output", "call_id":call, "output":output]], ["type":"response.create"]] {
            if let data = try? JSONSerialization.data(withJSONObject: value) { channel.sendData(RTCDataBuffer(data: data, isBinary: false)) }
        }
    }
}

extension VoiceClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let track = stream.audioTracks.first else { return }
        Task { @MainActor in remoteAudioTrack = track; track.isEnabled = !speakerMuted }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor in remoteAudioTrack = nil }
    }
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            if newState == .connected { disconnectTask?.cancel(); disconnectTask = nil; status = "active"; if durationTask == nil { durationTask = Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); elapsed += 1 } } }; if let callId { _ = try? await api("/api/voice/calls/\(callId)/active", method: "POST", body: [:]) } }
            if newState == .disconnected {
                disconnectTask?.cancel(); disconnectTask = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { error = "The voice connection dropped."; await end() } }
            }
            if newState == .failed { error = "The voice connection dropped."; await end() }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) { Task { @MainActor in channel = dataChannel; dataChannel.delegate = self } }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        Task { @MainActor in
            if state == .connected { status = "active"; if let callId { _ = try? await api("/api/voice/calls/\(callId)/active", method: "POST", body: [:]) } }
            if state == .failed { error = "The voice connection dropped."; await end() }
        }
    }
}

extension VoiceClient: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary, let value = String(data: buffer.data, encoding: .utf8) else { return }
        Task { @MainActor in receive(value) }
    }
}
#endif
