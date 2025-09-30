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
                    // Show loading while starting up
                    ProgressView(mode == .sender ? Strings.Sync.looking.string : Strings.Sync.waitingConnection.string)
                    
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
                    ProgressView(Strings.Sync.processing.string)
                    
                case .completed:
                    CompletedView(mode: mode, onDismiss: {
                        dismiss()
                        DispatchQueue.main.async {
                            syncManager.cancel()
                        }
                    })
                    
                case .error:
                    ErrorView()
                }
            }
            .padding()
            .navigationTitle(Strings.Sync.title.string)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Strings.General.cancel.string) {
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
            // Start sync immediately when the sheet appears
            startSync()
        }
        .onDisappear {
            // Defensive: make sure we stop any transport activity if the sheet goes away
            syncManager.cancel()
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

private struct BrowsingView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(Strings.Sync.looking.string)
                .font(.headline)
            
            if !syncManager.discoveredPeers.isEmpty {
                Text(Strings.Sync.foundDevices.string)
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
            
            Text(Strings.Sync.waitingConnection.string)
                .font(.headline)
            
            Text(Strings.Sync.makeSure.string)
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
            
            Text(Strings.Sync.connecting.string)
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
            
            Text(Strings.Sync.connected.string)
                .font(.headline)
            
            Button(Strings.Sync.sendObservations.string, action: onSend)
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
            
            Text(mode == .sender ? Strings.Sync.sending.string : Strings.Sync.receiving.string)
                .font(.headline)
            
            Text("\(Int(syncManager.progress * 100))%")
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

private struct CompletedView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    let mode: SyncMode
    let onDismiss: () -> Void
    
    var body: some View {
        SuccessView(
            title: Strings.Sync.complete.string,
            message: successMessage,
            recordCountMessage: recordCountMessage,
            onDismiss: onDismiss
        )
    }
    
    private var successMessage: String {
        switch mode {
        case .sender:
            return Strings.Sync.successSent.string
        case .receiver:
            return Strings.Sync.successReceived.string
        }
    }
    
    private var recordCountMessage: String {
        switch mode {
        case .sender:
            let count = syncManager.lastSentRecordCount
            return count == 1 ? Strings.Sync.recordSentSingle.string : String(format: Strings.Sync.recordSentMultiple.string, count)
        case .receiver:
            let count = syncManager.lastReceivedRecordCount
            return count == 1 ? Strings.Sync.recordReceivedSingle.string : String(format: Strings.Sync.recordReceivedMultiple.string, count)
        }
    }
}

private struct ErrorView: View {
    @Environment(SyncSessionManager.self) private var syncManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text(Strings.Sync.failed.string)
                .font(.headline)
            
            if let errorMessage = syncManager.errorMessage {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Button(Strings.General.done.string) {
                dismiss()
                DispatchQueue.main.async {
                    syncManager.cancel()
                }
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
            
            Text(Strings.Sync.connected.string)
                .font(.headline)
            
            Text(Strings.Sync.waitReceive.string)
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
