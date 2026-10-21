import AppKit
import Combine
import CoreGraphics
import LumenCore

enum AppPage: String {
    case ask = "Ask"
    case listen = "Listen"
    case notes = "Notes"
    case teleprompter = "Prompter"
    case settings = "Settings"
    var symbol: String {
        switch self {
        case .ask: return "bubble.left.and.text.bubble.right"
        case .listen: return "waveform"
        case .notes: return "text.book.closed"
        case .teleprompter: return "text.alignleft"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var data: WorkspaceData
    @Published var page: AppPage = .ask {
        didSet { if oldValue == .teleprompter && page != .teleprompter { pauseTeleprompter() } }
    }
    @Published var draft = ""
    @Published var error: String?
    @Published var isGenerating = false
    @Published var networkPaused = false
    @Published var account = ChatGPTAccount(isSignedIn: false, summary: "Connect your ChatGPT account")
    @Published var accountBusy = false
    @Published var models: [ModelOption] = []
    @Published var apiKeyDraft = ""
    @Published var keySaved = false
    @Published var isListening = false
    @Published var listeningBusy = false
    @Published var answersPaused = false
    @Published var transcript = ""
    @Published var audioLevel: Float = 0
    @Published var sessionStartedAt: Date?
    @Published var captureBusy = false
    @Published var attachment: CapturedScreen?
    @Published var availableDisplays: [CaptureDisplay] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var selectedNoteID: UUID?
    @Published var noteSearch = ""
    @Published var noteFilter = "All"
    @Published var notePreview = ""
    @Published var notePreviewID: UUID?
    @Published var activeConversationID: UUID
    @Published var activity: [String] = []
    @Published var recordingShortcut: ShortcutAction?
    @Published var mousePassthrough = false
    @Published var screenAccessStatus = "Not checked"
    @Published var automaticScreenState = AutomaticScreenSession.State()
    @Published var teleprompterRunning = false
    @Published var teleprompterStarting = false
    @Published var teleprompterEditing = false
    @Published var teleprompterResetID = UUID()
    @Published var teleprompterSpokenOffset: Int?
    @Published var teleprompterVoiceStatus = "Ready to follow your voice"
    @Published var notchExpanded = false
    @Published var notchSizing = false
    @Published var notchTopInset: CGFloat = 28
    @Published var notchCameraWidth: CGFloat = 94
    var teleprompterScrollOffset: CGFloat = 0
    var hideWindow: (() -> Void)?
    var applyShortcut: ((ShortcutAction, ShortcutBinding) -> String?)?
    var shortcutRecordingChanged: ((Bool) -> Void)?

    let store: WorkspaceStore
    private let chatGPT: ChatGPTClient
    private let api = APIClient()
    private let audio = AudioCapture()
    private let screen = ScreenCapture()
    private let automaticScreens = AutomaticScreenSession()
    private var saving: AnyCancellable?
    private var requestTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var loginPoll: Task<Void, Never>?
    private var lastAutoQuestion = ""
    private var generationID = UUID()
    private enum ResponseSource { case manual, listen, automaticScreen }
    private var responseSource = ResponseSource.manual
    private var canPersist = true
    private var scriptFollower = ScriptFollower(script: "")
    private var prompterOwnsAudio = false
    private var prompterAudioID = UUID()
    private var prompterStartTask: Task<Void, Never>?

    init(directory: URL) throws {
        store = try WorkspaceStore(directory: directory)
        var loaded = WorkspaceData()
        var loadError: String?
        do { loaded = try store.load() } catch {
            loadError = "Local data could not be read. The original file is preserved. \(error.localizedDescription)"
        }
        if loaded.conversations.isEmpty { loaded.conversations = [Conversation()] }
        data = loaded
        scriptFollower = ScriptFollower(script: loaded.preferences.teleprompter?.script ?? "")
        activeConversationID = loaded.conversations[0].id
        chatGPT = ChatGPTClient(
            homeDirectory: directory.appendingPathComponent("ChatGPT", isDirectory: true),
            workingDirectory: directory.appendingPathComponent("Assistant", isDirectory: true))
        if let loadError {
            self.error = loadError
            canPersist = false
        }
        audio.onTranscript = { [weak self] text in
            guard let self else { return }
            if self.prompterOwnsAudio {
                self.followScript(text)
            } else {
                self.transcript = text
                self.scheduleSuggestion()
            }
        }
        audio.onLevel = { [weak self] value in self?.audioLevel = value }
        audio.onError = { [weak self] message in
            guard let self else { return }
            self.error = message
            if self.prompterOwnsAudio { self.pauseTeleprompter() } else { self.stopListening() }
        }
        saving = $data.dropFirst().debounce(for: .milliseconds(500), scheduler: RunLoop.main).sink {
            [weak self] value in
            guard let self, self.canPersist else { return }
            do { try self.store.save(value) } catch {
                self.error = "Could not save your changes: \(error.localizedDescription)"
            }
        }
        loadProviderKey()
        automaticScreens.onChange = { [weak self] state in self?.automaticScreenState = state }
    }

    var messages: [ChatMessage] { data.conversations.first(where: { $0.id == activeConversationID })?.messages ?? [] }
    var providerReady: Bool { data.preferences.provider == .chatGPT ? account.isSignedIn : keySaved }
    var providerStatus: String {
        if networkPaused { return "AI paused · notes stay available" }
        if isGenerating { return "\(data.preferences.provider.title) is responding" }
        if data.preferences.provider == .chatGPT {
            return account.isSignedIn ? "ChatGPT plan connected" : "Connect ChatGPT in Settings"
        }
        return keySaved ? "\(data.preferences.provider.title) connected" : "Add your optional key in Settings"
    }
    var overlayShortcutLabel: String { data.preferences.shortcut(for: .toggleOverlay).display }
    var mouseShortcutLabel: String { data.preferences.shortcut(for: .clickThrough).display }
    var automaticScreenShortcutLabel: String { data.preferences.shortcut(for: .automaticScreen).display }
    var teleprompterShortcutLabel: String { data.preferences.shortcut(for: .teleprompter).display }
    var teleprompterSettings: TeleprompterSettings {
        get { data.preferences.teleprompter ?? .init() }
        set { data.preferences.teleprompter = newValue }
    }
    var notchSettings: NotchSettings {
        get { data.preferences.notch ?? .init() }
        set {
            var settings = newValue
            settings.width = min(900, max(480, settings.width))
            settings.readingLines = min(8, max(2, settings.readingLines))
            data.preferences.notch = settings
        }
    }
    var notchReading: Bool {
        notchSettings.enabled && page == .teleprompter && !teleprompterEditing
            && !teleprompterSettings.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var notchHeldOpen: Bool { teleprompterRunning || teleprompterStarting || recordingShortcut != nil || notchSizing }

    func toggleNotchMode() {
        notchSettings.enabled.toggle()
        notchExpanded = notchSettings.enabled
    }

    private func prepareTeleprompterPresentation() {
        if notchSettings.automaticallyForTeleprompter { notchSettings.enabled = true }
        if notchSettings.enabled { notchExpanded = true }
    }
    var latestTeleprompterAnswer: String? {
        messages.last(where: {
            $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text
    }
    var filteredNotes: [Note] {
        data.notes.filter { note in
            let matchesFilter =
                noteFilter == "Archived"
                ? note.isArchived : !note.isArchived && (noteFilter != "Favorites" || note.isFavorite)
            let term = noteSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesFilter
                && (term.isEmpty
                    || (note.title + " " + note.content + " " + note.tags.joined(separator: " "))
                        .localizedCaseInsensitiveContains(term))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func log(_ text: String) {
        activity.insert(text, at: 0)
        if activity.count > 30 { activity.removeLast(activity.count - 30) }
    }

    func refreshAccount() {
        guard !accountBusy else { return }
        accountBusy = true
        Task {
            defer { accountBusy = false }
            do {
                account = try await chatGPT.checkAccount()
                if account.isSignedIn { models = try await chatGPT.listModels() }
            } catch { self.error = error.localizedDescription }
        }
    }

    func connectChatGPT() {
        guard !accountBusy else { return }
        accountBusy = true
        Task {
            do {
                let url = try await chatGPT.beginLogin()
                guard NSWorkspace.shared.open(url) else {
                    throw LumenError.message("Could not open the ChatGPT sign-in page.")
                }
                accountBusy = false
                log("Opened ChatGPT sign-in. Finish connecting in your browser.")
                loginPoll?.cancel()
                loginPoll = Task {
                    for _ in 0..<120 {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        guard !Task.isCancelled else { return }
                        if let result = try? await chatGPT.checkAccount(), result.isSignedIn {
                            account = result
                            models = (try? await chatGPT.listModels()) ?? []
                            log("ChatGPT plan connected.")
                            return
                        }
                    }
                }
            } catch {
                accountBusy = false
                self.error = error.localizedDescription
            }
        }
    }

    func disconnectChatGPT() {
        stopAutomaticScreens()
        cancelGeneration()
        loginPoll?.cancel()
        Task {
            do {
                try await chatGPT.logout()
                account = .init(isSignedIn: false, summary: "Connect your ChatGPT account")
                models = []
            } catch { self.error = error.localizedDescription }
        }
    }

    func loadProviderKey() {
        apiKeyDraft = ""
        keySaved = false
        guard data.preferences.provider != .chatGPT else { return }
        do { keySaved = !(try KeychainStore.read(provider: data.preferences.provider) ?? "").isEmpty } catch {
            self.error = error.localizedDescription
        }
    }

    func saveProviderKey() {
        do {
            let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw LumenError.message("Enter a key to save it.") }
            try KeychainStore.save(key, provider: data.preferences.provider)
            keySaved = true
            apiKeyDraft = ""
            log("Saved \(data.preferences.provider.title) key in macOS Keychain.")
        } catch { self.error = error.localizedDescription }
    }

    func deleteProviderKey() {
        stopAutomaticScreens()
        do {
            try KeychainStore.delete(provider: data.preferences.provider)
            keySaved = false
            apiKeyDraft = ""
        } catch { self.error = error.localizedDescription }
    }

    func newConversation() {
        stopAutomaticScreens()
        cancelGeneration()
        let conversation = Conversation()
        data.conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        attachment = nil
        draft = ""
        page = .ask
    }

    func send(_ suppliedPrompt: String? = nil, fromListen: Bool = false) {
        let text = (suppliedPrompt ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating, !captureBusy else { return }
        let image = fromListen ? nil : attachment?.jpegData
        guard
            appendQuestion(
                text, conversationID: activeConversationID, image: image, source: fromListen ? .listen : .manual)
        else { return }
        if !fromListen {
            draft = ""
            attachment = nil
        }
    }

    @discardableResult
    private func appendQuestion(_ text: String, conversationID: UUID, image: Data?, source: ResponseSource = .manual)
        -> Bool
    {
        guard !isGenerating else { return false }
        guard !networkPaused else {
            error = "AI is paused. Resume it before sending a question."
            return false
        }
        guard providerReady else {
            page = .settings
            return false
        }
        guard let index = data.conversations.firstIndex(where: { $0.id == conversationID }) else { return false }
        data.conversations[index].messages.append(ChatMessage(role: .user, text: text))
        if data.conversations[index].messages.count == 1 && source != .automaticScreen {
            data.conversations[index].title = String(text.prefix(60))
        }
        let history = data.conversations[index].messages.filter { !$0.text.isEmpty }
        let requestMessages = source == .automaticScreen ? Array(history.suffix(3)) : history
        let response = ChatMessage(role: .assistant, text: "")
        data.conversations[index].messages.append(response)
        data.conversations[index].updatedAt = Date()
        let context = requestContext(includeTranscript: data.preferences.includeListenContext || source == .listen)
        runGeneration(messages: requestMessages, context: context, image: image, source: source) { [weak self] delta in
            guard let self, let i = self.data.conversations.firstIndex(where: { $0.id == conversationID }),
                let m = self.data.conversations[i].messages.firstIndex(where: { $0.id == response.id })
            else { return }
            self.data.conversations[i].messages[m].text += delta
        }
        return true
    }

    private func requestContext(includeTranscript: Bool) -> String {
        var parts: [String] = []
        if !data.preferences.personalContext.isEmpty {
            parts.append("User-provided context:\n" + data.preferences.personalContext)
        }
        if includeTranscript && !transcript.isEmpty {
            parts.append("Recent live transcript:\n" + String(transcript.suffix(24_000)))
        }
        return parts.joined(separator: "\n\n")
    }

    private func runGeneration(
        messages: [ChatMessage], context: String, image: Data?, source: ResponseSource = .manual,
        onDelta: @escaping (String) -> Void
    ) {
        let preferences = data.preferences
        let requestID = UUID()
        generationID = requestID
        isGenerating = true
        error = nil
        responseSource = source
        log(
            image == nil
                ? "Sent a text request to \(preferences.provider.title)."
                : "Sent your selected screenshot and question to \(preferences.provider.title).")
        requestTask = Task {
            do {
                let stream: AsyncThrowingStream<String, Error>
                if preferences.provider == .chatGPT {
                    stream = await chatGPT.stream(
                        messages: messages, instructions: preferences.instructions, context: context, imageJPEG: image,
                        model: preferences.chatGPTModel)
                } else {
                    let key = try KeychainStore.read(provider: preferences.provider) ?? ""
                    stream = api.stream(
                        provider: preferences.provider, apiKey: key, model: preferences.selectedModel,
                        messages: messages, instructions: preferences.instructions, context: context, imageJPEG: image)
                }
                for try await delta in stream {
                    try Task.checkCancellation()
                    guard generationID == requestID else { return }
                    onDelta(delta)
                }
            } catch is CancellationError {
                if source == .automaticScreen, generationID == requestID, !Task.isCancelled {
                    automaticScreens.stop()
                    self.error = "Automatic screen explanations stopped because the response was interrupted."
                }
            } catch {
                if generationID == requestID {
                    self.error = error.localizedDescription
                    if source == .automaticScreen {
                        automaticScreens.stop()
                        log("Automatic screen explanations stopped after a response error.")
                    }
                }
            }
            if generationID == requestID {
                isGenerating = false
                requestTask = nil
            }
        }
    }

    func cancelGeneration() {
        if responseSource == .automaticScreen && isGenerating { automaticScreens.stop() }
        responseSource = .manual
        generationID = UUID()
        requestTask?.cancel()
        requestTask = nil
        isGenerating = false
    }

    func toggleNetwork() {
        networkPaused.toggle()
        if networkPaused {
            stopAutomaticScreens()
            cancelGeneration()
            suggestionTask?.cancel()
        }
    }

    func captureScreen(thenAsk prompt: String? = nil) {
        guard !captureBusy else { return }
        captureBusy = true
        error = nil
        attachment = nil
        Task {
            defer { captureBusy = false }
            do {
                availableDisplays = screen.displays()
                attachment = try await screen.capture(displayID: selectedDisplayID)
                screenAccessStatus = "Allowed"
                log("Prepared one screenshot locally. It is sent only when you ask.")
                page = .ask
                if let prompt {
                    captureBusy = false
                    send(prompt)
                }
            } catch {
                self.error = error.localizedDescription
                screenAccessStatus = "Capture unavailable"
            }
        }
    }

    func checkScreenAccess() {
        guard !captureBusy else { return }
        captureBusy = true
        error = nil
        Task {
            defer { captureBusy = false }
            do {
                _ = try await ScreenCaptureAccess.content()
                screenAccessStatus = "Allowed"
                log("ScreenCaptureKit accepted screen access for this build.")
            } catch {
                screenAccessStatus = "Access unavailable"
                self.error = error.localizedDescription
            }
        }
    }

    func explainScreen() {
        guard !captureBusy else { return }
        if isGenerating { cancelGeneration() }
        captureScreen(thenAsk: "Explain what's on this screen and help me understand the relevant information.")
    }

    func toggleAutomaticScreens() {
        if automaticScreenState.isRunning {
            stopAutomaticScreens()
            return
        }
        guard !networkPaused else {
            error = "Resume AI before starting automatic screen explanations."
            return
        }
        guard providerReady else {
            page = .settings
            error = "Connect your AI provider first."
            return
        }
        guard !isGenerating, !captureBusy else {
            error = "Wait for the current response or capture to finish, then start automatic screen explanations."
            return
        }
        cancelShortcutRecording()
        let conversation = Conversation(title: "Automatic screen explanations")
        data.conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        page = .ask
        error = nil
        log("Automatic screen explanations started: every minute, up to 60 screenshots.")
        automaticScreens.start(
            canCapture: { [weak self] in
                guard let self else { return false }
                return !self.isGenerating && !self.captureBusy
            },
            captureAndSend: { [weak self] in
                guard let self else { throw CancellationError() }
                guard !self.networkPaused, self.providerReady else {
                    throw LumenError.message("Automatic screen explanations stopped: the AI connection is unavailable.")
                }
                self.captureBusy = true
                defer { self.captureBusy = false }
                self.availableDisplays = self.screen.displays()
                let screenshot = try await self.screen.capture(displayID: self.selectedDisplayID)
                try Task.checkCancellation()
                self.screenAccessStatus = "Allowed"
                let number = self.automaticScreenState.sentCount + 1
                let prompt =
                    "Automatic screenshot \(number) of 60. Explain what's on this screen and help me understand the relevant information. Focus on meaningful changes since the previous screenshot, if any."
                guard
                    self.appendQuestion(
                        prompt, conversationID: conversation.id, image: screenshot.jpegData, source: .automaticScreen)
                else {
                    throw LumenError.message(
                        "Automatic screen explanations stopped before the screenshot could be sent.")
                }
            },
            onError: { [weak self] error in
                self?.error = error.localizedDescription
                self?.log("Automatic screen explanations stopped: \(error.localizedDescription)")
            })
    }

    func stopAutomaticScreens() {
        let wasRunning = automaticScreenState.isRunning
        automaticScreens.stop()
        if responseSource == .automaticScreen && isGenerating { cancelGeneration() }
        if wasRunning {
            log("Automatic screen explanations stopped after \(automaticScreenState.sentCount) screenshots.")
        }
    }

    func setTeleprompterScript(_ text: String) {
        teleprompterEditing = true
        teleprompterSettings.script = text
        resetTeleprompter()
    }

    func useAnswerInTeleprompter(_ text: String) {
        setTeleprompterScript(text)
        teleprompterEditing = false
        page = .teleprompter
    }

    func resetTeleprompter() {
        pauseTeleprompter()
        scriptFollower = ScriptFollower(script: teleprompterSettings.script)
        teleprompterSpokenOffset = nil
        teleprompterScrollOffset = 0
        teleprompterResetID = UUID()
        teleprompterVoiceStatus = "Ready to follow your voice"
    }

    func toggleTeleprompter() {
        page = .teleprompter
        if teleprompterRunning || teleprompterStarting {
            pauseTeleprompter()
            return
        }
        guard !teleprompterSettings.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            teleprompterEditing = true
            return
        }
        teleprompterEditing = false
        guard teleprompterSettings.followVoice else {
            prepareTeleprompterPresentation()
            teleprompterRunning = true
            return
        }
        guard !isListening, !listeningBusy else {
            error =
                "End the Listen session before using voice-follow. Timed scrolling is available without the microphone."
            return
        }
        if scriptFollower.isAtEnd { resetTeleprompter() }
        prepareTeleprompterPresentation()
        scriptFollower.beginRecognition()
        let id = UUID()
        prompterAudioID = id
        prompterOwnsAudio = true
        teleprompterStarting = true
        teleprompterVoiceStatus = "Starting microphone…"
        error = nil
        prompterStartTask = Task {
            do {
                try await audio.start(source: .microphone, localeIdentifier: data.preferences.localeIdentifier)
                try Task.checkCancellation()
                guard prompterAudioID == id else { return }
                teleprompterStarting = false
                teleprompterRunning = true
                teleprompterVoiceStatus = "Listening for words in your script"
                prompterStartTask = nil
            } catch {
                guard prompterAudioID == id else { return }
                pauseTeleprompter()
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func pauseTeleprompter() {
        teleprompterRunning = false
        teleprompterStarting = false
        prompterAudioID = UUID()
        prompterStartTask?.cancel()
        prompterStartTask = nil
        if prompterOwnsAudio {
            audio.stop()
            prompterOwnsAudio = false
        }
    }

    private func followScript(_ transcript: String) {
        guard teleprompterRunning else { return }
        if let offset = scriptFollower.update(transcript: transcript) {
            teleprompterSpokenOffset = offset
            teleprompterVoiceStatus = "Following your voice · pauses when you pause"
            if scriptFollower.isAtEnd {
                pauseTeleprompter()
                teleprompterVoiceStatus = "End of script"
            }
        } else {
            teleprompterVoiceStatus = "Waiting for matching script words"
        }
    }

    func beginShortcutRecording(_ action: ShortcutAction) {
        mousePassthrough = false
        cancelShortcutRecording()
        recordingShortcut = action
        shortcutRecordingChanged?(true)
    }

    func cancelShortcutRecording() {
        guard recordingShortcut != nil else { return }
        recordingShortcut = nil
        shortcutRecordingChanged?(false)
    }

    func setShortcut(_ binding: ShortcutBinding, for action: ShortcutAction) {
        cancelShortcutRecording()
        for other in ShortcutAction.allCases where other != action {
            if binding.conflicts(with: data.preferences.shortcut(for: other)) {
                error =
                    "\(binding.display) is already assigned to \(other.title). Choose another combination or change that shortcut first."
                return
            }
        }
        if let message = applyShortcut?(action, binding) {
            error = message
            return
        }
        var custom = data.preferences.shortcuts ?? [:]
        custom[action.rawValue] = binding
        data.preferences.shortcuts = custom
    }

    func toggleListening() {
        guard !listeningBusy else { return }
        guard !prompterOwnsAudio else {
            error = "Pause the voice-follow teleprompter before starting Listen."
            return
        }
        if isListening {
            stopListening()
            return
        }
        listeningBusy = true
        Task {
            defer { listeningBusy = false }
            do {
                transcript = ""
                lastAutoQuestion = ""
                answersPaused = false
                try await audio.start(
                    source: data.preferences.audioSource, localeIdentifier: data.preferences.localeIdentifier)
                isListening = true
                sessionStartedAt = Date()
                page = .listen
                log("Started on-device \(data.preferences.audioSource.title.lowercased()) transcription.")
            } catch { self.error = error.localizedDescription }
        }
    }

    func stopListening() {
        guard !prompterOwnsAudio else { return }
        audio.stop()
        suggestionTask?.cancel()
        audioLevel = 0
        let wasListening = isListening
        isListening = false
        sessionStartedAt = nil
        if wasListening && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let note = Note(
                title: "Conversation · \(formatter.string(from: Date()))", content: "", transcript: transcript,
                tags: ["conversation"])
            data.notes.insert(note, at: 0)
            selectedNoteID = note.id
            log("Saved the session transcript to Notes.")
        }
    }

    func toggleAnswersPause() {
        answersPaused.toggle()
        if answersPaused {
            suggestionTask?.cancel()
            if responseSource == .listen { cancelGeneration() }
        }
    }

    private func scheduleSuggestion() {
        suggestionTask?.cancel()
        guard isListening, data.preferences.automaticSuggestions, !answersPaused, !networkPaused, providerReady else {
            return
        }
        let lines = transcript.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let last = String((lines.last ?? transcript).suffix(800))
        let suffix = last.components(separatedBy: CharacterSet(charactersIn: ".!؟?"))
        let question = last.contains("?") || last.contains("؟") ? last : (suffix.last ?? last)
        let normalized = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let starters = [
            "what ", "how ", "why ", "when ", "where ", "can you ", "could you ", "tell me ", "explain ", "ما ", "كيف ",
            "لماذا ", "هل ",
        ]
        guard normalized.count > 15, normalized != lastAutoQuestion,
            last.contains("?") || last.contains("؟") || starters.contains(where: normalized.hasPrefix)
        else { return }
        suggestionTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, !isGenerating, isListening, !answersPaused else { return }
            lastAutoQuestion = normalized
            send(
                "Draft a concise response to the latest question in this transcript. Use only relevant context, and do not invent personal facts.\n\nLatest question: \(question)",
                fromListen: true)
        }
    }

    func newNote() {
        let note = Note()
        data.notes.insert(note, at: 0)
        selectedNoteID = note.id
        noteFilter = "All"
        page = .notes
    }

    func updateNote(id: UUID, _ change: (inout Note) -> Void) {
        guard let index = data.notes.firstIndex(where: { $0.id == id }) else { return }
        change(&data.notes[index])
        data.notes[index].updatedAt = Date()
    }

    func deleteNote(id: UUID) {
        data.notes.removeAll { $0.id == id }
        if selectedNoteID == id { selectedNoteID = nil }
    }

    func summarizeNote(id: UUID) {
        guard !isGenerating, !captureBusy, !networkPaused else { return }
        guard providerReady else {
            page = .settings
            return
        }
        guard let note = data.notes.first(where: { $0.id == id }) else { return }
        let source = note.transcript.isEmpty ? note.content : note.transcript
        guard !source.isEmpty else { return }
        notePreview = ""
        notePreviewID = id
        runGeneration(
            messages: [
                ChatMessage(
                    role: .user,
                    text:
                        "Create clear meeting notes from this content. Include a brief summary, decisions, and action items only where supported. Use Markdown.\n\n\(source)"
                )
            ], context: "", image: nil
        ) { [weak self] delta in
            self?.notePreview += delta
        }
    }

    func applyNotePreview() {
        guard let id = notePreviewID, !notePreview.isEmpty else { return }
        let preview = notePreview
        updateNote(id: id) { $0.content = preview }
        notePreviewID = nil
        notePreview = ""
    }

    func exportNote(_ note: Note, asPDF: Bool = false) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            String(note.title.replacingOccurrences(of: "/", with: "-").prefix(100)) + (asPDF ? ".pdf" : ".md")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if asPDF {
                try PDFExporter.write(note: note, to: url)
            } else {
                try note.markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { self.error = error.localizedDescription }
    }

    func shutdown() {
        pauseTeleprompter()
        stopAutomaticScreens()
        cancelShortcutRecording()
        stopListening()
        cancelGeneration()
        loginPoll?.cancel()
        if canPersist { do { try store.save(data) } catch {} }
        Task { await chatGPT.disconnect() }
    }
}

enum LumenError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}
