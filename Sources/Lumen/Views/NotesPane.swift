import AppKit
import LumenCore
import SwiftUI

struct NotesPane: View {
    @ObservedObject var model: AppModel
    @State private var confirmDelete = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search notes", text: $model.noteSearch).textFieldStyle(.plain).font(.system(size: 12))
                Menu {
                    ForEach(["All", "Favorites", "Archived"], id: \.self) { name in
                        Button(name) { model.noteFilter = name }
                    }
                } label: {
                    Text(model.noteFilter).font(.system(size: 10))
                }.menuStyle(.borderlessButton).fixedSize()
                IconButton(symbol: "plus", help: "New note") { model.newNote() }
            }.padding(.horizontal, 22).padding(.vertical, 15)
            Divider().opacity(0.4)
            if model.data.notes.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "text.book.closed").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(
                        LumenStyle.accent)
                    Text("Make room for what matters.").font(.system(size: 20, weight: .medium, design: .rounded))
                    Text("Save a thought, or end a Listen session\nto keep its transcript here.").font(
                        .system(size: 12)
                    ).multilineTextAlignment(.center).foregroundStyle(LumenStyle.muted)
                    Button("Create a note") { model.newNote() }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.filteredNotes) { note in
                                Button {
                                    model.selectedNoteID = note.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(spacing: 4) {
                                            if note.isFavorite {
                                                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(
                                                    LumenStyle.accent)
                                            }
                                            Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        }
                                        Text(note.updatedAt, style: .date).font(.system(size: 9)).foregroundStyle(
                                            LumenStyle.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
                                        model.selectedNoteID == note.id ? Color.white.opacity(0.06) : .clear)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(width: 163)
                    Divider().opacity(0.4)
                    if let id = model.selectedNoteID, let note = model.data.notes.first(where: { $0.id == id }) {
                        noteEditor(note)
                    } else {
                        Text(model.filteredNotes.isEmpty ? "No matching notes" : "Choose a note").font(
                            .system(size: 12)
                        ).foregroundStyle(LumenStyle.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
    private func noteEditor(_ note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "Untitled note",
                    text: Binding(
                        get: { model.data.notes.first(where: { $0.id == note.id })?.title ?? "" },
                        set: { text in model.updateNote(id: note.id) { $0.title = text } })
                )
                .textFieldStyle(.plain).font(.system(size: 21, weight: .medium, design: .rounded))
                HStack(spacing: 12) {
                    IconButton(symbol: note.isFavorite ? "star.fill" : "star", help: "Favorite") {
                        model.updateNote(id: note.id) { $0.isFavorite.toggle() }
                    }
                    IconButton(
                        symbol: note.isArchived ? "tray.and.arrow.up" : "archivebox",
                        help: note.isArchived ? "Unarchive" : "Archive"
                    ) { model.updateNote(id: note.id) { $0.isArchived.toggle() } }
                    Menu {
                        Button("Markdown") { model.exportNote(note) }
                        Button("PDF") { model.exportNote(note, asPDF: true) }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(note.markdown, forType: .string)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    IconButton(symbol: "trash", help: "Delete note") { confirmDelete = true }
                }.foregroundStyle(LumenStyle.muted)
                TextField(
                    "Tags, separated by commas",
                    text: Binding(
                        get: { note.tags.joined(separator: ", ") },
                        set: { text in
                            model.updateNote(id: note.id) {
                                $0.tags = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        })
                ).font(.system(size: 10)).textFieldStyle(.plain).foregroundStyle(LumenStyle.muted)
                TextEditor(
                    text: Binding(
                        get: { model.data.notes.first(where: { $0.id == note.id })?.content ?? "" },
                        set: { text in model.updateNote(id: note.id) { $0.content = text } })
                )
                .font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 210)
                Button("Draft a summary", systemImage: "sparkles") { model.summarizeNote(id: note.id) }.buttonStyle(
                    .bordered
                ).font(.system(size: 11)).disabled(
                    model.isGenerating || (note.content.isEmpty && note.transcript.isEmpty))
                if model.notePreviewID == note.id {
                    Divider()
                    SmallHeading(model.isGenerating ? "DRAFTING SUMMARY" : "SUMMARY PREVIEW")
                    Text(.init(model.notePreview)).font(.system(size: 12)).textSelection(.enabled)
                    HStack {
                        Button("Apply") { model.applyNotePreview() }.disabled(
                            model.isGenerating || model.notePreview.isEmpty)
                        Button("Discard") {
                            model.cancelGeneration()
                            model.notePreviewID = nil
                            model.notePreview = ""
                        }
                    }.font(.system(size: 11))
                }
                if !note.transcript.isEmpty {
                    DisclosureGroup("Transcript") {
                        Text(note.transcript).font(.system(size: 11)).lineSpacing(4).textSelection(.enabled).frame(
                            maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 11)).foregroundStyle(LumenStyle.muted)
                }
                Text("Saved on this Mac").font(.system(size: 9)).foregroundStyle(LumenStyle.muted)
            }.padding(18)
        }.confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
            Button("Delete note", role: .destructive) { model.deleteNote(id: note.id) }
        }
    }
}
