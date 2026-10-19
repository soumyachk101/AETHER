#if os(macOS)
import AppKit
import SwiftUI

@main
struct AETHERApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var server = ServerController()
    @StateObject private var web = WebViewStore()

    var body: some Scene {
        WindowGroup("AETHER") {
            RootView()
                .environmentObject(server)
                .environmentObject(web)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            AETHERCommands(server: server, web: web)
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
    @ObservedObject var web: WebViewStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("AETHER") {
            Button("Reload") {
                web.reload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!server.phase.isReady)

            Button("Open in Browser") {
                web.openInBrowser()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!server.phase.isReady)

            Divider()

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
