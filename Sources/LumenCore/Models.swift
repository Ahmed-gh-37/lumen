import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPT, gemini, claude
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .gemini: return "Google Gemini"
        case .claude: return "Claude"
        }
    }
}

public enum AudioSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case microphone, system
    public var id: String { rawValue }
    public var title: String { self == .microphone ? "Microphone" : "System audio" }
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: UUID
    public var role: Role
    public var text: String
    public var createdAt: Date
    public init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct Conversation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public var updatedAt: Date
    public init(
        id: UUID = UUID(), title: String = "New conversation", messages: [ChatMessage] = [], updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var transcript: String
    public var tags: [String]
    public var isFavorite: Bool
    public var isArchived: Bool
    public var updatedAt: Date
    public init(
        id: UUID = UUID(), title: String = "Untitled note", content: String = "", transcript: String = "",
        tags: [String] = [], isFavorite: Bool = false, isArchived: Bool = false, updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.transcript = transcript
        self.tags = tags
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }
    public var markdown: String {
        "# \(title)\n\n\(content)" + (transcript.isEmpty ? "" : "\n\n## Transcript\n\n\(transcript)") + "\n"
    }
}

public enum ShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggleOverlay, ask, listen, notes, captureScreen, explainScreen, clickThrough, automaticScreen, teleprompter
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .toggleOverlay: return "Toggle overlay"
        case .ask: return "Ask"
        case .listen: return "Start or stop listening"
        case .notes: return "Open notes"
        case .captureScreen: return "Capture screen"
        case .explainScreen: return "Explain my screen"
        case .clickThrough: return "Mouse click-through"
        case .automaticScreen: return "Automatic screen explanations"
        case .teleprompter: return "Teleprompter play or pause"
        }
    }
    public var hotKeyID: UInt32 {
        switch self {
        case .toggleOverlay: return 1
        case .ask: return 2
        case .listen: return 3
        case .notes: return 4
        case .captureScreen: return 5
        case .explainScreen: return 6
        case .clickThrough: return 7
        case .automaticScreen: return 8
        case .teleprompter: return 9
        }
    }
    public var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleOverlay: return ShortcutBinding(keyCode: 49, modifiers: 3, keyLabel: "Space")
        case .ask: return ShortcutBinding(keyCode: 0, modifiers: 3, keyLabel: "A")
        case .listen: return ShortcutBinding(keyCode: 37, modifiers: 3, keyLabel: "L")
        case .notes: return ShortcutBinding(keyCode: 45, modifiers: 3, keyLabel: "N")
        case .captureScreen: return ShortcutBinding(keyCode: 1, modifiers: 3, keyLabel: "S")
        case .explainScreen: return ShortcutBinding(keyCode: 14, modifiers: 3, keyLabel: "E")
        case .clickThrough: return ShortcutBinding(keyCode: 37, modifiers: 1, keyLabel: "L")
        case .automaticScreen: return ShortcutBinding(keyCode: 11, modifiers: 1, keyLabel: "B")
        case .teleprompter: return ShortcutBinding(keyCode: 17, modifiers: 3, keyLabel: "T")
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32?
    /// Command = 1, Option = 2, Shift = 4, Control = 8.
    public var modifiers: UInt32
    public var keyLabel: String
    public init(keyCode: UInt32?, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
    public var display: String {
        guard keyCode != nil else { return "Not assigned" }
        var symbols = ""
        if modifiers & 8 != 0 { symbols += "⌃" }
        if modifiers & 2 != 0 { symbols += "⌥" }
        if modifiers & 4 != 0 { symbols += "⇧" }
        if modifiers & 1 != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }
    public func conflicts(with other: ShortcutBinding) -> Bool {
        guard let keyCode, let otherCode = other.keyCode else { return false }
        return keyCode == otherCode && modifiers == other.modifiers
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var provider: AIProvider = .chatGPT
    public var chatGPTModel: String = ""
    public var geminiModel: String = "gemini-3.8-flash"
    public var claudeModel: String = "claude-sonnet-5-5"
    public var opacity: Double = 0.96
    public var protectCapture: Bool = true
    public var localeIdentifier: String = "en-US"
    public var audioSource: AudioSource = .microphone
    public var includeListenContext: Bool = true
    public var automaticSuggestions: Bool = false
    public var personalContext: String = ""
    public var instructions: String =
        "Be a helpful, concise desktop assistant. Answer the user's question directly. Use supplied screen and conversation context only when relevant. Distinguish uncertainty."
    /// Missing actions use defaults; an explicit binding with a nil key disables that action.
    public var shortcuts: [String: ShortcutBinding]? = nil
    public var teleprompter: TeleprompterSettings? = nil
    public var notch: NotchSettings? = nil
    public init() {}
    public var selectedModel: String {
        switch provider {
        case .chatGPT: return chatGPTModel
        case .gemini: return geminiModel
        case .claude: return claudeModel
        }
    }
    public func shortcut(for action: ShortcutAction) -> ShortcutBinding {
        shortcuts?[action.rawValue] ?? action.defaultBinding
    }
}

public struct TeleprompterSettings: Codable, Equatable, Sendable {
    public var script = ""
    public var fontSize: Double = 32
    public var speed: Double = 30
    public var followVoice = true
    public init() {}
}

public struct NotchSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var automaticallyForTeleprompter = false
    public var width: Double = 640
    public var readingLines = 4
    public init() {}
}

public struct WorkspaceData: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var preferences: Preferences = .init()
    public var notes: [Note] = []
    public var conversations: [Conversation] = []
    public init() {}
}

public struct ChatGPTAccount: Equatable, Sendable {
    public var isSignedIn: Bool
    public var summary: String
    public init(isSignedIn: Bool, summary: String) {
        self.isSignedIn = isSignedIn
        self.summary = summary
    }
}

public struct ModelOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
