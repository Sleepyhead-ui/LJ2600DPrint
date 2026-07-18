import CoreGraphics
import Foundation
import ImageIO
import UIKit

struct RasterPage {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: Data
}

enum DocumentRenderer {
    static func render(
        url: URL,
        resolution: Int,
        orientation: PrintOrientationOption = .automatic,
        scaling: PrintScalingOption = .fit,
        contentMode: PrintContentMode = .text,
        lightness: PrintLightnessOption = .normal,
        imageAdjustments: ImagePrintAdjustments = .none
    ) throws -> [RasterPage] {
        var pages: [RasterPage] = []
        _ = try forEachPage(
            url: url,
            resolution: resolution,
            orientation: orientation,
            scaling: scaling,
            contentMode: contentMode,
            lightness: lightness,
            imageAdjustments: imageAdjustments
        ) { pages.append($0) }
        return pages
    }

    static func forEachPage(
        url: URL,
        resolution: Int,
        pageIndices: [Int]? = nil,
        orientation: PrintOrientationOption = .automatic,
        scaling: PrintScalingOption = .fit,
        contentMode: PrintContentMode = .text,
        lightness: PrintLightnessOption = .normal,
        imageAdjustments: ImagePrintAdjustments = .none,
        _ body: (RasterPage) throws -> Void
    ) throws -> Int {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let document = CGPDFDocument(url as CFURL) {
            guard document.numberOfPages > 0 else { throw RenderError.unsupportedDocument }
            let indices = pageIndices ?? Array(1...document.numberOfPages)
            guard !indices.isEmpty else { throw RenderError.noSelectedPages }
            for index in indices {
                guard index > 0, index <= document.numberOfPages,
                      let page = document.page(at: index) else { throw RenderError.noSelectedPages }
                try body(renderPDFPage(
                    page,
                    resolution: resolution,
                    orientation: orientation,
                    scaling: scaling,
                    contentMode: contentMode,
                    lightness: lightness
                ))
            }
            return indices.count
        }

        let image = try loadImage(url: url, resolution: resolution)
        guard let adjustedImage = ImageAdjustmentProcessor.apply(imageAdjustments, to: image) else {
            throw RenderError.unsupportedDocument
        }
        if let pageIndices, !pageIndices.contains(1) { throw RenderError.noSelectedPages }
        try body(renderImage(
            adjustedImage,
            resolution: resolution,
            orientation: orientation,
            scaling: scaling,
            contentMode: contentMode,
            lightness: lightness,
            marginMillimeters: imageAdjustments.marginMillimeters
        ))
        return 1
    }

    static func pageCount(url: URL) -> Int {
        if url.pathExtension.lowercased() == "pdf", let document = CGPDFDocument(url as CFURL) {
            return document.numberOfPages
        }
        return 1
    }

