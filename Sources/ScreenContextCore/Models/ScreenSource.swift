import CoreGraphics
import Foundation

public struct ScreenSource: Codable, Hashable, Identifiable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frame: CGRect
    public let backingScaleFactor: Double
    public let isPrimary: Bool

    public var id: UInt32 { displayID }

    public init(
        displayID: UInt32,
        name: String,
        pixelWidth: Int,
        pixelHeight: Int,
        frame: CGRect,
        backingScaleFactor: Double,
        isPrimary: Bool
    ) {
        self.displayID = displayID
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frame = frame
        self.backingScaleFactor = backingScaleFactor
        self.isPrimary = isPrimary
    }
}

public struct CaptureDeviceOption: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
