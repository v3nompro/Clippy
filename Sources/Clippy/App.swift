import AppKit
import ClippyCore
import ServiceManagement

@main
enum ClippyApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preview = CommandLine.arguments.contains("--preview")
    private let work = DispatchQueue(label: "app.clippy.history", qos: .userInitiated)
    private var store: HistoryStore?
    private var statusItem: NSStatusItem!
    private var panel: HistoryPanel!
    private var monitor: ClipboardMonitor?
    private let hotKey = GlobalHotKey()
    private let paster = PasteController()
    private var target: NSRunningApplication?
    private var pendingChoice: UUID?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var toast: NSPanel?
    private var hasStorageError = false
    private lazy var previewPasteboard = NSPasteboard.withUniqueName()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        panel = HistoryPanel(preview: preview)
        panel.onChoose = { [weak self] in self?.choose($0) }
        panel.onPin = { [weak self] entry in self?.change { try $0.setPinned(id: entry.id, pinned: !entry.pinned) } }
        panel.onDelete = { [weak self] entry in self?.change { try $0.delete(id: entry.id) } }
        panel.onClear = { [weak self] in self?.change { try $0.clear() } }
        panel.onSettings = { [weak self] button in self?.options().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 5), in: button) }
        panel.onPermission = { [weak self] in self?.panel.dismiss(); PasteController.requestPermission() }
        panel.onClose = { [weak self] in self?.pendingChoice = nil; self?.paster.cancel() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippy clipboard history")
        statusItem.button?.toolTip = "Clippy — Clipboard history (⌥V)"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let dataURL: URL
        if preview {
            dataURL = FileManager.default.temporaryDirectory.appendingPathComponent("Clippy-preview-\(ProcessInfo.processInfo.processIdentifier)/History.sqlite")
        } else {
            dataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Clippy/History.sqlite")
        }
        let samples = preview ? Self.samples() : []
        work.async { [weak self] in
            guard let self else { return }
            do {
                self.store = try HistoryStore(url: dataURL)
                for (index, snapshot) in samples.enumerated() {
                    let source = ["Notes", "Safari", "Terminal", "Preview", "Safari"][index]
                    try self.store?.add(snapshot, source: source, thumbnail: ClipboardMonitor.thumbnail(for: snapshot),
                                        now: Date().addingTimeInterval(Double(index) * -95 - 60))
                    if index == 0 { try self.store?.setPinned(id: snapshot.fingerprint, pinned: true) }
                }
                let entries = try self.store?.entries() ?? []
                DispatchQueue.main.async {
                    self.panel.update(entries: entries)
                    self.ready()
                }
            } catch { DispatchQueue.main.async { self.storageFailed(error) } }
        }
        observeDismissal()
    }

    // AppKit's field editor routes standard Command shortcuts through the menu,
    // even when an accessory app has no visible menu bar of its own.
    private func installMainMenu() {
        let main = NSMenu()
        let application = NSMenuItem(title: "Clippy", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Clippy")
        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        application.submenu = appMenu
        main.addItem(application)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard panel != nil else { return false }
        if !panel.isVisible { toggle() }
        return true
    }

    private func ready() {
        if preview {
            panel.show(centered: true)
            if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.indices.contains(index + 1) {
                let output = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                    guard let view = panel.contentView,
                          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: output))
                    }
                    NSApp.terminate(nil)
                }
            }
            return
        }
        let clipboard = ClipboardMonitor()
        clipboard.onCopy = { [weak self] snapshot, source in
            self?.change { try $0.add(snapshot, source: source, thumbnail: ClipboardMonitor.thumbnail(for: snapshot)) }
        }
        clipboard.start()
        monitor = clipboard
        hotKey.onPress = { [weak self] in self?.toggle() }
        if !hotKey.register() {
            panel.setStatus("⌥V is in use")
            statusItem.button?.toolTip = "Clippy — ⌥V is already in use. Click to open history."
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            toggle()
        }
    }

    private func change(_ action: @escaping (HistoryStore) throws -> Void) {
        work.async { [weak self] in
            guard let self, let store = self.store else { return }
            do {
                try action(store)
                let entries = try store.entries()
                DispatchQueue.main.async { self.panel.update(entries: entries) }
            } catch { DispatchQueue.main.async { self.storageFailed(error) } }
        }
    }
    private func storageFailed(_ error: Error) {
        panel.setStatus("History unavailable")
        guard !hasStorageError else { return }
        hasStorageError = true
        monitor?.paused = true
        let alert = NSAlert()
        alert.messageText = "Clippy couldn’t save your history"
        alert.informativeText = error.localizedDescription + " Your existing history has been left in place."
        alert.runModal()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button {
            options().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else { toggle() }
    }
    private func toggle() {
        if panel.isVisible { panel.dismiss(); return }
        paster.cancel()
        pendingChoice = nil
        toast?.orderOut(nil)
        target = NSWorkspace.shared.frontmostApplication
        panel.show(centered: preview)
    }

    private func choose(_ entry: HistoryEntry) {
        let destination = target
        let choice = UUID()
        pendingChoice = choice
        work.async { [weak self] in
            guard let self else { return }
            do {
                guard let snapshot = try self.store?.snapshot(id: entry.id) else { return }
                DispatchQueue.main.async { [self] in
                    guard self.pendingChoice == choice, self.panel.isVisible else { return }
                    // Preview uses its own pasteboard, so it cannot replace real copied content.
                    let copied = self.preview ? snapshot.write(to: self.previewPasteboard) : self.monitor?.write(snapshot) == true
                    guard copied else { self.showToast("Couldn’t copy this item"); return }
                    self.panel.dismiss()
                    guard !self.preview, PasteController.isAllowed, let destination,
                          destination.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                        self.showToast(self.preview ? "Preview item selected" : "Copied · Press ⌘V to paste")
                        return
                    }
                    self.paster.paste(into: destination, clipboardChangeCount: NSPasteboard.general.changeCount) { [weak self] sent in
                        if !sent { self?.showToast("Auto-paste skipped · Use ⌘V") }
                    }
                }
            } catch { DispatchQueue.main.async { self.storageFailed(error) } }
        }
    }

    private func observeDismissal() {
        if !preview {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                // Let the status item's own action toggle the panel exactly once.
                if let button = self.statusItem.button, let window = button.window {
                    let rectangle = window.convertToScreen(button.convert(button.bounds, to: nil))
                    if rectangle.contains(NSEvent.mouseLocation) { return }
                }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.panel.dismiss() }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.panel.isVisible, event.window !== self.panel,
               event.window !== self.statusItem.button?.window { self.panel.dismiss() }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != self.target?.processIdentifier else { return }
            self.panel.dismiss()
            self.paster.cancel()
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.dismiss()
            self?.paster.cancel()
        })
    }

    private func options() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, action: Selector, state: NSControl.StateValue? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let state { item.state = state }
            menu.addItem(item)
        }
        let name = NSMenuItem(title: "Clippy  ·  ⌥V", action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)
        menu.addItem(.separator())
        item("Pause clipboard history", action: #selector(togglePause), state: monitor?.paused == true ? .on : .off)
        item("Launch at login", action: #selector(toggleLogin), state: SMAppService.mainApp.status == .enabled ? .on : .off)
        if !PasteController.isAllowed { item("Enable automatic pasting…", action: #selector(enablePermission)) }
        menu.addItem(.separator())
        item("Clear history (keep pins)", action: #selector(clearHistory))
        item("Delete all history…", action: #selector(deleteAll))
        menu.addItem(.separator())
        item("Quit Clippy", action: #selector(quit))
        return menu
    }
    @objc private func togglePause() {
        monitor?.paused.toggle()
        panel.setStatus(monitor?.paused == true ? "History paused" : "On this Mac")
        statusItem.button?.appearsDisabled = monitor?.paused == true
    }
    @objc private func enablePermission() { panel.dismiss(); PasteController.requestPermission() }
    @objc private func toggleLogin() {
        guard !preview else { showToast("Available in the installed app"); return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showToast("Move Clippy to Applications, then try again") }
    }
    @objc private func clearHistory() { change { try $0.clear() } }
    @objc private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all clipboard history?"
        alert.informativeText = "This also deletes pinned items."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { change { try $0.clear(includePinned: true) } }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        monitor?.paused = true
        work.sync {} // Finish any committed captures before quitting.
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        if preview { previewPasteboard.releaseGlobally() }
    }

    private func showToast(_ message: String) {
        toast?.orderOut(nil)
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 310, height: 45))
        view.material = .popover
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 14, width: 290, height: 18)
        view.addSubview(label)
        let window = NSPanel(contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = view
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 155, y: screen.visibleFrame.minY + 80))
        }
        window.orderFrontRegardless()
        toast = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak window] in window?.orderOut(nil) }
    }

    private static func samples() -> [ClipboardSnapshot] {
        func text(_ string: String) -> ClipboardSnapshot { .init(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(string.utf8)]]) }
        let image = NSImage(size: NSSize(width: 240, height: 140))
        image.lockFocus()
        NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 240, height: 140)).fill()
        NSColor(calibratedRed: 0.52, green: 0.80, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 165, y: 80, width: 36, height: 36)).fill()
        NSColor(calibratedRed: 0.26, green: 0.49, blue: 0.48, alpha: 1).setFill()
        let mountain = NSBezierPath()
        mountain.move(to: .zero); mountain.line(to: NSPoint(x: 85, y: 105))
        mountain.line(to: NSPoint(x: 160, y: 22)); mountain.line(to: NSPoint(x: 210, y: 73))
        mountain.line(to: NSPoint(x: 240, y: 0)); mountain.close(); mountain.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = bitmap.representation(using: .png, properties: [:])!
        return [
            text("Good ideas deserve a place to land."),
            text("https://developer.apple.com/documentation/appkit"),
            text("swift build -c release"),
            ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.png.rawValue: png]]),
            text("Small tools. Fewer distractions. More flow.")
        ]
    }
}
