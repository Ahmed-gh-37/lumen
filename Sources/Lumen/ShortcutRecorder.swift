import AppKit
import LumenCore
import SwiftUI

struct ShortcutRow: View {
    @ObservedObject var model: AppModel
    let action: ShortcutAction
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.system(size: 12))
                if action == .explainScreen {
                    Text("Captures and sends a screen question").font(.system(size: 9)).foregroundStyle(
                        LumenStyle.muted)
                }
                if action == .clickThrough {
                    Text("Toggle mouse passthrough; press again to restore").font(.system(size: 9)).foregroundStyle(
                        LumenStyle.muted)
                }
                if action == .automaticScreen {
                    Text("Start or stop · every minute · up to 60 screenshots").font(.system(size: 9)).foregroundStyle(
                        LumenStyle.muted)
                }
                if action == .teleprompter {
                    Text("Open the script and start or pause reading").font(.system(size: 9)).foregroundStyle(
                        LumenStyle.muted)
                }
            }
            Spacer(minLength: 8)
            if model.recordingShortcut == action {
                KeyRecorder(
                    onKey: { event in
                        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                        if event.keyCode == 53 && flags.isEmpty {
                            model.cancelShortcutRecording()
                            return
                        }
                        var modifiers: UInt32 = 0
                        if flags.contains(.command) { modifiers |= 1 }
                        if flags.contains(.option) { modifiers |= 2 }
                        if flags.contains(.shift) { modifiers |= 4 }
                        if flags.contains(.control) { modifiers |= 8 }
                        let binding = ShortcutBinding(
                            keyCode: UInt32(event.keyCode), modifiers: modifiers,
                            keyLabel: KeyRecorderView.label(for: event))
                        model.setShortcut(binding, for: action)
                    }, onCancel: { model.cancelShortcutRecording() }
                )
                .frame(width: 146, height: 30)
            } else {
                Button {
                    model.beginShortcutRecording(action)
                } label: {
                    Text(model.data.preferences.shortcut(for: action).display)
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(
                            LumenStyle.accent
                        )
                        .frame(minWidth: 118, minHeight: 30).background(.white.opacity(0.055)).clipShape(
                            RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel("Change \(action.title) shortcut")
            }
            Menu {
                Button("Reset to default") { model.setShortcut(action.defaultBinding, for: action) }
                Button("Remove shortcut") {
                    model.setShortcut(ShortcutBinding(keyCode: nil, modifiers: 0, keyLabel: ""), for: action)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 15)
            }.menuStyle(.borderlessButton).fixedSize()
        }
    }
}

private struct KeyRecorder: NSViewRepresentable {
    var onKey: (NSEvent) -> Void
    var onCancel: () -> Void
    func makeNSView(context: Context) -> KeyRecorderView { KeyRecorderView(onKey: onKey, onCancel: onCancel) }
    func updateNSView(_ view: KeyRecorderView, context: Context) {
        view.onKey = onKey
        view.onCancel = onCancel
    }
    static func dismantleNSView(_ view: KeyRecorderView, coordinator: ()) { view.stopMonitoring() }
}

final class KeyRecorderView: NSView {
    var onKey: (NSEvent) -> Void
    var onCancel: () -> Void
    private var monitor: Any?
    override var acceptsFirstResponder: Bool { true }

    init(onKey: @escaping (NSEvent) -> Void, onCancel: @escaping () -> Void) {
        self.onKey = onKey
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor(calibratedRed: 0.78, green: 0.91, blue: 0.61, alpha: 0.12).cgColor
        let label = NSTextField(labelWithString: "Press a shortcut…")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(calibratedRed: 0.78, green: 0.91, blue: 0.61, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel("Press a new shortcut. Escape cancels.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, monitor == nil else { return }
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                let point = self.convert(event.locationInWindow, from: nil)
                if event.window !== self.window || !self.bounds.contains(point) { self.onCancel() }
                return event
            }
            self.onKey(event)
            return nil
        }
    }
    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    deinit { stopMonitoring() }

    static func label(for event: NSEvent) -> String {
        let labels: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
            90: "F20",
        ]
        return labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}
