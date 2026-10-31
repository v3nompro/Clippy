import AppKit
import ApplicationServices
import ClippyCore

private let accent = NSColor(calibratedRed: 0.39, green: 0.85, blue: 0.74, alpha: 1)

private func textLabel(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    return label
}

final class ActionButton: NSButton {
    var perform: (() -> Void)?
    init(symbol: String, help: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        isBordered = false
        bezelStyle = .inline
        contentTintColor = .secondaryLabelColor
        toolTip = help
        setAccessibilityLabel(help)
        target = self
        self.action = #selector(invoke)
        perform = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { perform?() }
}

private final class ClipboardRow: NSTableRowView {
    override var isSelected: Bool { didSet { needsDisplay = true } }
    override func drawBackground(in dirtyRect: NSRect) {
        guard isSelected else { return }
        accent.withAlphaComponent(0.12).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10)
        path.fill()
        accent.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override func drawSelection(in dirtyRect: NSRect) {}
}

private final class ClipboardCell: NSTableCellView {
    init(entry: HistoryEntry, pin: @escaping () -> Void, delete: @escaping () -> Void) {
        super.init(frame: .zero)
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 7
        icon.layer?.masksToBounds = true
        if let data = entry.thumbnail, let image = NSImage(data: data) {
            icon.image = image
        } else {
            icon.image = NSImage(systemSymbolName: entry.kind == "file" ? "doc.on.doc" : "doc.text", accessibilityDescription: entry.kind)
            icon.contentTintColor = accent.withAlphaComponent(0.85)
            icon.symbolConfiguration = .init(pointSize: 20, weight: .regular)
            icon.layer?.backgroundColor = accent.withAlphaComponent(0.07).cgColor
        }
        let title = textLabel(entry.title.isEmpty ? "Empty text" : entry.title, size: 12.5, weight: .medium)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.cell?.wraps = true
        let age = RelativeDateTimeFormatter()
        age.unitsStyle = .short
        let metadata = textLabel("\(entry.source)  ·  \(age.localizedString(for: entry.copiedAt, relativeTo: Date()))",
                                 size: 10.5, color: .secondaryLabelColor)
        metadata.lineBreakMode = .byTruncatingTail
        let pinButton = ActionButton(symbol: entry.pinned ? "pin.fill" : "pin", help: entry.pinned ? "Unpin item" : "Pin item", action: pin)
        if entry.pinned { pinButton.contentTintColor = accent }
        let deleteButton = ActionButton(symbol: "xmark", help: "Delete item", action: delete)
        for view in [icon, title, metadata, pinButton, deleteButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38), icon.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            title.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -7),
            metadata.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            metadata.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor), pinButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor), deleteButton.widthAnchor.constraint(equalToConstant: 22)
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel("\(entry.title), \(entry.source)\(entry.pinned ? ", pinned" : "")")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class HistoryPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onChoose: ((HistoryEntry) -> Void)?
    var onPin: ((HistoryEntry) -> Void)?
    var onDelete: ((HistoryEntry) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: ((NSButton) -> Void)?
    var onPermission: (() -> Void)?
    var onClose: (() -> Void)?
    private let search = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let countLabel = textLabel("RECENT COPIES", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let statusLabel = textLabel("On this Mac", size: 10.5, color: .secondaryLabelColor)
    private let permission = NSStackView()
    private let empty = NSStackView()
    private let emptyTitle = textLabel("Your clipboard starts here", size: 16, weight: .medium)
    private let emptyDetail = textLabel("Copy something, then press ⌥V to find it here.", size: 11.5, color: .secondaryLabelColor)
    private var allEntries: [HistoryEntry] = []
    private var visibleEntries: [HistoryEntry] = []
    private var keyMonitor: Any?
    private var permissionTimer: Timer?
    private var bannerHeight: NSLayoutConstraint!
    private let preview: Bool

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(preview: Bool) {
        self.preview = preview
        super.init(contentRect: NSRect(x: 0, y: 0, width: 392, height: 574),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        title = "Clippy Clipboard History"
        buildInterface()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func buildInterface() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        contentView = root

        let brand = textLabel("CLIPPY", size: 10, weight: .bold, color: accent)
        let title = textLabel("Clipboard", size: 23, weight: .semibold)
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .inline
        clear.font = .systemFont(ofSize: 11)
        clear.contentTintColor = .secondaryLabelColor
        clear.toolTip = "Clear history, keeping pinned items"
        let settings = ActionButton(symbol: "ellipsis.circle", help: "Clippy options") { }
        settings.perform = { [weak self, weak settings] in
            if let settings { self?.onSettings?(settings) }
        }
        search.placeholderString = "Search your clipboard"
        search.controlSize = .large
        search.font = .systemFont(ofSize: 13)
        search.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search clipboard history")

        permission.orientation = .horizontal
        permission.spacing = 10
        permission.alignment = .centerY
        permission.wantsLayer = true
        permission.layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
        permission.layer?.cornerRadius = 9
        permission.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 9)
        let permissionText = textLabel("Enable direct paste into your apps", size: 11)
        let enable = NSButton(title: "Enable", target: self, action: #selector(enablePaste))
        enable.bezelStyle = .rounded
        enable.controlSize = .small
        permission.addArrangedSubview(permissionText)
        permission.addArrangedSubview(NSView())
        permission.addArrangedSubview(enable)

        let column = NSTableColumn(identifier: .init("clipboard"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 82
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clickedRow)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("Clipboard items")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)!)
        emptyIcon.contentTintColor = accent.withAlphaComponent(0.6)
        emptyIcon.symbolConfiguration = .init(pointSize: 32, weight: .light)
        empty.orientation = .vertical
        empty.alignment = .centerX
        empty.spacing = 13
        empty.addArrangedSubview(emptyIcon)
        empty.addArrangedSubview(emptyTitle)
        empty.addArrangedSubview(emptyDetail)

        let line = NSBox()
        line.boxType = .separator
        let dot = textLabel("●", size: 7, color: accent)
        let hints = textLabel("↑↓ navigate    ↵ paste    esc close", size: 10, color: .secondaryLabelColor)
        for view in [brand, title, clear, settings, search, permission, countLabel, scroll, empty, line, dot, statusLabel, hints] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        bannerHeight = permission.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: root.topAnchor, constant: 21), brand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 21),
            title.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 6), title.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -19), settings.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            settings.widthAnchor.constraint(equalToConstant: 24),
            clear.trailingAnchor.constraint(equalTo: settings.leadingAnchor, constant: -11), clear.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18), search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), search.heightAnchor.constraint(equalToConstant: 32),
            permission.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10), permission.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            permission.trailingAnchor.constraint(equalTo: search.trailingAnchor), bannerHeight,
            countLabel.topAnchor.constraint(equalTo: permission.bottomAnchor, constant: 13), countLabel.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 9),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -9), scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -9),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), line.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            line.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -41),
            dot.leadingAnchor.constraint(equalTo: brand.leadingAnchor), dot.centerYAnchor.constraint(equalTo: hints.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6), statusLabel.centerYAnchor.constraint(equalTo: hints.centerYAnchor),
            hints.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), hints.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -15)
        ])
        refreshPermission()
        reload(resetSelection: true)
    }

    func refreshPermission() {
        let allowed = preview || PasteController.isAllowed
        permission.isHidden = allowed
        bannerHeight.constant = allowed ? 0 : 42
    }
    func update(entries: [HistoryEntry]) {
        allEntries = entries
        reload(resetSelection: false)
    }
    func setStatus(_ text: String) { statusLabel.stringValue = text }
    func show(centered: Bool = false) {
        search.stringValue = ""
        refreshPermission()
        reload(resetSelection: true)
        if centered {
            center()
        } else {
            positionNearInsertionPoint()
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        permissionTimer?.invalidate()
        if !preview {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPermission() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
        }
    }
    func dismiss() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        orderOut(nil)
        onClose?()
    }
    private func reload(resetSelection: Bool) {
        let oldID = visibleEntries.indices.contains(table.selectedRow) ? visibleEntries[table.selectedRow].id : nil
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleEntries = allEntries.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) }
        table.reloadData()
        let index = resetSelection ? 0 : visibleEntries.firstIndex { $0.id == oldID } ?? max(0, table.selectedRow)
        if !visibleEntries.isEmpty { table.selectRowIndexes(IndexSet(integer: min(index, visibleEntries.count - 1)), byExtendingSelection: false) }
        countLabel.stringValue = query.isEmpty ? "RECENT COPIES  ·  \(allEntries.count) / 25" : "\(visibleEntries.count) \(visibleEntries.count == 1 ? "RESULT" : "RESULTS")"
        empty.isHidden = !visibleEntries.isEmpty
        emptyTitle.stringValue = query.isEmpty ? "Your clipboard starts here" : "No matching copies"
        emptyDetail.stringValue = query.isEmpty ? "Copy something, then press ⌥V to find it here." : "Try another word or app name."
        scroll.isHidden = visibleEntries.isEmpty
    }
    func controlTextDidChange(_ notification: Notification) { reload(resetSelection: true) }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipboardRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row) else { return nil }
        let entry = visibleEntries[row]
        return ClipboardCell(entry: entry, pin: { [weak self] in self?.onPin?(entry) }, delete: { [weak self] in self?.onDelete?(entry) })
    }
    @objc private func clickedRow() {
        guard visibleEntries.indices.contains(table.clickedRow) else { return }
        onChoose?(visibleEntries[table.clickedRow])
    }
    @objc private func clearHistory() { onClear?() }
    @objc private func enablePaste() { onPermission?() }

    private func handle(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { dismiss(); return true }
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 51, visibleEntries.indices.contains(table.selectedRow) {
                onDelete?(visibleEntries[table.selectedRow]); return true
            }
            if event.charactersIgnoringModifiers?.lowercased() == "p", visibleEntries.indices.contains(table.selectedRow) {
                onPin?(visibleEntries[table.selectedRow]); return true
            }
            if let value = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(value), visibleEntries.indices.contains(value - 1) {
                onChoose?(visibleEntries[value - 1]); return true
            }
            return false
        }
        switch event.keyCode {
        case 125, 126:
            guard !visibleEntries.isEmpty else { return true }
            let row = min(max(0, table.selectedRow + (event.keyCode == 125 ? 1 : -1)), visibleEntries.count - 1)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case 36, 76:
            if visibleEntries.indices.contains(table.selectedRow) { onChoose?(visibleEntries[table.selectedRow]) }
            return true
        default: return false
        }
    }

    private func positionNearInsertionPoint() {
        let pointer = NSEvent.mouseLocation
        let caret = insertionPoint()
        let anchor = caret.map { NSPoint(x: $0.minX, y: $0.minY) } ?? pointer
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { center(); return }
        var origin = NSPoint(x: anchor.x, y: anchor.y - frame.height - 10)
        if origin.y < visible.minY + 12, let caret { origin.y = caret.maxY + 10 }
        origin.x = max(visible.minX + 12, min(origin.x, visible.maxX - frame.width - 12))
        origin.y = max(visible.minY + 12, min(origin.y, visible.maxY - frame.height - 12))
        setFrameOrigin(origin)
    }
    private func insertionPoint() -> NSRect? {
        guard PasteController.isAllowed else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)
        var range: CFTypeRef?
        var bounds: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rectangle = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rectangle), rectangle.height > 0, rectangle.origin.x.isFinite,
              rectangle.origin.y.isFinite else { return nil }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rectangle.minX, y: desktopTop - rectangle.maxY, width: rectangle.width, height: rectangle.height)
    }
    deinit {
        permissionTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
