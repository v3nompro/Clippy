import AppKit
import ClippyCore

private var failures = 0
private func record(_ pass: Bool, _ message: String, file: StaticString, line: UInt) {
    if !pass { failures += 1; print("FAIL \(file):\(line): \(message)") }
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    record(a == b, "\(a) != \(b)", file: file, line: line)
}
private func expectNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    record(a != b, "Unexpected equal values", file: file, line: line)
}
private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    record(value, "Expected true", file: file, line: line)
}
private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    record(!value, "Expected false", file: file, line: line)
}
private func expectNil<T>(_ value: T?, _ message: String = "Expected nil", file: StaticString = #filePath, line: UInt = #line) {
    record(value == nil, message, file: file, line: line)
}
private func expectAtMost<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    record(a <= b, "Value exceeded its limit", file: file, line: line)
}
private func expectThrows<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body(); record(false, "Expected an error", file: file, line: line) } catch { }
}

@main
enum CheckRunner {
    static func main() {
        let suite = HistoryTests()
        let checks: [(String, () throws -> Void)] = [
            ("Persistence, formatting, and file permissions", suite.testPersistsRichClipboardAcrossReopening),
            ("Duplicate recency and pin preservation", suite.testDuplicateMovesToTopWithoutLosingPin),
            ("25-item eviction", suite.testOldestUnpinnedItemEvictedAt25),
            ("All-pinned protection", suite.testAllPinnedHistoryRejectsNewCopies),
            ("32 MiB storage budget", suite.testByteBudgetEvictsLargeOldCopies),
            ("Clear and delete semantics", suite.testClearPreservesPinsAndDeleteAllRemovesThem),
            ("Stable content deduplication", suite.testFingerprintIsIndependentOfRepresentationOrder),
            ("Multi-item private pasteboard round trip", suite.testPrivatePasteboardRoundTripPreservesAllItemsAndFormatting),
            ("Confidential clipboard filtering", suite.testConfidentialAndTransientCopiesAreSkipped),
            ("Unsupported and oversized clipboard rejection", suite.testOversizeAndUnsupportedCopiesAreRejected),
            ("File reference preservation", suite.testMultiFileReferencesAreRetainedWithoutOpeningFiles),
            ("Unicode and embedded NUL persistence", suite.testUnicodeAndEmbeddedNullRemainSearchable),
            ("Mixed confidential clipboard rejection", suite.testSensitiveItemRejectsEntireMultiItemCopy),
            ("Invalid writes preserve existing clipboard", suite.testEmptyWriteDoesNotClearPasteboard),
            ("Exact item-size boundary", suite.testExactSizeLimitIsAccepted),
            ("Unpinning restores chronological ordering", suite.testUnpinRestoresRecencyOrder)
        ]
        for (name, check) in checks {
            let before = failures
            do { try suite.setUpWithError(); try check() }
            catch { failures += 1; print("FAIL \(name): \(error)") }
            do { try suite.tearDownWithError() }
            catch { failures += 1; print("FAIL cleanup: \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(checks.count) checks; \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

final class HistoryTests {
    private var directory: URL!
    private var store: HistoryStore!

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClippyTests-\(UUID().uuidString)")
        store = try HistoryStore(url: directory.appendingPathComponent("History.sqlite"))
    }
    func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func clip(_ text: String) -> ClipboardSnapshot {
        ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)]])
    }
    private func add(_ text: String, time: Double = 1) throws {
        try store.add(clip(text), source: "Tests", now: Date(timeIntervalSince1970: time))
    }

