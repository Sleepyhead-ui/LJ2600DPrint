import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum ImageRotationOption: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270

    var id: Int { rawValue }
    var title: String { rawValue == 0 ? "原始" : "\(rawValue)°" }
    var isQuarterTurn: Bool { self == .clockwise90 || self == .clockwise270 }

    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .none: return .up
        case .clockwise90: return .right
        case .clockwise180: return .down
        case .clockwise270: return .left
        }
    }

    func rotatedClockwise() -> Self {
        Self(rawValue: (rawValue + 90) % 360) ?? .none
    }

    func rotatedCounterclockwise() -> Self {
        Self(rawValue: (rawValue + 270) % 360) ?? .none
    }
}

enum ImageCropOption: String, CaseIterable, Identifiable, Sendable {
    case original
    case a4
    case square
    case fourThree

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "原图"
        case .a4: return "A4"
        case .square: return "正方形"
        case .fourThree: return "4:3"
        }
    }

    func aspectRatio(for size: CGSize) -> CGFloat? {
        let landscape = size.width >= size.height
        switch self {
        case .original: return nil
        case .a4: return landscape ? 297 / 210 : 210 / 297
        case .square: return 1
        case .fourThree: return landscape ? 4 / 3 : 3 / 4
        }
    }
}

struct ImagePrintAdjustments: Equatable, Sendable {
    var rotation: ImageRotationOption = .none
    var crop: ImageCropOption = .original
    var marginMillimeters: Double = 0

    static let none = ImagePrintAdjustments()

    var summary: String {
        var parts: [String] = []
        if rotation != .none { parts.append(rotation.title) }
        if crop != .original { parts.append(crop.title) }
        if marginMillimeters > 0 { parts.append("\(Int(marginMillimeters)) mm") }
        return parts.isEmpty ? "未调整" : parts.joined(separator: " · ")
    }

    var processingKey: String {
        "\(rotation.rawValue)-\(crop.rawValue)"
    }
}

enum ImageAdjustmentProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ adjustments: ImagePrintAdjustments, to image: CGImage) -> CGImage? {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let rotatedSize = adjustments.rotation.isQuarterTurn
            ? CGSize(width: sourceSize.height, height: sourceSize.width)
            : sourceSize

        var workingImage = image
        if let rotatedAspect = adjustments.crop.aspectRatio(for: rotatedSize) {
            let sourceAspect = adjustments.rotation.isQuarterTurn ? 1 / rotatedAspect : rotatedAspect
            let cropRect = centeredCropRect(size: sourceSize, aspectRatio: sourceAspect)
            guard let cropped = image.cropping(to: cropRect) else { return nil }
            workingImage = cropped
        }

        guard adjustments.rotation != .none else { return workingImage }
        let oriented = CIImage(cgImage: workingImage).oriented(adjustments.rotation.imageOrientation)
        return context.createCGImage(oriented, from: oriented.extent.integral)
    }

    private static func centeredCropRect(size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let sourceAspect = size.width / max(size.height, 1)
        let cropSize: CGSize
        if sourceAspect > aspectRatio {
            cropSize = CGSize(width: floor(size.height * aspectRatio), height: size.height)
        } else {
            cropSize = CGSize(width: size.width, height: floor(size.width / aspectRatio))
        }
        return CGRect(
            x: floor((size.width - cropSize.width) / 2),
            y: floor((size.height - cropSize.height) / 2),
            width: max(1, cropSize.width),
            height: max(1, cropSize.height)
        )
    }
}
