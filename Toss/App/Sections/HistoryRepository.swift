import Foundation

struct ThreadModel: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var lastMessageAt: Date
    var createdAt: Date
    var updatedAt: Date
}

enum MessageRole: String, Codable { case user, assistant, system, tool, action }
enum MessageStatus: String, Codable { case draft, streaming, final, error }

struct MessageModel: Identifiable, Equatable, Codable {
    let id: UUID
    let threadId: UUID
    let role: MessageRole
    var content: String
    var status: MessageStatus
    var createdAt: Date
    var updatedAt: Date
}

protocol HistoryRepositoryProtocol {
    func upsertThread(title: String) -> ThreadModel
    func appendMessage(threadId: UUID, role: MessageRole, content: String, status: MessageStatus)
        -> MessageModel
    func listThreads() -> [ThreadModel]
    func listMessages(threadId: UUID) -> [MessageModel]
    func clear()
}

final class PersistentHistoryRepository: HistoryRepositoryProtocol {
    private var threads: [UUID: ThreadModel] = [:]
    private var messages: [UUID: [MessageModel]] = [:]
    private let queue = DispatchQueue(label: "history.repo.queue", qos: .userInitiated)
    private var defaultThreadId: UUID?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let tossDir = appSupport.appendingPathComponent("ai.toss.mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: tossDir, withIntermediateDirectories: true)
        self.fileURL = tossDir.appendingPathComponent("history.json")
        load()
    }

    private func load() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(StorageFormat.self, from: data)
                self.threads = Dictionary(uniqueKeysWithValues: decoded.threads.map { ($0.id, $0) })
                self.messages = decoded.messages
                self.defaultThreadId = decoded.defaultThreadId
                NSLog(
                    "[History] Loaded \(threads.count) threads, \(messages.values.flatMap { $0 }.count) messages"
                )
            } catch {
                NSLog("[History] Load error: \(error)")
            }
        }
    }

    private func save() {
        queue.async {
            do {
                let storage = StorageFormat(
                    threads: Array(self.threads.values),
                    messages: self.messages,
                    defaultThreadId: self.defaultThreadId
                )
                let data = try JSONEncoder().encode(storage)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                NSLog("[History] Save error: \(error)")
            }
        }
    }

    func upsertThread(title: String) -> ThreadModel {
        return queue.sync {
            if let id = defaultThreadId, let existing = threads[id] {
                return existing
            }
            let now = Date()
            let id = UUID()
            let thread = ThreadModel(
                id: id, title: title, lastMessageAt: now, createdAt: now, updatedAt: now)
            threads[id] = thread
            defaultThreadId = id
            save()
            return thread
        }
    }

    func appendMessage(threadId: UUID, role: MessageRole, content: String, status: MessageStatus)
        -> MessageModel
    {
        return queue.sync {
            let now = Date()
            var thread =
                threads[threadId]
                ?? ThreadModel(
                    id: threadId, title: "Quick Dictations", lastMessageAt: now, createdAt: now,
                    updatedAt: now)
            thread.lastMessageAt = now
            thread.updatedAt = now
            threads[threadId] = thread
            let msg = MessageModel(
                id: UUID(), threadId: threadId, role: role, content: content, status: status,
                createdAt: now, updatedAt: now)
            var arr = messages[threadId] ?? []
            arr.append(msg)
            messages[threadId] = arr
            save()
            return msg
        }
    }

    func listThreads() -> [ThreadModel] {
        return queue.sync { threads.values.sorted { $0.lastMessageAt > $1.lastMessageAt } }
    }

    func listMessages(threadId: UUID) -> [MessageModel] {
        return queue.sync { messages[threadId] ?? [] }
    }

    func clear() {
        queue.sync {
            threads.removeAll()
            messages.removeAll()
            defaultThreadId = nil
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[History] Cleared all data")
        }
    }

    private struct StorageFormat: Codable {
        let threads: [ThreadModel]
        let messages: [UUID: [MessageModel]]
        let defaultThreadId: UUID?
    }
}

enum History {
    static let shared = PersistentHistoryRepository()
}
