import Combine
import Foundation
import UIKit

enum DiagnosticCategory: String, Codable, Sendable {
    case app
    case document
    case print
    case network
    case recovery

    var title: String {
        switch self {
        case .app: return "应用"
        case .document: return "文档"
        case .print: return "打印"
        case .network: return "网络"
        case .recovery: return "恢复"
        }
    }
}

enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case success
    case warning
    case error
}

struct DiagnosticEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: DiagnosticCategory
    let level: DiagnosticLevel
    let message: String
}

@MainActor
final class DiagnosticStore: ObservableObject {
    static let shared = DiagnosticStore()

    @Published private(set) var events: [DiagnosticEvent]

    private static let maximumEvents = 250
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    private var saveTask: Task<Void, Never>?
    private var recordedSessionStart = false

    private init() {
        events = Self.loadEvents()
        prune()
    }

    func recordSessionStart() {
        guard !recordedSessionStart else { return }
        recordedSessionStart = true
        record(category: .app, level: .info, "应用会话已启动")
    }

    func record(
        category: DiagnosticCategory,
        level: DiagnosticLevel = .info,
        _ message: String
    ) {
        let sanitized = DiagnosticPrivacy.sanitize(message)
        guard !sanitized.isEmpty else { return }
        events.append(DiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            category: category,
            level: level,
            message: sanitized
        ))
        prune()
        scheduleSave()
    }

    func clear() {
        events.removeAll()
        saveTask?.cancel()
        saveTask = nil
        try? FileManager.default.removeItem(at: Self.eventsURL)
    }

    func makeReport(gateway: String, queue: String) throws -> URL {
        let report = DiagnosticPrivacy.sanitizeReport(reportText(gateway: gateway, queue: queue))
        let stamp = Self.fileDateFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LJ2600D-Diagnostics-\(stamp).txt")
        try Data(report.utf8).write(to: url, options: .atomic)
        return url
    }

    static func errorSummary(_ error: Error) -> String {
        if error is CancellationError { return "CancellationError" }
        if error is LPRError || error is GatewayRecoveryError ||
            error is BrLaserEncoder.EncoderError || error is DocumentRenderer.RenderError {
            return "\(String(describing: type(of: error))): \(DiagnosticPrivacy.sanitize(error.localizedDescription))"
        }
        let nsError = error as NSError
        return "\(String(describing: type(of: error))) [\(nsError.domain):\(nsError.code)]"
    }

    static func redactedHost(_ host: String) -> String {
        DiagnosticPrivacy.redactedHost(host)
    }

    private func reportText(gateway: String, queue: String) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let process = ProcessInfo.processInfo
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(process.physicalMemory),
            countStyle: .memory
        )
        let safeQueue = DiagnosticPrivacy.sanitize(String(queue.prefix(60)))
        let eventLines = events.suffix(200).map { event in
            "\(Self.reportDateFormatter.string(from: event.timestamp)) " +
            "[\(event.level.rawValue.uppercased())] [\(event.category.title)] \(event.message)"
        }

        return ([
            "LJ2600D Print 诊断报告",
            "生成时间：\(Self.reportDateFormatter.string(from: Date()))",
            "",
            "隐私说明：报告不包含文档名称或内容、完整 IP/MAC、Telnet 凭据和密码。",
            "",
            "== 应用与设备 ==",
            "App：\(version) (\(build))",
            "系统：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "设备类别：\(UIDevice.current.model)",
            "内存：\(memory)",
            "低电量模式：\(process.isLowPowerModeEnabled ? "开启" : "关闭")",
            "热状态：\(Self.thermalStateText(process.thermalState))",
            "",
            "== 脱敏配置 ==",
            "打印服务器：\(Self.redactedHost(gateway))",
            "端口：515",
            "LPR 队列：\(safeQueue.isEmpty ? "<未设置>" : safeQueue)",
            "",
            "== 最近事件（最多 200 条） =="
        ] + (eventLines.isEmpty ? ["无诊断事件"] : eventLines)).joined(separator: "\n") + "\n"
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maximumAge)
        events.removeAll { $0.timestamp < cutoff }
        if events.count > Self.maximumEvents {
            events.removeFirst(events.count - Self.maximumEvents)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = events
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            try? Self.persist(snapshot)
        }
    }

    private static func loadEvents() -> [DiagnosticEvent] {
        guard let data = try? Data(contentsOf: eventsURL),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(_ events: [DiagnosticEvent]) throws {
        try FileManager.default.createDirectory(
            at: diagnosticsDirectory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = diagnosticsDirectory
        try? directory.setResourceValues(values)
        let data = try JSONEncoder().encode(events)
        try data.write(to: eventsURL, options: .atomic)
    }

    private static var diagnosticsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static var eventsURL: URL {
        diagnosticsDirectory.appendingPathComponent("events.json")
    }

    private static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "轻微升温"
        case .serious: return "较热"
        case .critical: return "过热"
        @unknown default: return "未知"
        }
    }
}

enum DiagnosticPrivacy {
    static func sanitize(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        result = replace(#"(?i)Fh@[0-9a-f]{6}"#, in: result, with: "<credential>")
        result = replace(#"(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b"#, in: result, with: "<MAC>")
        result = replace(#"(?i)\b[0-9a-f]{12}\b"#, in: result, with: "<MAC>")
        result = replace(#"\b(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}\b"#, in: result, with: "$1.$2.x.x")
        result = replace(#"(?i)(?:file://)?/(?:private/var|var/mobile|var/folders|tmp)/\S+"#, in: result, with: "<local-path>")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > 500 { result = String(result.prefix(500)) + "…" }
        return result
    }

    static func sanitizeReport(_ value: String) -> String {
        value.components(separatedBy: "\n")
            .map(sanitize)
            .joined(separator: "\n")
    }

    static func redactedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<未设置>" }
        let redacted = sanitize(trimmed)
        return redacted == trimmed && !trimmed.contains("x.x") ? "<已配置主机>" : redacted
    }

    private static func replace(_ pattern: String, in value: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
