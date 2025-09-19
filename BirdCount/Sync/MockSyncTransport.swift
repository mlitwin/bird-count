import Foundation

/// Mock transport for testing sync functionality in simulator
/// This bypasses MultipeerConnectivity limitations
class MockSyncTransport: ObservableObject {
    static let shared = MockSyncTransport()
    
    @Published var availablePeers: [String] = []
    @Published var incomingPayloads: [(String, PayloadV1)] = []
    
    private var connections: [String: MockConnection] = [:]
    
    private init() {}
    
    func startAdvertising(deviceName: String) {
        if !availablePeers.contains(deviceName) {
            availablePeers.append(deviceName)
        }
    }
    
    func stopAdvertising(deviceName: String) {
        availablePeers.removeAll { $0 == deviceName }
    }
    
    func sendPayload(_ payload: PayloadV1, to peer: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.incomingPayloads.append((peer, payload))
            completion(.success(()))
        }
    }
    
    func receivePayload(from sender: String) -> PayloadV1? {
        if let index = incomingPayloads.firstIndex(where: { $0.0 == sender }) {
            let payload = incomingPayloads[index].1
            incomingPayloads.remove(at: index)
            return payload
        }
        return nil
    }
}

private struct MockConnection {
    let deviceName: String
    let isConnected: Bool
}
