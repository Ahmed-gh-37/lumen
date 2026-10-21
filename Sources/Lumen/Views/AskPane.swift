import AppKit
import LumenCore
import SwiftUI

struct AskPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if !model.messages.isEmpty {
                HStack {
                    Menu {
                        ForEach(model.data.conversations.sorted { $0.updatedAt > $1.updatedAt }) { item in
                            Button(item.title) {
                                model.cancelGeneration()
                                model.activeConversationID = item.id
                            }
                        }
                    } label: {
                        Label("Conversations", systemImage: "clock.arrow.circlepath").font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Button("New chat", systemImage: "square.and.pencil") { model.newConversation() }.font(
                        .system(size: 11)
                    ).buttonStyle(.plain)
                }.foregroundStyle(LumenStyle.muted).padding(.horizontal, 24).padding(.top, 16)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.messages.isEmpty { emptyState }
                        ForEach(model.messages) { message in
                            MessageView(
                                message: message, pending: model.isGenerating && message.id == model.messages.last?.id,
                                onPrompter: { model.useAnswerInTeleprompter(message.text) }
                            ).id(message.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(25)
                }
                .onChange(of: model.messages.last?.text) { _, _ in
                    if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            composer
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "asterisk").font(.system(size: 37, weight: .ultraLight)).foregroundStyle(
                LumenStyle.accent
            ).padding(.top, 28)
            Text("A little clarity,\nright where you are.").font(.system(size: 33, weight: .medium, design: .rounded))
                .tracking(-1.2).lineSpacing(2)
            Text("Ask a question. Bring in your screen.\nKeep the conversation in view.").font(.system(size: 13))
                .lineSpacing(4).foregroundStyle(LumenStyle.muted)
            VStack(spacing: 0) {
                quickAction("Explain what's on my screen", icon: "viewfinder") { model.explainScreen() }
                Divider().opacity(0.4)
                quickAction("Catch me up on the conversation", icon: "waveform") {
                    model.send("Summarize the recent conversation and the main points I should know.")
                }.disabled(model.transcript.isEmpty)
            }.padding(.top, 14)
            if !model.providerReady {
                Button {
                    model.page = .settings
                } label: {
                    HStack {
                        Text("Connect your ChatGPT plan")
                        Image(systemName: "arrow.up.right")
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(LumenStyle.accent)
                }.buttonStyle(.plain).padding(.top, 4)
            }
        }.padding(.bottom, 10)
    }
    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).padding(.vertical, 14)
        }.buttonStyle(.plain)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attachment = model.attachment {
                HStack(spacing: 10) {
                    Image(nsImage: attachment.image).resizable().aspectRatio(contentMode: .fill).frame(
                        width: 60, height: 40
                    ).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screen attached").font(.system(size: 11, weight: .medium))
                        Text("Sent with your next question").font(.system(size: 10)).foregroundStyle(LumenStyle.muted)
                    }
                    Spacer()
                    IconButton(symbol: "xmark", help: "Remove screenshot") { model.attachment = nil }
                }
            }
            TextField("Ask anything…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...5).onSubmit { model.send() }
                .accessibilityLabel("Your question")
            HStack(spacing: 12) {
                Button {
                    model.captureScreen()
                } label: {
                    Label(model.captureBusy ? "Capturing…" : "Screen", systemImage: "viewfinder").font(
                        .system(size: 11))
                }
                .buttonStyle(.plain).disabled(model.captureBusy || model.isGenerating)
                if model.availableDisplays.count > 1 {
                    Menu {
                        ForEach(model.availableDisplays) { display in
                            Button(display.name) { model.selectedDisplayID = display.id }
                        }
                    } label: {
                        Image(systemName: "display.2").font(.system(size: 11))
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Toggle(isOn: $model.data.preferences.includeListenContext) {
                    Label("Listen context", systemImage: "ear").font(.system(size: 10))
                }.toggleStyle(.checkbox).disabled(model.transcript.isEmpty)
                Spacer()
                Button {
                    model.isGenerating ? model.cancelGeneration() : model.send()
                } label: {
                    Image(systemName: model.isGenerating ? "stop.fill" : "arrow.up").font(
                        .system(size: 13, weight: .bold)
                    ).foregroundStyle(LumenStyle.background)
                        .frame(width: 31, height: 31).background(LumenStyle.accent).clipShape(Circle())
                }.buttonStyle(.plain).disabled(
                    !model.isGenerating
                        && (model.captureBusy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ).accessibilityLabel(model.isGenerating ? "Stop response" : "Send question")
            }.foregroundStyle(LumenStyle.muted)
        }.padding(16).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
    }
}
