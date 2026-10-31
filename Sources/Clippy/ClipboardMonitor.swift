import AppKit
import Carbon
import ClippyCore
import ImageIO
import UniformTypeIdentifiers

final class ClipboardMonitor {
    var onCopy: ((ClipboardSnapshot, String) -> Void)?
    var paused = false
    private var timer: Timer?
    private var lastChange: Int
    private let pasteboard: NSPasteboard
    private let excludedSources: Set<String> = [
        "com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop",
        "com.apple.Passwords", "org.keepassxc.keepassxc"
    ]

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChange = pasteboard.changeCount // Do not import the clipboard from before the app started.
    }
    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChange else { return }
        lastChange = count
        guard !paused, !IsSecureEventInputEnabled() else { return }
        let source = NSWorkspace.shared.frontmostApplication
        guard !excludedSources.contains(source?.bundleIdentifier ?? ""),
              let snapshot = ClipboardSnapshot(pasteboard: pasteboard) else { return }
        onCopy?(snapshot, source?.localizedName ?? "Clipboard")
    }
    func write(_ snapshot: ClipboardSnapshot) -> Bool {
        let result = snapshot.write(to: pasteboard)
        lastChange = pasteboard.changeCount
        return result
    }
    deinit { timer?.invalidate() }

    static func thumbnail(for snapshot: ClipboardSnapshot) -> Data? {
        guard let data = snapshot.imageData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
