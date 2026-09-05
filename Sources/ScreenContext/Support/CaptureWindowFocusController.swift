import AppKit
import ApplicationServices
import ScreenContextCore

@MainActor
enum CaptureWindowFocusController {
    private static var focusTask: Task<Void, Never>?

    static func focus(
        _ source: WindowSource,
        completion: @escaping @MainActor () -> Void
    ) {
        focusTask?.cancel()

        // The HUD is a nonactivating panel. After the first handoff it remains
        // clickable while ScreenContext is inactive, so every selection must first
        // establish a fresh activation before yielding it to the target app.
        NSApp.activate(ignoringOtherApps: true)

        focusTask = Task { @MainActor in
            await Task.yield()
            await waitUntilScreenContextIsActive()
            guard !Task.isCancelled else { return }

            guard let application = NSRunningApplication(
                processIdentifier: source.processIdentifier
            ) else {
                completion()
                return
            }

            application.unhide()
            NSApp.yieldActivation(to: application)
            let activationWasAccepted = application.activate(
                from: .current,
                options: [.activateAllWindows]
            )
            if !activationWasAccepted {
                application.activate(options: [.activateAllWindows])
            }

            await waitUntilActive(application)
            guard !Task.isCancelled else { return }

            if AXIsProcessTrusted() {
                raiseExactWindow(source)
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    private static func waitUntilScreenContextIsActive() async {
        for _ in 0..<25 {
            guard !Task.isCancelled, !NSApp.isActive else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func waitUntilActive(_ application: NSRunningApplication) async {
        for _ in 0..<25 {
            guard !Task.isCancelled, !application.isActive else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func raiseExactWindow(_ source: WindowSource) {
        let applicationElement = AXUIElementCreateApplication(source.processIdentifier)
        guard let windows = attribute(
            kAXWindowsAttribute as CFString,
            from: applicationElement
        ) as? [AXUIElement] else {
            return
        }

        let candidates = windows.compactMap { element -> WindowCandidate? in
            guard let frame = frame(of: element) else { return nil }
            return WindowCandidate(
                element: element,
                title: attribute(kAXTitleAttribute as CFString, from: element) as? String ?? "",
                frame: frame
            )
        }
        guard let candidate = candidates.min(by: {
            $0.score(for: source) < $1.score(for: source)
        }), candidate.isPlausibleMatch(for: source) else {
            return
        }

        _ = AXUIElementPerformAction(candidate.element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            candidate.element
        )
    }

    private static func attribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(
            kAXPositionAttribute as CFString,
            from: element
        ),
              let sizeValue = axValue(
                kAXSizeAttribute as CFString,
                from: element
              ) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              let primaryDisplayMaxY = NSScreen.screens.first(where: {
                guard let number = $0.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else { return false }
                return number.uint32Value == CGMainDisplayID()
              })?.frame.maxY else {
            return nil
        }

        return ScreenCaptureKitSourceCatalog.appKitFrame(
            fromScreenCaptureFrame: CGRect(origin: position, size: size),
            primaryDisplayMaxY: primaryDisplayMaxY
        )
    }

    private static func axValue(
        _ name: CFString,
        from element: AXUIElement
    ) -> AXValue? {
        guard let value = attribute(name, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}

private struct WindowCandidate {
    let element: AXUIElement
    let title: String
    let frame: CGRect

    func score(for source: WindowSource) -> CGFloat {
        geometryDistance(from: source) + (titleMatches(source) ? 0 : 10_000)
    }

    func isPlausibleMatch(for source: WindowSource) -> Bool {
        titleMatches(source) || geometryDistance(from: source) < 200
    }

    private func titleMatches(_ source: WindowSource) -> Bool {
        !source.title.isEmpty && title == source.title
    }

    private func geometryDistance(from source: WindowSource) -> CGFloat {
        abs(frame.minX - source.frame.minX)
            + abs(frame.minY - source.frame.minY)
            + abs(frame.width - source.frame.width)
            + abs(frame.height - source.frame.height)
    }
}
