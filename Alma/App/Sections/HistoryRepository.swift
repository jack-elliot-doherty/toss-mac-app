import Foundation

struct ThreadModel: Identifiable, Equatable {
    let id: UUID
    var title: String
    var lastMessageAt: Date
    var createdAt: Date
    var updatedAt: Date
}

enum MessageRole: String { case user, assistant, system, tool, action }
enum MessageStatus: String { case draft, streaming, final, error }

struct MessageModel: Identifiable, Equatable {
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
}

final class InMemoryHistoryRepository: HistoryRepositoryProtocol {
    private var threads: [UUID: ThreadModel] = [:]
    private var messages: [UUID: [MessageModel]] = [:]
    private let queue = DispatchQueue(label: "history.repo.queue", qos: .userInitiated)
    private var defaultThreadId: UUID?

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
            return msg
        }
    }

    func listThreads() -> [ThreadModel] {
        return queue.sync { threads.values.sorted { $0.lastMessageAt > $1.lastMessageAt } }
    }

    func listMessages(threadId: UUID) -> [MessageModel] {
        return queue.sync { messages[threadId] ?? [] }
    }
}

enum History {
    static let shared = InMemoryHistoryRepository()
}
