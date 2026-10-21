import AppKit
import LumenCore
import SwiftUI

struct SettingsPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                Text("Your AI, your choice.").font(.system(size: 26, weight: .medium, design: .rounded)).tracking(-0.7)
                providerSettings
                Divider().opacity(0.5)
                SmallHeading("YOUR OVERLAY")
                Toggle(
                    "Attach Lumen to the notch",
                    isOn: Binding(
                        get: { model.notchSettings.enabled },
                        set: { enabled in
                            model.notchSettings.enabled = enabled
                            model.notchExpanded = enabled
                        })
                ).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                Toggle(
                    "Use notch mode when the teleprompter starts",
                    isOn: Binding(
                        get: { model.notchSettings.automaticallyForTeleprompter },
                        set: { model.notchSettings.automaticallyForTeleprompter = $0 })
                )
                .font(.system(size: 11)).toggleStyle(.switch).controlSize(.small)
                Text(
                    "Hover to expand. The teleprompter stays open while running. The notch button returns to the floating window."
                ).font(.system(size: 10)).foregroundStyle(LumenStyle.muted)
                NotchSizingControls(model: model)
                Divider().opacity(0.5)
                Toggle("Let mouse clicks pass through Lumen", isOn: $model.mousePassthrough).font(.system(size: 12))
                    .toggleStyle(.switch).controlSize(.small)
                Text(
                    "Press \(model.mouseShortcutLabel) again to interact. The Lumen menu also restores mouse interaction."
                ).font(.system(size: 10)).foregroundStyle(LumenStyle.muted)
                HStack {
                    Text("Opacity")
                    Slider(value: $model.data.preferences.opacity, in: 0.45...1)
                        .accessibilityLabel("Overlay opacity")
                        .accessibilityValue("\(Int(model.data.preferences.opacity * 100)) percent")
                    Text("\(Int(model.data.preferences.opacity * 100))%")
                        .monospacedDigit().frame(width: 34)
                }.font(.system(size: 12))
                Toggle("Request capture exclusion", isOn: $model.data.preferences.protectCapture).font(
                    .system(size: 12)
                ).toggleStyle(.switch).controlSize(.small)
                Text(
                    "Capture apps on newer macOS versions may still include the overlay. Verify with your screen-sharing app before relying on this setting."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
                HStack {
                    Text("Screen access: \(model.screenAccessStatus)").font(.system(size: 11))
                    Spacer()
                    Button("Check access") { model.checkScreenAccess() }.font(.system(size: 10)).disabled(
                        model.captureBusy)
                }
                HStack(spacing: 15) {
                    Button("Screen Recording settings") {
                        NSWorkspace.shared.open(
                            URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        )
                    }
                    Button("Show this app") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(LumenStyle.accent)
                Divider().opacity(0.5)
                SmallHeading("AUTOMATIC SCREEN EXPLANATIONS")
                Text(
                    "Capture and send your selected screen to \(model.data.preferences.provider.title) immediately, then every minute. Stops after 60 screenshots. Responses appear in a dedicated chat."
                ).font(.system(size: 11)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
                HStack {
                    Button(
                        model.automaticScreenState.isRunning
                            ? "Stop automatic screenshots" : "Start automatic screenshots"
                    ) { model.toggleAutomaticScreens() }
                    .buttonStyle(.bordered).font(.system(size: 11))
                    .disabled(
                        !model.automaticScreenState.isRunning
                            && (!model.providerReady || model.networkPaused || model.isGenerating || model.captureBusy))
                    Spacer()
                    Text("\(model.automaticScreenState.sentCount) / 60 sent").font(.system(size: 11)).monospacedDigit()
                }
                Text(
                    "\(model.automaticScreenShortcutLabel) starts or stops the session. Busy minutes are skipped. Pause AI, a capture or response error, or quitting stops the session. Starting again resets the counter. Uses your connected plan or API allowance."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
                Divider().opacity(0.5)
                SmallHeading("LISTEN & CONTEXT")
                SpeechLanguagePicker(selection: $model.data.preferences.localeIdentifier)
                    .font(.system(size: 12))
                    .disabled(model.isListening || model.teleprompterRunning || model.teleprompterStarting)
                Text(
                    "On-device speech recognition must be available for your selected language. No cloud speech fallback is used."
                ).font(.system(size: 10)).foregroundStyle(LumenStyle.muted)
                Text("Personal context").font(.system(size: 12, weight: .medium))
                TextEditor(text: $model.data.preferences.personalContext).font(.system(size: 12)).frame(height: 80)
                    .scrollContentBackground(.hidden).padding(8).background(.white.opacity(0.04)).clipShape(
                        RoundedRectangle(cornerRadius: 8))
                Text("Add background or terminology to include with your questions.").font(.system(size: 10))
                    .foregroundStyle(LumenStyle.muted)
                DisclosureGroup("Assistant instructions") {
                    TextEditor(text: $model.data.preferences.instructions).font(.system(size: 11)).frame(height: 90)
                        .scrollContentBackground(.hidden)
                }.font(.system(size: 11))
                Divider().opacity(0.5)
                SmallHeading("SHORTCUTS")
                Text(
                    "Click a shortcut, then press your new key combination. Escape cancels. Changes apply immediately and are saved on this Mac."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
                VStack(spacing: 12) {
                    ForEach(ShortcutAction.allCases) { action in ShortcutRow(model: model, action: action) }
                }
                Divider().opacity(0.5)
                HStack {
                    SmallHeading("LOCAL DATA")
                    Spacer()
                    Button("Open folder") { NSWorkspace.shared.open(model.store.directory) }.font(.system(size: 11))
                        .buttonStyle(.plain)
                }
                Text(
                    "Notes, chat text, and preferences stay in this app's folder. Screenshots stay in memory until sent or removed. ChatGPT manages its own sign-in in a separate app profile; optional API keys use Keychain."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
                if !model.activity.isEmpty {
                    DisclosureGroup("Activity") {
                        ForEach(Array(model.activity.prefix(8).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 10)).foregroundStyle(LumenStyle.muted).frame(
                                maxWidth: .infinity, alignment: .leading
                            ).padding(.vertical, 3)
                        }
                    }.font(.system(size: 11))
                }
            }.padding(25)
        }.onDisappear { model.cancelShortcutRecording() }
    }
    private var providerSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("AI connection", selection: $model.data.preferences.provider) {
                ForEach(AIProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }.pickerStyle(.segmented).labelsHidden().onChange(of: model.data.preferences.provider) { _, _ in
                model.stopAutomaticScreens()
                model.cancelGeneration()
                model.loadProviderKey()
            }
            if model.data.preferences.provider == .chatGPT {
                HStack(spacing: 10) {
                    Image(systemName: model.account.isSignedIn ? "checkmark.circle.fill" : "person.crop.circle")
                        .foregroundStyle(model.account.isSignedIn ? LumenStyle.accent : LumenStyle.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.account.isSignedIn ? "ChatGPT plan connected" : "Use your ChatGPT subscription")
                            .font(.system(size: 13, weight: .medium))
                        Text(model.account.summary).font(.system(size: 10)).foregroundStyle(LumenStyle.muted)
                    }
                    Spacer()
                    if model.accountBusy { ProgressView().controlSize(.small) }
                }
                if model.account.isSignedIn {
                    HStack {
                        Picker("Model", selection: $model.data.preferences.chatGPTModel) {
                            Text("Automatic").tag("")
                            ForEach(model.models) { option in Text(option.title).tag(option.id) }
                        }.font(.system(size: 11))
                        Button("Disconnect") { model.disconnectChatGPT() }.font(.system(size: 10)).buttonStyle(.plain)
                    }
                } else {
                    HStack {
                        Button("Continue with ChatGPT") { model.connectChatGPT() }.buttonStyle(.borderedProminent)
                            .foregroundStyle(LumenStyle.background).disabled(model.accountBusy)
                        Button("Check connection") { model.refreshAccount() }.font(.system(size: 10)).buttonStyle(
                            .plain
                        ).disabled(model.accountBusy)
                    }
                }
                Text(
                    "Eligible plan usage counts toward your existing Codex / work allowance. Your ChatGPT conversations and memories are not imported."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
            } else {
                Text("Optional · bring your own \(model.data.preferences.provider.title) API key").font(
                    .system(size: 12, weight: .medium))
                HStack {
                    SecureField(model.keySaved ? "Key saved in Keychain" : "Paste API key", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { model.saveProviderKey() }.disabled(model.apiKeyDraft.isEmpty)
                    if model.keySaved {
                        IconButton(symbol: "trash", help: "Remove saved key") { model.deleteProviderKey() }
                    }
                }
                HStack {
                    Text("Model").font(.system(size: 11))
                    TextField(
                        "Model ID",
                        text: Binding(
                            get: { model.data.preferences.selectedModel },
                            set: { text in
                                if model.data.preferences.provider == .gemini {
                                    model.data.preferences.geminiModel = text
                                } else {
                                    model.data.preferences.claudeModel = text
                                }
                            })
                    ).textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
                Text("Requests go directly to your selected provider. API usage is billed separately by that provider.")
                    .font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
            }
        }
    }
}