    private static func renderPDFPage(
        _ page: CGPDFPage,
        resolution: Int,
        orientation: PrintOrientationOption,
        scaling: PrintScalingOption,
        contentMode: PrintContentMode,
        lightness: PrintLightnessOption
    ) throws -> RasterPage {
        let box = page.getBoxRect(.mediaBox)
        let target = pageSize(resolution: resolution)
        let rotate = shouldRotate(sourceSize: box.size, orientation: orientation)
        let logicalTarget = rotate
            ? CGSize(width: target.height, height: target.width)
            : target
        let drawRect = placement(
            sourceSize: box.size,
            targetRect: CGRect(origin: .zero, size: logicalTarget),
            scaling: scaling,
            actualScale: CGFloat(resolution) / 72
        )

        return try makeBitmap(
            width: Int(target.width),
            height: Int(target.height),
            contentMode: contentMode,
            lightness: lightness,
            reverseHorizontally: true
        ) { context in
            context.saveGState()
            if rotate {
                context.translateBy(x: 0, y: target.height)
                context.rotate(by: -.pi / 2)
            }
            context.translateBy(x: drawRect.minX, y: logicalTarget.height - drawRect.minY)
            context.scaleBy(x: drawRect.width / box.width, y: -drawRect.height / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
        }
    }

    private static func renderImage(
        _ image: CGImage,
        resolution: Int,
        orientation: PrintOrientationOption,
        scaling: PrintScalingOption,
        contentMode: PrintContentMode,
        lightness: PrintLightnessOption,
        marginMillimeters: Double
    ) throws -> RasterPage {
        let target = pageSize(resolution: resolution)
        let sourceSize = CGSize(width: image.width, height: image.height)
        let rotate = shouldRotate(sourceSize: sourceSize, orientation: orientation)
        let logicalTarget = rotate
            ? CGSize(width: target.height, height: target.width)
            : target
        let margin = CGFloat(max(0, marginMillimeters) / 25.4 * Double(resolution))
        let maximumMargin = max(0, min(logicalTarget.width, logicalTarget.height) / 2 - 1)
        let contentRect = CGRect(origin: .zero, size: logicalTarget)
            .insetBy(dx: min(margin, maximumMargin), dy: min(margin, maximumMargin))
        let drawRect = placement(
            sourceSize: sourceSize,
            targetRect: contentRect,
            scaling: scaling,
            actualScale: 1
        )

        // The CGImage path has the opposite horizontal basis from the verified PDF raster path.
        return try makeBitmap(
            width: Int(target.width),
            height: Int(target.height),
            contentMode: contentMode,
            lightness: lightness,
            reverseHorizontally: false
        ) { context in
            context.saveGState()
            if rotate {
                context.translateBy(x: 0, y: target.height)
                context.rotate(by: -.pi / 2)
            }
            context.draw(image, in: drawRect)
            context.restoreGState()
        }
    }

    private static func shouldRotate(sourceSize: CGSize, orientation: PrintOrientationOption) -> Bool {
        switch orientation {
        case .automatic: return sourceSize.width > sourceSize.height
        case .portrait: return false
        case .landscape: return true
        }
    }

    private static func placement(
        sourceSize: CGSize,
        targetRect: CGRect,
        scaling: PrintScalingOption,
        actualScale: CGFloat
    ) -> CGRect {
        let widthScale = targetRect.width / max(sourceSize.width, 1)
        let heightScale = targetRect.height / max(sourceSize.height, 1)
        let scale: CGFloat
        switch scaling {
        case .fit: scale = min(widthScale, heightScale)
        case .fill: scale = max(widthScale, heightScale)
        case .actual: scale = actualScale
        }
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func loadImage(url: URL, resolution: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw RenderError.unsupportedDocument
        }
        let target = pageSize(resolution: resolution)
        let maxPixelSize = Int(max(target.width, target.height).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw RenderError.unsupportedDocument
        }
        return image
    }

    private static func makeBitmap(
        width: Int,
        height: Int,
        contentMode: PrintContentMode,
        lightness: PrintLightnessOption,
        reverseHorizontally: Bool,
        draw: (CGContext) -> Void
    ) throws -> RasterPage {
        let packedBytesPerRow = (width + 7) / 8
        let grayBytesPerRow = ((width + 63) / 64) * 64
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: grayBytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: 0
        ) else { throw RenderError.bitmapCreationFailed }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        draw(context)
        guard let raw = context.data else { throw RenderError.bitmapCreationFailed }

        let source = raw.assumingMemoryBound(to: UInt8.self)
        let bitmap = packMonochrome(
            source: source,
            width: width,
            height: height,
            sourceBytesPerRow: grayBytesPerRow,
            destinationBytesPerRow: packedBytesPerRow,
            contentMode: contentMode,
            lightness: lightness,
            reverseHorizontally: reverseHorizontally
        )
        return RasterPage(width: width, height: height, bytesPerRow: packedBytesPerRow, data: bitmap)
    }

    private static func packMonochrome(
        source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        sourceBytesPerRow: Int,
        destinationBytesPerRow: Int,
        contentMode: PrintContentMode,
        lightness: PrintLightnessOption,
        reverseHorizontally: Bool
    ) -> Data {
        switch contentMode {
        case .text:
            return packText(
                source: source,
                width: width,
                height: height,
                sourceBytesPerRow: sourceBytesPerRow,
                destinationBytesPerRow: destinationBytesPerRow,
                lightness: lightness,
                reverseHorizontally: reverseHorizontally
            )
        case .graphics:
            return packGraphics(
                source: source,
                width: width,
                height: height,
                sourceBytesPerRow: sourceBytesPerRow,
                destinationBytesPerRow: destinationBytesPerRow,
                lightness: lightness,
                reverseHorizontally: reverseHorizontally
            )
        case .photo:
            return packPhoto(
                source: source,
                width: width,
                height: height,
                sourceBytesPerRow: sourceBytesPerRow,
                destinationBytesPerRow: destinationBytesPerRow,
                lightness: lightness,
                reverseHorizontally: reverseHorizontally
            )
        }
    }

