#if os(macOS)
import AppKit
import SwiftUI

@main
struct AETHERApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var server = ServerController()

    var body: some Scene {
        WindowGroup("AETHER") {
            RootView()
                .environmentObject(server)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            AETHERCommands(server: server)
        }

        Settings {
            SettingsView()
                .environmentObject(server)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AETHERCommands: Commands {
    @ObservedObject var server: ServerController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("OpenDots") {
            Button("Restart Local Server") {
                Task { await server.restart() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Open Project Folder") {
                if let root = server.rootURL {
                    NSWorkspace.shared.open(root)
                }
            }
            .disabled(server.rootURL == nil)

            Button("Reveal Server Log in Finder") {
                server.revealLog()
            }
        }
    }
}
#endif
