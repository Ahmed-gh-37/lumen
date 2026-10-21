import XCTest

@testable import LumenCore

final class ScriptFollowerTests: XCTestCase {
    func testProgressiveSpeechSilenceAndPartialRevisionsNeverRewind() {
        let script = "Good morning everyone. Today we present our results."
        var follower = ScriptFollower(script: script)
        XCTAssertNil(follower.update(transcript: "Good"))
        XCTAssertEqual(follower.update(transcript: "Good morning"), (script as NSString).range(of: "morning").location)
        XCTAssertNil(follower.update(transcript: "Good morning"))
        XCTAssertNil(follower.update(transcript: "Good"))
        XCTAssertNil(follower.update(transcript: "Good morning"))
        XCTAssertEqual(
            follower.update(transcript: "Good morning everyone"), (script as NSString).range(of: "everyone").location)
        XCTAssertEqual(follower.consumedWords, 3)
    }

    func testOffScriptQuestionDoesNotMoveAndReadingResumes() {
        let script = "Our revenue is growing. We plan to expand next year. Thank you everyone."
        var follower = ScriptFollower(script: script)
        XCTAssertNotNil(follower.update(transcript: "Our revenue is growing"))
        let before = follower.consumedWords
        XCTAssertNil(follower.update(transcript: "Our revenue is growing. Can you explain the budget?"))
        XCTAssertEqual(follower.consumedWords, before)
        XCTAssertNotNil(follower.update(transcript: "Can you explain the budget? We plan to expand"))
        XCTAssertEqual(follower.consumedWords, 8)
    }

    func testRepeatedPhrasesChooseNearestOccurrenceAndResumeAfterPause() {
        var follower = ScriptFollower(
            script: "Thank you everyone. First we review sales. Thank you everyone. Now we review costs.")
        XCTAssertNotNil(follower.update(transcript: "Thank you everyone"))
        XCTAssertEqual(follower.consumedWords, 3)
        follower.beginRecognition()
        XCTAssertNotNil(follower.update(transcript: "First we review sales"))
        XCTAssertEqual(follower.consumedWords, 7)
        XCTAssertNotNil(follower.update(transcript: "First we review sales thank you everyone"))
        XCTAssertEqual(follower.consumedWords, 10)
    }

    func testUnicodeNormalizationPreservesOriginalUTF16LayoutOffsets() {
        let script = "🌙 أَهْلًا وَسَهْلًا بالجميع. Café prices are stable."
        var follower = ScriptFollower(script: script)
        XCTAssertEqual(
            follower.update(transcript: "اهلا وسهلا بالجميع"), (script as NSString).range(of: "بالجميع").location)
        XCTAssertEqual(
            follower.update(transcript: "cafe prices are stable"), (script as NSString).range(of: "stable").location)
        XCTAssertTrue(follower.isAtEnd)
    }

    func testUnrelatedCommonWordsCannotJumpFarAhead() {
        let middle = Array(repeating: "unique unrelated material", count: 35).joined(separator: " ")
        var follower = ScriptFollower(script: "This is our introduction. \(middle) financial outlook improves")
        XCTAssertNil(follower.update(transcript: "financial outlook improves"))
        XCTAssertEqual(follower.consumedWords, 0)
        var common = ScriptFollower(
            script: "This is our introduction. Some extra words come before the final section. Thank you.")
        XCTAssertNil(common.update(transcript: "thank you"))
        XCTAssertEqual(common.consumedWords, 0)
    }

    func testEmptySingleWordAndApostropheScripts() {
        var empty = ScriptFollower(script: "")
        XCTAssertNil(empty.update(transcript: "hello"))
        var single = ScriptFollower(script: "Hello!")
        XCTAssertEqual(single.update(transcript: "hello"), 0)
        XCTAssertTrue(single.isAtEnd)
        var contraction = ScriptFollower(script: "I'm ready to begin.")
        XCTAssertEqual(contraction.update(transcript: "im ready"), 4)
    }
}
