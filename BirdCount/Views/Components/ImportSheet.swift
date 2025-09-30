import SwiftUI

struct ImportSheet: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDocumentPicker: Bool = false
    @State private var importError: ImportError?
    @State private var showImportError: Bool = false
    @State private var importSuccess: Bool = false
    @State private var showImportSuccess: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding()
                
                // Instructions
                Text(Strings.Import.instructions.string)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Import button
                Button(action: {
                    showDocumentPicker = true
                }) {
                    Text(Strings.Import.importData.string)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(Strings.Import.selectFile.string)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Strings.General.cancel.string) {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert(Strings.Import.error.string, isPresented: $showImportError) {
            Button(Strings.General.ok.string) { }
        } message: {
            let errorMessage = importError?.localizedDescription ?? Strings.Import.unknownError.string
            let suggestion = importError?.recoverySuggestion ?? ""
            Text(suggestion.isEmpty ? errorMessage : "\(errorMessage)\n\n\(suggestion)")
        }
        .alert(Strings.Import.success.string, isPresented: $showImportSuccess) {
            Button(Strings.General.ok.string) {
                // Auto-dismiss the sheet after user acknowledges success
                dismiss()
            }
        } message: {
            Text(Strings.Import.successMessage.string)
        }
    }
    
    // MARK: - Import Logic
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFromURL(url)
        case .failure(let error):
            importError = ImportError.fileAccessError(error.localizedDescription)
            showImportError = true
        }
    }
    
    private func importFromURL(_ url: URL) {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            importError = ImportError.fileAccessError("Unable to access the selected file. Please ensure the app has permission to read the file.")
            showImportError = true
            return
        }
        
        // Ensure we stop accessing the resource when done
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        do {
            // Check if the file is readable
            guard url.isFileURL else {
                throw ImportError.fileAccessError("Selected item is not a valid file.")
            }
            
            // Check if we can actually read the file
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw ImportError.fileAccessError("The selected file cannot be read. Please check file permissions.")
            }
            
            let jsonData = try String(contentsOf: url, encoding: .utf8)
            try ObservationJSONImportService.importFromJSON(jsonData, into: observations)
            importSuccess = true
            showImportSuccess = true
        } catch let error as ImportError {
            importError = error
            showImportError = true
        } catch let error as ObservationJSONImportService.ImportError {
            importError = ImportError.jsonImportError(error.localizedDescription)
            showImportError = true
        } catch {
            importError = ImportError.unknownError(error.localizedDescription)
            showImportError = true
        }
    }
}

// MARK: - Import Error Types

enum ImportError: Error, LocalizedError {
    case fileAccessError(String)
    case jsonImportError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileAccessError(let message):
            return "File access error: \(message)"
        case .jsonImportError(let message):
            return message
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .fileAccessError:
            return "Try selecting the file again from the Files app, or ensure the file is stored in a location the app can access (such as iCloud Drive or On My iPhone)."
        case .jsonImportError:
            return "Please ensure you're importing a valid JSON file exported from this app."
        case .unknownError:
            return "Please try again or contact support if the problem persists."
        }
    }
}

#if DEBUG
#Preview {
    ImportSheet()
        .environment(ObservationStore())
}
#endif