import AppKit
import SwiftUI

/// The message field: a text view that grows to 8 lines, sends on Return (Shift/Option+Return is a new line),
/// takes pasted pictures and files as attachments, and leaves dropped files to the window (no path pasted as text).
struct MessageEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder = "Message"
    let submit: () -> Void
    let attachFiles: ([URL]) -> Void
    let attachImage: (NSImage) -> Void

    static let maxLines = 8

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 7)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.placeholder = placeholder
        // Nothing is dropped into the text itself: a dragged file would turn into its path.
        // The window takes the drop and attaches it.
        textView.unregisterDraggedTypes()

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        // Files dragged over the field go to the window's drop zone.
        scroll.unregisterDraggedTypes()
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? EditorTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.onSubmit = submit
        textView.onFiles = attachFiles
        textView.onImage = attachImage
        context.coordinator.measure(textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageEditor

        init(parent: MessageEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? EditorTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
            measure(textView)
        }

        func measure(_ textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let lineHeight = layout.defaultLineHeight(for: textView.font ?? .preferredFont(forTextStyle: .body))
            let used = max(layout.usedRect(for: container).height, lineHeight)
            let inset = textView.textContainerInset.height * 2
            let height = min(used, lineHeight * CGFloat(MessageEditor.maxLines)) + inset
            if abs(parent.height - height) > 0.5 {
                let binding = parent.$height
                Task { @MainActor in binding.wrappedValue = height }
            }
        }
    }
}

final class EditorTextView: NSTextView {
    var placeholder = ""
    var onSubmit: () -> Void = {}
    var onFiles: ([URL]) -> Void = { _ in }
    var onImage: (NSImage) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !hasMarkedText() {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit()
            }
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘V: copied files and pictures (a screenshot has no file) become attachments; text is pasted as text.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onFiles(urls)
            return
        }
        let hasText = pasteboard.availableType(from: [.string]) != nil
        if !hasText, pasteboard.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
                                                     NSPasteboard.PasteboardType("public.heic")]) != nil,
           let image = NSImage(pasteboard: pasteboard) {
            onImage(image)
            return
        }
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height))
    }
}
