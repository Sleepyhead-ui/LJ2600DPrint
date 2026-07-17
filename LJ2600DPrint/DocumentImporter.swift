import Foundation

enum DocumentImporter {
    static func copyToTemporary(_ sourceURL: URL) throws -> URL {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let safeName = sourceURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
