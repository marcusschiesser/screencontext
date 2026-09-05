import Foundation
@preconcurrency import ScreenCaptureKit

struct ResolvedScreenCaptureTarget {
    let filter: SCContentFilter
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ScreenCaptureKitContentFilterFactory {
    static func resolve(
        for source: CaptureSource,
        in content: SCShareableContent,
        excludingBundleIdentifier bundleIdentifier: String
    ) throws -> ResolvedScreenCaptureTarget {
        switch source {
        case let .display(screen):
            guard let display = content.displays.first(where: {
                $0.displayID == screen.displayID
            }) else {
                throw PipelineError.selectedSourceUnavailable
            }
            let excludedApplications = content.applications.filter {
                $0.bundleIdentifier == bundleIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            return ResolvedScreenCaptureTarget(
                filter: filter,
                pixelWidth: display.width,
                pixelHeight: display.height
            )

        case let .window(sourceWindow):
            guard let window = content.windows.first(where: {
                $0.windowID == sourceWindow.windowID
                    && $0.owningApplication?.processID == sourceWindow.processIdentifier
                    && $0.owningApplication?.bundleIdentifier
                        == sourceWindow.applicationBundleIdentifier
            }) else {
                throw PipelineError.selectedSourceUnavailable
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let dimensions = pixelDimensions(
                contentRect: filter.contentRect,
                pointPixelScale: CGFloat(filter.pointPixelScale)
            )
            return ResolvedScreenCaptureTarget(
                filter: filter,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
        }
    }

    static func pixelDimensions(
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) -> (width: Int, height: Int) {
        let scale = pointPixelScale.isFinite && pointPixelScale > 0
            ? pointPixelScale
            : 1
        return (
            width: max(2, Int((contentRect.width * scale).rounded())),
            height: max(2, Int((contentRect.height * scale).rounded()))
        )
    }
}
