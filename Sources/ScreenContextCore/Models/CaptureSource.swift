import CoreGraphics
import Foundation

public enum CaptureSourceKind: String, Codable, Hashable, Sendable {
    case display
    case window
}

public struct CaptureSourceID: Codable, Hashable, Sendable {
    public let kind: CaptureSourceKind
    public let rawValue: UInt32

    public init(kind: CaptureSourceKind, rawValue: UInt32) {
        self.kind = kind
        self.rawValue = rawValue
    }

    public static func display(_ displayID: UInt32) -> CaptureSourceID {
        CaptureSourceID(kind: .display, rawValue: displayID)
    }

    public static func window(_ windowID: UInt32) -> CaptureSourceID {
        CaptureSourceID(kind: .window, rawValue: windowID)
    }
}

public struct WindowSource: Codable, Hashable, Identifiable, Sendable {
    public let windowID: UInt32
    public let title: String
    public let applicationName: String
    public let applicationBundleIdentifier: String?
    public let processIdentifier: Int32
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frame: CGRect
    public let backingScaleFactor: Double

    public var id: UInt32 { windowID }

    public var displayName: String {
        guard !title.isEmpty, title != applicationName else { return applicationName }
        return "\(applicationName) — \(title)"
    }

    public init(
        windowID: UInt32,
        title: String,
        applicationName: String,
        applicationBundleIdentifier: String?,
        processIdentifier: Int32,
        pixelWidth: Int,
        pixelHeight: Int,
        frame: CGRect,
        backingScaleFactor: Double
    ) {
        self.windowID = windowID
        self.title = title
        self.applicationName = applicationName
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.processIdentifier = processIdentifier
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frame = frame
        self.backingScaleFactor = backingScaleFactor
    }

    public func matchesRuntimeIdentity(of other: WindowSource) -> Bool {
        windowID == other.windowID
            && processIdentifier == other.processIdentifier
            && applicationBundleIdentifier == other.applicationBundleIdentifier
            && title == other.title
    }
}

public enum CaptureSource: Codable, Hashable, Identifiable, Sendable {
    case display(ScreenSource)
    case window(WindowSource)

    public var id: CaptureSourceID {
        switch self {
        case let .display(screen): .display(screen.displayID)
        case let .window(window): .window(window.windowID)
        }
    }

    public var displayName: String {
        switch self {
        case let .display(screen): screen.name
        case let .window(window): window.displayName
        }
    }

    public var pixelWidth: Int {
        switch self {
        case let .display(screen): screen.pixelWidth
        case let .window(window): window.pixelWidth
        }
    }

    public var pixelHeight: Int {
        switch self {
        case let .display(screen): screen.pixelHeight
        case let .window(window): window.pixelHeight
        }
    }

    public var frame: CGRect {
        switch self {
        case let .display(screen): screen.frame
        case let .window(window): window.frame
        }
    }

    public var backingScaleFactor: Double {
        switch self {
        case let .display(screen): screen.backingScaleFactor
        case let .window(window): window.backingScaleFactor
        }
    }
}
