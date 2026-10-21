import AVFoundation
import CoreMedia
import LumenCore
import ScreenCaptureKit
import Speech

/// Live transcription requires Apple's on-device recognizer. Audio is never sent to
/// a fallback recognition service, and neither input is written to disk.
@MainActor
final class AudioCapture {
    var onTranscript: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private var sessionID: UUID?
    private var recognizer: SFSpeechRecognizer?
    private var input: SpeechInput?
    private var audioEngine: AVAudioEngine?
    private var systemStream: SCStream?
    private var tapInstalled = false
    private var currentSegment: UUID?
    private var segmentOrder: [UUID] = []
    private var segmentText: [UUID: String] = [:]
    private var jobs: [UUID: RecognitionJob] = [:]
    private var rolloverTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init() {}

    func start(source: AudioSource, localeIdentifier: String) async throws {
        stop()
        let session = UUID()
        sessionID = session
        segmentOrder = []
        segmentText = [:]
        consecutiveFailures = 0

        do {
            let permission: SFSpeechRecognizerAuthorizationStatus
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                permission = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                }
            } else {
                permission = SFSpeechRecognizer.authorizationStatus()
            }
            try checkSession(session)
            guard permission == .authorized else { throw AudioCaptureError.speechPermission }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
                throw AudioCaptureError.unsupportedLanguage(localeIdentifier)
            }
            guard recognizer.supportsOnDeviceRecognition else {
                throw AudioCaptureError.onDeviceUnavailable(localeIdentifier)
            }
            guard recognizer.isAvailable else { throw AudioCaptureError.recognizerUnavailable }
            self.recognizer = recognizer

            if source == .microphone {
                let allowed: Bool
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: allowed = true
                case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
                default: allowed = false
                }
                try checkSession(session)
                guard allowed else { throw AudioCaptureError.microphonePermission }
            }

            let input = SpeechInput(
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        guard let self, self.sessionID == session else { return }
                        self.onLevel?(level)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.sessionID == session else { return }
                        self.fail(error.localizedDescription)
                    }
                }
            )
            self.input = input
            try beginRecognition(session: session)

            switch source {
            case .microphone:
                let engine = AVAudioEngine()
                self.audioEngine = engine
                let node = engine.inputNode
                let format = node.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noMicrophone }
                node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    input.append(buffer)
                }
                tapInstalled = true
                engine.prepare()
                try engine.start()
            case .system:
                let content = try await ScreenCaptureAccess.content()
                try checkSession(session)
                guard
                    let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                        ?? content.displays.first
                else {
                    throw AudioCaptureError.noDisplay
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 1
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: input)
                self.systemStream = stream
                try stream.addStreamOutput(
                    input, type: .audio, sampleHandlerQueue: DispatchQueue(label: "Lumen.system-audio"))
                try await stream.startCapture()
                // Stop can be pressed while ScreenCaptureKit is starting.
                guard sessionID == session, !Task.isCancelled else {
                    try? await stream.stopCapture()
                    throw CancellationError()
                }
            }
        } catch {
            if sessionID == session { stop() }
            throw error
        }
    }

    func stop() {
        sessionID = nil
        rolloverTask?.cancel()
        rolloverTask = nil
        input?.finish()
        if let engine = audioEngine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        audioEngine = nil
        for job in jobs.values {
            job.expiration?.cancel()
            job.request.endAudio()
            job.task?.cancel()
        }
        jobs.removeAll()
        currentSegment = nil
        recognizer = nil
        if let stream = systemStream, let input {
            // Keep the delegate alive until the asynchronous stream shutdown ends.
            stream.stopCapture { [input] _ in _ = input }
        }
        systemStream = nil
        input = nil
        onLevel?(0)
    }

    private func checkSession(_ session: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == session else { throw CancellationError() }
    }

    private func beginRecognition(session: UUID) throws {
        try checkSession(session)
        guard let recognizer, recognizer.isAvailable else { throw AudioCaptureError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AudioCaptureError.onDeviceUnavailable(recognizer.locale.identifier)
        }
        let token = UUID()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        let job = RecognitionJob(request: request)
        jobs[token] = job
        segmentOrder.append(token)
        currentSegment = token
        job.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.sessionID == session, self.jobs[token] != nil else { return }
                if let text, !text.isEmpty {
                    self.segmentText[token] = text
                    self.consecutiveFailures = 0
                    self.publishTranscript()
                }
                if isFinal || error != nil {
                    self.recognitionEnded(token: token, session: session, error: error)
                }
            }
        }
        // The sink assigns each audio buffer to exactly one request, including
        // during rollover. Final callbacks revise their own segment in place.
        input?.replaceRequest(request)
        rolloverTask?.cancel()
        rolloverTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 50_000_000_000) } catch { return }
            guard let self, self.sessionID == session, self.currentSegment == token else { return }
            do {
                try self.beginRecognition(session: session)
                self.finishSegment(token, session: session)
            } catch { self.fail(error.localizedDescription) }
        }
    }

    private func finishSegment(_ token: UUID, session: UUID) {
        guard let job = jobs[token] else { return }
        job.request.endAudio()
        job.expiration = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self, self.sessionID == session else { return }
            self.jobs.removeValue(forKey: token)?.task?.cancel()
        }
    }

    private func recognitionEnded(token: UUID, session: UUID, error: Error?) {
        let job = jobs.removeValue(forKey: token)
        job?.expiration?.cancel()
        job?.request.endAudio()
        guard currentSegment == token else { return }
        rolloverTask?.cancel()
        input?.replaceRequest(nil)
        currentSegment = nil
        if let error {
            consecutiveFailures += 1
            guard consecutiveFailures < 3 else {
                fail(
                    "On-device transcription stopped: \(error.localizedDescription). Check your selected language and try again."
                )
                return
            }
        }
        do { try beginRecognition(session: session) } catch { fail(error.localizedDescription) }
    }

    private func publishTranscript() {
        onTranscript?(segmentOrder.compactMap { segmentText[$0] }.joined(separator: " "))
    }

    private func fail(_ message: String) {
        stop()
        onError?(message)
    }
}

