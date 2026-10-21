import Foundation

/// One session owns its timer. Missed minutes are skipped rather than queued.
@MainActor
public final class AutomaticScreenSession {
    public static let interval: TimeInterval = 60
    public static let limit = 60

    public struct State: Equatable, Sendable {
        public var isRunning = false
        public var sentCount = 0
        public init() {}
    }

    public private(set) var state = State()
    public var onChange: ((State) -> Void)?
    private let now: () -> Date
    private let sleepUntil: (Date) async throws -> Void
    private var task: Task<Void, Never>?
    private var sessionID = UUID()

    public init(
        now: @escaping () -> Date = Date.init,
        sleepUntil: @escaping (Date) async throws -> Void = { deadline in
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
        }
    ) {
        self.now = now
        self.sleepUntil = sleepUntil
    }

    public func start(
        canCapture: @escaping () -> Bool,
        captureAndSend: @escaping () async throws -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !state.isRunning else { return }
        sessionID = UUID()
        let id = sessionID
        state = State()
        state.isRunning = true
        publish()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                while self.sessionID == id && !Task.isCancelled {
                    let tick = self.now()
                    if canCapture() {
                        try await captureAndSend()
                        try Task.checkCancellation()
                        guard self.sessionID == id else { return }
                        self.state.sentCount += 1
                        if self.state.sentCount == Self.limit {
                            self.finish()
                            return
                        }
                        self.publish()
                    }
                    // Never catch up with a burst after a slow capture or system sleep.
                    let next = tick.addingTimeInterval(Self.interval)
                    let deadline = next > self.now() ? next : self.now().addingTimeInterval(Self.interval)
                    try await self.sleepUntil(deadline)
                }
            } catch {
                guard self.sessionID == id, !Task.isCancelled else { return }
                self.finish()
                if !(error is CancellationError) { onError(error) }
            }
        }
    }

    public func stop() {
        sessionID = UUID()
        task?.cancel()
        finish()
    }

    private func finish() {
        task = nil
        state.isRunning = false
        publish()
    }

    private func publish() { onChange?(state) }
}
