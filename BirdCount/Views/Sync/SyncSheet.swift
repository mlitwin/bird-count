import SwiftUI

struct SyncSheet: View {
    @Environment(SyncSessionManager.self) private var syncManager
    @Environment(ObservationStore.self) private var observationStore
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(\.dismiss) private var dismiss
    
    private let mode: SyncMode
    @State private var incomingPayload: PayloadV1?
    @State private var showingApproval = false
    @State private var approvalCompletion: ((Bool) -> Void)?
    
    init(initialMode: SyncMode = .sender) {
        self.mode = initialMode
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                switch syncManager.state {
                case .idle:
                    IdleView(mode: mode) {
                        startSync()
                    }
                    
                case .browsing:
                    BrowsingView()
                    
                case .advertising:
                    AdvertisingView()
                    
                case .connecting:
                    ConnectingView()
                    
                case .connected:
                    if mode == .sender {
                        ConnectedView {
                            sendObservations()
                        }
                    } else {
                        WaitingToReceiveView()
                    }
                    
                case .transferring:
                    TransferringView(mode: mode)
                    
                case .receivingApproval:
                    // This state is handled by the sheet presentation
                    ProgressView("Processing...")
                    
                case .completed:
                    CompletedView()
                    
                case .error:
                    ErrorView()
                }
            }
            .padding()
            .navigationTitle("Sync Observations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        syncManager.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingApproval) {
                if let payload = incomingPayload {
                    SyncApprovalSheet(
                        payload: payload,
                        onResponse: { approved in
                            approvalCompletion?(approved)
                            if approved {
                                importObservations(payload)
                            }
                            showingApproval = false
                            incomingPayload = nil
                            approvalCompletion = nil
                        }
                    )
                }
            }
        }
        .onAppear {
            setupIncomingSyncHandler()
        }
    }
    
    private func startSync() {
        switch mode {
        case .sender:
            syncManager.startBrowsing()
        case .receiver:
            syncManager.startAdvertising { payload, completion in
                incomingPayload = payload
                approvalCompletion = completion
                showingApproval = true
            }
        }
    }
    
    private func sendObservations() {
        let currentRange = dateRangeStore.dateRange
        let payload = ObservationExportService.exportForSync(in: currentRange, from: observationStore)
        
        syncManager.sendSync(payload: payload) { result in
            switch result {
            case .success:
                // Success is handled by state management
                break
            case .failure(let error):
                print("Sync failed: \(error)")
            }
        }
    }
    
    private func importObservations(_ payload: PayloadV1) {
        do {
            try ObservationImportService.importFromSync(payload, into: observationStore)
        } catch {
            print("Import failed: \(error)")
        }
    }
    
    private func setupIncomingSyncHandler() {
        // The handler is set when we start advertising
    }
}

// MARK: - Sub-views

private struct IdleView: View {
    let mode: SyncMode
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Sync Observations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(mode == .sender 
                ? "Send your bird observations to another iPhone nearby"
                : "Receive bird observations from another iPhone nearby")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button(action: onStart) {
                Text(mode == .sender ? "Find Devices" : "Wait for Connection")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct BrowsingView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Looking for devices...")
                .font(.headline)
            
            if !syncManager.discoveredPeers.isEmpty {
                Text("Found Devices:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(syncManager.discoveredPeers, id: \.displayName) { peer in
                    Button(action: {
                        syncManager.connect(to: peer)
                    }) {
                        HStack {
                            Image(systemName: "iphone")
                            Text(peer.displayName)
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }
}

private struct AdvertisingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Waiting for connection...")
                .font(.headline)
            
            Text("Make sure the sending device is looking for your device")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

private struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Connecting...")
                .font(.headline)
        }
    }
}

private struct ConnectedView: View {
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Connected!")
                .font(.headline)
            
            Button("Send Observations", action: onSend)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct TransferringView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    let mode: SyncMode
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: syncManager.progress)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text(mode == .sender ? "Sending observations..." : "Receiving observations...")
                .font(.headline)
            
            Text("\(Int(syncManager.progress * 100))%")
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

private struct CompletedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Sync Complete!")
                .font(.headline)
            
            Text("Observations have been successfully synced")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

private struct ErrorView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Sync Failed")
                .font(.headline)
            
            if let errorMessage = syncManager.errorMessage {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct WaitingToReceiveView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Connected!")
                .font(.headline)
            
            Text("Waiting to receive observations...")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            ProgressView()
                .scaleEffect(1.2)
        }
    }
}

// MARK: - Supporting Types

enum SyncMode {
    case sender
    case receiver
}
