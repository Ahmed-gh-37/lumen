import CoreGraphics
import XCTest

@testable import LumenCore

final class NotchGeometryTests: XCTestCase {
    func testCollapsedFrameSurroundsCameraAndAttachesToScreenTop() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = NotchGeometry.frame(
            screen: screen, cameraCenterX: 756, cameraWidth: 180, topInset: 37,
            expanded: false, preferredWidth: 640, bodyHeight: 700)
        XCTAssertEqual(frame.width, 276)
        XCTAssertEqual(frame.height, 45)
        XCTAssertEqual(frame.midX, 756)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testReadingPanelUsesRequestedLinesAndPreservesTopAnchor() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let body = NotchGeometry.readingBodyHeight(fontSize: 32, lines: 4)
        let frame = NotchGeometry.frame(
            screen: screen, cameraCenterX: 756, cameraWidth: 180, topInset: 37,
            expanded: true, preferredWidth: 640, bodyHeight: body)
        XCTAssertEqual(frame.width, 640)
        XCTAssertEqual(frame.height, body + 37, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertLessThan(frame.height, 400)
        XCTAssertGreaterThan(NotchGeometry.readingBodyHeight(fontSize: 32, lines: 6), body)
    }

    func testSecondaryDisplayWithNegativeOriginAndNoCamera() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let frame = NotchGeometry.frame(
            screen: screen, cameraCenterX: -960, cameraWidth: 94, topInset: 0,
            expanded: true, preferredWidth: 720, bodyHeight: 700)
        XCTAssertEqual(frame.midX, -960)
        XCTAssertEqual(frame.maxY, 0)
        XCTAssertTrue(screen.contains(frame))
    }

    func testLargeScriptAndOffCenterCameraStayInsideSmallDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = NotchGeometry.frame(
            screen: screen, cameraCenterX: 50, cameraWidth: 200, topInset: 37,
            expanded: true, preferredWidth: 1400,
            bodyHeight: NotchGeometry.readingBodyHeight(fontSize: 64, lines: 8))
        XCTAssertEqual(frame.width, 776)
        XCTAssertEqual(frame.height, 576)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testNarrowDisplayAndMalformedPreferencesRemainBounded() {
        let screen = CGRect(x: 100, y: 100, width: 320, height: 300)
        let frame = NotchGeometry.frame(
            screen: screen, cameraCenterX: -3000, cameraWidth: 1000, topInset: -10,
            expanded: true, preferredWidth: -100, bodyHeight: 900)
        XCTAssertEqual(frame.width, 296)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(
            NotchGeometry.readingBodyHeight(fontSize: 2, lines: 30),
            NotchGeometry.readingBodyHeight(fontSize: 24, lines: 8))
    }
}
