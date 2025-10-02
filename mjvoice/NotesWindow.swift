import AppKit
import SwiftUI

final class NotesWindow: NSWindow {
    private let textView = NSTextView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered,
                   defer: false)
        title = "mjvoice Notes"
        center()

        let scrollView = NSScrollView(frame: contentView!.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        textView.frame = scrollView.bounds
        textView.autoresizingMask = [.width, .height]
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isEditable = true
        textView.string = ""

        scrollView.documentView = textView
        contentView?.addSubview(scrollView)
    }

    func append(text: String) {
        DispatchQueue.main.async {
            self.textView.string += text + "\n"
            self.textView.scrollToEndOfDocument(nil)
        }
    }

    func clear() {
        textView.string = ""
    }
}
