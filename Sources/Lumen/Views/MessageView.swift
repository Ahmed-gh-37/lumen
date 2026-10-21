import AppKit
import LumenCore
import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    var pending = false
    var onPrompter: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.crop.circle" : "sparkle")
                Text(message.role == .user ? "YOU" : "LUMEN").tracking(1.4)
                Spacer()
                if message.role == .assistant, !message.text.isEmpty, !pending, let onPrompter {
                    IconButton(symbol: "text.alignleft", help: "Read in teleprompter", action: onPrompter)
                }
                if !message.text.isEmpty {
                    IconButton(symbol: "doc.on.doc", help: "Copy message") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }
                }
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(
                message.role == .user ? LumenStyle.muted : LumenStyle.accent)
            if message.text.isEmpty && pending {
                ProgressView().controlSize(.small).padding(.vertical, 6)
            } else if message.text.isEmpty {
                Text("Response stopped before any text arrived.").font(.system(size: 12)).foregroundStyle(
                    LumenStyle.muted)
            } else {
                Text(.init(message.text)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
