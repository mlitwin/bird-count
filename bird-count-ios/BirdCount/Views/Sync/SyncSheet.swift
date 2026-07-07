import SwiftUI

struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SyncViewModel
    @State private var showRangePicker = false

    init(observationStore: ObservationStore, settingsStore: SettingsStore, dateRangeStore: DateRangeStore) {
        _vm = State(wrappedValue: SyncViewModel(
            transport: NetworkSyncTransport(),
            observationStore: observationStore,
            settingsStore: settingsStore,
            initialFilter: dateRangeStore.dateRange
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rolePicker
                    if vm.rolePreference != .receiveOnly {
                        filterRow
                    }
                    Divider()
                    discoverySection
                    actionSection
                }
                .padding()
            }
            .navigationTitle("Sync with Nearby Phones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.cancel.string) {
                        vm.cancel()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showRangePicker) {
            DateRangePickerSheet(range: $vm.syncFilter)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.cancel() }
    }

    // MARK: - Role Picker

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $vm.rolePreference) {
                ForEach(SyncRolePreference.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            Text(vm.syncFilter.formattedSummary())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { showRangePicker = true }) {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .padding(6)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel(Strings.Share.Accessibility.editRange.string)
        }
    }

    // MARK: - Discovery Section

    @ViewBuilder
    private var discoverySection: some View {
        switch vm.state {
        case .idle:
            EmptyView()

        case .discovering:
            HStack(spacing: 12) {
                ProgressView()
                Text("Looking for nearby devices…")
                    .foregroundStyle(.secondary)
            }

        case .handshaking(let peerName):
            HStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(peerName)…")
                    .foregroundStyle(.secondary)
            }

        case .readyToSync(let info):
            peerCard(info: info)

        case .incompatible(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)

        case .transferring:
            HStack(spacing: 12) {
                ProgressView()
                Text("Syncing…")
                    .foregroundStyle(.secondary)
            }

        case .completed(let stats):
            completionSummary(stats: stats)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
    }

    private func peerCard(info: SyncReadyInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(info.peerName)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                if info.localWillSend {
                    let s = vm.localSendSummary
                    HStack {
                        Image(systemName: "arrow.up.circle").foregroundStyle(.blue)
                        Text("Sending \(s.speciesCount) species")
                    }
                    .font(.subheadline)
                }

                if let peerSummary = info.peerWillSend {
                    HStack {
                        Image(systemName: "arrow.down.circle").foregroundStyle(.green)
                        Text("Receiving \(peerSummary.speciesCount) species")
                    }
                    .font(.subheadline)
                }

                if !info.localWillSend && info.peerWillSend == nil {
                    Text("Nothing to transfer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func completionSummary(stats: SyncCompletionStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Sync complete")
                    .font(.headline)
            }
            if stats.sentCount > 0 {
                Text("Sent \(stats.sentCount) observation\(stats.sentCount == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if stats.receivedCount > 0 {
                Text("Received \(stats.receivedCount) new observation\(stats.receivedCount == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if stats.duplicatesSkipped > 0 {
                Text("\(stats.duplicatesSkipped) duplicate\(stats.duplicatesSkipped == 1 ? "" : "s") skipped")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch vm.state {
        case .readyToSync:
            Button("Sync") { vm.initiateSync() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

        case .transferring:
            EmptyView()

        case .completed, .error:
            HStack(spacing: 12) {
                Button(Strings.General.done.string) {
                    vm.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Sync Again") { vm.restart() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

        case .incompatible:
            Button(Strings.General.done.string) {
                vm.cancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

        default:
            Button("Sync") { }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(true)
        }
    }
}
