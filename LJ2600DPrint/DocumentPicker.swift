import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// UIKit document picker using copy/import mode. This avoids relying on a
/// long-lived security-scoped URL, which is unreliable for some TrollStore
/// installations and third-party file providers.
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            defer { parent.isPresented = false }
            guard let sourceURL = urls.first else {
                parent.completion(.failure(PickerError.noFileSelected))
                return
            }

            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { sourceURL.stopAccessingSecurityScopedResource() }
            }

            do {
                let safeName = sourceURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)-\(safeName)")
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                parent.completion(.success(destination))
            } catch {
                parent.completion(.failure(error))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }

    enum PickerError: LocalizedError {
        case noFileSelected
        var errorDescription: String? { "没有收到所选文件" }
    }
}
