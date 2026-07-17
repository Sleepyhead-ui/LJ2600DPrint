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
    static func render(url: URL, resolution: Int) throws -> [RasterPage] {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let document = CGPDFDocument(url as CFURL) {
            var pages: [RasterPage] = []
            for index in 1...document.numberOfPages {
                guard let page = document.page(at: index) else { continue }
                pages.append(try renderPDFPage(page, resolution: resolution))
            }
            if !pages.isEmpty { return pages }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RenderError.unsupportedDocument
        }
        return [try renderImage(image, resolution: resolution)]
    }

    private static func renderPDFPage(_ page: CGPDFPage, resolution: Int) throws -> RasterPage {
        let box = page.getBoxRect(.mediaBox)
        let target = pageSize(resolution: resolution)
        let pageAspect = box.width / max(box.height, 1)
        let targetAspect = target.width / target.height
        let drawRect: CGRect
        if pageAspect > targetAspect {
            let h = target.width / pageAspect
            drawRect = CGRect(x: 0, y: (target.height - h) / 2, width: target.width, height: h)
        } else {
            let w = target.height * pageAspect
            drawRect = CGRect(x: (target.width - w) / 2, y: 0, width: w, height: target.height)
        }

        return try makeBitmap(width: Int(target.width), height: Int(target.height)) { context in
            context.saveGState()
            context.translateBy(x: drawRect.minX, y: target.height - drawRect.minY)
            context.scaleBy(x: drawRect.width / box.width, y: -drawRect.height / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
        }
    }

    private static func renderImage(_ image: CGImage, resolution: Int) throws -> RasterPage {
        let target = pageSize(resolution: resolution)
        let imageAspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let targetAspect = target.width / target.height
        let drawRect: CGRect
        if imageAspect > targetAspect {
            let h = target.width / imageAspect
            drawRect = CGRect(x: 0, y: (target.height - h) / 2, width: target.width, height: h)
        } else {
            let w = target.height * imageAspect
            drawRect = CGRect(x: (target.width - w) / 2, y: 0, width: w, height: target.height)
        }

        return try makeBitmap(width: Int(target.width), height: Int(target.height)) { context in
            context.draw(image, in: drawRect)
        }
    }

    private static func makeBitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> RasterPage {
        let packedBytesPerRow = (width + 7) / 8
        let grayBytesPerRow = ((width + 63) / 64) * 64
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: grayBytesPerRow,
            space: colorSpace,
            bitmapInfo: 0
        ) else {
            throw RenderError.bitmapCreationFailed
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        draw(context)
        guard let raw = context.data else { throw RenderError.bitmapCreationFailed }

        // iOS does not reliably create 1-bit grayscale bitmap contexts. Render
        // into an aligned 8-bit grayscale context, then threshold and pack it
        // manually. In the printer raster, 1 means black and 0 means white.
        let source = raw.assumingMemoryBound(to: UInt8.self)
        var bitmap = Data(repeating: 0, count: packedBytesPerRow * height)
        bitmap.withUnsafeMutableBytes { destinationRaw in
            let destination = destinationRaw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let sourceRow = y * grayBytesPerRow
                let destinationRow = y * packedBytesPerRow
                for x in 0..<width where source[sourceRow + x] < 160 {
                    destination[destinationRow + x / 8] |= UInt8(0x80 >> (x & 7))
                }
            }
        }
        return RasterPage(width: width, height: height, bytesPerRow: packedBytesPerRow, data: bitmap)
    }

    private static func pageSize(resolution: Int) -> CGSize {
        CGSize(
            width: CGFloat((210 * resolution * 10 + 127) / 254),
            height: CGFloat((297 * resolution * 10 + 127) / 254)
        )
    }

    enum RenderError: LocalizedError {
        case unsupportedDocument
        case bitmapCreationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedDocument: return "无法读取 PDF 或图片"
            case .bitmapCreationFailed: return "无法创建打印点阵"
            }
        }
    }
}
