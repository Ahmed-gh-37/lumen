import AppKit
import CoreText
import LumenCore

enum PDFExporter {
    static func write(note: Note, to url: URL) throws {
        let text = NSMutableAttributedString(
            string: note.title + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.black])
        text.append(
            NSAttributedString(
                string: note.content + (note.transcript.isEmpty ? "" : "\n\nTRANSCRIPT\n\n" + note.transcript),
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else {
            throw LumenError.message("Could not create the PDF.")
        }
        let setter = CTFramesetterCreateWithAttributedString(text)
        var position = 0
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: position, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let range = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard range.length > 0 else { break }
            position += range.length
        } while position < text.length
        context.closePDF()
    }
}
