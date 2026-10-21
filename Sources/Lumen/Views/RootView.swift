import AppKit
import LumenCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.notchSettings.enabled {
                VStack(spacing: 0) {
                    if model.notchExpanded {
                        Color.clear.frame(height: model.notchTopInset)
                        if model.notchReading { NotchTeleprompterPane(model: model) } else { workspace }
                    } else {
                        NotchCollapsedView(model: model)
                    }
                }
                .ignoresSafeArea()
                .background(Color.black)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 0))
            } else {
                workspace
                    .background(LumenStyle.background.opacity(0.96))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
                    .frame(minWidth: 480, minHeight: 580)
            }
        }.preferredColorScheme(.dark).tint(LumenStyle.accent).clipped()
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            header
            navigation
            if model.automaticScreenState.isRunning {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder").foregroundStyle(LumenStyle.accent)
                    Text("Auto screen · \(model.automaticScreenState.sentCount)/60 sent").monospacedDigit()
                    Spacer()
                    Button("Stop · \(model.automaticScreenShortcutLabel)") { model.stopAutomaticScreens() }.buttonStyle(
                        .plain
                    ).foregroundStyle(LumenStyle.accent)
                }.font(.system(size: 11)).padding(.horizontal, 24).padding(.vertical, 10).background(
                    LumenStyle.accent.opacity(0.07))
            }
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.system(size: 12)).textSelection(.enabled)
                    Spacer(minLength: 0)
                    IconButton(symbol: "xmark", help: "Dismiss") { model.error = nil }
                }.foregroundStyle(Color.orange.opacity(0.95)).padding(12).background(Color.orange.opacity(0.07))
            }
            Group {
                switch model.page {
                case .ask: AskPane(model: model)
                case .listen: ListenPane(model: model)
                case .notes: NotesPane(model: model)
                case .teleprompter: TeleprompterPane(model: model)
                case .settings: SettingsPane(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 21, weight: .medium)).foregroundStyle(LumenStyle.accent)
            Text("lumen").font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(-0.7)
            Text("A LITTLE CLARITY").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(
                LumenStyle.muted
            ).padding(.leading, 5)
            Spacer()
            NotchModeButton(model: model)
            IconButton(symbol: "slider.horizontal.3", help: "Settings") {
                model.page = model.page == .settings ? .ask : .settings
            }
            IconButton(symbol: "minus", help: "Hide · \(model.overlayShortcutLabel)") { model.hideWindow?() }
        }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
    }
    private var navigation: some View {
        HStack(spacing: 17) {
            ForEach([AppPage.ask, .listen, .notes, .teleprompter], id: \.self) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: page.symbol).font(.system(size: 12))
                        Text(page.rawValue).font(.system(size: 13, weight: .medium))
                        if page == .listen && model.isListening {
                            Circle().fill(LumenStyle.accent).frame(width: 5, height: 5)
                        }
                    }
                    .foregroundStyle(model.page == page ? LumenStyle.accent : LumenStyle.muted)
                    .padding(.bottom, 13)
                    .overlay(alignment: .bottom) {
                        if model.page == page { Rectangle().fill(LumenStyle.accent).frame(height: 2) }
                    }
                }.buttonStyle(.plain)
            }
            Spacer()
            Text(
                model.mousePassthrough
                    ? "CLICK-THROUGH · \(model.mouseShortcutLabel)"
                    : model.page == .settings ? "PREFERENCES" : "\(model.overlayShortcutLabel) to hide"
            ).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(
                model.mousePassthrough ? LumenStyle.accent : LumenStyle.muted)
        }.padding(.horizontal, 25).overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(
                model.networkPaused ? Color.orange : model.providerReady ? LumenStyle.accent : LumenStyle.muted
            ).frame(width: 5, height: 5)
            Text(
                model.mousePassthrough
                    ? "Clicks pass through · \(model.mouseShortcutLabel) restores interaction" : model.providerStatus
            ).font(.system(size: 10)).foregroundStyle(LumenStyle.muted).lineLimit(1)
            Spacer(minLength: 2)
            Button {
                model.toggleNetwork()
            } label: {
                Image(systemName: model.networkPaused ? "play.circle" : "pause.circle").font(.system(size: 14))
            }.buttonStyle(.plain).foregroundStyle(LumenStyle.muted)
                .help(model.networkPaused ? "Resume AI" : "Pause AI and cancel the current request")
                .accessibilityLabel(model.networkPaused ? "Resume AI" : "Pause AI")
        }.padding(.horizontal, 23).padding(.vertical, 13).overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}
