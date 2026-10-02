import AppKit
import SwiftUI

/// A multi-line text box (task notes, quick capture's subtasks): a plain AppKit text view that
/// grows with its text. SwiftUI's TextEditor doesn't reliably take clicks in Nextlet's layout.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = 90
    var maxHeight: CGFloat = 320
    /// Bump to put the cursor in the box.
    var focusRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.string = text
        textView.placeholder = placeholder
        textView.font = FontBook.sansNSFont(fontSize)
        textView.textColor = NSColor(Palette.ink2)
        textView.insertionPointColor = NSColor(Palette.indigo)
        textView.placeholderColor = NSColor(Palette.faint)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(placeholder)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.focusRequest = focusRequest
        if focusRequest > 0 { focusSoon(textView) }
        return scrollView
    }

    private func focusSoon(_ textView: NSTextView) {
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        // Never replace the text while it is being typed, or the cursor would jump.
        if textView.string != text, scrollView.window?.firstResponder !== textView {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.placeholder = placeholder
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            focusSoon(textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let textView = scrollView.documentView as? NSTextView,
              let container = textView.textContainer, let layout = textView.layoutManager
        else { return nil }
        let inset = textView.textContainerInset
        container.containerSize = NSSize(width: max(0, width - inset.width * 2), height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height + inset.height * 2
        return CGSize(width: width, height: min(max(ceil(used), minHeight), maxHeight))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var focusRequest = 0

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// A text view that shows a placeholder while it is empty.
final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { if placeholder != oldValue { needsDisplay = true } } }
    var placeholderColor = NSColor.placeholderTextColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: placeholderColor]
        (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height), withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
