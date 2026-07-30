import PDFKit
import SwiftUI
import UIKit
import ImageIO

struct PagePaperView: View {
    let url: URL
    let pageNumber: Int
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    var contentMode: PrintContentMode = .text
    var lightness: PrintLightnessOption = .normal
    var imageAdjustments: ImagePrintAdjustments = .none
    var compact = false

    @State private var image: UIImage?

    var body: some View {
        Color.white
            .aspectRatio(paperAspect, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let image {
                        let margin = previewMargin(for: geometry.size)
                        previewImage(image)
                            .padding(.horizontal, margin.width)
                            .padding(.vertical, margin.height)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 8, style: .continuous))
            .shadow(color: .black.opacity(compact ? 0.10 : 0.16), radius: compact ? 3 : 10, y: compact ? 1 : 5)
            .task(id: "\(url.path)-\(pageNumber)-\(compact)-\(contentMode.rawValue)-\(lightness.rawValue)-\(imageAdjustments.processingKey)") {
                let size = compact ? CGSize(width: 180, height: 255) : CGSize(width: 900, height: 1278)
                image = nil
                image = await Task.detached(priority: .userInitiated) {
                    PreviewImageLoader.load(
                        url: url,
                        pageNumber: pageNumber,
                        size: size,
                        contentMode: contentMode,
                        lightness: lightness,
                        imageAdjustments: imageAdjustments
                    )
                }.value
            }
    }

    private var paperIsLandscape: Bool {
        orientation == .landscape || (orientation == .automatic && (image?.size.width ?? 0) > (image?.size.height ?? 1))
    }

    private var paperAspect: CGFloat {
        paperIsLandscape
            ? CGFloat(6814) / CGFloat(4800)
            : CGFloat(4800) / CGFloat(6814)
    }

    private func previewMargin(for size: CGSize) -> CGSize {
        let millimeters = CGFloat(max(0, imageAdjustments.marginMillimeters))
        let paperWidth: CGFloat = paperIsLandscape ? 297 : 210
        let paperHeight: CGFloat = paperIsLandscape ? 210 : 297
        return CGSize(
            width: min(size.width / 2, size.width * millimeters / paperWidth),
            height: min(size.height / 2, size.height * millimeters / paperHeight)
        )
    }

    private func previewImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: scaling == .fill ? .fill : .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

struct ImposedPaperView: View {
    let url: URL
    let pages: [Int]
    let pagesPerSheet: PagesPerSheetOption
    let drawPageBorder: Bool
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    var contentMode: PrintContentMode = .text
    var lightness: PrintLightnessOption = .normal
    var imageAdjustments: ImagePrintAdjustments = .none
    var compact = false

    var body: some View {
        if pagesPerSheet == .one {
            PagePaperView(
                url: url,
                pageNumber: pages.first ?? 1,
                orientation: orientation,
                scaling: scaling,
                contentMode: contentMode,
                lightness: lightness,
                imageAdjustments: imageAdjustments,
                compact: compact
            )
        } else {
            Color.white
                .aspectRatio(paperAspect, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        let layout = cellLayout(in: geometry.size)
                        ForEach(0..<pagesPerSheet.rawValue, id: \.self) { index in
                            NUpPreviewCell(
                                url: url,
                                pageNumber: index < pages.count ? pages[index] : nil,
                                scaling: scaling == .actual ? .fit : scaling,
                                contentMode: contentMode,
                                lightness: lightness,
                                imageAdjustments: imageAdjustments,
                                drawBorder: drawPageBorder,
                                compact: compact
                            )
                            .frame(width: layout.cellSize.width, height: layout.cellSize.height)
                            .position(layout.positions[index])
                        }
                    }
                    .padding(compact ? 3 : 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 8, style: .continuous))
                .shadow(color: .black.opacity(compact ? 0.10 : 0.16), radius: compact ? 3 : 10, y: compact ? 1 : 5)
        }
    }

    private var paperIsLandscape: Bool {
        switch orientation {
        case .portrait: return false
        case .landscape: return true
        case .automatic: return pagesPerSheet == .two
        }
    }

    private var paperAspect: CGFloat {
        paperIsLandscape
            ? CGFloat(6814) / CGFloat(4800)
            : CGFloat(4800) / CGFloat(6814)
    }

