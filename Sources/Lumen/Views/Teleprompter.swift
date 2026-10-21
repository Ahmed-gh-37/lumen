import AppKit
import LumenCore
import SwiftUI

struct TeleprompterPane: View {
    @ObservedObject var model: AppModel
    private var hasScript: Bool {
        !model.teleprompterSettings.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var editing: Bool { model.teleprompterEditing || !hasScript }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Teleprompter").font(.system(size: 24, weight: .medium, design: .rounded))
                Spacer()
                Button(editing ? "Read script" : "Edit script") {
                    model.pauseTeleprompter()
                    model.teleprompterEditing = !editing
                }.font(.system(size: 11)).buttonStyle(.plain).disabled(!hasScript)
            }
            HStack(spacing: 13) {
                Button("Use latest AI response", systemImage: "sparkles") {
                    if let text = model.latestTeleprompterAnswer { model.useAnswerInTeleprompter(text) }
                }.disabled(model.latestTeleprompterAnswer == nil || model.isGenerating)
                Spacer()
                Text("Saved on this Mac").foregroundStyle(LumenStyle.muted)
            }.font(.system(size: 10)).buttonStyle(.plain)

            if editing {
                ZStack(alignment: .topLeading) {
                    if !hasScript {
                        Text("Paste or type your presentation here…").foregroundStyle(LumenStyle.muted).padding(13)
                            .allowsHitTesting(false)
                    }
                    TextEditor(
                        text: Binding(
                            get: { model.teleprompterSettings.script }, set: { model.setTeleprompterScript($0) })
                    )
                    .font(.system(size: 15)).scrollContentBackground(.hidden).padding(7)
                    .accessibilityLabel("Teleprompter script")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.04)).clipShape(
                    RoundedRectangle(cornerRadius: 10))
            } else {
                PrompterReader(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9)).foregroundStyle(
                            LumenStyle.accent
                        )
                        .padding(.top, 77).padding(.leading, 6).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .background(.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Toggle(
                "Follow my voice",
                isOn: Binding(
                    get: { model.teleprompterSettings.followVoice },
                    set: {
                        model.pauseTeleprompter()
                        model.teleprompterSettings.followVoice = $0
                    })
            ).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            if model.teleprompterSettings.followVoice {
                Text(
                    model.teleprompterRunning || model.teleprompterStarting
                        ? model.teleprompterVoiceStatus
                        : "Matches your spoken words to the script. Pauses during silence or off-script questions."
                )
                .font(.system(size: 10)).foregroundStyle(LumenStyle.muted).lineSpacing(3)
                SpeechLanguagePicker(title: "Speaking language", selection: $model.data.preferences.localeIdentifier)
                    .font(.system(size: 11))
                    .disabled(model.isListening || model.teleprompterRunning || model.teleprompterStarting)
            } else {
                HStack {
                    Text("Scroll speed").frame(width: 77, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { model.teleprompterSettings.speed }, set: { model.teleprompterSettings.speed = $0 }),
                        in: 10...100, step: 5
                    )
                    .accessibilityLabel("Teleprompter scroll speed")
                    Text("\(Int(model.teleprompterSettings.speed)) pt/s").monospacedDigit().frame(width: 51)
                }.font(.system(size: 11))
            }
            HStack {
                Text("Text size").frame(width: 77, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { model.teleprompterSettings.fontSize }, set: { model.teleprompterSettings.fontSize = $0 }),
                    in: 24...64, step: 2
                )
                .accessibilityLabel("Teleprompter text size")
                Text("\(Int(model.teleprompterSettings.fontSize)) pt").monospacedDigit().frame(width: 51)
            }.font(.system(size: 11))
            HStack(spacing: 15) {
                Button {
                    model.toggleTeleprompter()
                } label: {
                    Label(
                        model.teleprompterStarting
                            ? "Cancel"
                            : model.teleprompterRunning
                                ? "Pause" : model.teleprompterSettings.followVoice ? "Start following" : "Play",
                        systemImage: model.teleprompterRunning || model.teleprompterStarting
                            ? "pause.fill" : "play.fill")
                }.buttonStyle(.borderedProminent).foregroundStyle(LumenStyle.background).disabled(!hasScript)
                Button("Restart", systemImage: "backward.end.fill") { model.resetTeleprompter() }.buttonStyle(.plain)
                    .disabled(!hasScript)
                Spacer()
                Text(model.teleprompterShortcutLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(
                    LumenStyle.accent)
            }.font(.system(size: 12))
            Text(
                model.teleprompterSettings.followVoice
                    ? "Microphone and on-device speech recognition are used only after Start. No audio is sent to AI or read aloud. Use a close microphone to reduce other speakers being picked up."
                    : "Timed scrolling needs no microphone or AI connection. Pausing keeps your place."
            )
            .font(.system(size: 9)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
        }.padding(22)
    }
}

