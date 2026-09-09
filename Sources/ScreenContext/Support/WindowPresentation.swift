import AppKit

@MainActor
enum WindowPresentation {
    static func afterMenuDismissal(_ action: @escaping @MainActor () -> Void) {
        // Menu tracking can restore the previous app's focus when it ends.
        // The default run-loop mode runs only after that tracking has finished.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    static func bringToFront(_ window: NSWindow) {
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Activation is asynchronous; order the requested window above other
        // apps immediately, without changing its normal window level.
        window.orderFrontRegardless()
    }
}
