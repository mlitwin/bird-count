import SwiftUI
import UniformTypeIdentifiers

/// A SwiftUI wrapper for UIActivityViewController to present system share sheet
struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// A helper for sharing text content with subject line support (e.g., for email)
class TextShareItem: NSObject, UIActivityItemSource {
    let content: String
    let subject: String

    init(content: String, subject: String) {
        self.content = content
        self.subject = subject
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return content
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return content
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }
}

/// A helper for creating temporary files with proper UTI types for sharing
class TemporaryFileItem: NSObject, UIActivityItemSource {
    let content: String
    let filename: String
    let utType: UTType
    let subject: String

    init(content: String, filename: String, utType: UTType, subject: String? = nil) {
        self.content = content
        self.filename = filename
        self.utType = utType
        self.subject = subject ?? filename
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return content
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
            return tempFile
        } catch {
            // Fallback to string content
            return content
        }
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return utType.identifier
    }
}
