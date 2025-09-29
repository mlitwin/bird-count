import SwiftUI

struct ImportSheet: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDocumentPicker: Bool = false
    @State private var importError: ImportError? = nil
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
            Text(importError?.localizedDescription ?? Strings.Import.unknownError.string)
        }
        .alert(Strings.Import.success.string, isPresented: $showImportSuccess) {
            Button(Strings.General.ok.string) { }
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
        do {
            let jsonData = try String(contentsOf: url, encoding: .utf8)
            try ObservationJSONImportService.importFromJSON(jsonData, into: observations)
            importSuccess = true
            showImportSuccess = true
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
}

#if DEBUG
#Preview {
    ImportSheet()
        .environment(ObservationStore())
}
#endif