    func testPersistsRichClipboardAcrossReopening() throws {
        let snapshot = ClipboardSnapshot(items: [[
            NSPasteboard.PasteboardType.string.rawValue: Data("Hello 🌍".utf8),
            NSPasteboard.PasteboardType.html.rawValue: Data("<b>Hello 🌍</b>".utf8),
            NSPasteboard.PasteboardType.rtf.rawValue: Data("{\\rtf1 Hello}".utf8)
        ]])
        try store.add(snapshot, source: "Notes")
        store = nil
        store = try HistoryStore(url: directory.appendingPathComponent("History.sqlite"))
        expectEqual(try store.snapshot(id: snapshot.fingerprint), snapshot)
        expectEqual(try store.entries().first?.source, "Notes")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("History.sqlite").path)[.posixPermissions] as? Int
        expectEqual(permissions, 0o600)
    }

    func testDuplicateMovesToTopWithoutLosingPin() throws {
        try add("first", time: 1)
        try store.setPinned(id: clip("first").fingerprint, pinned: true)
        try add("second", time: 2)
        try add("first", time: 3)
        let entries = try store.entries()
        expectEqual(entries.count, 2)
        expectEqual(entries.first?.title, "first")
        expectEqual(entries.first?.pinned, true)
        expectEqual(entries.first?.copiedAt, Date(timeIntervalSince1970: 3))
    }

    func testOldestUnpinnedItemEvictedAt25() throws {
        try add("pinned", time: 0)
        try store.setPinned(id: clip("pinned").fingerprint, pinned: true)
        for number in 1...30 { try add("copy \(number)", time: Double(number)) }
        let entries = try store.entries()
        expectEqual(entries.count, 25)
        expectEqual(entries.first?.title, "pinned")
        expectEqual(entries.last?.title, "copy 7")
        expectNil(try store.snapshot(id: clip("copy 1").fingerprint))
    }

    func testAllPinnedHistoryRejectsNewCopies() throws {
        for number in 1...25 {
            let snapshot = clip("pin \(number)")
            try store.add(snapshot, source: "Tests")
            try store.setPinned(id: snapshot.fingerprint, pinned: true)
        }
        expectFalse(try store.add(clip("new copy"), source: "Tests"))
        expectEqual(try store.entries().count, 25)
        expectTrue(try store.entries().allSatisfy(\.pinned))
    }

    func testByteBudgetEvictsLargeOldCopies() throws {
        for number in 0..<12 {
            let snapshot = ClipboardSnapshot(items: [["public.png": Data(repeating: UInt8(number), count: 3 * 1_024 * 1_024)]])
            try store.add(snapshot, source: "Tests", now: Date(timeIntervalSince1970: Double(number)))
        }
        let entries = try store.entries()
        expectEqual(entries.count, 10)
        expectAtMost(entries.reduce(0) { $0 + $1.byteCount }, HistoryStore.byteLimit)
    }

    func testClearPreservesPinsAndDeleteAllRemovesThem() throws {
        try add("keep")
        try store.setPinned(id: clip("keep").fingerprint, pinned: true)
        try add("discard")
        try store.clear()
        expectEqual(try store.entries().map(\.title), ["keep"])
        try store.clear(includePinned: true)
        expectTrue(try store.entries().isEmpty)
        expectNil(try store.snapshot(id: clip("keep").fingerprint))
    }

    func testFingerprintIsIndependentOfRepresentationOrder() {
        let first = ClipboardSnapshot(items: [["public.utf8-plain-text": Data("text".utf8), "public.html": Data("<b>text</b>".utf8)]])
        var second: [String: Data] = [:]
        second["public.html"] = Data("<b>text</b>".utf8)
        second["public.utf8-plain-text"] = Data("text".utf8)
        expectEqual(first.fingerprint, ClipboardSnapshot(items: [second]).fingerprint)
        expectNotEqual(first.fingerprint, clip("text").fingerprint)
    }

    func testPrivatePasteboardRoundTripPreservesAllItemsAndFormatting() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let snapshot = ClipboardSnapshot(items: [
            ["public.utf8-plain-text": Data("one".utf8), "public.html": Data("<b>one</b>".utf8)],
            ["public.utf8-plain-text": Data("two".utf8)]
        ])
        expectTrue(snapshot.write(to: board))
        expectEqual(ClipboardSnapshot(pasteboard: board), snapshot)
    }

    func testConfidentialAndTransientCopiesAreSkipped() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        // Older pasteboard APIs exposed a non-UTI "Pasteboard generator type";
        // modern NSPasteboardItem refuses to create that representation.
        for type in ClipboardSnapshot.ignoredTypes where !type.contains(" ") {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString("private value", forType: .string)
            item.setData(Data(), forType: .init(type))
            expectTrue(board.writeObjects([item]))
            expectNil(ClipboardSnapshot(pasteboard: board), "Captured sensitive type: \(type)")
        }
    }

    func testOversizeAndUnsupportedCopiesAreRejected() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let large = ClipboardSnapshot(items: [["public.utf8-plain-text": Data(repeating: 65, count: ClipboardSnapshot.maximumBytes + 1)]])
        expectTrue(large.write(to: board))
        expectNil(ClipboardSnapshot(pasteboard: board))
        expectThrows(try store.add(large, source: "Tests"))
        board.clearContents()
        expectTrue(board.setData(Data([1, 2]), forType: .init("unsupported.custom-format")))
        expectNil(ClipboardSnapshot(pasteboard: board))
        expectTrue(try store.entries().isEmpty)
    }

    func testMultiFileReferencesAreRetainedWithoutOpeningFiles() {
        let snapshot = ClipboardSnapshot(items: [
            ["public.file-url": Data("file:///tmp/first.txt".utf8)],
            ["public.file-url": Data("file:///tmp/second.txt".utf8)]
        ])
        expectEqual(snapshot.kind, "file")
        expectEqual(snapshot.title, "first.txt, second.txt")
    }

    func testUnicodeAndEmbeddedNullRemainSearchable() throws {
        let text = "Hello 🌍\0日本語 café"
        try add(text)
        let entry = try store.entries().first!
        expectEqual(entry.title, text)
        expectEqual(entry.searchText, text)
        expectEqual(try store.snapshot(id: entry.id)?.text, text)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        expectEqual(permissions, 0o700)
    }

    func testSensitiveItemRejectsEntireMultiItemCopy() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let ordinary = NSPasteboardItem()
        ordinary.setString("ordinary text", forType: .string)
        let confidential = NSPasteboardItem()
        confidential.setString("private test fixture", forType: .string)
        confidential.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        expectTrue(board.writeObjects([ordinary, confidential]))
        expectNil(ClipboardSnapshot(pasteboard: board))
    }

    func testEmptyWriteDoesNotClearPasteboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        expectTrue(clip("original").write(to: board))
        let count = board.changeCount
        expectFalse(ClipboardSnapshot(items: [[:]]).write(to: board))
        expectEqual(board.changeCount, count)
        expectEqual(board.string(forType: .string), "original")
    }

    func testExactSizeLimitIsAccepted() throws {
        let snapshot = ClipboardSnapshot(items: [["public.utf8-plain-text": Data(repeating: 65, count: ClipboardSnapshot.maximumBytes)]])
        expectTrue(try store.add(snapshot, source: "Tests"))
        expectEqual(try store.snapshot(id: snapshot.fingerprint), snapshot)
    }

    func testUnpinRestoresRecencyOrder() throws {
        try add("older", time: 1)
        try add("newer", time: 2)
        let id = clip("older").fingerprint
        try store.setPinned(id: id, pinned: true)
        expectEqual(try store.entries().first?.title, "older")
        try store.setPinned(id: id, pinned: false)
        expectEqual(try store.entries().map(\.title), ["newer", "older"])
    }
}
