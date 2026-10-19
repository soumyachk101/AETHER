import AppKit
import Combine
import Foundation

/// A small lock-protected holder so the Node process can be terminated from
/// application shutdown callbacks without hopping actors.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func replace(with newProcess: Process?) {
        lock.lock()
        let previous = process
        process = newProcess
        lock.unlock()
        if let previous, previous !== newProcess {
            previous.terminate()
        }
    }

    func terminate() {
        lock.lock()
        let current = process
        process = nil
        lock.unlock()
        current?.terminate()
    }
}

struct ServerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class ServerController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case locating
        case building
        case starting
        case ready
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .locating, .building, .starting: return true
            default: return false
            }
        }

        var failedMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var logs = ""
    @Published private(set) var rootURL: URL?
    @Published private(set) var serverURL: URL?
    @Published private(set) var generation = 0

    let serverLogURL: URL

    private let processBox = ProcessBox()
    private var logHandle: FileHandle?
    private var isStopping = false
    private var runID = UUID()
    private var terminationObserver: NSObjectProtocol?

    init() {
        let logBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        let logDirectory = logBase.appendingPathComponent("AETHER", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        serverLogURL = logDirectory.appendingPathComponent("server.log")
        if !FileManager.default.fileExists(atPath: serverLogURL.path) {
            FileManager.default.createFile(atPath: serverLogURL.path, contents: nil)
        }
        logHandle = try? FileHandle(forWritingTo: serverLogURL)
        _ = try? logHandle?.seekToEnd()

        let box = processBox
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            box.terminate()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        try? logHandle?.close()
    }

    var port: Int {
        let saved = UserDefaults.standard.integer(forKey: "openDotsPort")
        return saved > 0 ? saved : 4310
    }

    var statusText: String {
        switch phase {
        case .idle: return "Starting…"
        case .locating: return "Finding your AETHER project…"
        case .building: return "Building AETHER…"
        case .starting: return "Starting the local server…"
        case .ready: return "Connected"
        case .failed(let message): return message
        }
    }

    var ownerToken: String? {
        if let token = ProcessInfo.processInfo.environment["OWNER_TOKEN"],
           !token.isEmpty {
            return token
        }
        guard let rootURL = rootURL ?? Self.locateRoot(),
              let contents = try? String(
                contentsOf: rootURL.appendingPathComponent(".env"),
                encoding: .utf8
              )
        else { return nil }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=")
            else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "OWNER_TOKEN" else { continue }
            var value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func start() async {
        if phase.isReady { return }

        isStopping = false
        runID = UUID()
        processBox.replace(with: nil)
        logs = ""
        phase = .locating

        guard let url = configuredServerURL else {
            fail("The AETHER server address is invalid.")
            return
        }

        let root = Self.locateRoot()
        rootURL = root
        if let root { appendLog("AETHER project: \(root.path)\n") }

        if await isHealthy(url) {
            appendLog("Attached to the server already running at \(url.absoluteString)\n")
            markReady(url)
            return
        }

        if isAttachOnly {
            appendLog("Waiting for an external AETHER server at \(url.absoluteString)…\n")
            if await waitForHealth(url, seconds: 20) {
                markReady(url)
            } else {
                fail("No server answered at \(url.absoluteString). Start AETHER first, or clear AETHER_URL.")
            }
            return
        }

        guard let root else {
            fail("Could not find the AETHER project. Open Settings and choose the folder that contains package.json.")
            return
        }

        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("node_modules").path
        ) else {
            fail("Dependencies are not installed. Run `npm ci` in \(root.path), then press Retry.")
            return
        }

        let entry = root.appendingPathComponent("dist/server/server/index.js")
        if !FileManager.default.fileExists(atPath: entry.path) {
            phase = .building
            appendLog("Building the AETHER client and server…\n")
            do {
                try await runShell("exec npm run build", root: root)
            } catch {
                fail(error.localizedDescription)
                return
            }
            guard FileManager.default.fileExists(atPath: entry.path) else {
                fail("The build completed but dist/server/server/index.js is missing. Run `npm run build` and check its output.")
                return
            }
        }

        phase = .starting
        appendLog("Starting AETHER on 127.0.0.1:\(port)…\n")
        do {
            try launchServer(root: root)
        } catch {
            fail(error.localizedDescription)
            return
        }

        if await waitForHealth(url, seconds: 120) {
            markReady(url)
        } else if phase.failedMessage == nil {
            fail("AETHER did not become ready. Check the server log for details.")
        }
    }

    func stop() {
        isStopping = true
        runID = UUID()
        processBox.terminate()
        serverURL = nil
        phase = .idle
    }

    func restart() async {
        isStopping = true
        runID = UUID()
        processBox.terminate()
        serverURL = nil
        phase = .idle
        try? await Task.sleep(nanoseconds: 350_000_000)
        isStopping = false
        await start()
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([serverLogURL])
    }

    private var configuredServerURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["AETHER_URL"] ?? environment["OPENDOTS_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    private var isAttachOnly: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["AETHER_URL"] != nil || environment["OPENDOTS_URL"] != nil
    }

    private func launchServer(root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-lc",
            "exec node --env-file-if-exists=.env dist/server/server/index.js"
        ]
        process.currentDirectoryURL = root

        var environment = ProcessInfo.processInfo.environment
        environment["HOST"] = "127.0.0.1"
        environment["PORT"] = String(port)
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let run = runID
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.runID == run else { return }
                self.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.runID == run, !self.isStopping else { return }
                self.processBox.replace(with: nil)
                let code = finished.terminationStatus
                if self.phase.isReady {
                    self.fail("AETHER stopped unexpectedly (exit code \(code)). See the server log.")
                } else if self.phase.isBusy {
                    self.fail("AETHER exited while starting (exit code \(code)). See the server log.")
                }
            }
        }

        processBox.replace(with: process)
        do {
            try process.run()
        } catch {
            processBox.replace(with: nil)
            throw error
        }
    }

    private func runShell(_ command: String, root: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let run = runID
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.runID == run else { return }
                self.appendLog(text)
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard status == 0 else {
            throw ServerError("Command failed with exit code \(status): \(command)")
        }
    }

    private func waitForHealth(_ url: URL, seconds: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await isHealthy(url) { return true }
            if phase.failedMessage != nil { return false }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private func isHealthy(_ url: URL) async -> Bool {
        guard let apiURL = URL(string: "/api/state", relativeTo: url) else { return false }
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            // 401 is still a healthy AETHER server that needs an owner token.
            return (200..<500).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func markReady(_ url: URL) {
        serverURL = url
        phase = .ready
        generation += 1
        appendLog("Ready at \(url.absoluteString)\n")
    }

    private func fail(_ message: String) {
        serverURL = nil
        phase = .failed(message)
        appendLog("\n\(message)\n")
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 200_000 {
            logs = String(logs.suffix(200_000))
        }
        if let data = text.data(using: .utf8) {
            try? logHandle?.write(contentsOf: data)
        }
    }

    // MARK: - Project discovery

    static func locateRoot() -> URL? {
        var candidates: [URL] = []
        let environment = ProcessInfo.processInfo.environment

        if let raw = environment["OPENDOTS_ROOT"], !raw.isEmpty {
            candidates.append(URL(fileURLWithPath: raw, isDirectory: true))
        }
        if let saved = UserDefaults.standard.string(forKey: "openDotsRoot"),
           !saved.isEmpty {
            candidates.append(URL(fileURLWithPath: saved, isDirectory: true))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
        candidates.append(Bundle.main.bundleURL)
        candidates.append(
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        )

        for candidate in candidates {
            var directory = candidate.hasDirectoryPath
                ? candidate
                : candidate.deletingLastPathComponent()
            for _ in 0..<16 {
                if isAetherRoot(directory) {
                    return directory.standardizedFileURL
                }
                let nestedApp = directory.appendingPathComponent("AETHER-web", isDirectory: true)
                if isAetherRoot(nestedApp) {
                    return nestedApp.standardizedFileURL
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return nil
    }

    private static func isAetherRoot(_ directory: URL) -> Bool {
        let package = directory.appendingPathComponent("package.json")
        let server = directory.appendingPathComponent("src/server/index.ts")
        guard FileManager.default.fileExists(atPath: server.path),
              let data = try? Data(contentsOf: package),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let name = manifest["name"] as? String
        return name == "aether" || name == "opendots"
    }
}
