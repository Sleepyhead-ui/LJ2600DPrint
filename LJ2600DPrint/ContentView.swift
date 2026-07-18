import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gateway") private var gateway = "192.168.1.1"
    @AppStorage("queue") private var queue = "LJ2600D"
    @AppStorage("copies") private var copies = 1
    @AppStorage("duplex") private var duplex = false
    @AppStorage("pageRange") private var pageRange = ""
    @AppStorage("orientation") private var orientationRaw = PrintOrientationOption.automatic.rawValue
    @AppStorage("scaling") private var scalingRaw = PrintScalingOption.fit.rawValue
    @AppStorage("quality") private var qualityRaw = PrintQualityOption.standard.rawValue

    @State private var selectedURL: URL?
    @State private var pageCount = 0
    @State private var showingImporter = false
    @State private var isPrinting = false
    @State private var status = "选择一份文档开始"
    @State private var imageAdjustments = ImagePrintAdjustments.none

    var body: some View {
        NavigationStack {
            Group {
                if let selectedURL {
                    DocumentWorkspace(
                        url: selectedURL,
                        pageCount: pageCount,
                        previewPages: previewPages,
                        status: status,
                        isPrinting: isPrinting,
                        duplex: duplex,
                        orientation: orientation,
                        scaling: scaling,
                        quality: quality,
                        imageAdjustments: imageAdjustments,
                        replaceAction: { showingImporter = true },
                        printAction: { Task { await printSelectedDocument() } },
                        settings: {
                            PrintSettingsOverview(
                                documentURL: selectedURL,
                                pageRange: $pageRange,
                                orientation: orientationBinding,
                                scaling: scalingBinding,
                                quality: qualityBinding,
                                copies: $copies,
                                duplex: $duplex,
                                imageAdjustments: $imageAdjustments,
                                pageCount: pageCount
                            )
                        },
                        preview: {
                            PrintPreviewView(
                                url: selectedURL,
                                pages: previewPages,
                                duplex: duplex,
                                orientation: orientation,
                                scaling: scaling,
                                imageAdjustments: imageAdjustments
                            )
                        }
                    )
                } else {
                    EmptyWorkspace { showingImporter = true }
                }
            }
            .navigationTitle("LJ2600D Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        NetworkSettingsView(gateway: $gateway, queue: $queue)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("打印服务设置")
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
                    switch result {
                    case .success(let url): select(url)
                    case .failure(let error): status = "导入失败：\(error.localizedDescription)"
                    }
                }
            }
            .onOpenURL { incomingURL in
                do { select(try DocumentImporter.copyToTemporary(incomingURL)) }
                catch { status = "导入失败：\(error.localizedDescription)" }
            }
        }
        .tint(Color(red: 0.08, green: 0.42, blue: 0.92))
    }

    private var orientation: PrintOrientationOption {
        PrintOrientationOption(rawValue: orientationRaw) ?? .automatic
    }

    private var scaling: PrintScalingOption {
        PrintScalingOption(rawValue: scalingRaw) ?? .fit
    }

    private var quality: PrintQualityOption {
        PrintQualityOption(rawValue: qualityRaw) ?? .standard
    }

    private var orientationBinding: Binding<PrintOrientationOption> {
        Binding(get: { orientation }, set: { orientationRaw = $0.rawValue })
    }

    private var scalingBinding: Binding<PrintScalingOption> {
        Binding(get: { scaling }, set: { scalingRaw = $0.rawValue })
    }

    private var qualityBinding: Binding<PrintQualityOption> {
        Binding(get: { quality }, set: { qualityRaw = $0.rawValue })
    }

    private var previewPages: [Int] {
        guard pageCount > 0 else { return [] }
        if !pageRange.trimmingCharacters(in: .whitespaces).isEmpty,
           let parsed = try? PageRangeParser.parse(pageRange, pageCount: pageCount) {
            return parsed
        }
        return Array(1...pageCount)
    }

    private func selectedPagesForPrinting() throws -> [Int]? {
        pageRange.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : try PageRangeParser.parse(pageRange, pageCount: pageCount)
    }

    private func select(_ url: URL) {
        if let oldURL = selectedURL, oldURL != url { try? FileManager.default.removeItem(at: oldURL) }
        selectedURL = url
        pageCount = DocumentRenderer.pageCount(url: url)
        imageAdjustments = .none
        status = "文档已就绪"
    }

    private func printSelectedDocument() async {
        guard let selectedURL else { return }
        await MainActor.run { isPrinting = true; status = "正在逐页生成打印任务…" }
        let spoolURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lj2600d-\(UUID().uuidString).prn")
        defer { try? FileManager.default.removeItem(at: spoolURL) }

        do {
            let selectedPages = try selectedPagesForPrinting()
            let jobName = selectedURL.deletingPathExtension().lastPathComponent
            let info = try BrLaserEncoder.encodeToFile(
                documentURL: selectedURL,
                resolution: quality.dpi,
                jobName: jobName,
                copies: copies,
                duplex: duplex,
                pageIndices: selectedPages,
                orientation: orientation,
                scaling: scaling,
                imageAdjustments: imageAdjustments,
                outputURL: spoolURL
            )
            let size = ByteCountFormatter.string(fromByteCount: Int64(info.bytes), countStyle: .file)
            await MainActor.run { status = "正在发送 \(info.pages) 页（\(size)）…" }
            try await LPRClient(host: gateway, port: 515, queue: queue)
                .print(fileURL: spoolURL, jobName: selectedURL.lastPathComponent)
            await MainActor.run { status = "成功：\(info.pages) 页任务已发送" }
        } catch {
            await MainActor.run { status = "失败：\(error.localizedDescription)" }
        }
        await MainActor.run { isPrinting = false }
    }
}

