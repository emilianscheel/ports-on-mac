import AppKit
import Darwin
import ServiceManagement
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let scanner = PortScanner()
    private let bindings = ServiceBindingStore.shared
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var showOutboundPorts = false
    private let updateUserDriver = UpdateUserDriver(hostBundle: .main)
    private var updater: SPUUpdater?
    private var lastSyncedDomains: [String] = []
    private var hasSyncedLiveDomains = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String {
            let updater = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: updateUserDriver,
                delegate: nil
            )
            do {
                try updater.start()
                self.updater = updater
            } catch {
                NSLog("Ports on Mac could not start the updater: \(error.localizedDescription)")
            }
        }

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

    func applicationWillTerminate(_ notification: Notification) {
        try? LocalProxyServer.shared.updateRoutes([:])
        ProxyHelperClient.shared.clearLiveDomainsBlocking()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let snapshot = makeSnapshot()
        syncProxy(with: snapshot)

        addStatusHeader(inboundCount: snapshot.inboundCount, outboundCount: snapshot.outboundCount)

        if !snapshot.services.isEmpty {
            menu.addItem(.separator())
            addServicesSection(snapshot.services)
        }

        menu.addItem(.separator())
        addSection(snapshot.inbound, to: menu)

        if showOutboundPorts {
            menu.addItem(.separator())
            addSection(snapshot.outbound, to: menu)
        }

        menu.addItem(.separator())

        let outboundToggleItem = NSMenuItem(
            title: showOutboundPorts ? "Hide Outbound Ports" : "Show Outbound Ports",
            action: #selector(toggleOutboundPorts),
            keyEquivalent: ""
        )
        outboundToggleItem.target = self
        outboundToggleItem.image = NSImage(
            systemSymbolName: showOutboundPorts ? "eye.slash" : "eye",
            accessibilityDescription: showOutboundPorts ? "Hide Outbound Ports" : "Show Outbound Ports"
        )
        menu.addItem(outboundToggleItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        menu.addItem(refreshItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(
            systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
            accessibilityDescription: "Check for Updates"
        )
        updateItem.isEnabled = updater?.canCheckForUpdates ?? true
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func makeSnapshot() -> MenuSnapshot {
        let sections = scanner.scan()
        let inbound = sections.first { $0.direction == .inbound } ?? PortSection(direction: .inbound, groups: [])
        let outbound = sections.first { $0.direction == .outbound } ?? PortSection(direction: .outbound, groups: [])

        let matches = bindings.liveMatches(from: inbound.groups.flatMap(\.entries))
        let matchedIdentities = Set(matches.map { "\($0.entry.processIdentity)#\($0.entry.port)" })

        let usefulInboundGroups = inbound.groups.compactMap { group -> PortGroup? in
            let useful = group.entries.filter(\.isUsefulInbound)
            guard !useful.isEmpty else { return nil }
            return PortGroup(direction: .inbound, port: group.port, entries: useful)
        }

        let remainingGroups = usefulInboundGroups.compactMap { group -> PortGroup? in
            let remaining = group.entries.filter { entry in
                !matchedIdentities.contains("\(entry.processIdentity)#\(entry.port)")
            }
            guard !remaining.isEmpty else { return nil }
            return PortGroup(direction: .inbound, port: group.port, entries: remaining)
        }

        let services = matches
            .sorted { $0.binding.domain.localizedCaseInsensitiveCompare($1.binding.domain) == .orderedAscending }

        return MenuSnapshot(
            inboundCount: usefulInboundGroups.count,
            outboundCount: outbound.groups.count,
            services: services,
            inbound: PortSection(direction: .inbound, groups: remainingGroups),
            outbound: outbound
        )
    }

    private func syncProxy(with snapshot: MenuSnapshot) {
        Task { @MainActor in
            do {
                try await applyProxy(snapshot: snapshot, forceHelper: false)
            } catch {
                NSLog("Ports on Mac could not sync local domains: \(error.localizedDescription)")
            }
        }
    }

    private func applyProxy(snapshot: MenuSnapshot, forceHelper: Bool) async throws {
        let routes = Dictionary(uniqueKeysWithValues: snapshot.services.map { ($0.binding.domain, $0.entry.port) })
        let domains = snapshot.services.map(\.binding.domain)
        try LocalProxyServer.shared.updateRoutes(routes)

        guard forceHelper || domains != lastSyncedDomains || !hasSyncedLiveDomains else { return }
        lastSyncedDomains = domains
        hasSyncedLiveDomains = true

        if !domains.isEmpty {
            try ProxyHelperClient.shared.prepareForAssignment()
        }
        if ProxyHelperClient.shared.status == .enabled {
            try await ProxyHelperClient.shared.syncLiveDomains(domains)
        } else if !domains.isEmpty {
            throw ProxyHelperError.notEnabled
        }
    }

    private func addStatusHeader(inboundCount: Int, outboundCount: Int) {
        let liveItem = NSMenuItem(title: "Live", action: nil, keyEquivalent: "")
        liveItem.isEnabled = false
        liveItem.image = ProcessIcon.liveDot()
        liveItem.attributedTitle = NSAttributedString(
            string: "Live",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(liveItem)

        let stats = "\(inboundCount) inbound, \(outboundCount) outbound"
        let statsItem = NSMenuItem(title: stats, action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        statsItem.image = ProcessIcon.placeholder()
        statsItem.attributedTitle = NSAttributedString(
            string: stats,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(statsItem)
    }

    private func addServicesSection(_ services: [(entry: PortEntry, binding: ServiceBinding)]) {
        let titleItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        for service in services {
            let item = NSMenuItem(title: service.binding.domain, action: nil, keyEquivalent: "")
            item.subtitle = ":\(service.entry.port)  \(service.entry.displayCommand)"
            item.image = ProcessIcon.image(for: service.entry, domain: service.binding.domain)
            item.submenu = makeProcessMenu(for: service.entry, domain: service.binding.domain)
            menu.addItem(item)
        }
    }

    private func addSection(_ section: PortSection, to menu: NSMenu) {
        let titleItem = NSMenuItem(title: section.direction.title, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if section.groups.isEmpty {
            let emptyItem = NSMenuItem(title: section.direction.emptyTitle, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for group in section.groups {
            let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            if let entry = group.entries.first {
                item.image = ProcessIcon.image(for: entry)
            } else {
                item.image = ProcessIcon.placeholder()
            }
            item.submenu = makePortMenu(for: group)
            menu.addItem(item)
        }
    }

    private func makePortMenu(for group: PortGroup) -> NSMenu {
        if group.hasSingleProcess, let entry = group.entries.first {
            return makeProcessMenu(for: entry, domain: bindings.binding(matching: entry)?.domain)
        }

        let portMenu = NSMenu()

        for entry in group.entries {
            let processItem = NSMenuItem(title: entry.processTitle, action: nil, keyEquivalent: "")
            processItem.image = ProcessIcon.image(for: entry)
            processItem.submenu = makeProcessMenu(for: entry, domain: bindings.binding(matching: entry)?.domain)
            portMenu.addItem(processItem)
        }

        return portMenu
    }

    private func makeProcessMenu(for entry: PortEntry, domain: String?) -> NSMenu {
        let processMenu = NSMenu()
        let context = PortMenuContext(entry: entry, domain: domain)

        for detail in entry.details {
            let detailItem = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            processMenu.addItem(detailItem)
        }

        processMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open", action: #selector(openPort(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open")
        openItem.representedObject = entry.openURL(domain: domain)
        openItem.isEnabled = entry.openURL(domain: domain) != nil
        processMenu.addItem(openItem)

        if domain != nil {
            processMenu.addItem(.separator())

            let unassignItem = NSMenuItem(title: "Unassign Domain", action: #selector(unassignDomain(_:)), keyEquivalent: "")
            unassignItem.target = self
            unassignItem.image = NSImage(systemSymbolName: "link.slash", accessibilityDescription: "Unassign Domain")
            unassignItem.representedObject = context
            processMenu.addItem(unassignItem)
        } else if entry.canAssignDomain {
            processMenu.addItem(.separator())

            let assignItem = NSMenuItem(title: "Assign Domain", action: #selector(assignDomain(_:)), keyEquivalent: "")
            assignItem.target = self
            assignItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Assign Domain")
            assignItem.representedObject = context
            processMenu.addItem(assignItem)
        }

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

    @objc private func checkForUpdates(_ sender: Any?) {
        if let updater {
            NSApp.activate(ignoringOtherApps: true)
            updater.checkForUpdates()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Updates aren’t available in this build"
        alert.informativeText = "Automatic updates are included in signed releases from GitHub. This development build won’t check for or install updates."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleOutboundPorts() {
        showOutboundPorts.toggle()
        rebuildMenu()
    }

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func assignDomain(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? PortMenuContext else { return }

        NSApp.activate(ignoringOtherApps: true)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 21))
        field.placeholderString = "all-in-agi.com"
        field.stringValue = context.domain ?? ""
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Assign Domain"
        alert.informativeText = "This hostname will open locally and proxy to this process."
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                let domain = try DomainName.normalize(field.stringValue)
                try ProxyHelperClient.shared.prepareForAssignment()
                try bindings.assign(domain: field.stringValue, to: context.entry)
                lastSyncedDomains = []
                do {
                    try await applyProxy(snapshot: makeSnapshot(), forceHelper: true)
                } catch {
                    try? bindings.unassign(domain: domain)
                    lastSyncedDomains = []
                    throw error
                }
                rebuildMenu()
            } catch ProxyHelperError.requiresApproval {
                showHelperApprovalAlert()
            } catch {
                presentError(error, title: "Couldn’t assign domain")
                rebuildMenu()
            }
        }
    }

    @objc private func unassignDomain(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? PortMenuContext else { return }

        do {
            if let domain = context.domain {
                try bindings.unassign(domain: domain)
            } else {
                try bindings.unassign(entry: context.entry)
            }
            lastSyncedDomains = []
            rebuildMenu()
        } catch {
            presentError(error, title: "Couldn’t unassign domain")
        }
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

    private func showHelperApprovalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow the Ports on Mac helper"
        alert.informativeText = ProxyHelperError.requiresApproval.localizedDescription
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func presentError(_ error: Error, title: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct MenuSnapshot {
    let inboundCount: Int
    let outboundCount: Int
    let services: [(entry: PortEntry, binding: ServiceBinding)]
    let inbound: PortSection
    let outbound: PortSection
}

private final class PortMenuContext: NSObject {
    let entry: PortEntry
    let domain: String?

    init(entry: PortEntry, domain: String?) {
        self.entry = entry
        self.domain = domain
    }
}