private final class RecognitionJob {
    let request: SFSpeechAudioBufferRecognitionRequest
    var task: SFSpeechRecognitionTask?
    var expiration: Task<Void, Never>?
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

/// Audio callbacks remain off the main actor. The lock makes replacing a Speech
/// request atomic with appending a buffer; callbacks cannot append after finish.
private final class SpeechInput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var active = true
    private var lastLevelTime: UInt64 = 0
    private let onLevel: (Float) -> Void
    private let onError: (Error) -> Void

    init(onLevel: @escaping (Float) -> Void, onError: @escaping (Error) -> Void) {
        self.onLevel = onLevel
        self.onError = onError
    }

    func replaceRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        self.request = request
    }

    func finish() {
        lock.lock()
        active = false
        request = nil
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        request?.append(buffer)
        let shouldMeter = shouldPublishLevel()
        lock.unlock()
        if shouldMeter, let channel = buffer.floatChannelData?.pointee {
            publishLevel(samples: channel, count: Int(buffer.frameLength))
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        request?.appendAudioSampleBuffer(sampleBuffer)
        let shouldMeter = shouldPublishLevel()
        lock.unlock()
        guard shouldMeter,
            let format = CMSampleBufferGetFormatDescription(sampleBuffer),
            let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            basic.mFormatID == kAudioFormatLinearPCM,
            basic.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            basic.mBitsPerChannel == 32
        else { return }
        let channels = max(1, Int(basic.mChannelsPerFrame))
        let bytes = MemoryLayout<AudioBufferList>.size + (channels - 1) * MemoryLayout<AudioBuffer>.size
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: bytes, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: bytes,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block
        )
        guard status == noErr else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let first = buffers.first, let data = first.mData else { return }
        withExtendedLifetime(block) {
            publishLevel(
                samples: data.assumingMemoryBound(to: Float.self),
                count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let shouldReport = active
        lock.unlock()
        if shouldReport { onError(error) }
    }

    private func shouldPublishLevel() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastLevelTime >= 80_000_000 else { return false }
        lastLevelTime = now
        return true
    }

    private func publishLevel(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        onLevel(min(1, sqrt(sum / Float(count)) * 4))
    }
}

private enum AudioCaptureError: LocalizedError {
    case speechPermission, microphonePermission
    case unsupportedLanguage(String)
    case onDeviceUnavailable(String)
    case recognizerUnavailable, noMicrophone, noDisplay

    var errorDescription: String? {
        switch self {
        case .speechPermission:
            return "Allow Speech Recognition for Lumen in System Settings → Privacy & Security."
        case .microphonePermission:
            return "Allow Microphone access for Lumen in System Settings → Privacy & Security."
        case .unsupportedLanguage(let language):
            return "Apple Speech does not support the selected language (\(language)). Choose another language."
        case .onDeviceUnavailable(let language):
            return
                "On-device speech recognition is unavailable for \(language) on this Mac. Choose a supported language or install the language's Dictation support in System Settings. Lumen will not send audio to a cloud recognizer."
        case .recognizerUnavailable:
            return "Apple's on-device speech recognizer is unavailable. Check Dictation language support and try again."
        case .noMicrophone:
            return "No microphone input is available. Connect a microphone and try again."
        case .noDisplay:
            return "No display is available for system-audio capture."
        }
    }
}
