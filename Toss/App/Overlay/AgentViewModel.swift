import Foundation
import SwiftUI

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var pendingToolCalls: [ToolCall] = []
    @Published var executingTools: [ExecutingTool] = []  // For read-only tool badges
    @Published var isProcessing: Bool = false
    @Published var isStreaming: Bool = false  // NEW: true when receiving tokens
    @Published var errorMessage: String?

    struct ExecutingTool: Identifiable, Equatable {
        let id: String
        let name: String
        var isComplete: Bool = false
    }

    struct DisplayMessage: Identifiable, Equatable {
        let id: UUID
        let role: MessageRole
        var content: String  // Mutable for streaming
        let timestamp: Date
    }

    private let api = AgentAPI.shared
    private let auth: AuthManager
    private let streamParser = AgentStreamParser()
    private var threadId: UUID?
    private var currentAssistantMessage: DisplayMessage?

    init(auth: AuthManager) {
        self.auth = auth
    }

    func startConversation(with initialMessage: String) {
        // Clear any previous session first
        clearConversation()

        threadId = UUID()

        // Send to agent
        Task {
            await sendMessageStreaming(initialMessage)
        }
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        Task {
            await sendMessageStreaming(text)
        }
    }

    // MARK: - Streaming Support

    /// Send message using new streaming endpoint
    func sendMessageStreaming(_ text: String) async {
        guard !text.isEmpty else { return }

        // Add user message
        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMsg)

        isProcessing = true
        errorMessage = nil

        // Build messages array for API
        let apiMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        do {
            try await streamFromAgent(messages: apiMessages)
        } catch {
            errorMessage = error.localizedDescription
            NSLog("[AgentViewModel] Streaming error: \(error)")
        }

        isProcessing = false
    }

    func clearConversation() {
        messages.removeAll()
        pendingToolCalls.removeAll()
        executingTools.removeAll()  // Clear these too
        threadId = nil
        isProcessing = false
        isStreaming = false  // Reset this too
        errorMessage = nil
        currentAssistantMessage = nil
    }

    private struct StreamRequest: Codable {
        let messages: [Message]

        struct Message: Codable {
            let id: String
            let role: String
            let parts: [Part]
        }

        struct Part: Codable {
            let type: String
            let text: String
        }
    }

    private func streamFromAgent(messages: [[String: String]]) async throws {
        guard let token = auth.accessToken else {
            throw NSError(
                domain: "AgentViewModel", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        let url = URL(string: "\(Config.serverURL)/agent/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Map the dictionary array to the encodable struct
        let requestMessages = messages.map { dict in
            StreamRequest.Message(
                id: UUID().uuidString,
                role: dict["role"] ?? "user",
                parts: [
                    StreamRequest.Part(
                        type: "text",
                        text: dict["content"] ?? ""
                    )
                ]
            )
        }

        let payload = StreamRequest(messages: requestMessages)
        let jsonData = try JSONEncoder().encode(payload)

        // Debug log to verify payload
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            NSLog("[AgentViewModel] JSON Body: %@", jsonString)
        }

        request.httpBody = jsonData

        // Stream events
        for try await event in streamParser.streamEvents(from: request) {
            await handleStreamEvent(event)
        }
    }

    private func handleStreamEvent(_ event: AgentStreamEvent) async {
        switch event {
        case .textDelta(let delta):
            appendToCurrentMessage(delta)

        case .textChunk(let chunk):  // NEW: Complete text chunks from agent steps
            appendToCurrentMessage(chunk)

        case .toolExecuting(let id, let name):
            // Tool started - show badge (may be removed if it needs approval)
            if !executingTools.contains(where: { $0.id == id }) {
                executingTools.append(ExecutingTool(id: id, name: name))
            }

        case .toolCallAwaitingApproval(let toolCall):  // NEW: Native approval from v6
            NSLog("[AgentViewModel] Tool awaiting approval: \(toolCall.name)")

            // REMOVE from executing tools - it needs approval, not a badge
            executingTools.removeAll { $0.id == toolCall.id }

            // Add to pending approval (show card)
            var mutableToolCall = toolCall
            mutableToolCall.status = .awaitingApproval
            pendingToolCalls.append(mutableToolCall)

            let msg = DisplayMessage(
                id: UUID(),
                role: .system,
                content: "⏸️ Waiting for approval: \(toolCall.displayName)",
                timestamp: Date()
            )
            messages.append(msg)

        case .toolCallApproved(let id):  // NEW: Server confirmed approval
            NSLog("[AgentViewModel] Tool approved by server: \(id)")
            if let index = pendingToolCalls.firstIndex(where: { $0.id == id }) {
                var toolCall = pendingToolCalls[index]
                toolCall.status = .executing
                pendingToolCalls[index] = toolCall
            }

        case .toolCallRejected(let id):  // NEW: Server confirmed rejection
            NSLog("[AgentViewModel] Tool rejected by server: \(id)")
            if let index = pendingToolCalls.firstIndex(where: { $0.id == id }) {
                pendingToolCalls.remove(at: index)
            }

        case .toolResult(let id, let result):
            NSLog("[AgentViewModel] Tool result: \(id)")

            // Remove from pending approval cards
            pendingToolCalls.removeAll { $0.id == id }

            // Mark executing tool as complete, then remove
            if let index = executingTools.firstIndex(where: { $0.id == id }) {
                executingTools[index].isComplete = true
                let toolId = id
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    executingTools.removeAll { $0.id == toolId }
                }
            }
        // Don't add raw JSON as system message

        case .agentStepFinish(let stepNumber):  // NEW: Agent step completed
            NSLog("[AgentViewModel] Agent step \(stepNumber) finished")
            finalizeCurrentMessage()

        case .done:
            NSLog("[AgentViewModel] Stream complete")
            finalizeCurrentMessage()
            NotificationCenter.default.post(
                name: NSNotification.Name("AgentMessagesChanged"), object: nil)

        case .error(let error):
            errorMessage = error
            NSLog("[AgentViewModel] Stream error: \(error)")

        }
    }

    private func appendToCurrentMessage(_ delta: String) {
        // Mark as streaming on first delta
        if !isStreaming {
            isStreaming = true
        }

        if var current = currentAssistantMessage {
            // Update existing message
            current.content += delta
            currentAssistantMessage = current

            // Update in messages array
            if let index = messages.firstIndex(where: { $0.id == current.id }) {
                messages[index] = current
            }
        } else {
            // Create new message
            let newMsg = DisplayMessage(
                id: UUID(),
                role: .assistant,
                content: delta,
                timestamp: Date()
            )
            currentAssistantMessage = newMsg
            messages.append(newMsg)
        }
    }

    private func finalizeCurrentMessage() {
        currentAssistantMessage = nil
        isStreaming = false  // Reset when done
    }

    // MARK: - Tool Approval

    func approveToolCall(_ toolCall: ToolCall) async {
        guard let index = pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) else {
            return
        }

        // Update UI immediately
        var mutableToolCall = toolCall
        mutableToolCall.status = .executing
        pendingToolCalls[index] = mutableToolCall

        // Send approval to server to execute tool manually
        do {
            let args = toolCall.arguments
            try await sendToolApproval(
                toolCallId: toolCall.id,
                toolName: toolCall.name,
                arguments: args,
                approved: true
            )
            NSLog("[AgentViewModel] Sent approval for: \(toolCall.name)")

            // Since we executed manually, mark complete
            // Wait a bit to show "executing" state
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let idx = self.pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) {
                var completedCall = self.pendingToolCalls[idx]
                completedCall.status = .completed(result: "Executed")
                self.pendingToolCalls[idx] = completedCall

                // Remove after delay
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if let i = self.pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) {
                        self.pendingToolCalls.remove(at: i)
                    }
                }
            }

            // Add system message
            let msg = DisplayMessage(
                id: UUID(),
                role: .system,
                content: "✅ Action completed",
                timestamp: Date()
            )
            messages.append(msg)

        } catch {
            errorMessage = "Failed to approve tool: \(error.localizedDescription)"
            // Revert status
            mutableToolCall.status = .failed(error: error.localizedDescription)
            pendingToolCalls[index] = mutableToolCall
        }
    }

    func rejectToolCall(_ toolCall: ToolCall) {
        guard let index = pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) else {
            return
        }

        // Remove from UI
        pendingToolCalls.remove(at: index)

        // Send rejection to server (just logging)
        Task {
            do {
                try await sendToolApproval(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: [:],
                    approved: false
                )
                NSLog("[AgentViewModel] Sent rejection for: \(toolCall.name)")
            } catch {
                errorMessage = "Failed to reject tool: \(error.localizedDescription)"
            }
        }
    }

    private func sendToolApproval(
        toolCallId: String,
        toolName: String,
        arguments: [String: AnyCodable],
        approved: Bool
    ) async throws {
        guard let token = auth.accessToken else {
            throw NSError(
                domain: "AgentViewModel", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        let url = URL(string: "\(Config.serverURL)/agent/approve-tool")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Convert arguments to pure JSON dictionary
        let argsDict = arguments.mapValues { $0.value }

        let body: [String: Any] = [
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argsDict,
            "approved": approved,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw NSError(
                domain: "AgentViewModel", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }
    }
}
