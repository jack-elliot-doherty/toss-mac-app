import Combine
import Foundation

enum MeetingSpeaker: String, Codable, CaseIterable {
    case user
    case remote
}

struct MeetingModel: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var createdAt: Date
    var updatedAt: Date
    var notes: String = ""
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
    func createMeeting(id: UUID, title: String) -> MeetingModel
    func endMeeting(id: UUID)
    func getMeeting(id: UUID) -> MeetingModel?
    func appendChunk(
        meetingId: UUID, index: Int, transcript: String, startedAt: Date, speaker: MeetingSpeaker
    ) -> MeetingChunkModel
    func listMeetings() -> [MeetingModel]
    func getChunks(meetingId: UUID) -> [MeetingChunkModel]
    func getFullTranscript(meetingId: UUID) -> String
    func updateMeetingTitle(meetingId: UUID, title: String)
    func updateMeetingNotes(meetingId: UUID, notes: String)
}

final class PersistentMeetingRepository: MeetingRepositoryProtocol, ObservableObject {
    @Published private var meetings: [UUID: MeetingModel] = [:]
    @Published private var chunks: [UUID: [MeetingChunkModel]] = [:]
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

    func createMeeting(id: UUID, title: String) -> MeetingModel {
        return queue.sync {
            let now = Date()
            let meeting = MeetingModel(
                id: id, title: title, startTime: now, endTime: nil, createdAt: now,
                updatedAt: now)
            meetings[meeting.id] = meeting
            chunks[meeting.id] = []
            save()
            return meeting
        }
    }

    func endMeeting(id: UUID) {
        queue.sync {
            guard var meeting = meetings[id] else { return }
            meeting.endTime = Date()
            meeting.updatedAt = Date()
            meetings[id] = meeting
            save()
        }
    }

    func getMeeting(id: UUID) -> MeetingModel? {
        return queue.sync { meetings[id] }
    }

    func appendChunk(
        meetingId: UUID, index: Int, transcript: String, startedAt: Date, speaker: MeetingSpeaker
    ) -> MeetingChunkModel {
        return queue.sync {
            let chunk = MeetingChunkModel(
                id: UUID(), meetingId: meetingId, chunkIndex: index, transcript: transcript,
                startedAt: startedAt, speaker: speaker)
            var arr = chunks[meetingId] ?? []
            arr.append(chunk)
            chunks[meetingId] = arr
            save()
            return chunk
        }
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
            save()
        }
    }

    func updateMeetingNotes(meetingId: UUID, notes: String) {
        queue.sync {
            guard var meeting = meetings[meetingId] else { return }
            meeting.notes = notes
            meeting.updatedAt = Date()
            meetings[meetingId] = meeting
            save()
        }
    }
}