private struct EmptyWorkspace: View {
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .frame(width: 150, height: 212)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
                Image(systemName: "doc.text")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                Text("准备打印").font(.title2.bold())
                Text("选择 PDF 或图片，预览每一页后再发送。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: importAction) {
                Label("选择文档", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct DocumentWorkspace<Settings: View, Preview: View>: View {
    let url: URL
    let pageCount: Int
    let previewPages: [Int]
    let status: String
    let isPrinting: Bool
    let duplex: Bool
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let quality: PrintQualityOption
    let imageAdjustments: ImagePrintAdjustments
    let replaceAction: () -> Void
    let printAction: () -> Void
    let settings: () -> Settings
    let preview: () -> Preview

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PagePaperView(
                    url: url,
                    pageNumber: previewPages.first ?? 1,
                    orientation: orientation,
                    scaling: scaling,
                    imageAdjustments: imageAdjustments
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .padding(.horizontal, 54)
                .padding(.top, 18)

                VStack(spacing: 7) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text("\(pageCount) 页 · A4 · \(quality.dpi) dpi")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    NavigationLink(destination: preview()) {
                        workspaceRow("打印预览", icon: "eye", detail: "\(previewPages.count) 页")
                    }
                    Divider().padding(.leading, 48)
                    NavigationLink(destination: settings()) {
                        workspaceRow("打印设置", icon: "slider.horizontal.3", detail: summary)
                    }
                    Divider().padding(.leading, 48)
                    Button(action: replaceAction) {
                        workspaceRow("更换文档", icon: "arrow.triangle.2.circlepath", detail: "")
                    }
                }
                .padding(.horizontal, 20)

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(status.hasPrefix("失败") ? Color.red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button(action: printAction) {
                HStack(spacing: 10) {
                    if isPrinting { ProgressView().tint(.white) }
                    Image(systemName: isPrinting ? "hourglass" : "printer.fill")
                    Text(isPrinting ? "正在处理" : "打印 \(previewPages.count) 页")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(isPrinting || previewPages.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var displayName: String {
        DocumentImporter.displayName(for: url)
    }

    private var summary: String {
        "\(duplex ? "双面" : "单面") · \(orientation.title) · \(quality.title)"
    }

    private func workspaceRow(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

#Preview { ContentView() }
