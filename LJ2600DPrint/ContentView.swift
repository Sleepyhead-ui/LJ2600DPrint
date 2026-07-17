import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gateway") private var gateway = "192.168.1.1"
    @AppStorage("queue") private var queue = "LJ2600D"
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
                    HStack {
                        Text("端口")
                        Spacer()
                        Text("515")
                            .foregroundStyle(.secondary)
                    }
                    TextField("LPR 队列", text: $queue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("文档") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label(selectedURL == nil ? "选择 PDF 或图片" : "重新选择文件", systemImage: "doc.badge.plus")
                    }

                    if let selectedURL {
                        Label(selectedURL.lastPathComponent, systemImage: "doc")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Button {
                        Task { await printSelectedDocument() }
                    } label: {
                        if isPrinting {
                            HStack {
                                ProgressView()
                                Text("正在处理…")
                            }
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

                Section {
                    Text("实验版：当前直接使用 Brother/Lenovo HBP 点阵协议和 LPR。若打印机固件与 HL-2240D 协议不完全兼容，需要根据实际打印结果调整编码器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("LJ2600D Print")
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    selectedURL = url
                    status = "已导入文件，可以打印"
                case .failure(let error):
                    status = "导入失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func printSelectedDocument() async {
        guard let selectedURL else { return }
        await MainActor.run {
            isPrinting = true
            status = "正在渲染页面…"
        }

        do {
            let accessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { selectedURL.stopAccessingSecurityScopedResource() }
            }

            let pages = try DocumentRenderer.render(url: selectedURL, resolution: 600)
            await MainActor.run { status = "正在生成打印数据（\(pages.count) 页）…" }
            let payload = try BrLaserEncoder.encode(pages: pages, jobName: selectedURL.deletingPathExtension().lastPathComponent)
            await MainActor.run { status = "正在发送到 \(gateway):515…" }
            try await LPRClient(host: gateway, port: 515, queue: queue).print(data: payload, jobName: selectedURL.lastPathComponent)
            await MainActor.run { status = "成功：打印任务已发送" }
        } catch {
            await MainActor.run { status = "失败：\(error.localizedDescription)" }
        }

        await MainActor.run { isPrinting = false }
    }
}

#Preview {
    ContentView()
}
