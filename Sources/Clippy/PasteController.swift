import AppKit
import ApplicationServices

final class PasteController {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        guard !isAllowed else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var attempt: UUID?
    func cancel() { attempt = nil }

    /// Never paste into an app the user switched to while the panel was closing.
    /// Wait for the opening/selection modifiers to be released to avoid Cmd-Option-V.
    func paste(into target: NSRunningApplication, clipboardChangeCount: Int, completion: @escaping (Bool) -> Void) {
        let id = UUID()
        attempt = id
        let deadline = Date().addingTimeInterval(1.5)
        func deliver() {
            guard self.attempt == id else { return }
            guard Self.isAllowed, !target.isTerminated,
                  NSPasteboard.general.changeCount == clipboardChangeCount,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                self.attempt = nil
                completion(false)
                return
            }
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            if !held.isEmpty {
                guard Date() < deadline else { self.attempt = nil; completion(false); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: deliver)
                return
            }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                self.attempt = nil
                completion(false)
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            self.attempt = nil
            completion(true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: deliver)
    }
}
