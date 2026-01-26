import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A custom text view that supports pasting and dropping images
/// Reports content height to SwiftUI so the page can scroll instead of internal scrolling
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var placeholder: String = ""
    var onImagePasted: ((Data) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        // Disable internal scrolling - let the page scroll instead
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = ImagePasteTextView()
        textView.delegate = context.coordinator
        textView.onImagePasted = onImagePasted
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        
        // Important: Allow the text view to become first responder
        textView.isFieldEditor = false
        textView.importsGraphics = true  // Allow image paste

        // Enable drag & drop
        textView.registerForDraggedTypes([.png, .tiff, .fileURL, .URL])

        // Configure text container for width tracking
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // Set size constraints
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Set initial text
        textView.string = text

        // Store reference
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        scrollView.documentView = textView
        
        // Calculate initial content height
        DispatchQueue.main.async {
            context.coordinator.updateContentHeight()
        }
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ImagePasteTextView else { return }
        
        // Prevent recursive updates - only update if not currently being edited by user
        let isFirstResponder = textView.window?.firstResponder === textView
        
        // Only update text if it differs AND we're not the first responder
        // This prevents the infinite loop: textDidChange -> binding update -> updateNSView -> textDidChange
        if textView.string != text && !isFirstResponder {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromSwiftUI = false
            
            // Recalculate height after text change from SwiftUI
            DispatchQueue.main.async {
                context.coordinator.updateContentHeight()
            }
        }

        // Update callback (may change between renders)
        textView.onImagePasted = onImagePasted
        
        // Update text color for dark mode
        textView.textColor = NSColor.white
        
        // Update content height when width changes
        DispatchQueue.main.async {
            context.coordinator.updateContentHeight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        weak var textView: ImagePasteTextView?
        weak var scrollView: NSScrollView?
        var isUpdatingFromSwiftUI = false

        init(_ parent: NotesTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            // Prevent recursive updates
            guard !isUpdatingFromSwiftUI else { return }
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update the binding on the main actor to avoid threading issues
            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.updateContentHeight()
            }
        }
        
        func updateContentHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            // Ensure layout is up to date
            layoutManager.ensureLayout(for: textContainer)
            
            // Get the used rect from layout manager
            let usedRect = layoutManager.usedRect(for: textContainer)
            
            // Add some padding for the cursor at the end
            let newHeight = usedRect.height + 20
            
            // Only update if height actually changed (avoid unnecessary SwiftUI updates)
            if abs(parent.contentHeight - newHeight) > 1 {
                parent.contentHeight = newHeight
            }
        }
    }
}

/// Custom NSTextView that intercepts paste and drag operations for images
class ImagePasteTextView: NSTextView {
    var onImagePasted: ((Data) -> Void)?

    // MARK: - First Responder
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        NSLog("[NotesTextView] becomeFirstResponder")
        return super.becomeFirstResponder()
    }
    
    // MARK: - Key handling for Cmd+V
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Cmd+V
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            NSLog("[NotesTextView] Cmd+V detected via performKeyEquivalent")
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    // MARK: - Menu validation
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)) || menuItem.action == #selector(pasteAsPlainText(_:)) {
            // Always allow paste - we handle both text and images
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    // MARK: - Paste handling

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        
        NSLog("[NotesTextView] paste() called, pasteboard types: %@", pasteboard.types?.map { $0.rawValue } ?? [])

        // Check for image types first
        if let imageData = getImageDataFromPasteboard(pasteboard) {
            NSLog("[NotesTextView] Pasting image: %d bytes", imageData.count)
            onImagePasted?(imageData)
            return
        }

        // Fall back to normal paste for text
        NSLog("[NotesTextView] No image found, falling back to text paste")
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for image types first
        if let imageData = getImageDataFromPasteboard(pasteboard) {
            NSLog("[NotesTextView] Pasting image (plain): %d bytes", imageData.count)
            onImagePasted?(imageData)
            return
        }

        // Fall back to normal paste for text
        super.pasteAsPlainText(sender)
    }

    private func getImageDataFromPasteboard(_ pasteboard: NSPasteboard) -> Data? {
        // Try PNG first (most common for screenshots)
        if let data = pasteboard.data(forType: .png) {
            NSLog("[NotesTextView] Found PNG data: %d bytes", data.count)
            return data
        }

        // Try TIFF (also common for screenshots on macOS)
        if let data = pasteboard.data(forType: .tiff) {
            NSLog("[NotesTextView] Found TIFF data: %d bytes", data.count)
            return data
        }

        // Try to get file URL and load image from it
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                   UTType(uti)?.conforms(to: .image) == true,
                   let data = try? Data(contentsOf: url) {
                    NSLog("[NotesTextView] Found image file URL: %@", url.path)
                    return data
                }
            }
        }

        return nil
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageInDrag(sender) {
            NSLog("[NotesTextView] Drag entered with image")
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageInDrag(sender) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        NSLog("[NotesTextView] performDragOperation - types: %@", pasteboard.types?.map { $0.rawValue } ?? [])

        // Try to get image data
        if let imageData = getImageDataFromDrag(pasteboard) {
            NSLog("[NotesTextView] Dropped image: %d bytes", imageData.count)
            onImagePasted?(imageData)
            return true
        }

        // Fall back to default behavior for text
        return super.performDragOperation(sender)
    }

    private func hasImageInDrag(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let types = pasteboard.types ?? []

        return types.contains(.png) ||
               types.contains(.tiff) ||
               types.contains(NSPasteboard.PasteboardType("public.image")) ||
               types.contains(.fileURL)
    }

    private func getImageDataFromDrag(_ pasteboard: NSPasteboard) -> Data? {
        // Try PNG
        if let data = pasteboard.data(forType: .png) {
            NSLog("[NotesTextView] Got PNG from drag")
            return data
        }

        // Try TIFF
        if let data = pasteboard.data(forType: .tiff) {
            NSLog("[NotesTextView] Got TIFF from drag")
            return data
        }

        // Try public.image
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.image")) {
            NSLog("[NotesTextView] Got public.image from drag")
            return data
        }

        // Try file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                NSLog("[NotesTextView] Checking file URL: %@", url.path)
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"].contains(ext) {
                    if let data = try? Data(contentsOf: url) {
                        NSLog("[NotesTextView] Loaded image from file: %d bytes", data.count)
                        return data
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Placeholder support

struct NotesTextViewWithPlaceholder: View {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var placeholder: String
    var isRecording: Bool
    var hasImages: Bool
    var onImagePasted: ((Data) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Actual text view - must be first so it receives all events
            NotesTextView(
                text: $text,
                contentHeight: $contentHeight,
                placeholder: placeholder,
                onImagePasted: onImagePasted
            )
            
            // Placeholder - overlaid on top but doesn't intercept events
            if text.isEmpty && isRecording && !hasImages {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.top, 1)
                    .padding(.leading, 2)
                    .allowsHitTesting(false)  // Critical: don't block clicks
            }
        }
    }
}
