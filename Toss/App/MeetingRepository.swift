import Combine
import Foundation

enum MeetingSpeaker: String, Codable, CaseIterable {
    case user
    case remote
}

enum MeetingSource: String, Codable {
    case calendar  // Synced from Google Calendar
    case adhoc  // Manually started (Slack huddle, quick record, etc.)
}

struct MeetingModel: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var createdAt: Date
    var updatedAt: Date
    var notes: String = ""  // AI-generated summary
    var userNotes: String = ""  // User's live notes during the meeting (Granola-style)
    var source: MeetingSource = .adhoc
    var actionItems: [StoredActionItem] = []  // Extracted action items
    var syncedAt: Date?  // Last sync to server

    // Custom decoder for backwards compatibility with existing data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        userNotes = try container.decodeIfPresent(String.self, forKey: .userNotes) ?? ""
        source = try container.decodeIfPresent(MeetingSource.self, forKey: .source) ?? .adhoc
        actionItems =
            try container.decodeIfPresent([StoredActionItem].self, forKey: .actionItems) ?? []
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
    }

    init(
        id: UUID, title: String, startTime: Date, endTime: Date?, createdAt: Date, updatedAt: Date,
        notes: String = "", userNotes: String = "", source: MeetingSource = .adhoc,
        actionItems: [StoredActionItem] = [], syncedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.userNotes = userNotes
        self.source = source
        self.actionItems = actionItems
        self.syncedAt = syncedAt
    }
}

struct MeetingChunkModel: Identifiable, Equatable, Codable {
    let id: UUID
    let meetingId: UUID
    let chunkIndex: Int
    var transcript: String
    let startedAt: Date
    let speaker: MeetingSpeaker

    init(
        id: UUID = UUID(),
        meetingId: UUID,
        chunkIndex: Int,
        transcript: String,
        startedAt: Date,
        speaker: MeetingSpeaker
    ) {
        self.id = id
        self.meetingId = meetingId
        self.chunkIndex = chunkIndex
        self.transcript = transcript
        self.startedAt = startedAt
        self.speaker = speaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        meetingId = try container.decode(UUID.self, forKey: .meetingId)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        transcript = try container.decode(String.self, forKey: .transcript)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        speaker = try container.decodeIfPresent(MeetingSpeaker.self, forKey: .speaker) ?? .user
    }
}

protocol MeetingRepositoryProtocol {
    func createMeeting(id: UUID, title: String, source: MeetingSource) -> MeetingModel
    func endMeeting(id: UUID)
    func getMeeting(id: UUID) -> MeetingModel?
    func appendChunk(
        meetingId: UUID, index: Int, transcript: String, startedAt: Date, speaker: MeetingSpeaker
    ) -> MeetingChunkModel?  // Optional since we might want to remove a duplicate chunk
    func listMeetings() -> [MeetingModel]
    func getChunks(meetingId: UUID) -> [MeetingChunkModel]
    func getFullTranscript(meetingId: UUID) -> String
    func updateMeetingTitle(meetingId: UUID, title: String)
    func updateMeetingNotes(meetingId: UUID, notes: String)
    func updateMeetingUserNotes(meetingId: UUID, userNotes: String)
    func updateMeetingActionItems(meetingId: UUID, actionItems: [StoredActionItem])
    func markMeetingSynced(meetingId: UUID)
    func cleanupOrphanedMeetings()
    func endMeetingIfActive(id: UUID)
    func deleteMeeting(id: UUID)
}

final class PersistentMeetingRepository: MeetingRepositoryProtocol, ObservableObject {
    private var meetings: [UUID: MeetingModel] = [:]
    private var chunks: [UUID: [MeetingChunkModel]] = [:]
    private let queue = DispatchQueue(label: "meeting.repo.queue", qos: .userInitiated)
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let tossDir = appSupport.appendingPathComponent("ai.toss.mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: tossDir, withIntermediateDirectories: true)
        self.fileURL = tossDir.appendingPathComponent("meetings.json")
        load()
    }

    private struct StorageFormat: Codable {
        let meetings: [MeetingModel]
        let chunks: [UUID: [MeetingChunkModel]]
    }

