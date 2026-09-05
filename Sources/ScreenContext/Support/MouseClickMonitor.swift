@preconcurrency import AppKit

@MainActor
final class MouseClickMonitor {
    private let onClick: @MainActor () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onClick: @escaping @MainActor () -> Void) {
        self.onClick = onClick
    }

    func setActive(_ isActive: Bool) {
        if isActive {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let eventMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
            [weak self] _ in
            Task { @MainActor in
                self?.onClick()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            self?.onClick()
            return event
        }
    }
}
