import Foundation
import SwiftUI

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var pendingToolCalls: [ToolCall] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

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
        threadId = UUID()

        // Add user message
        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: initialMessage,
            timestamp: Date()
        )
        messages.append(userMsg)

        // Send to agent
        sendToAgent(initialMessage)
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMsg)

        NotificationCenter.default.post(
            name: NSNotification.Name("AgentMessagesChanged"), object: nil)

        sendToAgent(text)

    }

    private func sendToAgent(_ message: String) {
        isProcessing = true
        errorMessage = nil

        // Build history for context
        let history = messages.dropLast().map { msg in
            AgentRequest.ChatMessage(
                role: msg.role.rawValue,
                content: msg.content
            )
        }

        let token = auth.accessToken

        api.sendMessage(
            message, threadId: threadId?.uuidString, history: Array(history), token: token
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isProcessing = false

                switch result {
                case .success(let response):
                    let assistantMsg = DisplayMessage(
                        id: UUID(),
                        role: .assistant,
                        content: response.response,
                        timestamp: Date()
                    )
                    self.messages.append(assistantMsg)

                    // Handle actions if any
                    if !response.actions.isEmpty {
                        NSLog(
                            "[AgentViewModel] Actions to perform: %@",
                            response.actions.joined(separator: ", "))
                        // TODO: Execute actions
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    NSLog("[AgentViewModel] Error: %@", error.localizedDescription)
                }
            }
        }
    }

    func clearConversation() {
        messages.removeAll()
        pendingToolCalls.removeAll()
        threadId = nil
        isProcessing = false
        errorMessage = nil
        currentAssistantMessage = nil
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

        let body = ["messages": messages]
        request.httpBody = try JSONEncoder().encode(body)

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

        case .toolCallAwaitingApproval(let toolCall):  // NEW: Native approval from v6
            NSLog("[AgentViewModel] Tool awaiting approval: \(toolCall.name)")

            // Server is paused - always add to pending
            var mutableToolCall = toolCall
            mutableToolCall.status = .awaitingApproval
            pendingToolCalls.append(mutableToolCall)

            // Add system message indicating we're waiting
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
            NSLog("[AgentViewModel] Tool result: \(id) - \(result)")

            // Remove from pending
            if let index = pendingToolCalls.firstIndex(where: { $0.id == id }) {
                var toolCall = pendingToolCalls[index]
                toolCall.status = .completed(result: result)
                pendingToolCalls[index] = toolCall

                // Remove after brief display
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let idx = self.pendingToolCalls.firstIndex(where: { $0.id == id }) {
                        self.pendingToolCalls.remove(at: idx)
                    }
                }
            }

            // Add result message
            let msg = DisplayMessage(
                id: UUID(),
                role: .system,
                content: "✅ \(result)",
                timestamp: Date()
            )
            messages.append(msg)

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

        // Send approval to server to continue stream
        do {
            try await sendToolApproval(toolCallId: toolCall.id, approved: true)
            NSLog("[AgentViewModel] Sent approval for: \(toolCall.name)")
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

        // Send rejection to server
        Task {
            do {
                try await sendToolApproval(toolCallId: toolCall.id, approved: false)
                NSLog("[AgentViewModel] Sent rejection for: \(toolCall.name)")
            } catch {
                errorMessage = "Failed to reject tool: \(error.localizedDescription)"
            }
        }
    }

    private func sendToolApproval(toolCallId: String, approved: Bool) async throws {
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

        let body =
            [
                "toolCallId": toolCallId,
                "approved": approved,
            ] as [String: Any]

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
