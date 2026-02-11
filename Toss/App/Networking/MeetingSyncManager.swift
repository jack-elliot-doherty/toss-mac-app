import AppKit
import CryptoKit
import Foundation

/// Represents a meeting that failed to sync and needs retry
struct PendingSync: Codable, Equatable {
    let meetingId: UUID
    let queuedAt: Date
    var retryCount: Int
    var lastAttempt: Date?
    var operation: SyncOperation
    var serverBaseURL: String?
    var accountScope: String?

    enum SyncOperation: String, Codable {
        case sync  // Create or update meeting
        case delete  // Delete meeting from server
    }
}

/// Manages background sync of meetings to the server with retry logic
@MainActor
final class MeetingSyncManager: ObservableObject {
    static let shared = MeetingSyncManager()

    @Published private(set) var isSyncing = false
    @Published private(set) var pendingSyncCount = 0

    private let queueFileURL: URL
    private var pendingSyncs: [PendingSync] = []
    private var retryTimer: Timer?
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]

    private weak var repository: PersistentMeetingRepository?

    private let maxRetries = 10
    private let retryInterval: TimeInterval = 5 * 60  // 5 minutes
    private var currentServerScope: String { Config.serverBaseURL.absoluteString }
    private var currentAccountScope: String? {
        // Use hashed auth token scope to partition retries by signed-in identity/org context.
        if let refresh = AuthManager.shared.refreshToken, !refresh.isEmpty {
            return hashedScope(refresh)
        }
        if let access = AuthManager.shared.accessToken, !access.isEmpty {
            return hashedScope(access)
        }
        return nil
    }

    private init() {
        self.queueFileURL = Config.appSupportFileURL("sync_queue.json")

        loadQueue()
        NSLog("[MeetingSyncManager] Using queue storage %@", queueFileURL.path)
    }

    // MARK: - Public API

    /// Sync a meeting to the server (called after meeting ends or after edits)
    /// Set triggerFlows to true for initial sync after meeting ends (not for subsequent edits)
    func syncMeeting(
        _ meetingId: UUID,
        triggerFlows: Bool = false,
        allowInProgress: Bool = false
    ) async {
        NSLog("[MeetingSyncManager] Syncing meeting: \(meetingId)")

        guard let repository = getRepository() else {
            NSLog("[MeetingSyncManager] No repository available")
            return
        }

        guard let meeting = repository.getMeeting(id: meetingId) else {
            NSLog("[MeetingSyncManager] Meeting not found: \(meetingId)")
            return
        }

        // Only sync ended meetings unless explicitly allowed
        if meeting.endTime == nil && !allowInProgress {
            NSLog("[MeetingSyncManager] Meeting not ended yet, skipping sync: \(meetingId)")
            return
        }

        let chunks = repository.getChunks(meetingId: meetingId)

        do {
            isSyncing = true
            try await MeetingsApi.shared.syncMeeting(
                meeting: meeting,
                chunks: chunks,
                actionItems: meeting.actionItems.map { $0.toExtractedAction() }
            )
            repository.markMeetingSynced(meetingId: meetingId)

            // Remove from pending queue if it was there
            removePending(meetingId: meetingId, operation: .sync)

            NSLog("[MeetingSyncManager] Successfully synced meeting: \(meetingId)")
            isSyncing = false

            // Trigger flows if requested (only for initial sync after meeting ends)
            if triggerFlows {
                await triggerFlowsForMeeting(meetingId)
            }
        } catch {
            NSLog("[MeetingSyncManager] Sync failed for meeting \(meetingId): \(error)")
            queueForRetry(meetingId: meetingId, operation: .sync)
            isSyncing = false
        }
    }

    /// Trigger flows for a meeting and start polling for completion
    private func triggerFlowsForMeeting(_ meetingId: UUID) async {
        NSLog("[MeetingSyncManager] Triggering flows for meeting: \(meetingId)")

        do {
            let response = try await FlowsAPI.shared.triggerFlows(for: meetingId)

            if response.triggered, let flows = response.flows, !flows.isEmpty {
                NSLog(
                    "[MeetingSyncManager] Triggered \(flows.count) flow(s) for meeting: \(meetingId)"
                )
                // Start polling for flow completion with flow details for notifications
                await FlowNotificationManager.shared.startPolling(for: meetingId, flows: flows)
            } else {
                NSLog(
                    "[MeetingSyncManager] No flows triggered: \(response.message ?? "unknown reason")"
                )
            }
        } catch {
            NSLog("[MeetingSyncManager] Failed to trigger flows: \(error)")
        }
    }

    /// Debounced sync for user edits (e.g., typing in notes)
    func debouncedSync(_ meetingId: UUID, delay: TimeInterval = 2.0) {
        // Cancel existing debounce for this meeting
        debounceTasks[meetingId]?.cancel()

        debounceTasks[meetingId] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await syncMeeting(meetingId)
            debounceTasks.removeValue(forKey: meetingId)
        }
    }

    /// Delete a meeting from the server
    func deleteMeetingFromServer(_ meetingId: UUID) async {
        NSLog("[MeetingSyncManager] Deleting meeting from server: \(meetingId)")

        do {
            try await MeetingsApi.shared.deleteMeetingFromServer(meetingId: meetingId)
            removePending(meetingId: meetingId, operation: .delete)
            // Also remove any pending sync operations for this meeting
            removePending(meetingId: meetingId, operation: .sync)
            NSLog("[MeetingSyncManager] Successfully deleted meeting from server: \(meetingId)")
        } catch {
            NSLog("[MeetingSyncManager] Delete failed for meeting \(meetingId): \(error)")
            queueForRetry(meetingId: meetingId, operation: .delete)
        }
    }

    /// Process all pending syncs (called on app launch and periodically)
    func processQueue() async {
        NSLog("[MeetingSyncManager] Processing sync queue (\(pendingSyncs.count) pending)")

        guard !pendingSyncs.isEmpty else { return }
        guard let accountScope = currentAccountScope else {
            NSLog("[MeetingSyncManager] Skipping queue processing: account scope unavailable")
            return
        }

        // Take a copy to iterate
        let syncsToProcess = pendingSyncs

        for pending in syncsToProcess {
            guard pending.serverBaseURL == currentServerScope else {
                NSLog(
                    "[MeetingSyncManager] Dropping queue item from mismatched or unscoped server: %@ (%@)",
                    pending.meetingId.uuidString,
                    pending.operation.rawValue
                )
                removePending(entry: pending)
                continue
            }

            guard pending.accountScope == accountScope else {
                NSLog(
                    "[MeetingSyncManager] Dropping queue item from different account scope: %@ (%@)",
                    pending.meetingId.uuidString,
                    pending.operation.rawValue
                )
                removePending(entry: pending)
                continue
            }

            // Check if enough time has passed (exponential backoff)
            let backoffSeconds = min(pow(2.0, Double(pending.retryCount)) * 30, 3600)
            if let lastAttempt = pending.lastAttempt {
                let elapsed = Date().timeIntervalSince(lastAttempt)
                if elapsed < backoffSeconds {
                    NSLog(
                        "[MeetingSyncManager] Skipping \(pending.meetingId) - backoff not elapsed")
                    continue
                }
            }

            // Check max retries
            if pending.retryCount >= maxRetries {
                NSLog(
                    "[MeetingSyncManager] Max retries exceeded for \(pending.meetingId), removing from queue"
                )
                removePending(entry: pending)
                continue
            }

            // Attempt sync/delete
            switch pending.operation {
            case .sync:
                await syncMeeting(pending.meetingId)
            case .delete:
                await deleteMeetingFromServer(pending.meetingId)
            }
        }
    }

    /// Start the periodic retry timer
    func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.processQueue()
            }
        }
        NSLog("[MeetingSyncManager] Retry timer started (interval: \(retryInterval)s)")
    }

    /// Stop the retry timer
    func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: - Queue Management

    private func queueForRetry(meetingId: UUID, operation: PendingSync.SyncOperation) {
        let serverScope = currentServerScope
        guard let accountScope = currentAccountScope else {
            NSLog(
                "[MeetingSyncManager] Not queueing retry for %@ (%@): account scope unavailable",
                meetingId.uuidString,
                operation.rawValue
            )
            return
        }

        // Check if already in queue
        if let index = pendingSyncs.firstIndex(where: {
            $0.meetingId == meetingId
                && $0.operation == operation
                && $0.serverBaseURL == serverScope
                && $0.accountScope == accountScope
        }) {
            // Update existing entry
            pendingSyncs[index].retryCount += 1
            pendingSyncs[index].lastAttempt = Date()
            pendingSyncs[index].serverBaseURL = serverScope
            pendingSyncs[index].accountScope = accountScope
        } else {
            // Add new entry
            let pending = PendingSync(
                meetingId: meetingId,
                queuedAt: Date(),
                retryCount: 0,
                lastAttempt: Date(),
                operation: operation,
                serverBaseURL: serverScope,
                accountScope: accountScope
            )
            pendingSyncs.append(pending)
        }

        pendingSyncCount = pendingSyncs.count
        saveQueue()
        NSLog("[MeetingSyncManager] Queued for retry: \(meetingId) (\(operation))")
    }

    private func removePending(entry: PendingSync) {
        pendingSyncs.removeAll {
            $0.meetingId == entry.meetingId
                && $0.operation == entry.operation
                && $0.serverBaseURL == entry.serverBaseURL
                && $0.accountScope == entry.accountScope
        }
        pendingSyncCount = pendingSyncs.count
        saveQueue()
    }

    private func removePending(
        meetingId: UUID,
        operation: PendingSync.SyncOperation
    ) {
        pendingSyncs.removeAll {
            $0.meetingId == meetingId
                && $0.operation == operation
                && $0.serverBaseURL == currentServerScope
                && $0.accountScope == currentAccountScope
        }
        pendingSyncCount = pendingSyncs.count
        saveQueue()
    }

    func clearPendingQueue(reason: String) {
        guard !pendingSyncs.isEmpty else { return }
        let clearedCount = pendingSyncs.count
        pendingSyncs.removeAll()
        pendingSyncCount = 0
        saveQueue()
        NSLog(
            "[MeetingSyncManager] Cleared %d pending sync operation(s): %@",
            clearedCount,
            reason
        )
    }

    // MARK: - Persistence

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: queueFileURL)
            let loaded = try JSONDecoder().decode([PendingSync].self, from: data)
            pendingSyncs = loaded.filter { pending in
                guard let queuedScope = pending.serverBaseURL else {
                    NSLog(
                        "[MeetingSyncManager] Discarding legacy unscoped queue item for safety: %@ (%@)",
                        pending.meetingId.uuidString,
                        pending.operation.rawValue
                    )
                    return false
                }

                guard pending.accountScope != nil else {
                    NSLog(
                        "[MeetingSyncManager] Discarding legacy unscoped account queue item for safety: %@ (%@)",
                        pending.meetingId.uuidString,
                        pending.operation.rawValue
                    )
                    return false
                }

                if queuedScope != currentServerScope {
                    NSLog(
                        "[MeetingSyncManager] Discarding queue item from different server (%@ != %@): %@ (%@)",
                        queuedScope,
                        currentServerScope,
                        pending.meetingId.uuidString,
                        pending.operation.rawValue
                    )
                    return false
                }

                return true
            }
            pendingSyncCount = pendingSyncs.count
            NSLog("[MeetingSyncManager] Loaded \(pendingSyncs.count) pending syncs from disk")

            if pendingSyncs.count != loaded.count {
                saveQueue()
            }
        } catch {
            NSLog("[MeetingSyncManager] Failed to load queue: \(error)")
        }
    }

    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(pendingSyncs)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            NSLog("[MeetingSyncManager] Failed to save queue: \(error)")
        }
    }

    // MARK: - Helpers

    private func getRepository() -> PersistentMeetingRepository? {
        if let repo = repository {
            return repo
        }
        NSLog("[MeetingSyncManager] Repository not configured - call configure(repository:) first")
        return nil
    }

    // ADD: New configure method
    func configure(repository: PersistentMeetingRepository) {
        self.repository = repository
        NSLog("[MeetingSyncManager] Configured with repository")
    }

    private func hashedScope(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
