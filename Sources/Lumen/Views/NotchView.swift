import AppKit
import LumenCore
import SwiftUI

struct NotchModeButton: View {
    @ObservedObject var model: AppModel
    var body: some View {
        IconButton(
            symbol: model.notchSettings.enabled ? "rectangle.on.rectangle" : "rectangle.topthird.inset.filled",
            help: model.notchSettings.enabled ? "Return to floating window" : "Attach to notch"
        ) { model.toggleNotchMode() }
    }
}

struct NotchCollapsedView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Button {
            model.notchExpanded = true
        } label: {
            HStack {
                Image(systemName: "sparkle").font(.system(size: 15)).foregroundStyle(LumenStyle.accent)
                Spacer(minLength: model.notchCameraWidth)
                Circle().fill(
                    model.isListening || model.automaticScreenState.isRunning
                        ? LumenStyle.accent : Color.white.opacity(0.45)
                ).frame(width: 6, height: 6)
            }.padding(.horizontal, 19).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Expand Lumen from notch").help("Hover or click to open Lumen")
    }
}

struct NotchSizingControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Notch width").frame(width: 78, alignment: .leading)
                Slider(
                    value: Binding(get: { model.notchSettings.width }, set: { model.notchSettings.width = $0 }),
                    in: 480...900, step: 20
                )
                .accessibilityLabel("Notch panel width")
                Text("\(Int(model.notchSettings.width))").monospacedDigit().frame(width: 30)
            }
            HStack {
                Text("Script lines").frame(width: 78, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(model.notchSettings.readingLines) },
                        set: { model.notchSettings.readingLines = Int($0) }), in: 2...8, step: 1
                )
                .accessibilityLabel("Notch script lines")
                Text("\(model.notchSettings.readingLines)").monospacedDigit().frame(width: 30)
            }
        }.font(.system(size: 11))
    }
}

struct NotchTeleprompterPane: View {
    @ObservedObject var model: AppModel
    @State private var sizing = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(LumenStyle.accent)
                Text("lumen").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("PROMPTER").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(LumenStyle.muted)
                Spacer()
                if model.mousePassthrough {
                    Text("\(model.mouseShortcutLabel) restores clicks").font(.system(size: 9)).foregroundStyle(
                        LumenStyle.muted)
                }
                Button {
                    sizing.toggle()
                } label: {
                    Image(systemName: "textformat.size")
                }.buttonStyle(.plain).accessibilityLabel("Adjust notch size")
                    .popover(isPresented: $sizing) {
                        NotchSizingControls(model: model).padding(18).frame(width: 320)
                            .onAppear { model.notchSizing = true }.onDisappear { model.notchSizing = false }
                    }
                NotchModeButton(model: model)
            }.frame(height: 24)
            if let error = model.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
            PrompterReader(model: model, verticalInset: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(
                        LumenStyle.accent
                    )
                    .padding(.leading, 7).padding(.top, 24).allowsHitTesting(false).accessibilityHidden(true)
                }
            HStack(spacing: 14) {
                Button {
                    model.toggleTeleprompter()
                } label: {
                    Label(
                        model.teleprompterStarting ? "Cancel" : model.teleprompterRunning ? "Pause" : "Play",
                        systemImage: model.teleprompterRunning || model.teleprompterStarting
                            ? "pause.fill" : "play.fill")
                }.buttonStyle(.plain).foregroundStyle(LumenStyle.accent)
                Button("Restart") { model.resetTeleprompter() }.buttonStyle(.plain)
                Button("Full controls") {
                    model.pauseTeleprompter()
                    model.teleprompterEditing = true
                }.buttonStyle(.plain)
                Spacer()
                Text(
                    model.teleprompterSettings.followVoice
                        ? (model.teleprompterRunning ? model.teleprompterVoiceStatus : "Voice follow · paused")
                        : "Timed scrolling"
                )
                .font(.system(size: 9)).foregroundStyle(LumenStyle.muted).lineLimit(1)
            }.font(.system(size: 11)).frame(height: 26)
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 14)
    }
}

/// Tracks the native window, so replacing collapsed/expanded SwiftUI content
/// does not lose hover events or activate the app the user is presenting from.
final class OverlayHostingView: NSHostingView<RootView> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
