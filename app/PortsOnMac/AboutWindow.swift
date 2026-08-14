import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: controller)
            window.title = "About Ports on Mac"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 420, height: 440))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    private let projectURL = URL(string: "https://ports-on-mac.vercel.app")!
    private let licensesURL = URL(string: "https://github.com/emilianscheel/ports-on-mac/blob/main/app/Licenses/NOTICE.md")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private var versionLine: String {
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text("Ports on Mac")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 10)

            Text(versionLine)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 5) {
                informationRow("Privacy", "Private and on-device")
                informationRow("Scan", "lsof · TCP and UDP")
                informationRow("Domains", "Local loopback proxy")
                informationRow("Updates", "Sparkle · MIT")
            }
            .font(.system(size: 13))
            .padding(.top, 24)

            Button {
                NSWorkspace.shared.open(projectURL)
            } label: {
                Text("More Info…")
                    .frame(width: 116)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 26)

            Spacer(minLength: 16)

            Button {
                NSWorkspace.shared.open(licensesURL)
            } label: {
                Text("Open-source licenses")
                    .underline()
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))

            Text("Copyright © 2026 Ports on Mac contributors.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 27)
        .padding(.bottom, 16)
        .padding(.horizontal, 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func informationRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
        }
    }
}