struct PrompterReader: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var verticalInset: CGFloat = 70

    func makeNSView(context: Context) -> PrompterScrollView {
        let view = PrompterScrollView()
        view.savedOffset = model.teleprompterScrollOffset
        return view
    }
    func updateNSView(_ view: PrompterScrollView, context: Context) {
        view.onPosition = { [weak model] offset in model?.teleprompterScrollOffset = offset }
        view.onEnd = { [weak model] in model?.pauseTeleprompter() }
        let settings = model.teleprompterSettings
        view.configure(
            script: settings.script, fontSize: settings.fontSize, speed: settings.speed,
            playing: model.teleprompterRunning && !settings.followVoice, resetID: model.teleprompterResetID,
            spokenOffset: settings.followVoice ? model.teleprompterSpokenOffset : nil, verticalInset: verticalInset)
    }
    static func dismantleNSView(_ view: PrompterScrollView, coordinator: ()) { view.stop() }
}

final class PrompterScrollView: NSScrollView {
    private let text = NSTextView(frame: .zero)
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var currentScript = ""
    private var currentFont: Double = 0
    private var currentReset: UUID?
    private var currentSpokenOffset: Int?
    private var lastLayoutSize = NSSize.zero
    private var speed: Double = 30
    private var playing = false
    var savedOffset: CGFloat = 0
    var onPosition: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 27, height: 70)
        text.textContainer?.widthTracksTextView = false
        documentView = text
        text.setAccessibilityLabel("Teleprompter reading area")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        script: String, fontSize: Double, speed: Double, playing: Bool, resetID: UUID, spokenOffset: Int?,
        verticalInset: CGFloat
    ) {
        self.speed = min(100, max(10, speed))
        let fontSize = min(64, max(24, fontSize))
        let reset = currentReset != nil && currentReset != resetID
        currentReset = resetID
        if reset {
            savedOffset = 0
            currentSpokenOffset = nil
        }
        if text.textContainerInset.height != verticalInset {
            text.textContainerInset.height = verticalInset
            lastLayoutSize = .zero
        }
        if currentScript != script || currentFont != fontSize {
            currentScript = script
            currentFont = fontSize
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = fontSize * 0.28
            paragraph.paragraphSpacing = fontSize * 0.5
            paragraph.baseWritingDirection = .natural
            text.textStorage?.setAttributedString(
                NSAttributedString(
                    string: script,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                        .foregroundColor: NSColor(white: 0.94, alpha: 1), .paragraphStyle: paragraph,
                    ]))
            lastLayoutSize = .zero
        }
        let speechChanged = currentSpokenOffset != spokenOffset
        currentSpokenOffset = spokenOffset
        layoutText()
        if reset { scroll(to: 0) }
        if let spokenOffset, speechChanged {
            followCharacter(spokenOffset)
        }
        if self.playing != playing {
            self.playing = playing
            if playing { startTimer() } else { stop() }
        }
    }

    override func layout() {
        super.layout()
        layoutText()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else if playing { startTimer() }
    }

    private func layoutText() {
        guard contentSize.width > 1, let container = text.textContainer, let manager = text.layoutManager else {
            return
        }
        if lastLayoutSize != contentSize {
            lastLayoutSize = contentSize
            container.containerSize = NSSize(width: max(1, contentSize.width - 54), height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            let height = max(
                contentSize.height, manager.usedRect(for: container).height + 2 * text.textContainerInset.height)
            text.setFrameSize(NSSize(width: contentSize.width, height: height))
            if let currentSpokenOffset { followCharacter(currentSpokenOffset) } else { scroll(to: savedOffset) }
        }
    }

    private func followCharacter(_ offset: Int) {
        guard let manager = text.layoutManager, let container = text.textContainer, !currentScript.isEmpty else {
            return
        }
        let range = NSRange(location: min(max(0, offset), (currentScript as NSString).length - 1), length: 1)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        scroll(to: rect.minY)
        onPosition?(savedOffset)
    }

    private func startTimer() {
        guard timer == nil, window != nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard playing, window?.isVisible == true else {
            lastTick = ProcessInfo.processInfo.systemUptime
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.1, max(0, now - lastTick))
        lastTick = now
        let maximum = max(0, text.frame.height - contentView.bounds.height)
        scroll(to: contentView.bounds.origin.y + CGFloat(speed * elapsed))
        if savedOffset >= maximum {
            stop()
            onEnd?()
        }
    }

    private func scroll(to offset: CGFloat) {
        let maximum = max(0, text.frame.height - contentView.bounds.height)
        savedOffset = min(maximum, max(0, offset))
        contentView.scroll(to: NSPoint(x: 0, y: savedOffset))
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        savedOffset = contentView.bounds.origin.y
        onPosition?(savedOffset)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        savedOffset = contentView.bounds.origin.y
        onPosition?(savedOffset)
    }
    deinit { timer?.invalidate() }
}
