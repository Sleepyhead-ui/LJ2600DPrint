import Combine
import Foundation

enum PrintHistoryError: LocalizedError {
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "文档超过 250 MB，未加入最近打印"
        }
    }
}

struct PrintHistorySettings: Codable, Equatable, Sendable {
    let resolution: Int
    let copies: Int
    let duplex: Bool
    let pageIndices: [Int]?
    let orientationRaw: String
    let scalingRaw: String
    let contentModeRaw: String
    let lightnessRaw: Int
    let rotationRaw: Int
    let cropRaw: String
    let marginMillimeters: Double

    init(request: PrintJobRequest) {
        resolution = request.resolution
        copies = request.copies
        duplex = request.duplex
        pageIndices = request.pageIndices
        orientationRaw = request.orientation.rawValue
        scalingRaw = request.scaling.rawValue
        contentModeRaw = request.contentMode.rawValue
        lightnessRaw = request.lightness.rawValue
        rotationRaw = request.imageAdjustments.rotation.rawValue
        cropRaw = request.imageAdjustments.crop.rawValue
        marginMillimeters = request.imageAdjustments.marginMillimeters
    }

    var orientation: PrintOrientationOption {
        PrintOrientationOption(rawValue: orientationRaw) ?? .automatic
    }

    var scaling: PrintScalingOption {
        PrintScalingOption(rawValue: scalingRaw) ?? .fit
    }

    var quality: PrintQualityOption {
        switch resolution {
        case 300: return .economy
        case 1200: return .high
        default: return .standard
        }
    }

    var contentMode: PrintContentMode {
        PrintContentMode(rawValue: contentModeRaw) ?? .text
    }

    var lightness: PrintLightnessOption {
        PrintLightnessOption(rawValue: lightnessRaw) ?? .normal
    }

    var imageAdjustments: ImagePrintAdjustments {
        ImagePrintAdjustments(
            rotation: ImageRotationOption(rawValue: rotationRaw) ?? .none,
            crop: ImageCropOption(rawValue: cropRaw) ?? .original,
            marginMillimeters: marginMillimeters
        )
    }

    var pageRangeText: String {
        guard let pageIndices, !pageIndices.isEmpty else { return "" }
        let pages = Array(Set(pageIndices)).sorted()
        var ranges: [String] = []
        var start = pages[0]
        var previous = pages[0]
        for page in pages.dropFirst() {
            if page == previous + 1 {
                previous = page
            } else {
                ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
                start = page
                previous = page
            }
        }
        ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return ranges.joined(separator: ",")
    }
}

struct PrintHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let printedAt: Date
    let displayName: String
    let storedFileName: String
    let printedPages: Int
    let fileSize: Int64
    let settings: PrintHistorySettings

    var settingsSummary: String {
        "\(settings.duplex ? "双面" : "单面") · \(settings.orientation.title) · \(settings.resolution) dpi"
    }
}

@MainActor
final class PrintHistoryStore: ObservableObject {
    @Published private(set) var entries: [PrintHistoryEntry] = []
    @Published private(set) var errorMessage: String?

    private let repository = PrintHistoryRepository()

    init() {
        Task { [weak self] in
            guard let self else { return }
            do {
                entries = try await repository.load()
            } catch {
                errorMessage = "无法读取打印记录：\(error.localizedDescription)"
            }
        }
    }

    func record(_ request: PrintJobRequest, printedPages: Int) async {
        do {
            entries = try await repository.record(request, printedPages: printedPages)
            errorMessage = nil
        } catch {
            errorMessage = "打印成功，但记录未保存：\(error.localizedDescription)"
        }
    }

    func delete(_ entry: PrintHistoryEntry) {
        Task { [weak self] in
            guard let self else { return }
            do {
                entries = try await repository.delete(ids: [entry.id])
                errorMessage = nil
            } catch {
                errorMessage = "无法删除记录：\(error.localizedDescription)"
            }
        }
    }

    func deleteAll() {
        Task { [weak self] in
            guard let self else { return }
            do {
                entries = try await repository.delete(ids: Set(entries.map(\.id)))
                errorMessage = nil
            } catch {
                errorMessage = "无法清空记录：\(error.localizedDescription)"
            }
        }
    }

