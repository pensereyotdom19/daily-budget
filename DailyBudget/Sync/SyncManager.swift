import Foundation
import Observation
import SwiftData
import UIKit

/// Signs in and out, and decides when to sync:
/// when the app opens, a few seconds after you change something, and when you leave the app.
/// The app keeps working the same without internet; changes wait on the phone until the next sync.
@MainActor
@Observable
final class SyncManager {
    enum Status: Equatable {
        case signedOut
        case idle
        case syncing
        case failed(String)
    }

    private(set) var session: AccountSession?
    private(set) var status: Status
    private(set) var lastSyncedAt: Date?
    private(set) var pending = 0
    /// Set when the server refused some records, or the sign-in ran out.
    private(set) var notice: String?

    var isSignedIn: Bool { session != nil }

    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var saveObserver: NSObjectProtocol?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var changedWhileSyncing = false
    @ObservationIgnored private let baseURL: URL

    init(baseURL: URL = APIClient.productionURL) {
        self.baseURL = baseURL
        let session = SessionStore.load()
        self.session = session
        self.state = SyncState.load()
        self.lastSyncedAt = state.lastSyncedAt
        self.status = session == nil ? .signedOut : .idle
    }

    /// Call once with the app's main database. Watches every save so changes upload on their own.
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        refreshPending()
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localDataSaved() }
        }
    }

    // MARK: Sign in / out

    func signIn(email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reply = try await APIClient(baseURL: baseURL).login(email: cleanEmail, password: password)
        if state.userID != reply.userId {
            // A different account than last time on this phone: start its sync from scratch.
            state = SyncState(userID: reply.userId)
            state.save()
            lastSyncedAt = nil
        }
        let new = AccountSession(token: reply.token, email: cleanEmail, userID: reply.userId, expiresAt: reply.expiresAt)
        SessionStore.save(new)
        session = new
        notice = nil
        status = .idle
        await syncNow()
    }

    /// Your data stays on this phone. Signing back in to the same account continues where it left off.
    func signOut() {
        scheduled?.cancel()
        SessionStore.clear()
        session = nil
        status = .signedOut
        notice = nil
    }

    // MARK: When to sync

    func appBecameActive() {
        guard isSignedIn else { return }
        refreshPending()
        if pending > 0 || lastSyncedAt.map({ Date.now.timeIntervalSince($0) > 5 * 60 }) ?? true {
            Task { await syncNow() }
        }
    }

    /// iOS gives a few extra seconds after leaving the app; use them to upload the latest changes.
    func appWentToBackground() {
        guard isSignedIn else { return }
        refreshPending()
        guard pending > 0 else { return }
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: "Daily Budget sync") {
            MainActor.assumeIsolated { task.end() }
        }
        Task {
            await syncNow()
            task.end()
        }
    }

    /// Holds the id iOS gives a background task, so it is ended exactly once.
    @MainActor
    private final class BackgroundTask {
        var id = UIBackgroundTaskIdentifier.invalid
        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    private func localDataSaved() {
        guard isSignedIn else { return }
        if status == .syncing { changedWhileSyncing = true; return }
        refreshPending()
        guard pending > 0 else { return }  // e.g. the sync's own save: nothing new to send
        scheduled?.cancel()
        scheduled = Task {
            try? await Task.sleep(for: .seconds(3))  // wait for more edits, then send them together
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    // MARK: Sync

    func syncNow() async {
        guard let session, let context, status != .syncing else { return }
        status = .syncing
        changedWhileSyncing = false
        var working = state
        let engine = SyncEngine(api: APIClient(baseURL: baseURL, token: session.token), context: context)
        do {
            let report = try await engine.run(state: &working)
            working.lastSyncedAt = .now
            lastSyncedAt = working.lastSyncedAt
            notice = report.problems.isEmpty ? nil
                : "Couldn't upload \(report.problems.count): " + report.problems.joined(separator: "; ")
            status = .idle
            if report.downloaded > 0 { AppRefresh.run(context: context) }
        } catch APIError.unauthorized {
            SessionStore.clear()
            self.session = nil
            status = .signedOut
            notice = "Your sign-in ran out. Sign in again to keep backing up."
        } catch {
            status = .failed(error.localizedDescription)
        }
        // Keep whatever finished, even if the sync stopped halfway.
        state = working
        state.save()
        refreshPending()
        if changedWhileSyncing && isSignedIn && pending > 0 {
            changedWhileSyncing = false
            localDataSaved()
        }
    }

    private func refreshPending() {
        guard let context else { return }
        pending = SyncEngine.pendingCount(context: context, state: state)
    }
}
