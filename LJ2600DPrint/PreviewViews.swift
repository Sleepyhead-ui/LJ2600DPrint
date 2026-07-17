import PDFKit
import SwiftUI
import UIKit

struct PagePaperView: View {
    let url: URL
    let pageNumber: Int
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    var compact = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: scaling == .fill ? .fill : .fit)
                    .rotationEffect(orientation == .landscape ? .degrees(90) : .zero)
                    .padding(compact ? 5 : 12)
                    .clipped()
            } else {
                ProgressView()
            }
        }
        .aspectRatio(CGFloat(4800) / CGFloat(6814), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 8, style: .continuous))
        .shadow(color: .black.opacity(compact ? 0.10 : 0.16), radius: compact ? 3 : 10, y: compact ? 1 : 5)
        .task(id: "\(url.path)-\(pageNumber)-\(compact)") {
            let size = compact ? CGSize(width: 180, height: 255) : CGSize(width: 900, height: 1278)
            image = await Task.detached(priority: .userInitiated) {
                PreviewImageLoader.load(url: url, pageNumber: pageNumber, size: size)
            }.value
        }
    }
}

struct PrintPreviewView: View {
    let url: URL
    let pages: [Int]
    let duplex: Bool
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption

    @State private var selectedPage: Int
    @State private var mode = PreviewMode.page

    init(
        url: URL,
        pages: [Int],
        duplex: Bool,
        orientation: PrintOrientationOption,
        scaling: PrintScalingOption
    ) {
        self.url = url
        self.pages = pages
        self.duplex = duplex
        self.orientation = orientation
        self.scaling = scaling
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
        VStack(spacing: 14) {
            PagePaperView(
                url: url,
                pageNumber: selectedPage,
                orientation: orientation,
                scaling: scaling
            )
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
                PagePaperView(url: url, pageNumber: page, orientation: orientation, scaling: scaling)
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
    static func load(url: URL, pageNumber: Int, size: CGSize) -> UIImage? {
        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: pageNumber - 1) {
            return page.thumbnail(of: size, for: .mediaBox)
        }
        return UIImage(contentsOfFile: url.path)
    }
}
