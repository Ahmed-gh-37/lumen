import Foundation

/// The workspace contains user content and preferences; provider keys live only in Keychain.
public final class WorkspaceStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var file: URL { directory.appendingPathComponent("workspace.json") }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    public func load() throws -> WorkspaceData {
        lock.lock()
        defer { lock.unlock() }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return WorkspaceData()
        }
        // Decode errors propagate. A damaged or newer workspace must never be silently replaced.
        let data = try JSONDecoder().decode(WorkspaceData.self, from: bytes)
        guard data.version == 1 else { throw WorkspaceStoreError.unsupportedVersion(data.version) }
        return data
    }

    public func save(_ data: WorkspaceData) throws {
        lock.lock()
        defer { lock.unlock() }
        guard data.version == 1 else { throw WorkspaceStoreError.unsupportedVersion(data.version) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(data)
        // Foundation writes a sibling file then renames it, preserving the old file on failure.
        try bytes.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

public enum WorkspaceStoreError: LocalizedError {
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return
                "This workspace uses format \(version), which this version of Lumen cannot open. Its saved data has been preserved."
        }
    }
}
