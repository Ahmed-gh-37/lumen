import AppKit
import LumenCore
import SwiftUI

struct ListenPane: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep the conversation.").font(.system(size: 25, weight: .medium, design: .rounded)).tracking(
                        -0.7)
                    Text("Live words. Useful context. Notes to come back to.").font(.system(size: 12)).foregroundStyle(
                        LumenStyle.muted)
                }
                Picker("Audio source", selection: $model.data.preferences.audioSource) {
                    ForEach(AudioSource.allCases) { source in Text(source.title).tag(source) }
                }.pickerStyle(.segmented).labelsHidden().disabled(model.isListening || model.listeningBusy)
                HStack(spacing: 15) {
                    Button {
                        model.toggleListening()
                    } label: {
                        Label(
                            model.listeningBusy ? "Starting…" : model.isListening ? "End session" : "Start listening",
                            systemImage: model.isListening ? "stop.fill" : "waveform"
                        )
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
                        .foregroundStyle(LumenStyle.background).background(LumenStyle.accent).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(model.listeningBusy)
                    if model.isListening {
                        Button(model.answersPaused ? "Resume answers" : "Pause answers") { model.toggleAnswersPause() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(LumenStyle.muted)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text(elapsed(at: timeline.date)).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(LumenStyle.accent)
                        }
                    }
                }
                HStack(spacing: 3) {
                    ForEach(0..<32) { i in
                        Capsule().fill(
                            model.isListening
                                ? LumenStyle.accent.opacity(0.45 + Double(i % 3) * 0.15) : Color.white.opacity(0.12)
                        )
                        .frame(width: 3, height: max(3, CGFloat(model.audioLevel) * CGFloat(14 + (i * 7) % 36)))
                    }
                    Spacer()
                    Text(model.isListening ? "ON DEVICE" : "READY WHEN YOU ARE").font(.system(size: 8, weight: .medium))
                        .tracking(1.4).foregroundStyle(LumenStyle.muted)
                }.frame(height: 42).animation(.easeOut(duration: 0.15), value: model.audioLevel)
                Toggle("Draft answers when a question is detected", isOn: $model.data.preferences.automaticSuggestions)
                    .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
                if model.answersPaused {
                    Text("Transcription continues while answers are paused.").font(.system(size: 11)).foregroundStyle(
                        LumenStyle.muted)
                }
                Divider().opacity(0.5)
                HStack {
                    SmallHeading("LIVE TRANSCRIPT")
                    Spacer()
                    if !model.transcript.isEmpty {
                        Button("Ask about this", systemImage: "arrow.up.right") {
                            model.page = .ask
                            model.draft = "Summarize this conversation."
                        }.font(.system(size: 11)).buttonStyle(.plain)
                    }
                }
                Text(
                    model.transcript.isEmpty
                        ? "Your transcript will appear here. Listening starts only when you press Start."
                        : model.transcript
                )
                .font(.system(size: 13)).lineSpacing(5).foregroundStyle(
                    model.transcript.isEmpty ? LumenStyle.muted : .white
                ).textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                if let last = model.messages.last, last.role == .assistant, !last.text.isEmpty {
                    Divider().opacity(0.5)
                    MessageView(
                        message: last, pending: model.isGenerating,
                        onPrompter: { model.useAnswerInTeleprompter(last.text) })
                }
                Text(
                    "Transcripts are saved to Notes when you end a session. Selected AI requests use your chosen provider."
                ).font(.system(size: 10)).lineSpacing(3).foregroundStyle(LumenStyle.muted)
            }.padding(25)
        }
    }
    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(model.sessionStartedAt ?? date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