    private func cellLayout(in size: CGSize) -> (cellSize: CGSize, positions: [CGPoint]) {
        let columns: Int
        let rows: Int
        if pagesPerSheet == .two {
            columns = paperIsLandscape ? 2 : 1
            rows = paperIsLandscape ? 1 : 2
        } else {
            columns = 2
            rows = 2
        }
        let gap: CGFloat = compact ? 2 : 6
        let width = max(1, (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let height = max(1, (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let positions = (0..<pagesPerSheet.rawValue).map { index in
            let row = index / columns
            let column = index % columns
            return CGPoint(
                x: CGFloat(column) * (width + gap) + width / 2,
                y: CGFloat(row) * (height + gap) + height / 2
            )
        }
        return (CGSize(width: width, height: height), positions)
    }
}

private struct NUpPreviewCell: View {
    let url: URL
    let pageNumber: Int?
    let scaling: PrintScalingOption
    let contentMode: PrintContentMode
    let lightness: PrintLightnessOption
    let imageAdjustments: ImagePrintAdjustments
    let drawBorder: Bool
    let compact: Bool

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                if let pageNumber, let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: scaling == .fill ? .fill : .fit)
                        .padding(previewPadding(for: geometry.size))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .overlay {
                if drawBorder && pageNumber != nil {
                    Rectangle()
                        .stroke(Color.primary.opacity(0.65), lineWidth: compact ? 0.5 : 1)
                }
            }
        }
        .task(id: taskID) {
            guard let pageNumber else {
                image = nil
                return
            }
            image = await Task.detached(priority: .userInitiated) {
                PreviewImageLoader.load(
                    url: url,
                    pageNumber: pageNumber,
                    size: compact ? CGSize(width: 120, height: 170) : CGSize(width: 600, height: 850),
                    contentMode: contentMode,
                    lightness: lightness,
                    imageAdjustments: imageAdjustments
                )
            }.value
        }
    }

    private var taskID: String {
        "\(url.path)-\(pageNumber ?? 0)-\(compact)-\(contentMode.rawValue)-\(lightness.rawValue)-\(imageAdjustments.processingKey)"
    }

    private func previewPadding(for size: CGSize) -> EdgeInsets {
        let millimeters = CGFloat(max(0, imageAdjustments.marginMillimeters))
        return EdgeInsets(
            top: min(size.height / 2, size.height * millimeters / 297),
            leading: min(size.width / 2, size.width * millimeters / 210),
            bottom: min(size.height / 2, size.height * millimeters / 297),
            trailing: min(size.width / 2, size.width * millimeters / 210)
        )
    }
}

struct PrintPreviewView: View {
    let url: URL
    let pages: [Int]
    let duplex: Bool
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let contentMode: PrintContentMode
    let lightness: PrintLightnessOption
    let imageAdjustments: ImagePrintAdjustments
    let pagesPerSheet: PagesPerSheetOption
    let drawPageBorder: Bool

    @State private var selectedSheetIndex = 0
    @State private var mode = PreviewMode.page

    init(
        url: URL,
        pages: [Int],
        duplex: Bool,
        orientation: PrintOrientationOption,
        scaling: PrintScalingOption,
        contentMode: PrintContentMode = .text,
        lightness: PrintLightnessOption = .normal,
        imageAdjustments: ImagePrintAdjustments = .none,
        pagesPerSheet: PagesPerSheetOption = .one,
        drawPageBorder: Bool = false
    ) {
        self.url = url
        self.pages = pages
        self.duplex = duplex
        self.orientation = orientation
        self.scaling = scaling
        self.contentMode = contentMode
        self.lightness = lightness
        self.imageAdjustments = imageAdjustments
        self.pagesPerSheet = pagesPerSheet
        self.drawPageBorder = drawPageBorder
    }

