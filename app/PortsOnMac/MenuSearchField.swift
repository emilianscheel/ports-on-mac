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
    private let caretView = MenuSearchCaretView(frame: .zero)
    private var caretTimer: Timer?
    private var caretOn = true

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
        container.onDetachedFromWindow = { [weak self] in
            self?.stopCaretBlink()
        }
    }

    func clear() {
        searchField.stringValue = ""
        updateClearButton()
        updateCaretPosition()
    }

    func restoreFocus() {
        guard let window = searchField.window else { return }
        window.makeKey()
        window.makeFirstResponder(searchField)
        if searchField.currentEditor() == nil {
            searchField.selectText(nil)
        }
        searchField.makeEditorTransparent()
        hideSystemCaret()
        startCaretBlink()
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
        searchField.controlSize = .regular
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
            cell.controlSize = .regular
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
        iconView.frame = NSRect(x: 18, y: 6, width: 16, height: 16)
        clearButton.frame = NSRect(x: container.bounds.width - 34, y: 6, width: 16, height: 16)
        clearButton.autoresizingMask = [.minXMargin]
        searchField.frame = searchFieldFrame(showingClear: false)
        searchField.autoresizingMask = [.width]
        caretView.isHidden = true
        container.addSubview(iconView)
        container.addSubview(searchField)
        container.addSubview(clearButton)
        container.addSubview(caretView)
    }

    private func searchFieldFrame(showingClear: Bool) -> NSRect {
        NSRect(
            x: 38,
            y: 5,
            width: container.bounds.width - (showingClear ? 64 : 54),
            height: 18
        )
    }

    private func updateClearButton() {
        clearButton.isHidden = searchField.stringValue.isEmpty
        searchField.frame = searchFieldFrame(showingClear: !clearButton.isHidden)
    }

    private func hideSystemCaret() {
        (searchField.currentEditor() as? NSTextView)?.insertionPointColor = .clear
    }

    private func startCaretBlink() {
        caretOn = true
        caretView.alphaValue = 1
        caretView.isHidden = false
        updateCaretPosition()
        caretTimer?.invalidate()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.toggleCaret()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        caretTimer = timer
    }

    private func stopCaretBlink() {
        caretTimer?.invalidate()
        caretTimer = nil
        caretView.isHidden = true
    }

    private func toggleCaret() {
        caretOn.toggle()
        caretView.alphaValue = caretOn ? 1 : 0
    }

    private func restartCaretBlink() {
        caretOn = true
        caretView.alphaValue = 1
        caretView.isHidden = false
        updateCaretPosition()
        startCaretBlink()
    }

    private func updateCaretPosition() {
        let font = searchField.font ?? NSFont.menuFont(ofSize: 13)
        let height = ceil(font.ascender - font.descender)
        var x = searchField.frame.minX

        if let editor = searchField.currentEditor() as? NSTextView {
            let location = min(editor.selectedRange.location, (editor.string as NSString).length)
            let screenRect = editor.firstRect(
                forCharacterRange: NSRange(location: location, length: 0),
                actualRange: nil
            )
            if let window = container.window, screenRect != .zero {
                let windowRect = window.convertFromScreen(screenRect)
                x = container.convert(windowRect, from: nil).minX
            } else {
                x = searchField.frame.minX + textWidth(searchField.stringValue, font: font)
            }
        } else {
            x = searchField.frame.minX + textWidth(searchField.stringValue, font: font)
        }

        caretView.frame = NSRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: (iconView.frame.midY - height / 2).rounded(.toNearestOrAwayFromZero),
            width: 1,
            height: height
        )
    }

    private func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private func moveSelectionIntoMenu() {
        guard let menu = menuItem.menu else { return }
        stopCaretBlink()
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
        hideSystemCaret()
        restartCaretBlink()
        onQueryChange?(searchField.stringValue)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        searchField.makeEditorTransparent()
        hideSystemCaret()
        startCaretBlink()
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
                restoreFocus()
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
        (currentEditor() as? NSTextView)?.insertionPointColor = .clear
        return result
    }

    func makeEditorTransparent() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.insertionPointColor = .clear
        if let scrollView = editor.enclosingScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
        }
    }
}

private final class MenuSearchFieldCell: NSSearchFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: alignedTextRect(for: cellFrame), in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        alignedTextRect(for: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        alignedTextRect(for: rect)
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        alignedTextRect(for: rect)
    }

    private func alignedTextRect(for rect: NSRect) -> NSRect {
        let font = self.font ?? NSFont.menuFont(ofSize: 13)
        let lineHeight = ceil(font.ascender - font.descender)
        var aligned = rect
        aligned.origin.y = floor((rect.height - lineHeight) / 2) + 1
        aligned.size.height = lineHeight
        return aligned
    }
}

private final class MenuSearchCaretView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        bounds.fill()
    }
}

private final class MenuSearchContainerView: NSView {
    var onAttachedToWindow: (() -> Void)?
    var onDetachedFromWindow: (() -> Void)?

    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            onDetachedFromWindow?()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onAttachedToWindow?()
        }
    }
}
