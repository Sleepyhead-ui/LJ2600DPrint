import SwiftUI
import UIKit

struct DiagnosticsView: View {
    let gateway: String
    let queue: String

    @ObservedObject private var diagnostics = DiagnosticStore.shared
    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?
    @State private var reportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingClearConfirmation = false
    @State private var exportError: String?

    var body: some View {
        List {
            Section {
                if let testResult {
                    diagnosticRow(
                        title: "LPR 端口 515",
                        value: testResult.lprOnline ? "在线" : "无响应",
                        systemImage: testResult.lprOnline ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        color: testResult.lprOnline ? .green : .orange
                    )
                    diagnosticRow(
                        title: "维护端口 23",
                        value: testResult.telnetOpen ? "已开启" : "已关闭",
                        systemImage: testResult.telnetOpen ? "lock.open.fill" : "lock.fill",
                        color: testResult.telnetOpen ? .orange : .green
                    )
                    LabeledContent("检测耗时", value: "\(testResult.elapsedMilliseconds) ms")
                } else {
                    Text("尚未运行连接自检")
                        .foregroundStyle(.secondary)
                }

                Button(action: runConnectionTest) {
                    Label("运行连接自检", systemImage: "stethoscope")
                }
                .disabled(isTesting)
            } header: {
                Text("连接自检")
            } footer: {
                Text("只检测端口状态，不会发送打印任务、开启 Telnet 或修改光猫配置。")
            }

            Section {
                Button(action: exportReport) {
                    Label("导出诊断报告", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("清空诊断记录", systemImage: "trash")
                }
                .disabled(diagnostics.events.isEmpty)
            } header: {
                Text("报告")
            } footer: {
                Text("导出前会再次脱敏，不包含文档名称或内容、完整 IP/MAC、Telnet 凭据和密码。记录最多保留 250 条和 30 天。")
            }

            Section("最近事件") {
                if diagnostics.events.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(diagnostics.events.reversed().prefix(50))) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .navigationTitle("诊断与支持")
        .overlay {
            if isTesting {
                ProgressView("正在检测…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let reportURL {
                ActivityView(items: [reportURL])
            }
        }
        .confirmationDialog("清空全部诊断记录？", isPresented: $showingClearConfirmation) {
            Button("清空记录", role: .destructive) { diagnostics.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不会影响打印历史和打印设置。")
        }
        .alert("无法导出报告", isPresented: exportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportError ?? "未知错误")
        }
    }

    private var exportAlert: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func runConnectionTest() {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil
        diagnostics.record(category: .network, "开始只读连接自检")
        let host = gateway.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let started = Date()
            async let lprOnline = GatewayRecoveryClient.isPortOpen(host: host, port: 515)
            async let telnetOpen = GatewayRecoveryClient.isPortOpen(host: host, port: 23)
            let (lprResult, telnetResult) = await (lprOnline, telnetOpen)
            let result = ConnectionTestResult(
                lprOnline: lprResult,
                telnetOpen: telnetResult,
                elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1_000)
            )
            testResult = result
            isTesting = false
            diagnostics.record(
                category: .network,
                level: result.lprOnline ? .success : .warning,
                "连接自检完成：LPR 515 \(result.lprOnline ? "在线" : "无响应")，维护端口 23 \(result.telnetOpen ? "已开启" : "已关闭")，耗时 \(result.elapsedMilliseconds) ms"
            )
        }
    }

    private func exportReport() {
        do {
            reportURL = try diagnostics.makeReport(gateway: gateway, queue: queue)
            diagnostics.record(category: .app, level: .success, "已生成脱敏诊断报告")
            showingShareSheet = true
        } catch {
            exportError = error.localizedDescription
            diagnostics.record(
                category: .app,
                level: .error,
                "诊断报告生成失败：\(DiagnosticStore.errorSummary(error))"
            )
        }
    }

    private func diagnosticRow(
        title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func eventRow(_ event: DiagnosticEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: eventIcon(event.level))
                .foregroundStyle(eventColor(event.level))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.category.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(Self.eventDateFormatter.string(from: event.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(event.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func eventIcon(_ level: DiagnosticLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func eventColor(_ level: DiagnosticLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct ConnectionTestResult {
    let lprOnline: Bool
    let telnetOpen: Bool
    let elapsedMilliseconds: Int
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
