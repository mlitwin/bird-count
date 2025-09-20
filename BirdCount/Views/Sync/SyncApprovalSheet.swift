import SwiftUI

struct SyncApprovalSheet: View {
    let payload: PayloadV1
    let onResponse: (Bool) -> Void
    
    private var observationCount: Int {
        payload.observations.count
    }
    
    private var speciesCount: Int {
        Set(payload.observations.map { $0.taxonId }).count
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                // Icon
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                // Title
                Text("Sync Request")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Sender info
                Text("From: \(payload.senderDisplayName)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                // Summary card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Import Summary")
                            .font(.headline)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Observations:")
                        Spacer()
                        Text("\(observationCount)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Species:")
                        Spacer()
                        Text("\(speciesCount)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Date Range:")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(dateFormatter.string(from: payload.rangeStart))
                            if !Calendar.current.isDate(payload.rangeStart, inSameDayAs: payload.rangeEnd) {
                                Text("to \(dateFormatter.string(from: payload.rangeEnd))")
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Warning text
                Text("New observations will be added to your records. Existing observations won't be modified.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { onResponse(true) }) {
                        Text("Accept and Import")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { onResponse(false) }) {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Incoming Sync")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
