import XCTest

@testable import LumenCore

final class WorkspaceStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LumenStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testAbsentWorkspaceReturnsEmptyWithoutCreatingFile() throws {
        let store = try WorkspaceStore(directory: directory)
        XCTAssertEqual(try store.load(), WorkspaceData())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path))
    }

    func testAtomicRoundTripAndReplacementPreserveAllContent() throws {
        let store = try WorkspaceStore(directory: directory)
        var original = WorkspaceData()
        original.preferences.provider = .gemini
        original.preferences.personalContext = "سياق شخصي 🌓"
        var prompter = TeleprompterSettings()
        prompter.script = "Welcome to the presentation. أهلاً بكم"
        prompter.fontSize = 44
        prompter.speed = 55
        prompter.followVoice = false
        original.preferences.teleprompter = prompter
        var notch = NotchSettings()
        notch.enabled = true
        notch.automaticallyForTeleprompter = true
        notch.width = 720
        notch.readingLines = 6
        original.preferences.notch = notch
        original.notes = [
            Note(title: "Meeting", content: "A note", transcript: "Spoken words", tags: ["work"], isFavorite: true)
        ]
        original.conversations = [Conversation(title: "Question", messages: [ChatMessage(role: .user, text: "Hello")])]
        try store.save(original)
        XCTAssertEqual(try WorkspaceStore(directory: directory).load(), original)
        original.notes[0].content = "Updated contents"
        original.conversations[0].messages.append(ChatMessage(role: .assistant, text: "أهلاً"))
        try store.save(original)
        XCTAssertEqual(try store.load(), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["workspace.json"])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("workspace.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptionThrowsAndPreservesOriginalBytes() throws {
        let store = try WorkspaceStore(directory: directory)
        let file = directory.appendingPathComponent("workspace.json")
        let corrupted = Data("{\"notes\": [broken".utf8)
        try corrupted.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
    }

    func testUnsupportedVersionCannotBeLoadedOrSavedOverExistingWorkspace() throws {
        let store = try WorkspaceStore(directory: directory)
        let original = WorkspaceData()
        try store.save(original)
        var future = original
        future.version = 2
        XCTAssertThrowsError(try store.save(future))
        XCTAssertEqual(try store.load(), original)
        let futureBytes = try JSONEncoder().encode(future)
        let file = directory.appendingPathComponent("workspace.json")
        try futureBytes.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file), futureBytes)
    }

    func testExistingDirectoryAtWorkspaceFilePathIsAnError() throws {
        let store = try WorkspaceStore(directory: directory)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("workspace.json"), withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(WorkspaceData()))
    }
}
