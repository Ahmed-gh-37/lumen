import SwiftUI

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct SmallHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(LumenStyle.muted)
    }
}

struct SpeechLanguagePicker: View {
    var title = "Speech language"
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("English (US)").tag("en-US")
            Text("العربية (السعودية)").tag("ar-SA")
            Text("Français").tag("fr-FR")
            Text("Español").tag("es-ES")
            Text("Deutsch").tag("de-DE")
        }
    }
}
