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
                Text(Strings.Sync.Approval.request.string)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Sender info
                Text(String(format: Strings.Sync.Approval.from.string, payload.senderDisplayName))
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                // Summary card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text(Strings.Sync.Approval.importSummary.string)
                            .font(.headline)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text(Strings.Sync.Approval.observationsLabel.string)
                        Spacer()
                        Text("\(observationCount)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text(Strings.Sync.Approval.speciesLabel.string)
                        Spacer()
                        Text("\(speciesCount)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text(Strings.Sync.Approval.dateRangeLabel.string)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(dateFormatter.string(from: payload.rangeStart))
                            if !Calendar.current.isDate(payload.rangeStart, inSameDayAs: payload.rangeEnd) {
                                Text(String(format: Strings.Sync.Approval.to.string, dateFormatter.string(from: payload.rangeEnd)))
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Warning text
                Text(Strings.Sync.Approval.disclaimer.string)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { onResponse(true) }) {
                        Text(Strings.Sync.Approval.accept.string)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { onResponse(false) }) {
                        Text(Strings.Sync.Approval.decline.string)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle(Strings.Sync.Approval.incoming.string)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
