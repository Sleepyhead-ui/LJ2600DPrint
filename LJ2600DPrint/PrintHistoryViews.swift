import SwiftUI

struct PrintHistoryView: View {
    @ObservedObject var store: PrintHistoryStore
    let isPrinting: Bool
    let openEntry: (PrintHistoryEntry) -> Void
    let reprintEntry: (PrintHistoryEntry) -> Void
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !store.entries.isEmpty {
                Section {
                    ForEach(store.entries) { entry in
                        NavigationLink {
                            PrintHistoryDetailView(
                                entry: entry,
                                documentURL: store.documentURL(for: entry),
                                isPrinting: isPrinting,
                                openAction: { openEntry(entry) },
                                reprintAction: { reprintEntry(entry) }
                            )
                        } label: {
                            historyRow(entry)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("最多保留 20 条、共 250 MB · 当前 \(historySizeText)")
                }
            }
        }
        .overlay {
            if store.entries.isEmpty && store.errorMessage == nil {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("还没有打印记录")
                        .font(.headline)
                    Text("成功发送的任务会保留在这里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("最近打印")
        .toolbar {
            if !store.entries.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清空打印记录")
                }
            }
        }
        .confirmationDialog(
            "清空全部打印记录？",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空记录", role: .destructive) { store.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存的文档副本也会一并删除，此操作无法撤销。")
        }
    }

    private func historyRow(_ entry: PrintHistoryEntry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: documentIcon(entry.displayName))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(entry.printedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(entry.settingsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(entry.printedPages) 页")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func documentIcon(_ name: String) -> String {
        name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo"
    }

    private var historySizeText: String {
        ByteCountFormatter.string(fromByteCount: store.totalSize, countStyle: .file)
    }
}

private struct PrintHistoryDetailView: View {
    let entry: PrintHistoryEntry
    let documentURL: URL
    let isPrinting: Bool
    let openAction: () -> Void
    let reprintAction: () -> Void

    var body: some View {
        List {
            Section {
                PagePaperView(
                    url: documentURL,
                    pageNumber: previewPage,
                    orientation: entry.settings.orientation,
                    scaling: entry.settings.scaling,
                    contentMode: entry.settings.contentMode,
                    lightness: entry.settings.lightness,
                    imageAdjustments: entry.settings.imageAdjustments
                )
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("任务") {
                LabeledContent("打印时间", value: entry.printedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("页码", value: entry.settings.pageRangeText.isEmpty ? "全部" : entry.settings.pageRangeText)
                LabeledContent("打印页数", value: "\(entry.printedPages) 页")
                LabeledContent("份数", value: "\(entry.settings.copies) 份")
                LabeledContent("纸张", value: entry.settings.duplex ? "双面 · 长边" : "单面")
            }

            Section("版式与画质") {
                LabeledContent("方向", value: entry.settings.orientation.title)
                LabeledContent("缩放", value: entry.settings.scaling.title)
                LabeledContent("画质", value: "\(entry.settings.quality.title) · \(entry.settings.resolution) dpi")
                LabeledContent("内容", value: "\(entry.settings.contentMode.title) · \(entry.settings.lightness.title)")
                if entry.settings.imageAdjustments != .none {
                    LabeledContent("图片调整", value: entry.settings.imageAdjustments.summary)
                }
            }

            Section("文件") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称").font(.subheadline).foregroundStyle(.secondary)
                    Text(entry.displayName)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("大小", value: fileSizeText)
            }
        }
        .navigationTitle("打印记录")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button(action: reprintAction) {
                    Label("再次打印", systemImage: "printer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(isPrinting)

                Button(action: openAction) {
                    Label("打开并调整", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isPrinting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var previewPage: Int {
        entry.settings.pageIndices?.first ?? 1
    }

    private var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file)
    }
}
