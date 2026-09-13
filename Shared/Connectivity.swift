@preconcurrency import WatchConnectivity
import Foundation
import Observation
import PulseCore

/// What is actually true about the watch, rather than one boolean pretending to
/// be the whole story. `reachable` is only true while the watch app is in the
/// foreground, so showing "not connected" whenever it was false told someone
/// wearing their watch that it was disconnected.
enum WatchLink: String, Sendable {
    case unsupported      // this device cannot pair a watch at all
    case notPaired        // no watch paired with this iPhone
    case appNotInstalled  // watch paired, Veyra not installed on it
    case idle             // installed and paired; the watch app is not open
    case reachable        // the watch app is open right now

    /// Whether the pairing is healthy, regardless of the watch app being open.
    var linked: Bool { self == .idle || self == .reachable }
}

@Observable @MainActor final class Connectivity: NSObject, WCSessionDelegate {
    var lastReceived: Date?
    var reachable = false
    var lastError: String?
    var onReceive: ((WatchEnvelope) -> Void)?
    /// Refreshed from the session whenever it changes, so Settings can explain
    /// what is actually missing.
    var link: WatchLink = .unsupported
    var activated = false
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
        guard session.isPaired else { link = .notPaired; return }
        #endif
        self.session = session
        session.delegate = self
        session.activate()
        refresh()
    }

    /// Reads the current state off the session. Call it when a screen appears:
    /// pairing and installation can change while the app is running, and
    /// WatchConnectivity does not always announce it.
    func refresh() {
        guard WCSession.isSupported() else { link = .unsupported; return }
        if session == nil {
            let session = WCSession.default
            #if os(iOS)
            guard session.isPaired else { link = .notPaired; return }
            #endif
            self.session = session
            session.delegate = self
            session.activate()
        }
        guard let session else { return }
        activated = session.activationState == .activated
        #if os(iOS)
        guard session.isPaired else { link = .notPaired; return }
        guard session.isWatchAppInstalled else { link = .appNotInstalled; return }
        #endif
        reachable = session.isReachable
        link = session.isReachable ? .reachable : .idle
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
        Task { @MainActor in
            self.refresh()
            if error != nil { self.lastError = "watchSyncFailed" }
        }
        receive(session.receivedApplicationContext)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    #endif
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
