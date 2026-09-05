@preconcurrency import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public actor ScreenCaptureKitSourceCatalog: CaptureSourceCatalog {
    private struct ScreenMetadata: Sendable {
        let displayID: UInt32
        let name: String
        let frame: CGRect
        let scale: Double
    }

    private let bundleIdentifier: String

    public init(bundleIdentifier: String = "de.marcusschiesser.contextcast") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func requestAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    public func sources() async throws -> [CaptureSource] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let screenMetadata = await MainActor.run {
            NSScreen.screens.compactMap { screen -> ScreenMetadata? in
                guard let value = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else {
                    return nil
                }
                return ScreenMetadata(
                    displayID: value.uint32Value,
                    name: screen.localizedName,
                    frame: screen.frame,
                    scale: screen.backingScaleFactor
                )
            }
        }
        let primaryDisplayID = CGMainDisplayID()
        let primaryDisplayMaxY = screenMetadata.first {
            $0.displayID == primaryDisplayID
        }?.frame.maxY ?? 0

        let displays = content.displays.map { display in
            let screen = screenMetadata.first { $0.displayID == display.displayID }
            let scale = screen?.scale ?? 1
            let fallbackFrame = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(display.width) / scale,
                height: CGFloat(display.height) / scale
            )
            return ScreenSource(
                displayID: display.displayID,
                name: screen?.name ?? "Display \(display.displayID)",
                pixelWidth: display.width,
                pixelHeight: display.height,
                frame: screen?.frame ?? fallbackFrame,
                backingScaleFactor: scale,
                isPrimary: display.displayID == primaryDisplayID
            )
        }
        .sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let windows = content.windows.compactMap { window -> WindowSource? in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= 160,
                  window.frame.height >= 90,
                  let application = window.owningApplication,
                  application.bundleIdentifier != bundleIdentifier else {
                return nil
            }

            let appKitFrame = Self.appKitFrame(
                fromScreenCaptureFrame: window.frame,
                primaryDisplayMaxY: primaryDisplayMaxY
            )
            let scale = screenMetadata
                .max {
                    $0.frame.intersection(appKitFrame).area
                        < $1.frame.intersection(appKitFrame).area
                }?
                .scale ?? 1
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WindowSource(
                windowID: window.windowID,
                title: title,
                applicationName: application.applicationName,
                applicationBundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processID,
                pixelWidth: max(2, Int((window.frame.width * scale).rounded())),
                pixelHeight: max(2, Int((window.frame.height * scale).rounded())),
                frame: appKitFrame,
                backingScaleFactor: scale
            )
        }
        .sorted {
            let applicationOrder = $0.applicationName.localizedStandardCompare($1.applicationName)
            if applicationOrder != .orderedSame { return applicationOrder == .orderedAscending }
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.windowID < $1.windowID
        }

        return displays.map(CaptureSource.display) + windows.map(CaptureSource.window)
    }

    public static func appKitFrame(
        fromScreenCaptureFrame frame: CGRect,
        primaryDisplayMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryDisplayMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
