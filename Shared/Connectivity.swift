@preconcurrency import WatchConnectivity
import Foundation
import Observation
import PulseCore

@Observable @MainActor final class Connectivity: NSObject, WCSessionDelegate {
    var lastReceived: Date?
    var reachable = false
    var lastError: String?
    var onReceive: ((WatchEnvelope) -> Void)?
    private var session: WCSession?
    override init() {
        super.init()
        #if os(iOS) && targetEnvironment(simulator)
        // An iPhone simulator cannot be paired with a watch simulator through
        // WatchConnectivity. Avoid creating the session so the daemon does not
        // emit misleading pairing and activation diagnostics during previews
        // and UI tests.
        return
        #endif
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        #if os(iOS)
        // The iPhone simulator and an iPhone without a paired Apple Watch
        // produce pairingID-mismatch diagnostics when a session is activated.
        // Wait until a real pairing exists; the next app launch will activate
        // the session after pairing.
        guard session.isPaired else { return }
        #endif
        self.session = session
        session.delegate = self
        session.activate()
    }
    func send(_ envelope: WatchEnvelope, queued: Bool = false) {
        guard let session, session.activationState == .activated else { lastError = "watchNotReady"; return }
        do {
            let packet: [String: Any] = ["envelope": try JSONEncoder().encode(envelope)]
            if queued { session.transferUserInfo(packet) }
            else { try session.updateApplicationContext(packet) }
            reachable = session.isReachable
        } catch { lastError = "watchSyncFailed" }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable; if error != nil { self.lastError = "watchSyncFailed" } }
        receive(session.receivedApplicationContext)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { let reachable = session.isReachable; Task { @MainActor in self.reachable = reachable } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }
    nonisolated private func receive(_ packet: [String: Any]) {
        guard let data = packet["envelope"] as? Data, let envelope = try? JSONDecoder().decode(WatchEnvelope.self, from: data), envelope.version == 1 else { return }
        Task { @MainActor in self.lastReceived = Date(); self.onReceive?(envelope) }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
