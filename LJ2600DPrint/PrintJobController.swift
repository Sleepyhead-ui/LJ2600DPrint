import Combine
import Foundation

struct PrintJobRequest: Sendable {
    let documentURL: URL
    let resolution: Int
    let jobName: String
    let copies: Int
    let duplex: Bool
    let pageIndices: [Int]?
    let totalPages: Int
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let contentMode: PrintContentMode
    let lightness: PrintLightnessOption
    let imageAdjustments: ImagePrintAdjustments
    let gateway: String
    let queue: String
}

struct PrintJobProgress: Equatable, Sendable {
    enum Phase: Sendable {
        case generating
        case sending
    }

    let phase: Phase
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var label: String {
        switch phase {
        case .generating: return "正在生成 \(completed)/\(total) 页"
        case .sending: return "正在发送 \(Int((fraction * 100).rounded()))%"
        }
    }
}

@MainActor
final class PrintJobController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "选择一份文档开始"
    @Published private(set) var progress: PrintJobProgress?

    private var task: Task<Void, Never>?
    private var currentID: UUID?

    func documentSelected() {
        guard !isRunning else { return }
        status = "文档已就绪"
    }

    func setStatus(_ value: String) {
        status = value
    }

    func start(_ request: PrintJobRequest) {
        guard !isRunning, request.totalPages > 0 else { return }
        let id = UUID()
        currentID = id
        isRunning = true
        status = "正在后台生成打印任务…"
        progress = PrintJobProgress(phase: .generating, completed: 0, total: request.totalPages)
        task = Task { [weak self] in
            await self?.run(request, id: id)
        }
    }

    func cancel() {
        guard isRunning else { return }
        status = "正在取消任务…"
        task?.cancel()
    }

    private func run(_ request: PrintJobRequest, id: UUID) async {
        let spoolURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lj2600d-\(id.uuidString).prn")
        defer {
            try? FileManager.default.removeItem(at: spoolURL)
            if currentID == id {
                isRunning = false
                progress = nil
                currentID = nil
                task = nil
            }
        }

        do {
            let encodeProgress: BrLaserEncoder.ProgressHandler = { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.updateProgress(
                        PrintJobProgress(phase: .generating, completed: completed, total: total),
                        id: id
                    )
                }
            }
            let encodingTask = Task.detached(priority: .userInitiated) {
                try BrLaserEncoder.encodeToFile(
                    documentURL: request.documentURL,
                    resolution: request.resolution,
                    jobName: request.jobName,
                    copies: request.copies,
                    duplex: request.duplex,
                    pageIndices: request.pageIndices,
                    orientation: request.orientation,
                    scaling: request.scaling,
                    contentMode: request.contentMode,
                    lightness: request.lightness,
                    imageAdjustments: request.imageAdjustments,
                    outputURL: spoolURL,
                    progress: encodeProgress
                )
            }
            let info = try await withTaskCancellationHandler {
                try await encodingTask.value
            } onCancel: {
                encodingTask.cancel()
            }

            try Task.checkCancellation()
            let size = ByteCountFormatter.string(fromByteCount: Int64(info.bytes), countStyle: .file)
            status = "正在发送 \(info.pages) 页（\(size)）…"
            progress = PrintJobProgress(phase: .sending, completed: 0, total: info.bytes)

            let sendProgress: LPRClient.ProgressHandler = { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.updateProgress(
                        PrintJobProgress(phase: .sending, completed: completed, total: total),
                        id: id
                    )
                }
            }
            try await LPRClient(host: request.gateway, port: 515, queue: request.queue)
                .print(fileURL: spoolURL, jobName: request.documentURL.lastPathComponent, progress: sendProgress)
            try Task.checkCancellation()
            status = "成功：\(info.pages) 页任务已发送"
        } catch {
            if Task.isCancelled || error is CancellationError {
                status = "任务已取消"
            } else {
                status = "失败：\(error.localizedDescription)"
            }
        }
    }

    private func updateProgress(_ value: PrintJobProgress, id: UUID) {
        guard isRunning, currentID == id else { return }
        progress = value
    }
}
