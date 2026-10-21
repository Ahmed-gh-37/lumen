import XCTest

@testable import LumenCore

@MainActor
final class AutomaticScreenSessionTests: XCTestCase {
    func testImmediateCaptureMinuteSpacingAndHardSixtyLimit() async {
        var now = Date(timeIntervalSince1970: 0)
        var captureTimes: [Date] = []
        var sleeps: [Date] = []
        let finished = expectation(description: "sixty screenshots sent")
        let session = AutomaticScreenSession(
            now: { now },
            sleepUntil: { deadline in
                sleeps.append(deadline)
                now = deadline
                await Task.yield()
            })
        session.onChange = { state in
            if !state.isRunning && state.sentCount == 60 { finished.fulfill() }
        }
        session.start(
            canCapture: { true },
            captureAndSend: {
                captureTimes.append(now)
            }, onError: { _ in XCTFail("Unexpected error") })
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(captureTimes.count, 60)
        XCTAssertEqual(sleeps.count, 59)
        XCTAssertEqual(captureTimes.map { $0.timeIntervalSince1970 }, (0..<60).map { Double($0 * 60) })
        XCTAssertFalse(session.state.isRunning)
    }

    func testBusyMinutesAreSkippedAndSlowCaptureDoesNotCreateCatchUpBurst() async {
        var now = Date(timeIntervalSince1970: 0)
        var ticks = 0
        var captureTimes: [Date] = []
        let finished = expectation(description: "session finished")
        let session = AutomaticScreenSession(
            now: { now },
            sleepUntil: { deadline in
                now = deadline
                await Task.yield()
            })
        session.onChange = { state in
            if !state.isRunning && state.sentCount == 60 { finished.fulfill() }
        }
        session.start(
            canCapture: {
                ticks += 1
                return ticks > 2
            },
            captureAndSend: {
                captureTimes.append(now)
                if captureTimes.count == 1 { now = now.addingTimeInterval(125) }
            }, onError: { _ in XCTFail("Unexpected error") })
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(ticks, 62)
        XCTAssertEqual(captureTimes.count, 60)
        XCTAssertEqual(captureTimes[0].timeIntervalSince1970, 120)
        XCTAssertEqual(captureTimes[1].timeIntervalSince1970, 305)
    }

    func testStopDuringCaptureCancelsBeforeTransmission() async {
        let capturing = expectation(description: "capture started")
        let returned = expectation(description: "capture returned after stop")
        var capture: CheckedContinuation<Void, Never>?
        var sent = 0
        let session = AutomaticScreenSession()
        session.start(
            canCapture: { true },
            captureAndSend: {
                await withCheckedContinuation { continuation in
                    capture = continuation
                    capturing.fulfill()
                }
                defer { returned.fulfill() }
                try Task.checkCancellation()
                sent += 1
            }, onError: { _ in XCTFail("Cancellation is not an error") })
        await fulfillment(of: [capturing], timeout: 2)
        session.stop()
        capture?.resume()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(session.state.sentCount, 0)
        XCTAssertFalse(session.state.isRunning)
    }

    func testStopWhileWaitingAndRestartIgnoreOldTimerAndDuplicateStart() async {
        let waiting = expectation(description: "waiting for next minute")
        var sleeper: CheckedContinuation<Void, Never>?
        var oldSends = 0
        var newSends = 0
        var now = Date(timeIntervalSince1970: 0)
        let session = AutomaticScreenSession(
            now: { now },
            sleepUntil: { deadline in
                if sleeper == nil {
                    await withCheckedContinuation { continuation in
                        sleeper = continuation
                        waiting.fulfill()
                    }
                } else {
                    now = deadline
                    await Task.yield()
                }
            })
        session.start(canCapture: { true }, captureAndSend: { oldSends += 1 }, onError: { _ in XCTFail() })
        session.start(canCapture: { true }, captureAndSend: { XCTFail("Duplicate loop") }, onError: { _ in XCTFail() })
        await fulfillment(of: [waiting], timeout: 2)
        session.stop()
        let finished = expectation(description: "new session finished")
        session.onChange = { state in
            if !state.isRunning && state.sentCount == 60 { finished.fulfill() }
        }
        session.start(canCapture: { true }, captureAndSend: { newSends += 1 }, onError: { _ in XCTFail() })
        sleeper?.resume()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(oldSends, 1)
        XCTAssertEqual(newSends, 60)
        XCTAssertEqual(session.state.sentCount, 60)
    }

    func testCaptureErrorStopsWithoutRetryOrFurtherScreenshots() async {
        enum Failure: Error { case denied }
        var attempts = 0
        let failed = expectation(description: "capture failure surfaced")
        let session = AutomaticScreenSession(sleepUntil: { _ in XCTFail("Must not schedule after failure") })
        session.start(
            canCapture: { true },
            captureAndSend: {
                attempts += 1
                throw Failure.denied
            }, onError: { _ in failed.fulfill() })
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(session.state.sentCount, 0)
        XCTAssertFalse(session.state.isRunning)
    }
}
