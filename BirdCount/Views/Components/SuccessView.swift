import SwiftUI

struct SuccessView: View {
    let title: String
    let message: String
    let recordCountMessage: String?
    let onDismiss: () -> Void
    
    init(
        title: String,
        message: String,
        recordCountMessage: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.recordCountMessage = recordCountMessage
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text(title)
                .font(.headline)
            
            VStack(spacing: 8) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                if let recordCountMessage = recordCountMessage {
                    Text(recordCountMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .font(.subheadline)
                }
            }
            
            Button(Strings.General.done.string) {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
#Preview {
    SuccessView(
        title: "Success!",
        message: "Your data has been processed successfully.",
        recordCountMessage: "3 records imported",
        onDismiss: {}
    )
}
#endif