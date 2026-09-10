import CoreGraphics
import Foundation

public enum WebcamMask: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case rectangle
    case rounded
    case square
    case circle

    public var id: String { rawValue }
}

public struct WebcamSize: Codable, Equatable, Sendable {
    public static let minimumPercentage = 15.0

    public let percentage: Double

    public init(percentage: Double) {
        let finitePercentage = percentage.isFinite ? percentage : 25
        self.percentage = max(finitePercentage, Self.minimumPercentage)
    }

    public var fraction: CGFloat { CGFloat(percentage / 100) }

    public static let small = WebcamSize(percentage: 15)
    public static let medium = WebcamSize(percentage: 25)
    public static let large = WebcamSize(percentage: 35)
    public static let extraLarge = WebcamSize(percentage: 50)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(percentage: try container.decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(percentage)
    }
}

public struct NormalizedWebcamPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0.84, y: Double = 0.80) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    public static let defaultPosition = NormalizedWebcamPosition()
}

public struct WebcamLayout: Codable, Equatable, Sendable {
    public var mask: WebcamMask
    public var size: WebcamSize
    public var position: NormalizedWebcamPosition

    public init(
        mask: WebcamMask = .rounded,
        size: WebcamSize = .medium,
        position: NormalizedWebcamPosition = .defaultPosition
    ) {
        self.mask = mask
        self.size = size
        self.position = position
    }

    public static let defaultLayout = WebcamLayout()
}

public struct WebcamPlacement: Equatable, Sendable {
    /// A top-left-origin rectangle in the supplied canvas.
    public let frame: CGRect
    public let cornerRadius: CGFloat

    public init(frame: CGRect, cornerRadius: CGFloat) {
        self.frame = frame
        self.cornerRadius = cornerRadius
    }
}

public enum WebcamLayoutEngine {
    /// The largest size that preserves the mask's aspect ratio inside the canvas.
    public static func maximumSize(
        canvasSize: CGSize,
        cameraSize: CGSize,
        mask: WebcamMask
    ) -> WebcamSize {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .small }
        let camera = cameraSize.width > 0 && cameraSize.height > 0
            ? cameraSize
            : CGSize(width: 16, height: 9)
        let longestSide = max(camera.width, camera.height)
        let isSquare = mask == .circle || mask == .square
        let width = isSquare ? min(camera.width, camera.height) : camera.width
        let height = isSquare ? width : camera.height
        let scale = min(canvasSize.width / width, canvasSize.height / height)
        let referenceDimension = sqrt(canvasSize.width * canvasSize.height)
        return WebcamSize(percentage: Double(longestSide * scale / referenceDimension * 100))
    }

    public static func placement(
        canvasSize: CGSize,
        cameraSize: CGSize,
        layout: WebcamLayout
    ) -> WebcamPlacement {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return WebcamPlacement(frame: .zero, cornerRadius: 0)
        }

        let safeCameraSize = cameraSize.width > 0 && cameraSize.height > 0
            ? cameraSize
            : CGSize(width: 16, height: 9)
        let referenceDimension = sqrt(canvasSize.width * canvasSize.height)
        let fittingSize = maximumSize(canvasSize: canvasSize, cameraSize: cameraSize, mask: layout.mask)
        let maximumDimension = referenceDimension * min(layout.size.fraction, fittingSize.fraction)
        let scale = min(
            maximumDimension / safeCameraSize.width,
            maximumDimension / safeCameraSize.height
        )
        var width = max(1, safeCameraSize.width * scale)
        var height = max(1, safeCameraSize.height * scale)

        if layout.mask == .circle || layout.mask == .square {
            let side = min(width, height)
            width = side
            height = side
        }

        let requestedX = CGFloat(layout.position.x) * canvasSize.width - width / 2
        let requestedY = CGFloat(layout.position.y) * canvasSize.height - height / 2
        let x = min(max(requestedX, 0), max(0, canvasSize.width - width))
        let y = min(max(requestedY, 0), max(0, canvasSize.height - height))
        let frame = CGRect(x: x, y: y, width: width, height: height)

        let radius: CGFloat
        switch layout.mask {
        case .rectangle, .square:
            radius = 0
        case .rounded:
            radius = min(24, max(12, min(width, height) * 0.12))
        case .circle:
            radius = min(width, height) / 2
        }
        return WebcamPlacement(frame: frame, cornerRadius: radius)
    }

    public static func normalizedPosition(
        forTopLeftOrigin center: CGPoint,
        canvasSize: CGSize
    ) -> NormalizedWebcamPosition {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return .defaultPosition
        }
        return NormalizedWebcamPosition(
            x: center.x / canvasSize.width,
            y: center.y / canvasSize.height
        )
    }
}
