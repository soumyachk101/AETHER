#if os(macOS)
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var server: ServerController
    @EnvironmentObject private var web: WebViewStore

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if server.phase.isReady, let url = server.serverURL {
                AetherWebView(url: url, token: server.ownerToken, store: web)
                    .id(server.generation)
                    .ignoresSafeArea()
            } else {
                LaunchView()
            }

            if server.phase.isReady, let error = web.lastError {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .lineLimit(2)
                        Spacer(minLength: 12)
                        Button("Reload") { web.reload() }
                        Button("Dismiss") { web.lastError = nil }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.12))
                    )
                    .padding(16)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .task {
            await server.start()
        }
    }
}

struct LaunchView: View {
    @EnvironmentObject private var server: ServerController

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.062, blue: 0.105),
                    Color(red: 0.105, green: 0.062, blue: 0.165),
                    Color(red: 0.028, green: 0.125, blue: 0.155)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.43, green: 0.35, blue: 1).opacity(0.22),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 320
                    )
                )
                .frame(width: 640, height: 640)
                .offset(x: -220, y: -240)
                .blur(radius: 20)

            VStack(spacing: 22) {
                AetherMark(size: 82)

                VStack(spacing: 5) {
                    Text("AETHER")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Your AETHER desktop")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: 9) {
                    if server.phase.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else if server.phase.failedMessage != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(server.phase.failedMessage ?? server.statusText)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                .frame(maxWidth: 720)

                if server.phase.failedMessage != nil {
                    HStack(spacing: 10) {
                        Button {
                            Task { await server.start() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            server.revealLog()
                        } label: {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        if let root = server.rootURL {
                            Button {
                                NSWorkspace.shared.open(root)
                            } label: {
                                Label("Open Project", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .tint(.white)

                    LogConsole(text: server.logs)
                } else {
                    Text("The local server is started automatically. The first launch may build the app.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            }
            .padding(48)
        }
    }
}

@MainActor
func loadAetherLogo() -> NSImage? {
    #if SWIFT_PACKAGE
    if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    #endif

    if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let image = NSImage(named: "logo") {
        return image
    }

    if let root = ServerController.locateRoot() {
        let parent = root.deletingLastPathComponent()
        let paths = [
            parent.appendingPathComponent("image.png"),
            root.appendingPathComponent("image.png"),
            parent.appendingPathComponent("AETHER-web/public/logo.png"),
            root.appendingPathComponent("public/logo.png"),
            parent.appendingPathComponent("AETHER-swift/Sources/AETHER/Resources/logo.png")
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path.path),
               let image = NSImage(contentsOf: path) {
                return image
            }
        }
    }
    return nil
}

struct AetherMark: View {
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let logo = loadAetherLogo() {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.36, blue: 1.0),
                                    Color(red: 0.24, green: 0.78, blue: 0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                                .strokeBorder(.white.opacity(0.22))
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.38), radius: size * 0.18, y: size * 0.09)
    }
}

struct LogConsole: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)

                Color.clear
                    .frame(height: 1)
                    .id("log-bottom")
            }
            .frame(maxWidth: 720, maxHeight: 220)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08))
            )
            .onChange(of: text) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
        }
    }
}
#endif
