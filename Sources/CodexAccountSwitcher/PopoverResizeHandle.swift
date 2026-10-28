import AppKit
import SwiftUI

enum PopoverSizing {
    static let minimumHeight: CGFloat = 220

    static func constrainedHeight(_ height: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), max(1, maximum))
    }

    @MainActor
    static func maximumHeight(for window: NSWindow? = nil) -> CGFloat {
        guard let screen = window?.screen ?? NSScreen.main else { return 900 }
        let top = min(window?.frame.maxY ?? screen.visibleFrame.maxY, screen.visibleFrame.maxY)
        let chrome = window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 0
        return max(1, top - screen.visibleFrame.minY - chrome - 8)
    }
}

/// Uses screen coordinates so moving the popover's bottom edge cannot change the drag delta.
struct PopoverResizeHandle: NSViewRepresentable {
    let help: String
    let onResize: (CGFloat, CGFloat) -> Void
    let onReset: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView() }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.toolTip = help
        view.setAccessibilityLabel(help)
        view.onResize = onResize
        view.onReset = onReset
    }
}

final class ResizeHandleView: NSView {
    var onResize: ((CGFloat, CGFloat) -> Void)?
    var onReset: (() -> Void)?
    private var dragOrigin: (y: CGFloat, height: CGFloat)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 16, y: bounds.midY - 2,
                                       width: 32, height: 4), xRadius: 2, yRadius: 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            dragOrigin = nil
            onReset?()
        } else {
            dragOrigin = (pointerY(for: event), window.contentLayoutRect.height)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        resize(to: dragOrigin.height + pointerY(for: event) - dragOrigin.y)
    }

    override func mouseUp(with event: NSEvent) { dragOrigin = nil }

    private func pointerY(for event: NSEvent) -> CGFloat {
        // Quartz stores the position when the event was generated. Converting a queued
        // window-relative event after a resize would use the window's newer origin.
        event.cgEvent?.location.y ?? -(window?.convertPoint(toScreen: event.locationInWindow).y ?? 0)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: adjustHeight(by: 40) // Down arrow grows the popover.
        case 126: adjustHeight(by: -40)
        default: super.keyDown(with: event)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityValue() -> Any? { window?.contentLayoutRect.height }
    override func accessibilityPerformIncrement() -> Bool { adjustHeight(by: 40); return true }
    override func accessibilityPerformDecrement() -> Bool { adjustHeight(by: -40); return true }

    private func adjustHeight(by delta: CGFloat) {
        guard let window else { return }
        resize(to: window.contentLayoutRect.height + delta)
    }

    private func resize(to height: CGFloat) {
        let maximum = PopoverSizing.maximumHeight(for: window)
        onResize?(PopoverSizing.constrainedHeight(height, maximum: maximum), maximum)
    }
}
