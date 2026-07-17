import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gateway") private var gateway = "192.168.1.1"
    @AppStorage("queue") private var queue = "LJ2600D"
    @AppStorage("copies") private var copies = 1
    @AppStorage("duplex") private var duplex = false
    @State private var selectedURL: URL?
    @State private var showingImporter = false
    @State private var isPrinting = false
    @State private var status = "请选择 PDF 或图片"

    var body: some View {
        NavigationStack {
            Form {
                Section("光猫打印服务") {
                    TextField("地址", text: $gateway)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("端口", value: "515")
                    TextField("LPR 队列", text: $queue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("打印设置") {
                    Stepper("份数：\(copies)", value: $copies, in: 1...20)
                    Toggle("双面打印（长边翻页）", isOn: $duplex)
                }

                Section("文档") {
                    Button { showingImporter = true } label: {
                        Label(selectedURL == nil ? "选择 PDF 或图片" : "重新选择文件", systemImage: "doc.badge.plus")
                    }
                    if let selectedURL {
                        Label(displayName(selectedURL), systemImage: "doc")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button {
                        Task { await printSelectedDocument() }
                    } label: {
                        if isPrinting {
                            HStack { ProgressView(); Text("正在处理…") }
                        } else {
                            Label("打印", systemImage: "printer.fill")
                        }
                    }
                    .disabled(selectedURL == nil || isPrinting || gateway.isEmpty || queue.isEmpty)
                }

                Section("状态") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(status.hasPrefix("成功") ? .green : .secondary)
                }
            }
            .navigationTitle("LJ2600D Print")
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
    }

    private func select(_ url: URL) {
        if let oldURL = selectedURL, oldURL != url { try? FileManager.default.removeItem(at: oldURL) }
        selectedURL = url
        status = "已导入文件，可以打印"
    }

    private func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard let separator = name.firstIndex(of: "-") else { return name }
        return String(name[name.index(after: separator)...])
    }

    private func printSelectedDocument() async {
        guard let selectedURL else { return }
        await MainActor.run { isPrinting = true; status = "正在逐页生成打印任务…" }
        let spoolURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lj2600d-\(UUID().uuidString).prn")
        defer { try? FileManager.default.removeItem(at: spoolURL) }

        do {
            let jobName = selectedURL.deletingPathExtension().lastPathComponent
            let info = try BrLaserEncoder.encodeToFile(
                documentURL: selectedURL,
                resolution: 600,
                jobName: jobName,
                copies: copies,
                duplex: duplex,
                outputURL: spoolURL
            )
            let size = ByteCountFormatter.string(fromByteCount: Int64(info.bytes), countStyle: .file)
            await MainActor.run { status = "正在发送 \(info.pages) 页（\(size)）…" }
            try await LPRClient(host: gateway, port: 515, queue: queue)
                .print(fileURL: spoolURL, jobName: selectedURL.lastPathComponent)
            await MainActor.run { status = "成功：\(info.pages) 页打印任务已发送" }
        } catch {
            await MainActor.run { status = "失败：\(error.localizedDescription)" }
        }
        await MainActor.run { isPrinting = false }
    }
}

#Preview { ContentView() }
