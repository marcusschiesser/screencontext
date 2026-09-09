import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindowAttached: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessView {
        WindowAccessView(onWindowAttached: onWindowAttached)
    }

    func updateNSView(_ nsView: WindowAccessView, context: Context) {
        nsView.onWindowAttached = onWindowAttached
    }

    final class WindowAccessView: NSView {
        var onWindowAttached: @MainActor (NSWindow) -> Void

        init(onWindowAttached: @escaping @MainActor (NSWindow) -> Void) {
            self.onWindowAttached = onWindowAttached
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowAttached(window)
            }
        }
    }
}
