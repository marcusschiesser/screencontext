import CoreGraphics
import Foundation

public struct OutputProfile: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let videoBitRate: Int
    public let frameRate: Int
    public let audioBitRate: Int

    public init(width: Int, height: Int, videoBitRate: Int, frameRate: Int = 30, audioBitRate: Int = 160_000) {
        self.width = width
        self.height = height
        self.videoBitRate = videoBitRate
        self.frameRate = frameRate
        self.audioBitRate = audioBitRate
    }

    public static func make(for source: CaptureSource) -> OutputProfile {
        make(pixelWidth: source.pixelWidth, pixelHeight: source.pixelHeight)
    }

    public static func make(for screen: ScreenSource) -> OutputProfile {
        make(pixelWidth: screen.pixelWidth, pixelHeight: screen.pixelHeight)
    }

    static func make(pixelWidth: Int, pixelHeight: Int) -> OutputProfile {
        let sourceSize = CGSize(width: pixelWidth, height: pixelHeight)
        let scale = min(1, min(3840 / sourceSize.width, 2160 / sourceSize.height))
        let width = even(Int((sourceSize.width * scale).rounded(.down)))
        let height = even(Int((sourceSize.height * scale).rounded(.down)))
        let isAtLeastFullHD = width >= 1920 && height >= 1080
        return OutputProfile(
            width: max(2, width),
            height: max(2, height),
            videoBitRate: isAtLeastFullHD ? 6_000_000 : 4_500_000
        )
    }

    private static func even(_ value: Int) -> Int {
        value - value % 2
    }
}
