import SwiftUI

@main
struct PortsOnMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--debug-raw-lsof") {
            print(PortScanner().debugRawLsofOutput())
            Foundation.exit(0)
        }

        guard CommandLine.arguments.contains("--debug-scan") else { return }

        for section in PortScanner().scan() {
            print(section.direction.title)
            for group in section.groups {
                print(group.title)
                for entry in group.entries {
                    print("  \(entry.processTitle) \(entry.localEndpoint)")
                }
            }
        }

        Foundation.exit(0)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
