import AppKit
import Darwin
import ServiceManagement
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let bindings = ServiceBindingStore.shared
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var showOutboundPorts = false
    private let updateUserDriver = UpdateUserDriver(hostBundle: .main)
    private let aboutWindow = AboutWindowController()
    private var updater: SPUUpdater?
    private var lastSyncedDomains: [String] = []
    private var lastSyncedHTTPS = false
    private var hasSyncedLiveDomains = false
    private var lastSections: [PortSection] = []
    private var lastSnapshot = MenuSnapshot.empty
    private var lastMenuFingerprint = ""
    private var isMenuOpen = false
    private var hasRebuiltSinceOpen = false
    private var forceMenuRebuild = false
    private var isScanning = false
    private var queuedRefresh = false
    private var refreshWaiters: [CheckedContinuation<MenuSnapshot, Never>] = []
    private var scanLoopTask: Task<Void, Never>?
    private let menuSearch = MenuSearchFieldController()

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
        menuSearch.onQueryChange = { [weak self] _ in
            guard let self else { return }
            self.forceMenuRebuild = true
            self.rebuildMenu(from: self.lastSnapshot)
        }
        LicenseStore.shared.ensureTrialStarted()
        rebuildMenu(from: lastSnapshot)
        startScanLoop()
        Task {
            await LicenseStore.shared.refreshValidation()
            rebuildMenu(from: lastSnapshot)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scanLoopTask?.cancel()
        try? LocalProxyServer.shared.updateRoutes([:], preferHTTPS: [], enableTLS: false)
        ProxyHelperClient.shared.clearLiveDomainsBlocking()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        hasRebuiltSinceOpen = false
        scheduleRefresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        hasRebuiltSinceOpen = false
        forceMenuRebuild = false
        if !menuSearch.query.isEmpty {
            menuSearch.clear()
            forceMenuRebuild = true
            rebuildMenu(from: lastSnapshot)
        }
    }

    private func startScanLoop() {
        scanLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !(self.isMenuOpen && self.hasRebuiltSinceOpen) {
                    await self.refreshSnapshot()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func scheduleRefresh() {
        Task { [weak self] in
            await self?.refreshSnapshot()
        }
    }

    @discardableResult
    private func refreshSnapshot() async -> MenuSnapshot {
        if isScanning {
            queuedRefresh = true
            return await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
        }

        isScanning = true
        var snapshot = lastSnapshot
        repeat {
            queuedRefresh = false
            let sections = await Task.detached(priority: .userInitiated) {
                PortScanner().scan()
            }.value
            lastSections = sections
            snapshot = makeSnapshot(from: sections)
            rebuildMenu(from: snapshot)
        } while queuedRefresh

        isScanning = false
        let waiters = refreshWaiters
        refreshWaiters = []
        for waiter in waiters {
            waiter.resume(returning: snapshot)
        }
        return snapshot
    }

    private func rebuildMenu(from snapshot: MenuSnapshot) {
        lastSnapshot = snapshot
        let query = menuSearch.query
        let fingerprint = snapshot.fingerprint(
            showOutbound: showOutboundPorts,
            needsLicense: LicenseStore.shared.needsLicenseMenu,
            searchQuery: query
        )
        let force = forceMenuRebuild
        forceMenuRebuild = false

        if isMenuOpen {
            if hasRebuiltSinceOpen, !force {
                syncProxy(with: snapshot)
                return
            }
            hasRebuiltSinceOpen = true
            if fingerprint == lastMenuFingerprint, !force {
                syncProxy(with: snapshot)
                return
            }
        }

        lastMenuFingerprint = fingerprint
        syncProxy(with: snapshot)

        let keepSearchField = menu.items.contains { $0 === menuSearch.menuItem }
        if keepSearchField {
            replaceMenuItemsKeepingSearch(from: snapshot, query: query)
        } else {
            menu.removeAllItems()
            addStatusHeader(inboundCount: snapshot.inboundCount, outboundCount: snapshot.outboundCount)
            menu.addItem(menuSearch.menuItem)
            addProcessSections(
                from: snapshot.filtered(query: query, showOutbound: showOutboundPorts),
                isSearching: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            addFooterItems()
            if isMenuOpen {
                menuSearch.restoreFocus()
            }
        }
    }

    private func replaceMenuItemsKeepingSearch(from snapshot: MenuSnapshot, query: String) {
        guard let searchIndex = menu.items.firstIndex(where: { $0 === menuSearch.menuItem }) else { return }

        for index in stride(from: menu.numberOfItems - 1, through: searchIndex + 1, by: -1) {
            menu.removeItem(at: index)
        }
        for _ in 0..<searchIndex {
            menu.removeItem(at: 0)
        }

        addStatusHeader(inboundCount: snapshot.inboundCount, outboundCount: snapshot.outboundCount, at: 0)
        addProcessSections(
            from: snapshot.filtered(query: query, showOutbound: showOutboundPorts),
            isSearching: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        addFooterItems()
    }

    private func addProcessSections(from snapshot: MenuSnapshot, isSearching: Bool) {
        let hasServices = !snapshot.services.isEmpty
        let hasInbound = !snapshot.inbound.groups.isEmpty
        let hasOutbound = showOutboundPorts && !snapshot.outbound.groups.isEmpty

        if isSearching && !hasServices && !hasInbound && !hasOutbound {
            menu.addItem(.separator())
            let emptyItem = NSMenuItem(title: "No Results", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        if hasServices {
            menu.addItem(.separator())
            addServicesSection(snapshot.services)
        }

        if !isSearching || hasInbound {
            menu.addItem(.separator())
            addSection(snapshot.inbound, to: menu)
        }

        if showOutboundPorts, !isSearching || hasOutbound {
            menu.addItem(.separator())
            addSection(snapshot.outbound, to: menu)
        }
    }

    private func makeSnapshot(from sections: [PortSection]) -> MenuSnapshot {
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
        guard LicenseStore.shared.hasDomainAccess else {
            tearDownProxy()
            return
        }

        Task { @MainActor in
            do {
                try await applyProxy(snapshot: snapshot, forceHelper: false)
            } catch {
                NSLog("Ports on Mac could not sync local domains: \(error.localizedDescription)")
            }
        }
    }

    private func tearDownProxy() {
        try? LocalProxyServer.shared.updateRoutes([:], preferHTTPS: [], enableTLS: false)
        ProxyHelperClient.shared.clearLiveDomainsBlocking()
        lastSyncedDomains = []
        lastSyncedHTTPS = false
        hasSyncedLiveDomains = false
    }

    @discardableResult
    private func applyProxy(snapshot: MenuSnapshot, forceHelper: Bool) async throws -> String? {
        let routes = Dictionary(uniqueKeysWithValues: snapshot.services.map { ($0.binding.domain, $0.entry.port) })
        let domains = snapshot.services.map(\.binding.domain)
        let preferHTTPS = snapshot.services.filter(\.binding.usesHTTPS).map(\.binding.domain)
        var enableHTTPS = !domains.isEmpty
        var httpsWarning: String?

        if domains.isEmpty {
            try LocalProxyServer.shared.updateRoutes([:], preferHTTPS: [], enableTLS: false)
        } else {
            do {
                try LocalCertificateAuthority.shared.prepareCA()
                if try !LocalCertificateAuthority.shared.hasUserTrust() {
                    NSApp.activate(ignoringOtherApps: true)
                }
                try LocalCertificateAuthority.shared.installUserTrust()
                try LocalProxyServer.shared.updateRoutes(routes, preferHTTPS: preferHTTPS)
            } catch {
                NSLog("Ports on Mac local HTTPS setup failed: \(error.localizedDescription)")
                for domain in preferHTTPS {
                    try? bindings.setUsesHTTPS(false, domain: domain)
                }
                try LocalProxyServer.shared.updateRoutes(routes, preferHTTPS: [], enableTLS: false)
                enableHTTPS = false
                httpsWarning = "The domain still works over HTTP. HTTPS couldn’t be enabled (\(error.localizedDescription)). Choose Use HTTPS to try again."
            }
        }

        let shouldSyncHelper = forceHelper || domains != lastSyncedDomains || enableHTTPS != lastSyncedHTTPS || !hasSyncedLiveDomains
        guard shouldSyncHelper else { return httpsWarning }

        if !domains.isEmpty {
            try ProxyHelperClient.shared.prepareForAssignment()
        }
        guard ProxyHelperClient.shared.status == .enabled else {
            if !domains.isEmpty {
                throw ProxyHelperError.notEnabled
            }
            lastSyncedDomains = domains
            lastSyncedHTTPS = enableHTTPS
            hasSyncedLiveDomains = true
            return httpsWarning
        }

        if enableHTTPS {
            do {
                try await ProxyHelperClient.shared.ensureCurrentHelper()
                try await ProxyHelperClient.shared.syncLiveDomains(domains, enableHTTPS: true)
            } catch let error as ProxyHelperError {
                switch error {
                case .requiresApproval, .notEnabled:
                    throw error
                default:
                    NSLog("Ports on Mac HTTPS helper setup failed: \(error.localizedDescription)")
                    return try await fallBackToHTTP(
                        routes: routes,
                        domains: domains,
                        preferHTTPS: preferHTTPS,
                        reason: error.localizedDescription
                    )
                }
            } catch {
                NSLog("Ports on Mac HTTPS helper setup failed: \(error.localizedDescription)")
                return try await fallBackToHTTP(
                    routes: routes,
                    domains: domains,
                    preferHTTPS: preferHTTPS,
                    reason: error.localizedDescription
                )
            }
        } else {
            try await ProxyHelperClient.shared.syncLiveDomains(domains, enableHTTPS: false)
        }

        lastSyncedDomains = domains
        lastSyncedHTTPS = enableHTTPS
        hasSyncedLiveDomains = true
        return httpsWarning
    }

    private func fallBackToHTTP(
        routes: [String: Int],
        domains: [String],
        preferHTTPS: [String],
        reason: String
    ) async throws -> String {
        for domain in preferHTTPS {
            try? bindings.setUsesHTTPS(false, domain: domain)
        }
        try LocalProxyServer.shared.updateRoutes(routes, preferHTTPS: [], enableTLS: false)
        try await ProxyHelperClient.shared.syncLiveDomains(domains, enableHTTPS: false)
        lastSyncedDomains = domains
        lastSyncedHTTPS = false
        hasSyncedLiveDomains = true
        return "The domain still works over HTTP. HTTPS couldn’t be enabled (\(reason)). Choose Use HTTPS to try again."
    }

    private func addStatusHeader(inboundCount: Int, outboundCount: Int, at index: Int? = nil) {
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

        if let index {
            menu.insertItem(liveItem, at: index)
            menu.insertItem(statsItem, at: index + 1)
        } else {
            menu.addItem(liveItem)
            menu.addItem(statsItem)
        }
    }

    private func addFooterItems() {
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

        if LicenseStore.shared.needsLicenseMenu {
            let buyItem = NSMenuItem(
                title: "Buy License Key",
                action: #selector(buyLicenseKey),
                keyEquivalent: ""
            )
            buyItem.target = self
            buyItem.image = NSImage(systemSymbolName: "bag", accessibilityDescription: "Buy License Key")
            menu.addItem(buyItem)

            let activateItem = NSMenuItem(
                title: "Activate License Key",
                action: #selector(activateLicenseKey),
                keyEquivalent: ""
            )
            activateItem.target = self
            activateItem.image = NSImage(systemSymbolName: "key", accessibilityDescription: "Activate License Key")
            menu.addItem(activateItem)
        }

        let aboutItem = NSMenuItem(title: "About Ports on Mac", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About Ports on Mac")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func addServicesSection(_ services: [(entry: PortEntry, binding: ServiceBinding)]) {
        let titleItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        for service in services {
            let item = NSMenuItem(title: service.binding.domain, action: nil, keyEquivalent: "")
            item.subtitle = ":\(service.entry.port)  \(service.entry.displayCommand)"
            item.image = ProcessIcon.image(for: service.entry, domain: service.binding.domain, usesHTTPS: service.binding.usesHTTPS)
            item.submenu = makeProcessMenu(for: service.entry, binding: service.binding)
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
            item.subtitle = group.subtitle
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
            return makeProcessMenu(for: entry, binding: bindings.binding(matching: entry))
        }

        let portMenu = NSMenu()

        for entry in group.entries {
            let processItem = NSMenuItem(title: entry.processTitle, action: nil, keyEquivalent: "")
            processItem.image = ProcessIcon.image(for: entry)
            processItem.submenu = makeProcessMenu(for: entry, binding: bindings.binding(matching: entry))
            portMenu.addItem(processItem)
        }

        return portMenu
    }

    private func makeProcessMenu(for entry: PortEntry, binding: ServiceBinding?) -> NSMenu {
        let processMenu = NSMenu()
        let domain = binding?.domain
        let usesHTTPS = binding?.usesHTTPS ?? false
        let context = PortMenuContext(entry: entry, domain: domain, usesHTTPS: usesHTTPS)

        for detail in entry.details {
            let detailItem = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            processMenu.addItem(detailItem)
        }

        processMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open", action: #selector(openPort(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Open")
        openItem.representedObject = entry.openURL(domain: domain, usesHTTPS: usesHTTPS)
        openItem.isEnabled = entry.openURL(domain: domain, usesHTTPS: usesHTTPS) != nil
        processMenu.addItem(openItem)

        if LicenseStore.shared.hasDomainAccess {
            if domain != nil {
                processMenu.addItem(.separator())

                let httpsItem = NSMenuItem(title: "Use HTTPS", action: #selector(toggleHTTPS(_:)), keyEquivalent: "")
                httpsItem.target = self
                httpsItem.image = usesHTTPS
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Use HTTPS")
                    : nil
                httpsItem.representedObject = context
                processMenu.addItem(httpsItem)

                let unassignItem = NSMenuItem(title: "Unassign Domain", action: #selector(unassignDomain(_:)), keyEquivalent: "")
                unassignItem.target = self
                unassignItem.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Unassign Domain")
                unassignItem.representedObject = context
                processMenu.addItem(unassignItem)
            } else if entry.canAssignDomain {
                processMenu.addItem(.separator())

                let assignItem = NSMenuItem(title: "Assign Domain", action: #selector(assignDomain(_:)), keyEquivalent: "")
                assignItem.target = self
                assignItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Assign Domain")
                assignItem.representedObject = context
                processMenu.addItem(assignItem)
            }
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
        forceMenuRebuild = true
        scheduleRefresh()
    }

    @objc private func showAbout() {
        aboutWindow.show()
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

    @objc private func buyLicenseKey() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "PolarCheckoutURL") as? String
            ?? "https://ports-on-mac.vercel.app/checkout?products=66c8ee2f-990e-4d0d-b2f6-97e1ec5d4618"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func activateLicenseKey() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Activate License Key"
        alert.informativeText = "Paste the key Polar emailed after your purchase. One key works on up to 3 Macs."
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        alert.layout()

        let fieldWidth = max(220, alert.window.frame.width - 48)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: 21))
        field.placeholderString = "PORTS-…"
        field.stringValue = ""
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await LicenseStore.shared.activate(key: field.stringValue)
                rebuildMenu(from: lastSnapshot)
            } catch {
                presentError(error, title: "Couldn’t activate license")
            }
        }
    }

    @objc private func toggleOutboundPorts() {
        showOutboundPorts.toggle()
        lastMenuFingerprint = ""
        forceMenuRebuild = true
        rebuildMenu(from: lastSnapshot)
    }

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func assignDomain(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? PortMenuContext else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Assign Domain"
        alert.informativeText = "This hostname will open locally and proxy to this process."
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")
        alert.layout()

        let suggested = LastDomainStore.shared.domain(for: context.entry)
            ?? context.entry.suggestedDomain
            ?? DomainName.placeholder

        let fieldWidth = max(220, alert.window.frame.width - 48)
        let field = NSTextField(frame: NSRect(x: 0, y: 29, width: fieldWidth, height: 21))
        field.placeholderString = suggested
        field.stringValue = ""
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let httpsCheckbox = NSButton(checkboxWithTitle: "Use HTTPS", target: nil, action: nil)
        httpsCheckbox.state = .off
        httpsCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        httpsCheckbox.frame = NSRect(x: 0, y: 0, width: fieldWidth, height: 21)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: 50))
        accessory.addSubview(field)
        accessory.addSubview(httpsCheckbox)

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDomain = typed.isEmpty ? suggested : field.stringValue
                let domain = try DomainName.normalize(rawDomain)
                let usesHTTPS = httpsCheckbox.state == .on
                try ProxyHelperClient.shared.prepareForAssignment()
                try bindings.assign(domain: rawDomain, to: context.entry, usesHTTPS: usesHTTPS)
                lastSyncedDomains = []
                lastSyncedHTTPS = false
                let httpsWarning: String?
                do {
                    let snapshot = await refreshSnapshot()
                    httpsWarning = try await applyProxy(snapshot: snapshot, forceHelper: true)
                } catch {
                    try? bindings.unassign(domain: domain)
                    lastSyncedDomains = []
                    lastSyncedHTTPS = false
                    throw error
                }
                LastDomainStore.shared.remember(domain, for: context.entry)
                rebuildMenu(from: makeSnapshot(from: lastSections))
                if let httpsWarning {
                    presentNotice(httpsWarning, title: "Assigned without HTTPS")
                }
            } catch ProxyHelperError.requiresApproval {
                showHelperApprovalAlert()
            } catch {
                presentError(error, title: "Couldn’t assign domain")
                rebuildMenu(from: makeSnapshot(from: lastSections))
            }
        }
    }

    @objc private func toggleHTTPS(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? PortMenuContext,
              let domain = context.domain else { return }

        let enable = !context.usesHTTPS
        Task { @MainActor in
            do {
                try bindings.setUsesHTTPS(enable, domain: domain)
                let httpsWarning: String?
                do {
                    let snapshot = await refreshSnapshot()
                    httpsWarning = try await applyProxy(snapshot: snapshot, forceHelper: false)
                } catch {
                    try? bindings.setUsesHTTPS(!enable, domain: domain)
                    throw error
                }
                rebuildMenu(from: makeSnapshot(from: lastSections))
                if let httpsWarning {
                    presentNotice(httpsWarning, title: enable ? "Couldn’t enable HTTPS" : "Couldn’t disable HTTPS")
                }
            } catch ProxyHelperError.requiresApproval {
                showHelperApprovalAlert()
            } catch {
                presentError(error, title: enable ? "Couldn’t enable HTTPS" : "Couldn’t disable HTTPS")
                rebuildMenu(from: makeSnapshot(from: lastSections))
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
            lastSyncedHTTPS = false
            lastMenuFingerprint = ""
            rebuildMenu(from: makeSnapshot(from: lastSections))
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
            ProcessMetadata.invalidate(pid: pid)
            self?.scheduleRefresh()
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
        presentNotice(error.localizedDescription, title: title, style: .warning)
    }

    private func presentNotice(_ message: String, title: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct MenuSnapshot {
    static let empty = MenuSnapshot(
        inboundCount: 0,
        outboundCount: 0,
        services: [],
        inbound: PortSection(direction: .inbound, groups: []),
        outbound: PortSection(direction: .outbound, groups: [])
    )

    let inboundCount: Int
    let outboundCount: Int
    let services: [(entry: PortEntry, binding: ServiceBinding)]
    let inbound: PortSection
    let outbound: PortSection

    func filtered(query: String, showOutbound: Bool) -> MenuSnapshot {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return self }

        let filteredServices = services.filter { service in
            service.entry.matchesSearch(needle, extraTerms: [service.binding.domain])
        }
        let inboundGroups = inbound.groups.compactMap { $0.filtered(matching: needle) }
        let outboundGroups = showOutbound
            ? outbound.groups.compactMap { $0.filtered(matching: needle) }
            : outbound.groups

        return MenuSnapshot(
            inboundCount: inboundCount,
            outboundCount: outboundCount,
            services: filteredServices,
            inbound: PortSection(direction: .inbound, groups: inboundGroups),
            outbound: PortSection(direction: .outbound, groups: outboundGroups)
        )
    }

    func fingerprint(showOutbound: Bool, needsLicense: Bool, searchQuery: String = "") -> String {
        var parts = [
            "\(inboundCount)",
            "\(outboundCount)",
            showOutbound ? "out" : "in",
            needsLicense ? "lic" : "ok",
            "q:\(searchQuery)"
        ]
        parts.append(contentsOf: services.map { service in
            "\(service.binding.domain)#\(service.binding.usesHTTPS)#\(service.entry.processIdentity)#\(service.entry.port)"
        })
        parts.append(contentsOf: inbound.groups.map(Self.groupFingerprint))
        if showOutbound {
            parts.append(contentsOf: outbound.groups.map(Self.groupFingerprint))
        }
        return parts.joined(separator: "|")
    }

    private static func groupFingerprint(_ group: PortGroup) -> String {
        let entries = group.entries.map { entry in
            let docker = entry.dockerContainers.map(\.id).joined(separator: ",")
            return "\(entry.processIdentity)#\(entry.localEndpoint)#\(entry.currentWorkingDirectory ?? "")#\(docker)"
        }.joined(separator: ",")
        return "\(group.port):\(group.title):\(group.subtitle ?? ""):\(entries)"
    }
}

private final class PortMenuContext: NSObject {
    let entry: PortEntry
    let domain: String?
    let usesHTTPS: Bool

    init(entry: PortEntry, domain: String?, usesHTTPS: Bool = false) {
        self.entry = entry
        self.domain = domain
        self.usesHTTPS = usesHTTPS
    }
}
