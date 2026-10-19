import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var server: ServerController
    @State private var rootPath = ""
    @State private var portText = "4310"

    var body: some View {
        Form {
            Section("AETHER project") {
                TextField("Folder", text: $rootPath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: rootPath) { _ in save() }

                HStack {
                    Button("Choose Folder…") { chooseFolder() }
                    Button("Use Detected Folder") {
                        if let detected = ServerController.locateRoot() {
                            rootPath = detected.path
                            save()
                        }
                    }
                    Spacer()
                    if let root = server.rootURL {
                        Text(root.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("The folder must contain package.json and src/server/index.ts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local server") {
                HStack {
                    Text("Port")
                    TextField("4310", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: portText) { _ in save() }
                    Spacer()
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 8, height: 8)
                    Text(server.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Button("Restart Server") {
                        save()
                        Task { await server.restart() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reveal Server Log in Finder") {
                        server.revealLog()
                    }

                    Spacer()
                }

                Text("Restart to apply a new folder or port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Server log") {
                LogConsole(text: server.logs)
                    .frame(height: 180)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 660, height: 560)
        .onAppear(perform: load)
    }

    private var phaseColor: Color {
        switch server.phase {
        case .ready: return .green
        case .failed: return .red
        case .building, .starting, .locating: return .orange
        case .idle: return .gray
        }
    }

    private func load() {
        rootPath = UserDefaults.standard.string(forKey: "aetherRoot")
            ?? UserDefaults.standard.string(forKey: "openDotsRoot")
            ?? ServerController.locateRoot()?.path
            ?? ""
        portText = String(server.port)
    }

    private func save() {
        if rootPath.isEmpty {
            UserDefaults.standard.removeObject(forKey: "aetherRoot")
            UserDefaults.standard.removeObject(forKey: "openDotsRoot")
        } else {
            UserDefaults.standard.set(rootPath, forKey: "aetherRoot")
            UserDefaults.standard.set(rootPath, forKey: "openDotsRoot")
        }

        if let port = Int(portText), (1...65_535).contains(port) {
            UserDefaults.standard.set(port, forKey: "aetherPort")
            UserDefaults.standard.set(port, forKey: "openDotsPort")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose AETHER"
        if !rootPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            save()
        }
    }
}
