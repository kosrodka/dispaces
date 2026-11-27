import AppKit
import SpacesCore

/// Help › User manual: the manual (`UserManual`, built into the app) in a
/// read-only, selectable text window. Nothing is loaded from disk or the network.
@MainActor
final class ManualWindowController: NSObject, NSWindowDelegate {
    private var window: AppWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.present()
    }

    func windowWillClose(_ notification: Notification) {
        AppWindow.closing(window)
    }

    private func makeWindow() -> AppWindow {
        let window = AppWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        window.title = "Dispaces User Manual"
        window.minSize = NSSize(width: 380, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let scroll = NSTextView.scrollableTextView()
        scroll.autohidesScrollers = true
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 20, height: 18)
            text.textStorage?.setAttributedString(Self.render(UserManual.blocks()))
        }
        window.contentView = scroll
        window.center()
        window.setFrameAutosaveName("UserManual")
        return window
    }

    /// Draws the manual's blocks as styled text.
    static func render(_ blocks: [UserManual.Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let bold = NSFont.boldSystemFont(ofSize: 13)

        func style(before: CGFloat, after: CGFloat, indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineSpacing = 2
            style.firstLineHeadIndent = 0
            style.headIndent = indent
            if indent > 0 { style.tabStops = [NSTextTab(textAlignment: .left, location: indent)] }
            return style
        }
        func append(_ text: String, _ font: NSFont, _ paragraph: NSParagraphStyle) {
            out.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ]))
        }
        func append(_ spans: [UserManual.Span], _ paragraph: NSParagraphStyle) {
            for span in spans { append(span.text, span.bold ? bold : body, paragraph) }
        }

        for block in blocks {
            switch block {
            case .title(let text):
                append(text + "\n", NSFont.boldSystemFont(ofSize: 22), style(before: 0, after: 10))
            case .heading(let text):
                append(text + "\n", NSFont.systemFont(ofSize: 16, weight: .semibold), style(before: 14, after: 6))
            case .bullet(let spans):
                let paragraph = style(before: 0, after: 5, indent: 16)
                append("•\t", body, paragraph)
                append(spans, paragraph)
                append("\n", body, paragraph)
            case .paragraph(let spans):
                let paragraph = style(before: 0, after: 8)
                append(spans, paragraph)
                append("\n", body, paragraph)
            }
        }
        return out
    }
}
