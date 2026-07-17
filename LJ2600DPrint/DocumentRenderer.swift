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
        scaling: PrintScalingOption = .fit
    ) throws -> [RasterPage] {
        var pages: [RasterPage] = []
        _ = try forEachPage(
            url: url,
            resolution: resolution,
            orientation: orientation,
            scaling: scaling
        ) { pages.append($0) }
        return pages
    }

    static func forEachPage(
        url: URL,
        resolution: Int,
        pageIndices: [Int]? = nil,
        orientation: PrintOrientationOption = .automatic,
        scaling: PrintScalingOption = .fit,
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
                    scaling: scaling
                ))
            }
            return indices.count
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RenderError.unsupportedDocument
        }
        if let pageIndices, !pageIndices.contains(1) { throw RenderError.noSelectedPages }
        try body(renderImage(
            image,
            resolution: resolution,
            orientation: orientation,
            scaling: scaling
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
        scaling: PrintScalingOption
    ) throws -> RasterPage {
        let box = page.getBoxRect(.mediaBox)
        let target = pageSize(resolution: resolution)
        let rotate = shouldRotate(sourceSize: box.size, orientation: orientation)
        let logicalTarget = rotate
            ? CGSize(width: target.height, height: target.width)
            : target
        let drawRect = placement(
            sourceSize: box.size,
            targetSize: logicalTarget,
            scaling: scaling,
            actualScale: CGFloat(resolution) / 72
        )

        return try makeBitmap(width: Int(target.width), height: Int(target.height)) { context in
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
        scaling: PrintScalingOption
    ) throws -> RasterPage {
        let target = pageSize(resolution: resolution)
        let sourceSize = CGSize(width: image.width, height: image.height)
        let rotate = shouldRotate(sourceSize: sourceSize, orientation: orientation)
        let logicalTarget = rotate
            ? CGSize(width: target.height, height: target.width)
            : target
        let drawRect = placement(
            sourceSize: sourceSize,
            targetSize: logicalTarget,
            scaling: scaling,
            actualScale: 1
        )

        return try makeBitmap(width: Int(target.width), height: Int(target.height)) { context in
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
        targetSize: CGSize,
        scaling: PrintScalingOption,
        actualScale: CGFloat
    ) -> CGRect {
        let widthScale = targetSize.width / max(sourceSize.width, 1)
        let heightScale = targetSize.height / max(sourceSize.height, 1)
        let scale: CGFloat
        switch scaling {
        case .fit: scale = min(widthScale, heightScale)
        case .fill: scale = max(widthScale, heightScale)
        case .actual: scale = actualScale
        }
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: (targetSize.width - size.width) / 2,
            y: (targetSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func makeBitmap(
        width: Int,
        height: Int,
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
        var bitmap = Data(repeating: 0, count: packedBytesPerRow * height)
        bitmap.withUnsafeMutableBytes { destinationRaw in
            let destination = destinationRaw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let sourceRow = y * grayBytesPerRow
                let destinationRow = y * packedBytesPerRow
                for x in 0..<width where source[sourceRow + x] < 160 {
                    let printerX = width - 1 - x
                    destination[destinationRow + printerX / 8] |= UInt8(0x80 >> (printerX & 7))
                }
            }
        }
        return RasterPage(width: width, height: height, bytesPerRow: packedBytesPerRow, data: bitmap)
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
