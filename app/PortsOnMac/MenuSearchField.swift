import AppKit

@MainActor
final class MenuSearchFieldController: NSObject, NSSearchFieldDelegate {
    let menuItem = NSMenuItem()
    var onQueryChange: ((String) -> Void)?

    var query: String {
        searchField.stringValue
    }

    private let container = MenuSearchContainerView(
        frame: NSRect(x: 0, y: 0, width: 248, height: 28)
    )
    private let iconView = NSImageView(frame: .zero)
    private let searchField = MenuSearchField(frame: .zero)
    private let clearButton = NSButton(frame: .zero)

    override init() {
        super.init()
        configureIcon()
        configureSearchField()
        configureClearButton()
        layout()
        menuItem.view = container
        container.onAttachedToWindow = { [weak self] in
            self?.restoreFocus()
        }
    }

    func clear() {
        searchField.stringValue = ""
        updateClearButton()
    }

    func restoreFocus() {
        guard let window = searchField.window else { return }
        window.makeKey()
        window.makeFirstResponder(searchField)
        if searchField.currentEditor() == nil {
            searchField.selectText(nil)
        }
        searchField.makeEditorTransparent()
        showCaret()
    }

    private func configureIcon() {
        let symbol = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")?
            .withSymbolConfiguration(symbol)
        iconView.image?.isTemplate = true
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
    }

    private func configureSearchField() {
        searchField.delegate = self
        searchField.placeholderString = "Search"
        searchField.controlSize = .small
        searchField.font = NSFont.menuFont(ofSize: 13)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        if let cell = searchField.cell as? MenuSearchFieldCell {
            cell.placeholderString = "Search"
            cell.font = NSFont.menuFont(ofSize: 13)
            cell.controlSize = .small
            cell.isBordered = false
            cell.isBezeled = false
            cell.focusRingType = .none
            cell.drawsBackground = false
            cell.backgroundColor = .clear
            cell.isEditable = true
            cell.isSelectable = true
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }
    }

    private func configureClearButton() {
        let symbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")?
            .withSymbolConfiguration(symbol)
        clearButton.image?.isTemplate = true
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isHidden = true
    }

    private func layout() {
        container.autoresizingMask = [.width]
        iconView.frame = NSRect(x: 10, y: 6, width: 16, height: 16)
        clearButton.frame = NSRect(x: container.bounds.width - 26, y: 6, width: 16, height: 16)
        clearButton.autoresizingMask = [.minXMargin]
        searchField.frame = NSRect(
            x: 30,
            y: 4,
            width: container.bounds.width - 48,
            height: 20
        )
        searchField.autoresizingMask = [.width]
        container.addSubview(iconView)
        container.addSubview(searchField)
        container.addSubview(clearButton)
    }

    private func updateClearButton() {
        clearButton.isHidden = searchField.stringValue.isEmpty
        searchField.frame = NSRect(
            x: 30,
            y: 4,
            width: container.bounds.width - (clearButton.isHidden ? 38 : 48),
            height: 20
        )
    }

    private func showCaret() {
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        let location = (searchField.stringValue as NSString).length
        editor.selectedRange = NSRange(location: location, length: 0)
        editor.insertionPointColor = .controlAccentColor
        editor.updateInsertionPointStateAndRestartTimer(true)
    }

    private func moveSelectionIntoMenu() {
        guard let menu = menuItem.menu else { return }
        searchField.window?.makeFirstResponder(nil)

        let selectable = menu.items.first { item in
            item !== menuItem
                && !item.isSeparatorItem
                && item.view == nil
                && (item.isEnabled || item.submenu != nil)
        }

        if let selectable {
            let selector = NSSelectorFromString("highlightItem:")
            if menu.responds(to: selector) {
                menu.perform(selector, with: selectable)
                return
            }
        }

        postDownArrow(to: searchField.window)
    }

    private func postDownArrow(to window: NSWindow?) {
        guard let window else { return }
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        ) else { return }
        window.postEvent(event, atStart: false)
    }

    @objc private func clearClicked() {
        searchField.stringValue = ""
        updateClearButton()
        onQueryChange?("")
        restoreFocus()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateClearButton()
        searchField.makeEditorTransparent()
        onQueryChange?(searchField.stringValue)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        searchField.makeEditorTransparent()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelectionIntoMenu()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                updateClearButton()
                onQueryChange?("")
                return true
            }
            menuItem.menu?.cancelTracking()
            return true
        }

        return false
    }
}

private final class MenuSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { MenuSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    override var allowsVibrancy: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        cell?.drawInterior(withFrame: bounds, in: self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        makeEditorTransparent()
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .controlAccentColor
            editor.updateInsertionPointStateAndRestartTimer(true)
        }
        return result
    }

    func makeEditorTransparent() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.insertionPointColor = .controlAccentColor
        if let scrollView = editor.enclosingScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
        }
    }
}

private final class MenuSearchFieldCell: NSSearchFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        rect
    }
}

private final class MenuSearchContainerView: NSView {
    var onAttachedToWindow: (() -> Void)?

    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onAttachedToWindow?()
        }
    }
}
