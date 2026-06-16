import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let scanner = PortScanner()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "powercord", accessibilityDescription: "Ports on Mac")
            button.image?.isTemplate = true
            button.toolTip = "Ports on Mac"
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let groups = scanner.scan()
        if groups.isEmpty {
            let emptyItem = NSMenuItem(title: "No ports found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for group in groups {
                let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                item.submenu = makePortMenu(for: group)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func makePortMenu(for group: PortGroup) -> NSMenu {
        let portMenu = NSMenu()

        for entry in group.entries {
            let processItem = NSMenuItem(title: entry.processTitle, action: nil, keyEquivalent: "")
            processItem.submenu = makeProcessMenu(for: entry)
            portMenu.addItem(processItem)
        }

        return portMenu
    }

    private func makeProcessMenu(for entry: PortEntry) -> NSMenu {
        let processMenu = NSMenu()

        for detail in entry.details {
            let detailItem = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            processMenu.addItem(detailItem)
        }

        processMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open", action: #selector(openPort(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open")
        openItem.representedObject = entry.openURL
        openItem.isEnabled = entry.openURL != nil
        processMenu.addItem(openItem)

        processMenu.addItem(.separator())

        let killItem = NSMenuItem(title: "Kill", action: #selector(killProcess(_:)), keyEquivalent: "")
        killItem.target = self
        killItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Kill")
        killItem.representedObject = NSNumber(value: entry.pid)
        processMenu.addItem(killItem)

        return processMenu
    }

    @objc private func refresh() {
        rebuildMenu()
    }

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func killProcess(_ sender: NSMenuItem) {
        guard let pidNumber = sender.representedObject as? NSNumber else { return }

        let pid = pid_t(pidNumber.intValue)
        if Darwin.kill(pid, SIGTERM) != 0 {
            NSSound.beep()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
