import XCTest

@testable import LumenCore

final class APIClientTests: XCTestCase {
    private let client = APIClient()
    private let question = [ChatMessage(role: .user, text: "What is on screen?")]

    func testGeminiRequestUsesHeaderKeyAndUserScopedContextImage() throws {
        let request = try client.makeRequest(
            provider: .gemini, apiKey: "test-only-key", model: "gemini-3.8-flash",
            messages: question, instructions: "Keep it concise.", context: "Screen text", imageJPEG: Data([1, 2, 3]))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-only-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.url!.absoluteString.contains("test-only-key"))
        let body = try json(request)
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("test-only-key"))
        let system = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
        XCTAssertFalse(String(describing: system).contains("Screen text"))
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.first?["role"] as? String, "user")
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual((parts.first?["inlineData"] as? [String: Any])?["mimeType"] as? String, "image/jpeg")
        XCTAssertTrue((parts[1]["text"] as? String ?? "").contains("Screen text"))
        XCTAssertEqual(parts.last?["text"] as? String, "What is on screen?")
    }

    func testClaudeRequestUsesMessagesAndCorrectImageSchema() throws {
        let history = [ChatMessage(role: .user, text: "Hi"), ChatMessage(role: .assistant, text: "Hello")] + question
        let request = try client.makeRequest(
            provider: .claude, apiKey: "test-only-key", model: "claude-sonnet-5-5",
            messages: history, instructions: "Be helpful", context: "", imageJPEG: Data([4, 5]))
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-only-key")
        let body = try json(request)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual(body["system"] as? String, "Be helpful")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let source = try XCTUnwrap(parts.first?["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, Data([4, 5]).base64EncodedString())
    }

    func testRejectsChatGPTKeysInvalidModelHeaderInjectionAndAssistantPrefill() {
        for (provider, key, model, messages) in [
            (AIProvider.chatGPT, "key", "any", question),
            (.gemini, "key", "../../other-host?key=", question),
            (.claude, "key\r\nInjected: x", "claude-sonnet-5-5", question),
            (.claude, "key", "claude-sonnet-5-5", [ChatMessage(role: .assistant, text: "prefill")]),
        ] {
            XCTAssertThrowsError(
                try client.makeRequest(
                    provider: provider, apiKey: key, model: model,
                    messages: messages, instructions: "", context: "", imageJPEG: nil))
        }
    }

    func testSSEHandlesUTF8BytesCRLFCommentsAndMultipleDataLines() throws {
        let wire = "\u{FEFF}: keepalive\r\nevent: sample\r\ndata: مرحباً 👋\r\ndata: second line\r\n\r\n"
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in wire.utf8 { if let event = try parser.append(byte) { events.append(event) } }
        try parser.finish()
        XCTAssertEqual(events, [SSEEvent(name: "sample", data: "مرحباً 👋\nsecond line")])
    }

    func testSSERejectsInvalidUTF8AndUnterminatedEvent() throws {
        var invalid = SSEParser()
        _ = try invalid.append(0xff)
        XCTAssertThrowsError(try invalid.append(10)) { XCTAssertEqual($0 as? APIClientError, .malformedStream) }
        var partial = SSEParser()
        for byte in "data: {}\n".utf8 { _ = try partial.append(byte) }
        XCTAssertThrowsError(try partial.finish()) { XCTAssertEqual($0 as? APIClientError, .truncatedStream) }
    }

    func testGeminiTextThoughtFilteringAndTerminalMarker() throws {
        var decoder = ProviderStreamDecoder(provider: .gemini)
        let first = SSEEvent(
            data: #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"internal"},{"text":"Hello"}]}}]}"#)
        XCTAssertEqual(try decoder.consume(first), ["Hello"])
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? APIClientError, .truncatedStream) }
        XCTAssertEqual(try decoder.consume(SSEEvent(data: #"{"candidates":[{"finishReason":"STOP"}]}"#)), [])
        try decoder.finish()
    }

    func testGeminiProviderBlockMalformedPayloadAndOutputLimit() throws {
        var decoder = ProviderStreamDecoder(provider: .gemini)
        XCTAssertThrowsError(try decoder.consume(SSEEvent(data: #"{"error":{"message":"Rate limited"}}"#))) {
            XCTAssertEqual($0 as? APIClientError, .provider("Rate limited"))
        }
        XCTAssertThrowsError(try decoder.consume(SSEEvent(data: "{broken")))
        XCTAssertThrowsError(try decoder.consume(SSEEvent(data: #"{"promptFeedback":{"blockReason":"SAFETY"}}"#)))
        XCTAssertEqual(
            try decoder.consume(
                SSEEvent(
                    data: #"{"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}"#)),
            ["partial"])
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? APIClientError, .outputLimit) }
    }

    func testClaudeWaitsForMessageStopAndIgnoresUnknownEvents() throws {
        var decoder = ProviderStreamDecoder(provider: .claude)
        XCTAssertEqual(try decoder.consume(SSEEvent(name: "message_start", data: #"{"type":"message_start"}"#)), [])
        XCTAssertEqual(try decoder.consume(SSEEvent(name: "future_event", data: #"{"type":"future_event"}"#)), [])
        XCTAssertEqual(
            try decoder.consume(
                SSEEvent(
                    name: "content_block_delta",
                    data: #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#)), ["Hello"])
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? APIClientError, .truncatedStream) }
        _ = try decoder.consume(SSEEvent(name: "message_stop", data: #"{"type":"message_stop"}"#))
        try decoder.finish()
    }

    func testClaudeInStreamErrorAndMismatchedEventAreFailures() throws {
        var decoder = ProviderStreamDecoder(provider: .claude)
        XCTAssertThrowsError(
            try decoder.consume(
                SSEEvent(
                    name: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
                ))
        ) {
            XCTAssertEqual($0 as? APIClientError, .provider("Overloaded"))
        }
        XCTAssertThrowsError(try decoder.consume(SSEEvent(name: "message_stop", data: #"{"type":"message_start"}"#))) {
            XCTAssertEqual($0 as? APIClientError, .malformedStream)
        }
    }

    func testErrorMessagesAreBoundedAndKeyIsRedacted() {
        let long = Data(String(repeating: "x", count: 10_000).utf8)
        XCTAssertEqual(APIClient.errorDetail(long, fallback: "fallback").count, 1_024)
        XCTAssertEqual(
            APIClientError.provider("bad key secret").redacting(key: "secret"), .provider("bad key [redacted]"))
    }

    func testHTTPFailureIsSurfacedWithoutLeakingKey() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ErrorResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let stream = APIClient(session: session).stream(
            provider: .claude, apiKey: "test-only-key", model: "claude-sonnet-5-5",
            messages: question, instructions: "", context: "", imageJPEG: nil)
        do {
            for try await _ in stream { XCTFail("An HTTP failure must not produce answer text.") }
            XCTFail("Expected an HTTP failure")
        } catch {
            XCTAssertEqual(error as? APIClientError, .http(status: 401, message: "Invalid test key [redacted]"))
        }
    }

    func testCancellationStopsThePendingProviderRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = expectation(description: "Mock request started")
        let stopped = expectation(description: "Mock request canceled")
        PendingResponseProtocol.setCallbacks(onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        defer { PendingResponseProtocol.setCallbacks(onStart: nil, onStop: nil) }
        let stream = APIClient(session: session).stream(
            provider: .gemini, apiKey: "test-only-key", model: "gemini-3.8-flash",
            messages: question, instructions: "", context: "", imageJPEG: nil)
        let task = Task { for try await _ in stream {} }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        _ = await task.result
        await fulfillment(of: [stopped], timeout: 3)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

/// URLProtocol fixtures prevent every transport test from reaching a real provider.
private final class ErrorResponseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"message":"Invalid test key test-only-key"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class PendingResponseProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var onStart: (() -> Void)?
    private static var onStop: (() -> Void)?
    static func setCallbacks(onStart: (() -> Void)?, onStop: (() -> Void)?) {
        lock.lock()
        self.onStart = onStart
        self.onStop = onStop
        lock.unlock()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let callback = Self.onStart
        Self.lock.unlock()
        callback?()
    }
    override func stopLoading() {
        Self.lock.lock()
        let callback = Self.onStop
        Self.lock.unlock()
        callback?()
    }
}