    private static func packText(
        source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        sourceBytesPerRow: Int,
        destinationBytesPerRow: Int,
        lightness: PrintLightnessOption,
        reverseHorizontally: Bool
    ) -> Data {
        let threshold = max(96, min(208, 160 - lightness.rawValue * 20))
        var bitmap = Data(repeating: 0, count: destinationBytesPerRow * height)
        bitmap.withUnsafeMutableBytes { destinationRaw in
            let destination = destinationRaw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let sourceRow = y * sourceBytesPerRow
                let destinationRow = y * destinationBytesPerRow
                for x in 0..<width where Int(source[sourceRow + x]) < threshold {
                    setBlack(
                        destination,
                        row: destinationRow,
                        sourceX: x,
                        width: width,
                        reverseHorizontally: reverseHorizontally
                    )
                }
            }
        }
        return bitmap
    }

    private static func packGraphics(
        source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        sourceBytesPerRow: Int,
        destinationBytesPerRow: Int,
        lightness: PrintLightnessOption,
        reverseHorizontally: Bool
    ) -> Data {
        let toneCurve = makeToneCurve(gamma: 0.80, inkScale: lightness.inkScale)
        var bitmap = Data(repeating: 0, count: destinationBytesPerRow * height)
        bitmap.withUnsafeMutableBytes { destinationRaw in
            let destination = destinationRaw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let sourceRow = y * sourceBytesPerRow
                let destinationRow = y * destinationBytesPerRow
                let matrixRow = (y & 7) * 8
                for x in 0..<width {
                    let gray = toneCurve[Int(source[sourceRow + x])]
                    let threshold = Int(bayer8[matrixRow + (x & 7)]) * 4 + 2
                    if Int(gray) < threshold {
                        setBlack(
                            destination,
                            row: destinationRow,
                            sourceX: x,
                            width: width,
                            reverseHorizontally: reverseHorizontally
                        )
                    }
                }
            }
        }
        return bitmap
    }

    private static func packPhoto(
        source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        sourceBytesPerRow: Int,
        destinationBytesPerRow: Int,
        lightness: PrintLightnessOption,
        reverseHorizontally: Bool
    ) -> Data {
        let toneCurve = makeToneCurve(gamma: 0.55, inkScale: lightness.inkScale)
        var bitmap = Data(repeating: 0, count: destinationBytesPerRow * height)
        var currentError = [Int](repeating: 0, count: width + 2)
        var nextError = [Int](repeating: 0, count: width + 2)
        bitmap.withUnsafeMutableBytes { destinationRaw in
            let destination = destinationRaw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let sourceRow = y * sourceBytesPerRow
                let destinationRow = y * destinationBytesPerRow
                for x in 0..<width {
                    let tone = Int(toneCurve[Int(source[sourceRow + x])])
                    let adjusted = max(0, min(255, tone + currentError[x + 1] / 16))
                    let output = adjusted < 128 ? 0 : 255
                    if output == 0 {
                        setBlack(
                            destination,
                            row: destinationRow,
                            sourceX: x,
                            width: width,
                            reverseHorizontally: reverseHorizontally
                        )
                    }
                    let error = adjusted - output
                    currentError[x + 2] += error * 7
                    nextError[x] += error * 3
                    nextError[x + 1] += error * 5
                    nextError[x + 2] += error
                }
                swap(&currentError, &nextError)
                for index in nextError.indices { nextError[index] = 0 }
            }
        }
        return bitmap
    }

    @inline(__always)
    private static func setBlack(
        _ destination: UnsafeMutableBufferPointer<UInt8>,
        row: Int,
        sourceX: Int,
        width: Int,
        reverseHorizontally: Bool
    ) {
        let printerX = reverseHorizontally ? width - 1 - sourceX : sourceX
        destination[row + printerX / 8] |= UInt8(0x80 >> (printerX & 7))
    }

    private static let bayer8: [UInt8] = [
         0, 48, 12, 60,  3, 51, 15, 63,
        32, 16, 44, 28, 35, 19, 47, 31,
         8, 56,  4, 52, 11, 59,  7, 55,
        40, 24, 36, 20, 43, 27, 39, 23,
         2, 50, 14, 62,  1, 49, 13, 61,
        34, 18, 46, 30, 33, 17, 45, 29,
        10, 58,  6, 54,  9, 57,  5, 53,
        42, 26, 38, 22, 41, 25, 37, 21
    ]

    private static func makeToneCurve(gamma: Double, inkScale: Double) -> [UInt8] {
        (0...255).map { value in
            if value <= 8 { return 0 }
            if value >= 248 { return 255 }
            let normalized = Double(value) / 255
            let curved = pow(normalized, gamma) * 255
            let darkness = (255 - curved) * inkScale
            return UInt8(clamping: Int((255 - darkness).rounded()))
        }
    }

    private static func pageSize(resolution: Int) -> CGSize {
        CGSize(
            width: CGFloat(4800 * resolution / 600),
            height: CGFloat(6814 * resolution / 600)
        )
    }

    enum RenderError: LocalizedError {
        case unsupportedDocument
        case bitmapCreationFailed
        case noSelectedPages

        var errorDescription: String? {
            switch self {
            case .unsupportedDocument: return "无法读取 PDF 或图片"
            case .bitmapCreationFailed: return "无法创建打印点阵"
            case .noSelectedPages: return "没有可打印的页面"
            }
        }
    }
}
