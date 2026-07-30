import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gateway") private var gateway = "192.168.1.1"
    @AppStorage("queue") private var queue = "LJ2600D"
    @AppStorage("gatewayMAC") private var gatewayMAC = ""
    @AppStorage("copies") private var copies = 1
    @AppStorage("duplex") private var duplex = false
    @AppStorage("pageRange") private var pageRange = ""
    @AppStorage("orientation") private var orientationRaw = PrintOrientationOption.automatic.rawValue
    @AppStorage("scaling") private var scalingRaw = PrintScalingOption.fit.rawValue
    @AppStorage("quality") private var qualityRaw = PrintQualityOption.standard.rawValue

    @State private var selectedURL: URL?
    @State private var pageCount = 0
    @State private var showingImporter = false
    @State private var showingServiceRecovery = false
    @State private var showingOfflineAlert = false
    @State private var showingHistory = false
    @State private var isCheckingService = false
    @State private var isLoadingHistory = false
    @StateObject private var printJob = PrintJobController()
    @StateObject private var history = PrintHistoryStore()
    @State private var contentMode = PrintContentMode.text
    @State private var lightness = PrintLightnessOption.normal
    @State private var imageAdjustments = ImagePrintAdjustments.none

    var body: some View {
        NavigationStack {
            Group {
                if let selectedURL {
                    DocumentWorkspace(
                        url: selectedURL,
                        pageCount: pageCount,
                        previewPages: previewPages,
                        status: printJob.status,
                        isPrinting: printJob.isRunning,
                        jobProgress: printJob.progress,
                        duplex: duplex,
                        orientation: orientation,
                        scaling: scaling,
                        quality: quality,
                        contentMode: contentMode,
                        lightness: lightness,
                        imageAdjustments: imageAdjustments,
                        replaceAction: { showingImporter = true },
                        printAction: preparePrinting,
                        cancelAction: printJob.cancel,
                        settings: {
                            PrintSettingsOverview(
                                documentURL: selectedURL,
                                pageRange: $pageRange,
                                orientation: orientationBinding,
                                scaling: scalingBinding,
                                quality: qualityBinding,
                                copies: $copies,
                                duplex: $duplex,
                                contentMode: $contentMode,
                                lightness: $lightness,
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
                                contentMode: contentMode,
                                lightness: lightness,
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("最近打印")

                    NavigationLink {
                        NetworkSettingsView(
                            gateway: $gateway,
                            queue: $queue,
                            gatewayMAC: $gatewayMAC
                        )
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
                    case .failure(let error): printJob.setStatus("导入失败：\(error.localizedDescription)")
                    }
                }
            }
            .sheet(isPresented: $showingServiceRecovery) {
                NavigationStack {
                    NetworkSettingsView(
                        gateway: $gateway,
                        queue: $queue,
                        gatewayMAC: $gatewayMAC
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showingServiceRecovery = false }
                        }
                    }
                }
                .tint(Color(red: 0.08, green: 0.42, blue: 0.92))
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    PrintHistoryView(
                        store: history,
                        isPrinting: printJob.isRunning || isLoadingHistory,
                        openEntry: { useHistory($0, reprint: false) },
                        reprintEntry: { useHistory($0, reprint: true) }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { showingHistory = false }
                        }
                    }
                }
                .tint(Color(red: 0.08, green: 0.42, blue: 0.92))
            }
            .alert("打印服务未响应", isPresented: $showingOfflineAlert) {
                Button("取消", role: .cancel) {}
                Button("打开恢复") { showingServiceRecovery = true }
            } message: {
                Text("光猫的 515 端口当前无法连接。可以先检查并恢复服务，再重新打印。")
            }
            .onOpenURL { incomingURL in
                do { select(try DocumentImporter.copyToTemporary(incomingURL)) }
                catch { printJob.setStatus("导入失败：\(error.localizedDescription)") }
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
        guard !printJob.isRunning else {
            printJob.setStatus("请先取消当前打印任务")
            return
        }
        if let oldURL = selectedURL, oldURL != url { try? FileManager.default.removeItem(at: oldURL) }
        selectedURL = url
        pageCount = DocumentRenderer.pageCount(url: url)
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        contentMode = isImage ? .photo : .text
        lightness = isImage ? .light : .normal
        imageAdjustments = .none
        printJob.documentSelected()
    }

    private func startPrinting() {
        guard let selectedURL else { return }
        do {
            let selectedPages = try selectedPagesForPrinting()
            let request = PrintJobRequest(
                documentURL: selectedURL,
                resolution: quality.dpi,
                jobName: selectedURL.deletingPathExtension().lastPathComponent,
                copies: copies,
                duplex: duplex,
                pageIndices: selectedPages,
                totalPages: selectedPages?.count ?? pageCount,
                orientation: orientation,
                scaling: scaling,
                contentMode: contentMode,
                lightness: lightness,
                imageAdjustments: imageAdjustments,
                gateway: gateway,
                queue: queue
            )
            printJob.start(request) { request, printedPages in
                await history.record(request, printedPages: printedPages)
            }
        } catch {
            printJob.setStatus("失败：\(error.localizedDescription)")
        }
    }

    private func preparePrinting() {
        guard !isCheckingService, !printJob.isRunning else { return }
        isCheckingService = true
        printJob.setStatus("正在检查打印服务…")
        Task {
            let online = await GatewayRecoveryClient.isPortOpen(
                host: gateway.trimmingCharacters(in: .whitespacesAndNewlines),
                port: 515
            )
            isCheckingService = false
            if online {
                startPrinting()
            } else {
                printJob.setStatus("打印服务未响应")
                showingOfflineAlert = true
            }
        }
    }

    private func useHistory(_ entry: PrintHistoryEntry, reprint: Bool) {
        guard !printJob.isRunning, !isLoadingHistory else { return }
        isLoadingHistory = true
        Task {
            do {
                let url = try await history.makeTemporaryCopy(for: entry)
                select(url)
                copies = min(20, max(1, entry.settings.copies))
                duplex = entry.settings.duplex
                pageRange = entry.settings.pageRangeText
                orientationRaw = entry.settings.orientation.rawValue
                scalingRaw = entry.settings.scaling.rawValue
                qualityRaw = entry.settings.quality.rawValue
                contentMode = entry.settings.contentMode
                lightness = entry.settings.lightness
                imageAdjustments = entry.settings.imageAdjustments
                isLoadingHistory = false
                showingHistory = false
                if reprint {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    preparePrinting()
                }
            } catch {
                isLoadingHistory = false
                printJob.setStatus("无法打开打印记录：\(error.localizedDescription)")
                showingHistory = false
            }
        }
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
    let jobProgress: PrintJobProgress?
    let duplex: Bool
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let quality: PrintQualityOption
    let contentMode: PrintContentMode
    let lightness: PrintLightnessOption
    let imageAdjustments: ImagePrintAdjustments
    let replaceAction: () -> Void
    let printAction: () -> Void
    let cancelAction: () -> Void
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
                    contentMode: contentMode,
                    lightness: lightness,
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
                    .disabled(isPrinting)
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
            VStack(spacing: 9) {
                if let jobProgress {
                    HStack {
                        Text(jobProgress.label)
                        Spacer()
                        Text("\(Int((jobProgress.fraction * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    ProgressView(value: jobProgress.fraction)
                        .progressViewStyle(.linear)
                }

                Button(action: isPrinting ? cancelAction : printAction) {
                    HStack(spacing: 10) {
                        Image(systemName: isPrinting ? "stop.fill" : "printer.fill")
                        Text(isPrinting ? "取消任务" : "打印 \(previewPages.count) 页")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(isPrinting ? .red : Color.accentColor)
                .disabled(!isPrinting && previewPages.isEmpty)
            }
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