    var body: some View {
        VStack(spacing: 0) {
            if duplex {
                Picker("预览方式", selection: $mode) {
                    Text(pagesPerSheet == .one ? "页面" : "纸面").tag(PreviewMode.page)
                    Text("双面纸张").tag(PreviewMode.sheet)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            if mode == .sheet, duplex {
                sheetPreview
            } else {
                sidePreview
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("打印预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sidePreview: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                ImposedPaperView(
                    url: url,
                    pages: selectedSheetPages,
                    pagesPerSheet: pagesPerSheet,
                    drawPageBorder: drawPageBorder,
                    orientation: orientation,
                    scaling: scaling,
                    contentMode: contentMode,
                    lightness: lightness,
                    imageAdjustments: imageAdjustments
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(160, geometry.size.height - 165))
                .padding(.horizontal, 34)
                .padding(.top, 12)

                Text(selectedSheetDescription)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(sheetGroups.indices, id: \.self) { index in
                            Button { withAnimation(.easeOut(duration: 0.18)) { selectedSheetIndex = index } } label: {
                                VStack(spacing: 5) {
                                    ImposedPaperView(
                                        url: url,
                                        pages: sheetGroups[index],
                                        pagesPerSheet: pagesPerSheet,
                                        drawPageBorder: drawPageBorder,
                                        orientation: orientation,
                                        scaling: scaling,
                                        contentMode: contentMode,
                                        lightness: lightness,
                                        imageAdjustments: imageAdjustments,
                                        compact: true
                                    )
                                    .frame(width: 54)
                                    Text("\(index + 1)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(selectedSheetIndex == index ? Color.accentColor : .secondary)
                                }
                                .padding(5)
                                .background(selectedSheetIndex == index ? Color.accentColor.opacity(0.10) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .frame(height: 104)
            }
        }
    }

    private var sheetPreview: some View {
        TabView {
            ForEach(Array(duplexPairs.enumerated()), id: \.offset) { index, pair in
                VStack(spacing: 18) {
                    Text("第 \(index + 1) 张纸")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 18) {
                        sheetSide(title: "正面", pages: pair.front)
                        sheetSide(title: "背面", pages: pair.back)
                    }
                    .padding(.horizontal, 22)
                    Text("长边翻页")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    private func sheetSide(title: String, pages: [Int]?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if let pages {
                ImposedPaperView(
                    url: url,
                    pages: pages,
                    pagesPerSheet: pagesPerSheet,
                    drawPageBorder: drawPageBorder,
                    orientation: orientation,
                    scaling: scaling,
                    contentMode: contentMode,
                    lightness: lightness,
                    imageAdjustments: imageAdjustments
                )
            } else {
                ZStack {
                    Color.white
                    Text("空白").font(.caption).foregroundStyle(.tertiary)
                }
                .aspectRatio(blankPaperAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            Text(pages.map(pageDescription) ?? "无内容")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sheetGroups: [[Int]] {
        stride(from: 0, to: pages.count, by: pagesPerSheet.rawValue).map { index in
            Array(pages[index..<min(index + pagesPerSheet.rawValue, pages.count)])
        }
    }

    private var selectedSheetPages: [Int] {
        guard !sheetGroups.isEmpty else { return [] }
        return sheetGroups[min(selectedSheetIndex, sheetGroups.count - 1)]
    }

    private var selectedSheetDescription: String {
        "第 \(min(selectedSheetIndex + 1, max(sheetGroups.count, 1))) 面 · \(pageDescription(selectedSheetPages))"
    }

    private var duplexPairs: [(front: [Int], back: [Int]?)] {
        stride(from: 0, to: sheetGroups.count, by: 2).map { index in
            (sheetGroups[index], index + 1 < sheetGroups.count ? sheetGroups[index + 1] : nil)
        }
    }

    private var blankPaperAspect: CGFloat {
        let landscape = orientation == .landscape || (orientation == .automatic && pagesPerSheet == .two)
        return landscape ? CGFloat(6814) / CGFloat(4800) : CGFloat(4800) / CGFloat(6814)
    }

    private func pageDescription(_ pages: [Int]) -> String {
        guard let first = pages.first else { return "无内容" }
        if pages.count == 1 { return "文档第 \(first) 页" }
        return "文档第 \(pages.map(String.init).joined(separator: "、")) 页"
    }

    private enum PreviewMode: String, CaseIterable, Identifiable {
        case page
        case sheet
        var id: String { rawValue }
    }
}

enum PreviewImageLoader {
    static func load(
        url: URL,
        pageNumber: Int,
        size: CGSize,
        contentMode: PrintContentMode = .text,
        lightness: PrintLightnessOption = .normal,
        imageAdjustments: ImagePrintAdjustments = .none
    ) -> UIImage? {
        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: pageNumber - 1) {
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            guard let image = thumbnail.cgImage,
                  let toned = ImageAdjustmentProcessor.applyPreviewTone(
                    contentMode: contentMode,
                    lightness: lightness,
                    to: image
                  ) else { return thumbnail }
            return UIImage(cgImage: toned)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxPixelSize = Int((max(size.width, size.height) * 2).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard let adjusted = ImageAdjustmentProcessor.apply(imageAdjustments, to: thumbnail) else {
            return nil
        }
        guard let toned = ImageAdjustmentProcessor.applyPreviewTone(
            contentMode: contentMode,
            lightness: lightness,
            to: adjusted
        ) else { return UIImage(cgImage: adjusted) }
        return UIImage(cgImage: toned)
    }
}