    private func load() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(StorageFormat.self, from: data)
                self.meetings = Dictionary(
                    uniqueKeysWithValues: decoded.meetings.map { ($0.id, $0) })
                self.chunks = decoded.chunks
                NSLog("[Meetings] Loaded \(meetings.count) meetings")
            } catch {
                NSLog("[Meetings] Load error: \(error)")
            }
        }
    }

    private func save() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let storage = StorageFormat(
                    meetings: Array(self.meetings.values), chunks: self.chunks)
                let data = try JSONEncoder().encode(storage)
                try data.write(to: self.fileURL, options: .atomic)

                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }

            } catch {
                NSLog("[Meetings] Save error: \(error)")
            }
        }
    }

    func createMeeting(id: UUID, title: String, source: MeetingSource = .adhoc) -> MeetingModel {
        let meeting = queue.sync { () -> MeetingModel in
            let now = Date()
            let meeting = MeetingModel(
                id: id, title: title, startTime: now, endTime: nil, createdAt: now,
                updatedAt: now, source: source)
            meetings[meeting.id] = meeting
            chunks[meeting.id] = []
            return meeting
        }
        // Notify AFTER releasing the lock
        save()
        return meeting
    }

    func endMeeting(id: UUID) {
        queue.sync {
            guard var meeting = meetings[id] else { return }
            meeting.endTime = Date()
            meeting.updatedAt = Date()
            meetings[id] = meeting
        }
        save()
    }

    func getMeeting(id: UUID) -> MeetingModel? {
        return queue.sync { meetings[id] }
    }

    func appendChunk(
        meetingId: UUID, index: Int, transcript: String, startedAt: Date, speaker: MeetingSpeaker
    ) -> MeetingChunkModel? {
        let result = queue.sync { () -> MeetingChunkModel? in

            // Deduplication Logic
            if speaker == .user {
                if isDuplicate(transcript: transcript, startedAt: startedAt, meetingId: meetingId) {
                    return nil  // Drop this chunk
                }
            }

            // If we are adding a REMOTE chunk, we technically should re-check
            // past USER chunks to retroactive-delete them, but that's harder with append-only.
            // For now, just forward-filtering is a huge win.

            let chunk = MeetingChunkModel(
                id: UUID(), meetingId: meetingId, chunkIndex: index, transcript: transcript,
                startedAt: startedAt, speaker: speaker)
            var arr = chunks[meetingId] ?? []
            arr.append(chunk)

            // Keep sorted
            arr.sort { $0.startedAt < $1.startedAt }

            chunks[meetingId] = arr

            // Backward check: New REMOTE chunk vs existing USER chunks
            if speaker == .remote {
                retroactiveDedupe(newRemoteChunk: chunk, meetingId: meetingId)
            }

            return chunk
        }
        // Only save if we actually added a chunk
        if result != nil {
            save()
        }
        return result
    }

    func listMeetings() -> [MeetingModel] {
        return queue.sync { Array(meetings.values).sorted { $0.startTime > $1.startTime } }
    }

    func getChunks(meetingId: UUID) -> [MeetingChunkModel] {  // ← ADD THIS METHOD
        return queue.sync {
            (chunks[meetingId] ?? [])
                .sorted { $0.startedAt < $1.startedAt }
        }
    }

    func getFullTranscript(meetingId: UUID) -> String {
        return queue.sync {
            (chunks[meetingId] ?? [])
                .sorted { $0.startedAt < $1.startedAt }
                .map { $0.transcript }
                .joined(separator: " ")
        }
    }

    func updateMeetingTitle(meetingId: UUID, title: String) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.title = title
            meeting.updatedAt = Date()
            meetings[meetingId] = meeting
        }
        save()
    }

    func updateMeetingNotes(meetingId: UUID, notes: String) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.notes = notes
            meeting.updatedAt = Date()
            meetings[meetingId] = meeting
        }
        save()
    }

    func updateMeetingUserNotes(meetingId: UUID, userNotes: String) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.userNotes = userNotes
            meeting.updatedAt = Date()
            meetings[meetingId] = meeting
        }
        save()
    }

    func updateMeetingActionItems(meetingId: UUID, actionItems: [StoredActionItem]) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.actionItems = actionItems
            meeting.updatedAt = Date()
            meetings[meetingId] = meeting
        }
        save()
    }

    func markMeetingSynced(meetingId: UUID) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.syncedAt = Date()
            meetings[meetingId] = meeting
        }
        save()
    }

    // text cleaning for fuzzy match
    private func normalize(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Set(cleaned)
    }

    private func retroactiveDedupe(newRemoteChunk: MeetingChunkModel, meetingId: UUID) {
        guard var arr = chunks[meetingId] else { return }

        var indicesToRemove: [Int] = []

        // Look for user chunks that happened around the same time
        for (i, existing) in arr.enumerated() {
            if existing.speaker == .user
                && abs(existing.startedAt.timeIntervalSince(newRemoteChunk.startedAt)) < 5.0
            {

                // Check overlap
                let userWords = normalize(existing.transcript)
                let remoteWords = normalize(newRemoteChunk.transcript)
                let common = userWords.intersection(remoteWords)

                if Double(common.count) / Double(userWords.count) > 0.6 {
                    NSLog(
                        "[MeetingRepo] Retro-dropped user chunk #\(existing.chunkIndex): matches new remote chunk"
                    )
                    indicesToRemove.append(i)
                }
            }
        }

        // Remove duplicates (reverse order to keep indices valid)
        for i in indicesToRemove.reversed() {
            arr.remove(at: i)
        }
        chunks[meetingId] = arr
    }

    // Check overlap
    private func isDuplicate(transcript: String, startedAt: Date, meetingId: UUID) -> Bool {
        guard let chunks = chunks[meetingId] else { return false }

        // Look for remote chunks within ±5 seconds
        let candidates = chunks.filter { existing in
            existing.speaker == .remote
                && abs(existing.startedAt.timeIntervalSince(startedAt)) < 5.0
        }

        let userWords = normalize(transcript)
        if userWords.isEmpty { return false }  // Keep silence/noise? Or drop?

        for candidate in candidates {
            let remoteWords = normalize(candidate.transcript)
            let common = userWords.intersection(remoteWords)

            // If > 60% of user words are in the remote chunk → it's bleed
            if Double(common.count) / Double(userWords.count) > 0.6 {
                NSLog(
                    "[MeetingRepo] Dropped duplicate user chunk: '\(transcript)' matches remote: '\(candidate.transcript)'"
                )
                return true
            }
        }

        return false
    }

    /// Called on app launch to close any meetings that were left open due to crash/force quit
    func cleanupOrphanedMeetings() {
        queue.sync {
            let now = Date()
            var didChange = false

            for (id, meeting) in meetings {
                // If meeting has no endTime and started more than 1 minute ago, close it
                if meeting.endTime == nil && now.timeIntervalSince(meeting.startTime) > 60 {
                    var updated = meeting
                    updated.endTime = meeting.updatedAt  // Use last update time as end time
                    updated.updatedAt = now
                    meetings[id] = updated
                    didChange = true
                    NSLog("[Meetings] Cleaned up orphaned meeting: \(meeting.title)")
                }
            }

            if didChange {
                // Trigger save outside sync
            }
        }
        if meetings.values.contains(where: { $0.endTime == nil }) == false {
            save()
        }
    }

    /// Force-end a specific meeting (used on app termination)
    func endMeetingIfActive(id: UUID) {
        queue.sync {
            guard var meeting = meetings[id], meeting.endTime == nil else { return }
            meeting.endTime = Date()
            meeting.updatedAt = Date()
            meetings[id] = meeting
        }
        save()
    }

    func deleteMeeting(id: UUID) {
        queue.sync {
            meetings.removeValue(forKey: id)
            chunks.removeValue(forKey: id)
            NSLog("[Meetings] Deleted meeting with ID: \(id)")
        }
        save()
    }

    /// Returns meetings that have ended but haven't been synced, or were updated after last sync
    func getUnsyncedMeetings() -> [MeetingModel] {
        return queue.sync {
            Array(meetings.values).filter { meeting in
                // Must have ended
                guard meeting.endTime != nil else { return false }
                // Never synced, or updated after sync
                guard let syncedAt = meeting.syncedAt else { return true }
                return meeting.updatedAt > syncedAt
            }
        }
    }
}
