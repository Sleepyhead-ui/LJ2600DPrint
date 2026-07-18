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
            .task(id: "\(url.path)-\(pageNumber)-\(compact)-\(imageAdjustments.processingKey)") {
                let size = compact ? CGSize(width: 180, height: 255) : CGSize(width: 900, height: 1278)
                image = nil
                image = await Task.detached(priority: .userInitiated) {
                    PreviewImageLoader.load(
                        url: url,
                        pageNumber: pageNumber,
                        size: size,
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
            .grayscale(1)
            .contrast(contentMode.previewContrast)
            .brightness(contentMode.previewBrightness + lightness.previewBrightness)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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

    @State private var selectedPage: Int
    @State private var mode = PreviewMode.page

    init(
        url: URL,
        pages: [Int],
        duplex: Bool,
        orientation: PrintOrientationOption,
        scaling: PrintScalingOption,
        contentMode: PrintContentMode = .text,
        lightness: PrintLightnessOption = .normal,
        imageAdjustments: ImagePrintAdjustments = .none
    ) {
        self.url = url
        self.pages = pages
        self.duplex = duplex
        self.orientation = orientation
        self.scaling = scaling
        self.contentMode = contentMode
        self.lightness = lightness
        self.imageAdjustments = imageAdjustments
        _selectedPage = State(initialValue: pages.first ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if duplex {
                Picker("预览方式", selection: $mode) {
                    ForEach(PreviewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            if mode == .sheet, duplex {
                sheetPreview
            } else {
                pagePreview
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("打印预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pagePreview: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                PagePaperView(
                    url: url,
                    pageNumber: selectedPage,
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

                Text("第 \(selectedPage) 页，共选择 \(pages.count) 页")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(pages, id: \.self) { page in
                            Button { withAnimation(.easeOut(duration: 0.18)) { selectedPage = page } } label: {
                                VStack(spacing: 5) {
                                    PagePaperView(
                                        url: url,
                                        pageNumber: page,
                                        orientation: orientation,
                                        scaling: scaling,
                                        contentMode: contentMode,
                                        lightness: lightness,
                                        imageAdjustments: imageAdjustments,
                                        compact: true
                                    )
                                    .frame(width: 54)
                                    Text("\(page)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(selectedPage == page ? Color.accentColor : .secondary)
                                }
                                .padding(5)
                                .background(selectedPage == page ? Color.accentColor.opacity(0.10) : .clear)
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
            ForEach(Array(sheetPairs.enumerated()), id: \.offset) { index, pair in
                VStack(spacing: 18) {
                    Text("第 \(index + 1) 张纸")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 18) {
                        sheetSide(title: "正面", page: pair.front)
                        sheetSide(title: "背面", page: pair.back)
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

    private func sheetSide(title: String, page: Int?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if let page {
                PagePaperView(
                    url: url,
                    pageNumber: page,
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
                .aspectRatio(CGFloat(4800) / CGFloat(6814), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            Text(page.map { "第 \($0) 页" } ?? "无内容")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sheetPairs: [(front: Int, back: Int?)] {
        stride(from: 0, to: pages.count, by: 2).map { index in
            (pages[index], index + 1 < pages.count ? pages[index + 1] : nil)
        }
    }

    private enum PreviewMode: String, CaseIterable, Identifiable {
        case page
        case sheet
        var id: String { rawValue }
        var title: String { self == .page ? "页面" : "双面纸张" }
    }
}

enum PreviewImageLoader {
    static func load(
        url: URL,
        pageNumber: Int,
        size: CGSize,
        imageAdjustments: ImagePrintAdjustments = .none
    ) -> UIImage? {
        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: pageNumber - 1) {
            return page.thumbnail(of: size, for: .mediaBox)
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
        return UIImage(cgImage: adjusted)
    }
}