    func documentURL(for entry: PrintHistoryEntry) -> URL {
        PrintHistoryRepository.documentsDirectory
            .appendingPathComponent(entry.storedFileName)
    }

    func makeTemporaryCopy(for entry: PrintHistoryEntry) async throws -> URL {
        try await repository.makeTemporaryCopy(for: entry)
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.fileSize }
    }
}

private actor PrintHistoryRepository {
    static let rootDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("PrintHistory", isDirectory: true)

    static let documentsDirectory = rootDirectory.appendingPathComponent("Documents", isDirectory: true)
    private static let indexURL = rootDirectory.appendingPathComponent("history.json")
    private static let maximumCount = 20
    private static let maximumBytes: Int64 = 250 * 1024 * 1024

    private var cachedEntries: [PrintHistoryEntry]?

    func load() throws -> [PrintHistoryEntry] {
        if let cachedEntries { return cachedEntries }
        try prepareDirectories()
        var loaded: [PrintHistoryEntry] = []
        if FileManager.default.fileExists(atPath: Self.indexURL.path) {
            let data = try Data(contentsOf: Self.indexURL)
            loaded = try JSONDecoder().decode([PrintHistoryEntry].self, from: data)
        }
        loaded = loaded
            .filter { FileManager.default.fileExists(atPath: documentURL(for: $0).path) }
            .sorted { $0.printedAt > $1.printedAt }
        try save(loaded)
        try removeOrphanedDocuments(keeping: loaded)
        cachedEntries = loaded
        return loaded
    }

    func record(_ request: PrintJobRequest, printedPages: Int) throws -> [PrintHistoryEntry] {
        var current = try load()
        let id = UUID()
        let displayName = DocumentImporter.displayName(for: request.documentURL)
        let ext = request.documentURL.pathExtension.isEmpty ? "document" : request.documentURL.pathExtension
        let storedFileName = "\(id.uuidString).\(ext.lowercased())"
        let destination = Self.documentsDirectory.appendingPathComponent(storedFileName)

        do {
            try FileManager.default.copyItem(at: request.documentURL, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try? mutableDestination.setResourceValues(values)
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize <= Self.maximumBytes else { throw PrintHistoryError.fileTooLarge }
            let entry = PrintHistoryEntry(
                id: id,
                printedAt: Date(),
                displayName: displayName,
                storedFileName: storedFileName,
                printedPages: printedPages,
                fileSize: fileSize,
                settings: PrintHistorySettings(request: request)
            )
            current.insert(entry, at: 0)
            let kept = prune(current)
            try save(kept)
            let retainedIDs = Set(kept.map(\.id))
            for removed in current where !retainedIDs.contains(removed.id) {
                try? FileManager.default.removeItem(at: documentURL(for: removed))
            }
            cachedEntries = kept
            return kept
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func delete(ids: Set<UUID>) throws -> [PrintHistoryEntry] {
        let current = try load()
        let removed = current.filter { ids.contains($0.id) }
        let remaining = current.filter { !ids.contains($0.id) }
        try save(remaining)
        for entry in removed {
            try? FileManager.default.removeItem(at: documentURL(for: entry))
        }
        cachedEntries = remaining
        return remaining
    }

    func makeTemporaryCopy(for entry: PrintHistoryEntry) throws -> URL {
        let source = documentURL(for: entry)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let safeName = entry.displayName.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: Self.documentsDirectory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = Self.rootDirectory
        try? mutableRoot.setResourceValues(values)
    }

    private func prune(_ entries: [PrintHistoryEntry]) -> [PrintHistoryEntry] {
        var kept: [PrintHistoryEntry] = []
        var bytes: Int64 = 0
        for entry in entries {
            guard kept.count < Self.maximumCount,
                  bytes + entry.fileSize <= Self.maximumBytes else { continue }
            kept.append(entry)
            bytes += entry.fileSize
        }
        return kept
    }

    private func save(_ entries: [PrintHistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: Self.indexURL, options: .atomic)
    }

    private func documentURL(for entry: PrintHistoryEntry) -> URL {
        Self.documentsDirectory.appendingPathComponent(entry.storedFileName)
    }

    private func removeOrphanedDocuments(keeping entries: [PrintHistoryEntry]) throws {
        let retained = Set(entries.map(\.storedFileName))
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.documentsDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files where !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
