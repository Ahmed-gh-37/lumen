import XCTest

@testable import LumenCore

final class ShortcutTests: XCTestCase {
    func testOlderPreferencesWithoutShortcutsDecodeAndUseDefaults() throws {
        let legacy = Data(
            #"{"provider":"chatGPT","chatGPTModel":"","geminiModel":"gemini-3.8-flash","claudeModel":"claude-sonnet-5-5","opacity":0.96,"protectCapture":true,"localeIdentifier":"en-US","audioSource":"microphone","includeListenContext":true,"automaticSuggestions":false,"personalContext":"","instructions":"Be helpful."}"#
                .utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertNil(preferences.shortcuts)
        XCTAssertNil(preferences.teleprompter)
        XCTAssertNil(preferences.notch)
        for action in ShortcutAction.allCases {
            XCTAssertEqual(preferences.shortcut(for: action), action.defaultBinding)
        }
    }

    func testCustomAndExplicitlyDisabledBindingsSurviveRoundTrip() throws {
        var preferences = Preferences()
        let custom = ShortcutBinding(keyCode: 18, modifiers: 13, keyLabel: "1")
        let disabled = ShortcutBinding(keyCode: nil, modifiers: 0, keyLabel: "")
        preferences.shortcuts = [
            ShortcutAction.explainScreen.rawValue: custom,
            ShortcutAction.captureScreen.rawValue: disabled,
        ]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.shortcut(for: .explainScreen), custom)
        XCTAssertEqual(decoded.shortcut(for: .captureScreen), disabled)
        XCTAssertNil(decoded.shortcut(for: .captureScreen).keyCode)
        XCTAssertEqual(decoded.shortcut(for: .ask), ShortcutAction.ask.defaultBinding)
    }

    func testConflictsUseHardwareCodeAndModifiersRegardlessOfLabel() {
        let a = ShortcutBinding(keyCode: 0, modifiers: 3, keyLabel: "A")
        let alternateLabel = ShortcutBinding(keyCode: 0, modifiers: 3, keyLabel: "Q")
        XCTAssertTrue(a.conflicts(with: alternateLabel))
        XCTAssertTrue(alternateLabel.conflicts(with: a))
        XCTAssertFalse(a.conflicts(with: ShortcutBinding(keyCode: 0, modifiers: 7, keyLabel: "A")))
        XCTAssertFalse(a.conflicts(with: ShortcutBinding(keyCode: 12, modifiers: 3, keyLabel: "A")))
        let disabled = ShortcutBinding(keyCode: nil, modifiers: 3, keyLabel: "A")
        XCTAssertFalse(a.conflicts(with: disabled))
        XCTAssertFalse(disabled.conflicts(with: a))
        XCTAssertFalse(disabled.conflicts(with: disabled))
    }

    func testDisplayUsesConventionalModifierOrderAndDisabledLabel() {
        XCTAssertEqual(ShortcutBinding(keyCode: 14, modifiers: 15, keyLabel: "E").display, "⌃⌥⇧⌘E")
        XCTAssertEqual(ShortcutBinding(keyCode: 49, modifiers: 0, keyLabel: "Space").display, "Space")
        XCTAssertEqual(ShortcutBinding(keyCode: nil, modifiers: 15, keyLabel: "E").display, "Not assigned")
    }

    func testActionIDsAndDefaultsRemainStableAndDistinct() {
        XCTAssertEqual(ShortcutAction.allCases.map(\.hotKeyID), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(ShortcutAction.allCases.map { $0.defaultBinding.keyCode }, [49, 0, 37, 45, 1, 14, 37, 11, 17])
        XCTAssertEqual(ShortcutAction.allCases.map { $0.defaultBinding.modifiers }, [3, 3, 3, 3, 3, 3, 1, 1, 3])
        for action in ShortcutAction.allCases {
            for other in ShortcutAction.allCases where other != action {
                XCTAssertFalse(action.defaultBinding.conflicts(with: other.defaultBinding))
            }
        }
    }
}
