import Foundation

struct MeetingModel: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct MeetingChunkModel: Identifiable, Equatable, Codable {
    let id: UUID
    let meetingId: UUID
    let chunkIndex: Int
    var transcript: String
    let timestamp: Date
}

protocol MeetingRepositoryProtocol {
    func createMeeting(title: String) -> MeetingModel
    func endMeeting(id: UUID)
    func getMeeting(id: UUID) -> MeetingModel?
    func appendChunk(meetingId: UUID, index: Int, transcript: String) -> MeetingChunkModel
    func listMeetings() -> [MeetingModel]
    func getFullTranscript(meetingId: UUID) -> String
}

final class PersistentMeetingRepository: MeetingRepositoryProtocol {
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
        queue.async {
            do {
                let storage = StorageFormat(
                    meetings: Array(self.meetings.values), chunks: self.chunks)
                let data = try JSONEncoder().encode(storage)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                NSLog("[Meetings] Save error: \(error)")
            }
        }
    }

    func createMeeting(title: String) -> MeetingModel {
        return queue.sync {
            let now = Date()
            let meeting = MeetingModel(
                id: UUID(), title: title, startTime: now, endTime: nil, createdAt: now,
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

    func appendChunk(meetingId: UUID, index: Int, transcript: String) -> MeetingChunkModel {
        return queue.sync {
            let chunk = MeetingChunkModel(
                id: UUID(), meetingId: meetingId, chunkIndex: index, transcript: transcript,
                timestamp: Date())
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

    func getFullTranscript(meetingId: UUID) -> String {
        return queue.sync {
            (chunks[meetingId] ?? [])
                .sorted { $0.chunkIndex < $1.chunkIndex }
                .map { $0.transcript }
                .joined(separator: " ")
        }
    }
}
