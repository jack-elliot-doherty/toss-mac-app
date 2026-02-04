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
    @Published var isCompactMode: Bool = false  // Just input field, no header/messages

    /// Returns only the first tool awaiting approval (for sequential UX)
    /// We show one approval card at a time to avoid scroll chaos and match natural workflow
    var currentPendingApproval: ToolCall? {
        pendingToolCalls.first {
            if case .awaitingApproval = $0.status { return true }
            return false
        }
    }

    struct ExecutingTool: Identifiable, Equatable {
        let id: String
        let name: String
        var arguments: [String: Any] = [:]
        var result: [String: Any]?
        var isComplete: Bool = false

        static func == (lhs: ExecutingTool, rhs: ExecutingTool) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.isComplete == rhs.isComplete
        }
    }

    struct DisplayMessage: Identifiable, Equatable {
        let id: UUID
        let role: MessageRole
        var content: String  // Mutable for streaming
        let timestamp: Date
        // Tool call info (for assistant messages that invoke tools)
        var toolCall: ToolCallInfo? = nil
        // Tool result info (for tool response messages)
        var toolResult: ToolResultInfo? = nil
        // Memory save info (for inline memory notifications)
        var isMemorySave: Bool = false
        var memoryDetails: [String: Any]? = nil
        // Tool execution info (for persisted read tool notifications)
        var isToolExecution: Bool = false
        var toolExecutionId: String? = nil
        var toolExecutionName: String? = nil
        var toolExecutionArgs: [String: Any]? = nil
        var toolExecutionResult: [String: Any]? = nil
        var toolExecutionComplete: Bool = false
        // Tool approval waiting info (for subtle approval notifications)
        var isToolApprovalWaiting: Bool = false
        // Clipboard context was included with this message
        var hasClipboardContext: Bool = false

        static func == (lhs: DisplayMessage, rhs: DisplayMessage) -> Bool {
            lhs.id == rhs.id && lhs.role == rhs.role && lhs.content == rhs.content
                && lhs.isMemorySave == rhs.isMemorySave
                && lhs.isToolExecution == rhs.isToolExecution
                && lhs.toolExecutionComplete == rhs.toolExecutionComplete
                && lhs.isToolApprovalWaiting == rhs.isToolApprovalWaiting
                && lhs.hasClipboardContext == rhs.hasClipboardContext
        }
    }

    // Info about a tool call made by the assistant
    struct ToolCallInfo: Equatable {
        let toolCallId: String
        let toolName: String
        let arguments: [String: Any]

        static func == (lhs: ToolCallInfo, rhs: ToolCallInfo) -> Bool {
            lhs.toolCallId == rhs.toolCallId && lhs.toolName == rhs.toolName
        }
    }

    // Info about a tool result
    struct ToolResultInfo: Equatable {
        let toolCallId: String
        let result: [String: Any]

        static func == (lhs: ToolResultInfo, rhs: ToolResultInfo) -> Bool {
            lhs.toolCallId == rhs.toolCallId
        }
    }

    private let api = AgentAPI.shared
    private let auth: AuthManager
    private let streamParser = AgentStreamParser()
    private var threadId: UUID?
    private var serverConversationId: String?  // Server-assigned conversation ID for persistence
    private var currentAssistantMessage: DisplayMessage?
    private var currentStreamTask: Task<Void, Error>?  // Track current streaming task for cancellation

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

    /// Cancel the current streaming request
    func cancelCurrentRequest() {
        NSLog("[AgentViewModel] Cancelling current request")
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isProcessing = false
        isStreaming = false
        finalizeCurrentMessage()
    }

    // MARK: - Streaming Support

    /// Send message using new streaming endpoint
    /// Uses server-side conversation reconstruction - only sends the new message text
    func sendMessageStreaming(_ text: String) async {
        guard !text.isEmpty else { return }

        // Auto-reject any pending tool calls before sending a new message
        // This is required because Claude's API requires tool_result immediately after tool_use
        // If the user sends a follow-up message instead of approving, they're implicitly rejecting
        await autoRejectPendingTools()

        // Check for clipboard context before creating user message
        let clipboard = ClipboardMonitor.shared.getFreshClipboard(maxAge: 90)
        let hasClipboard = clipboard != nil

        // Add user message to local display
        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: text,
            timestamp: Date(),
            hasClipboardContext: hasClipboard
        )
        messages.append(userMsg)

        isProcessing = true
        errorMessage = nil

        // Store task for cancellation support
        currentStreamTask = Task {
            // Use new server format: just send message text, server reconstructs history from DB
            try await streamMessageToServer(text, clipboard: clipboard)
        }

        do {
            try await currentStreamTask?.value
        } catch is CancellationError {
            NSLog("[AgentViewModel] Stream cancelled by user")
        } catch {
            errorMessage = error.localizedDescription
            NSLog("[AgentViewModel] Streaming error: \(error)")
        }

        currentStreamTask = nil
        isProcessing = false
    }

    /// Auto-reject all pending tool calls
    /// Called when user sends a follow-up message instead of approving/rejecting tools
    private func autoRejectPendingTools() async {
        let toolsToReject = pendingToolCalls.filter {
            if case .awaitingApproval = $0.status { return true }
            return false
        }

        guard !toolsToReject.isEmpty else { return }

        NSLog("[AgentViewModel] Auto-rejecting \(toolsToReject.count) pending tool(s) before new message")

        for toolCall in toolsToReject {
            // Remove from pending UI list
            pendingToolCalls.removeAll { $0.id == toolCall.id }

            // Send rejection to server (fire and forget - don't block on errors)
            do {
                try await sendToolApproval(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: [:],
                    approved: false
                )
                NSLog("[AgentViewModel] Auto-rejected tool: \(toolCall.name)")

                // Convert arguments to [String: Any]
                let argsDict = toolCall.arguments.mapValues { $0.value }

                // Add rejection result to messages (for history)
                let toolMessage = DisplayMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "",
                    timestamp: Date(),
                    toolCall: ToolCallInfo(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        arguments: argsDict
                    ),
                    toolResult: ToolResultInfo(
                        toolCallId: toolCall.id,
                        result: ["rejected": true, "reason": "User sent follow-up message"]
                    )
                )
                messages.append(toolMessage)

                // Update the "waiting for approval" message if it exists
                if let waitingMsgIndex = messages.firstIndex(where: {
                    $0.toolExecutionId == toolCall.id && $0.isToolApprovalWaiting
                }) {
                    messages[waitingMsgIndex].toolExecutionComplete = true
                    messages[waitingMsgIndex].toolExecutionResult = ["rejected": true]
                }
            } catch {
                NSLog("[AgentViewModel] Failed to auto-reject tool \(toolCall.name): \(error)")
                // Continue anyway - we don't want to block the user's message
            }
        }
    }

    /// Send a single message to server using new format
    /// Server reconstructs conversation history from database
    private func streamMessageToServer(_ messageText: String, clipboard: (content: String, ageSeconds: Int)?) async throws {
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

        // Build payload with just the message text (server reconstructs history from DB)
        var payload: [String: Any] = ["message": messageText]

        if let conversationId = serverConversationId {
            payload["conversationId"] = conversationId
            NSLog("[AgentViewModel] Sending message with conversationId: %@", conversationId)
        }

        // Include fresh clipboard context if available
        if let clipboard = clipboard {
            payload["clipboardContext"] = [
                "content": clipboard.content,
                "ageSeconds": clipboard.ageSeconds
            ]
            NSLog("[AgentViewModel] Including clipboard context (%d chars, %ds old)", clipboard.content.count, clipboard.ageSeconds)
            // Mark clipboard as consumed so it won't be sent with subsequent messages
            ClipboardMonitor.shared.markClipboardConsumed()
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        // Debug log
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            let truncated =
                jsonString.count > 500
                ? String(jsonString.prefix(500)) + "... [truncated]"
                : jsonString
            NSLog("[AgentViewModel] JSON Body (new format): %@", truncated)
        }

        request.httpBody = jsonData

        // Stream events and capture conversation ID from response
        let streamResult = try await streamParser.streamEvents(from: request)

        // Store conversation ID from server (only on first message of conversation)
        if serverConversationId == nil, let newConversationId = streamResult.conversationId {
            serverConversationId = newConversationId
            NSLog("[AgentViewModel] Stored new conversationId: %@", newConversationId)
        }

        for try await event in streamResult.events {
            await handleStreamEvent(event)
        }
    }

    func clearConversation() {
        messages.removeAll()
        pendingToolCalls.removeAll()
        executingTools.removeAll()
        threadId = nil
        serverConversationId = nil  // Clear server conversation ID
        isProcessing = false
        isStreaming = false
        errorMessage = nil
        currentAssistantMessage = nil
        isCompactMode = false
    }

    // MARK: - Retry & Edit (Branch from here)

    /// Retry from a specific message - truncates conversation and regenerates
    /// - If assistant message: remove it and all after, resend the previous user message
    /// - If user message: remove all messages from here (inclusive), resend this user message
    func retryFromMessage(_ messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            NSLog("[AgentViewModel] retryFromMessage: message not found")
            return
        }

        let targetMessage = messages[index]

        if targetMessage.role == .assistant {
            // Find the previous user message to resend
            var userMessageContent: String?
            for i in stride(from: index - 1, through: 0, by: -1) {
                if messages[i].role == .user && !messages[i].content.isEmpty {
                    userMessageContent = messages[i].content
                    break
                }
            }

            guard let content = userMessageContent else {
                NSLog(
                    "[AgentViewModel] retryFromMessage: no user message found before assistant message"
                )
                return
            }

            // Truncate from the assistant message onwards
            messages.removeSubrange(index...)
            pendingToolCalls.removeAll()
            executingTools.removeAll()
            currentAssistantMessage = nil
            errorMessage = nil

            // Resend the user's message (don't add it again, it's already there)
            Task {
                await resendLastUserMessage()
            }
        } else if targetMessage.role == .user {
            let content = targetMessage.content

            // Truncate from this message onwards (including this message)
            messages.removeSubrange(index...)
            pendingToolCalls.removeAll()
            executingTools.removeAll()
            currentAssistantMessage = nil
            errorMessage = nil

            // Resend this user message
            Task {
                await sendMessageStreaming(content)
            }
        }
    }

    /// Edit a user message and resubmit - truncates conversation and regenerates with new content
    func editAndResend(messageId: UUID, newContent: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            NSLog("[AgentViewModel] editAndResend: message not found")
            return
        }

        // Truncate from this message onwards (including this message)
        messages.removeSubrange(index...)
        pendingToolCalls.removeAll()
        executingTools.removeAll()
        currentAssistantMessage = nil
        errorMessage = nil

        // Send the edited content as new message
        Task {
            await sendMessageStreaming(newContent)
        }
    }

    /// Resend by rebuilding messages from existing conversation (no new user message added)
    private func resendLastUserMessage() async {
        isProcessing = true
        errorMessage = nil

        // Build messages array for API using existing messages
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            if msg.role == .system && msg.toolCall == nil { continue }
            if msg.role == .tool { continue }

            if let toolCall = msg.toolCall, let toolResult = msg.toolResult {
                apiMessages.append([
                    "id": msg.id.uuidString,
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-\(toolCall.toolName)",
                            "toolCallId": toolCall.toolCallId,
                            "state": "output-available",
                            "input": toolCall.arguments,
                            "output": toolResult.result,
                        ]
                    ],
                ])
            } else if let toolCall = msg.toolCall {
                apiMessages.append([
                    "id": msg.id.uuidString,
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-\(toolCall.toolName)",
                            "toolCallId": toolCall.toolCallId,
                            "state": "input-available",
                            "input": toolCall.arguments,
                        ]
                    ],
                ])
            } else if !msg.content.isEmpty {
                apiMessages.append([
                    "id": msg.id.uuidString,
                    "role": msg.role.rawValue,
                    "parts": [
                        ["type": "text", "text": msg.content]
                    ],
                ])
            }
        }

        do {
            try await streamFromAgentWithParts(messages: apiMessages)
        } catch {
            errorMessage = error.localizedDescription
            NSLog("[AgentViewModel] Retry error: \(error)")
        }

        isProcessing = false
    }

    /// Continue the agent conversation after all tool executions are complete
    /// Uses continuation format - server reconstructs conversation from DB
    private func streamFromAgentContinuation() async throws {
        guard let token = auth.accessToken else {
            throw NSError(
                domain: "AgentViewModel", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        guard let conversationId = serverConversationId else {
            throw NSError(
                domain: "AgentViewModel", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "No conversation ID for continuation"])
        }

        let url = URL(string: "\(Config.serverURL)/agent/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Use continuation format - server loads conversation history from DB
        let payload: [String: Any] = [
            "continue": true,
            "conversationId": conversationId
        ]

        NSLog("[AgentViewModel] Continuation with conversationId: %@", conversationId)

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData

        // Stream events
        let streamResult = try await streamParser.streamEvents(from: request)

        for try await event in streamResult.events {
            await handleStreamEvent(event)
        }
    }

    private func streamFromAgentWithParts(messages: [[String: Any]]) async throws {
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

        // Build payload with messages and optional conversationId
        var payload: [String: Any] = ["messages": messages]
        if let conversationId = serverConversationId {
            payload["conversationId"] = conversationId
            NSLog("[AgentViewModel] Sending with existing conversationId: %@", conversationId)
        }

        // Include fresh clipboard context if available (copied within last 90 seconds)
        if let clipboard = ClipboardMonitor.shared.getFreshClipboard(maxAge: 90) {
            payload["clipboardContext"] = [
                "content": clipboard.content,
                "ageSeconds": clipboard.ageSeconds
            ]
            NSLog("[AgentViewModel] Including clipboard context (%d chars, %ds old)", clipboard.content.count, clipboard.ageSeconds)
            // Mark clipboard as consumed so it won't be sent with subsequent messages
            // (unless the user copies something new)
            ClipboardMonitor.shared.markClipboardConsumed()
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        // Debug log to verify payload (truncated)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            let truncated =
                jsonString.count > 1000
                ? String(jsonString.prefix(1000)) + "... [truncated]"
                : jsonString
            NSLog("[AgentViewModel] JSON Body: %@", truncated)
        }

        request.httpBody = jsonData

        // Stream events and capture conversation ID from response
        let streamResult = try await streamParser.streamEvents(from: request)

        // Store conversation ID from server (only on first message of conversation)
        if serverConversationId == nil, let newConversationId = streamResult.conversationId {
            serverConversationId = newConversationId
            NSLog("[AgentViewModel] Stored new conversationId: %@", newConversationId)
        }

        for try await event in streamResult.events {
            await handleStreamEvent(event)
        }
    }

    private func handleStreamEvent(_ event: AgentStreamEvent) async {
        switch event {
        case .textDelta(let delta):
            appendToCurrentMessage(delta)

        case .textChunk(let chunk):  // NEW: Complete text chunks from agent steps
            appendToCurrentMessage(chunk)

        case .toolExecuting(let id, let name, let arguments):
            // Finalize any in-progress text message so tool appears after it
            // and subsequent text will be in a new message
            finalizeCurrentMessage()

            // Special handling for memory tool - add a persistent inline message
            if name.lowercased().contains("memory") || name.lowercased() == "savememory" {
                let memoryContent =
                    (arguments["memory"] as? String) ?? String(describing: arguments)
                let msg = DisplayMessage(
                    id: UUID(),
                    role: .system,
                    content: "💭 Remembered: \(memoryContent)",
                    timestamp: Date(),
                    isMemorySave: true,
                    memoryDetails: arguments
                )
                messages.append(msg)
            } else {
                // Add persistent tool execution message (will update with result later)
                let msg = DisplayMessage(
                    id: UUID(),
                    role: .system,
                    content: "",
                    timestamp: Date(),
                    isToolExecution: true,
                    toolExecutionId: id,
                    toolExecutionName: name,
                    toolExecutionArgs: arguments,
                    toolExecutionComplete: false
                )
                messages.append(msg)

                // Also add to transient executingTools (may be removed if it needs approval)
                if !executingTools.contains(where: { $0.id == id }) {
                    executingTools.append(ExecutingTool(id: id, name: name, arguments: arguments))
                }

                // Check if this is a client-side tool that should auto-execute
                // Server sets needsApproval: false for these, so no approval event will come
                let tempToolCall = ToolCall(id: id, name: name, arguments: arguments.mapValues { AnyCodable($0) })
                if tempToolCall.isClientSideTool {
                    NSLog("[AgentViewModel] Client-side tool detected, auto-executing: \(name)")
                    Task {
                        await executeClientSideToolDirectly(tempToolCall)
                    }
                }
            }

        case .toolCallAwaitingApproval(let toolCall):  // NEW: Native approval from v6
            NSLog("[AgentViewModel] Tool awaiting approval: \(toolCall.name)")

            // REMOVE from executing tools - it needs approval, not a badge
            executingTools.removeAll { $0.id == toolCall.id }

            // Also remove the persistent tool execution message if one was added
            messages.removeAll { $0.toolExecutionId == toolCall.id }

            // Add to pending approval (show card)
            var mutableToolCall = toolCall
            mutableToolCall.status = .awaitingApproval
            pendingToolCalls.append(mutableToolCall)

            // Add subtle "waiting for approval" message
            let msg = DisplayMessage(
                id: UUID(),
                role: .system,
                content: toolCall.displayName,
                timestamp: Date(),
                isToolExecution: false,
                toolExecutionId: toolCall.id,
                toolExecutionName: toolCall.name,
                toolExecutionArgs: toolCall.arguments.mapValues { $0.value },
                isToolApprovalWaiting: true
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

            // Parse result JSON
            var parsedResult: [String: Any] = [:]
            if let data = result.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                parsedResult = json
            } else {
                parsedResult = ["raw": result]
            }

            // Update persistent tool execution message with result AND add tool result info for API
            if let index = messages.firstIndex(where: { $0.toolExecutionId == id }) {
                messages[index].toolExecutionResult = parsedResult
                messages[index].toolExecutionComplete = true

                // Add tool call/result info so it gets sent to the API on next message
                if let toolName = messages[index].toolExecutionName,
                    let toolArgs = messages[index].toolExecutionArgs
                {
                    messages[index].toolCall = ToolCallInfo(
                        toolCallId: id,
                        toolName: toolName,
                        arguments: toolArgs
                    )
                    messages[index].toolResult = ToolResultInfo(
                        toolCallId: id,
                        result: parsedResult
                    )
                    // Change role to assistant so it gets included in API calls
                    messages[index] = DisplayMessage(
                        id: messages[index].id,
                        role: .assistant,
                        content: "",
                        timestamp: messages[index].timestamp,
                        toolCall: messages[index].toolCall,
                        toolResult: messages[index].toolResult,
                        isToolExecution: true,
                        toolExecutionId: id,
                        toolExecutionName: toolName,
                        toolExecutionArgs: toolArgs,
                        toolExecutionResult: parsedResult,
                        toolExecutionComplete: true
                    )
                }
            }

            // Mark executing tool as complete with result, then remove after delay
            if let index = executingTools.firstIndex(where: { $0.id == id }) {
                executingTools[index].isComplete = true
                executingTools[index].result = parsedResult
                let toolId = id
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // Shorter delay since we have persistent message
                    executingTools.removeAll { $0.id == toolId }
                }
            }

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

    /// Execute a client-side tool directly (for auto-execute scenarios where needsApproval is false)
    /// This is called when we receive tool-input-available for a client-side tool
    private func executeClientSideToolDirectly(_ toolCall: ToolCall) async {
        NSLog("[AgentViewModel] Executing client-side tool directly: \(toolCall.name)")

        do {
            // Execute the tool locally
            let toolResult = await executeClientTool(toolCall)

            // Send result to server
            try await sendToolApproval(
                toolCallId: toolCall.id,
                toolName: toolCall.name,
                arguments: toolCall.arguments,
                approved: true,
                clientResult: toolResult
            )
            NSLog("[AgentViewModel] Sent client tool result for: \(toolCall.name)")

            // Convert arguments to [String: Any]
            let argsDict = toolCall.arguments.mapValues { $0.value }

            // Add the tool result to messages (for history)
            let toolMessage = DisplayMessage(
                id: UUID(),
                role: .assistant,
                content: "",
                timestamp: Date(),
                toolCall: ToolCallInfo(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: argsDict
                ),
                toolResult: ToolResultInfo(
                    toolCallId: toolCall.id,
                    result: toolResult
                )
            )
            messages.append(toolMessage)

            // Update the tool execution message to mark it as complete
            if let msgIndex = messages.firstIndex(where: { $0.toolExecutionId == toolCall.id }) {
                messages[msgIndex].toolExecutionComplete = true
                messages[msgIndex].toolExecutionResult = toolResult
            }

            // Remove from executingTools
            executingTools.removeAll { $0.id == toolCall.id }

            // Continue the conversation with the tool result
            NSLog("[AgentViewModel] Client tool executed, continuing conversation")
            try await streamFromAgentContinuation()

        } catch {
            NSLog("[AgentViewModel] Error executing client-side tool: \(error)")
            errorMessage = "Failed to execute tool: \(error.localizedDescription)"
        }
    }

    func approveToolCall(_ toolCall: ToolCall) async {
        guard let index = pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) else {
            return
        }

        // Update UI immediately
        var mutableToolCall = toolCall
        mutableToolCall.status = .executing
        pendingToolCalls[index] = mutableToolCall

        do {
            var toolResult: [String: Any]

            // Check if this is a client-side tool that needs local execution
            if toolCall.isClientSideTool {
                NSLog("[AgentViewModel] Executing client-side tool: \(toolCall.name)")
                toolResult = await executeClientTool(toolCall)

                // Send approval with client result to server (for logging/analytics)
                try await sendToolApproval(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: toolCall.arguments,
                    approved: true,
                    clientResult: toolResult
                )
                NSLog("[AgentViewModel] Sent client tool result for: \(toolCall.name)")
            } else {
                // Server-side tool - send approval and get result back
                let serverResult = try await sendToolApprovalAndGetResult(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: toolCall.arguments,
                    approved: true
                )
                toolResult = serverResult
                NSLog("[AgentViewModel] Got server tool result for: \(toolCall.name)")
            }

            // Convert arguments to [String: Any]
            let argsDict = toolCall.arguments.mapValues { $0.value }

            // Add the tool result to messages immediately (for history)
            let toolMessage = DisplayMessage(
                id: UUID(),
                role: .assistant,
                content: "",
                timestamp: Date(),
                toolCall: ToolCallInfo(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: argsDict
                ),
                toolResult: ToolResultInfo(
                    toolCallId: toolCall.id,
                    result: toolResult
                )
            )
            messages.append(toolMessage)

            // Update the original "waiting for approval" message to mark it as complete
            if let waitingMsgIndex = messages.firstIndex(where: {
                $0.toolExecutionId == toolCall.id && $0.isToolApprovalWaiting
            }) {
                messages[waitingMsgIndex].toolExecutionComplete = true
                messages[waitingMsgIndex].toolExecutionResult = toolResult
            }

            // Mark complete in UI
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

            // Check if there are more tools still awaiting approval
            let stillPendingApproval = pendingToolCalls.contains {
                if case .awaitingApproval = $0.status { return true }
                return false
            }

            if stillPendingApproval {
                // More tools pending - don't continue conversation yet
                // User needs to approve the remaining tools first
                NSLog(
                    "[AgentViewModel] More tools awaiting approval, not continuing conversation yet"
                )
            } else {
                // All tools approved! Now continue the conversation
                NSLog("[AgentViewModel] All pending tools approved, continuing conversation")
                do {
                    try await streamFromAgentContinuation()
                } catch {
                    errorMessage = error.localizedDescription
                    NSLog("[AgentViewModel] Error continuing after tools: \(error)")
                }
            }

        } catch {
            errorMessage = "Failed to approve tool: \(error.localizedDescription)"
            // Revert status
            mutableToolCall.status = .failed(error: error.localizedDescription)
            pendingToolCalls[index] = mutableToolCall
        }
    }

    // MARK: - Client-Side Tool Execution

    /// Execute a tool that runs locally on the Mac
    private func executeClientTool(_ toolCall: ToolCall) async -> [String: Any] {
        switch toolCall.name {
        case "screenshot":
            return await executeScreenshot(toolCall.arguments)
        case "connectSlack":
            return await executeConnect(provider: "slack", endpoint: "/slack/connect")
        case "connectLinear":
            return await executeConnect(provider: "linear", endpoint: "/linear/connect")
        case "connectGoogleCalendar":
            return await executeConnect(provider: "google", endpoint: "/google/connect")
        default:
            return ["error": "Unknown client tool: \(toolCall.name)"]
        }
    }

    /// Execute a connect tool - opens OAuth flow in browser (or confirms already connected)
    private func executeConnect(provider: String, endpoint: String) async -> [String: Any] {
        // First, check if already connected via IntegrationsManager
        // This handles the case where OAuth was already completed via the UI
        let integrationsManager = IntegrationsManager.shared

        switch provider {
        case "slack":
            if integrationsManager.slackStatus?.connected == true {
                let teamName = integrationsManager.slackStatus?.teamName ?? "your workspace"
                NSLog("[AgentViewModel] \(provider) already connected to \(teamName)")
                return [
                    "success": true,
                    "provider": provider,
                    "connected": true,
                    "teamName": teamName,
                    "message": "Slack is now connected to \(teamName).",
                ]
            }
        case "linear":
            if integrationsManager.linearStatus?.connected == true {
                let orgName =
                    integrationsManager.linearStatus?.organizationName ?? "your organization"
                NSLog("[AgentViewModel] \(provider) already connected to \(orgName)")
                return [
                    "success": true,
                    "provider": provider,
                    "connected": true,
                    "organizationName": orgName,
                    "message": "Linear is now connected to \(orgName).",
                ]
            }
        case "google":
            if integrationsManager.googleStatus?.connected == true {
                let email = integrationsManager.googleStatus?.email ?? "your account"
                NSLog("[AgentViewModel] \(provider) already connected as \(email)")
                return [
                    "success": true,
                    "provider": provider,
                    "connected": true,
                    "email": email,
                    "message": "Google Calendar is now connected as \(email).",
                ]
            }
        default:
            break
        }

        // Not connected yet - initiate OAuth flow
        guard let url = URL(string: "\(Config.serverURL)\(endpoint)") else {
            return ["success": false, "error": "Invalid URL"]
        }

        NSLog("[AgentViewModel] Initiating \(provider) connection")

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                // Open OAuth URL in browser
                await MainActor.run {
                    NSWorkspace.shared.open(authURL)
                }
                NSLog("[AgentViewModel] Opened \(provider) OAuth URL")
                return [
                    "success": true,
                    "provider": provider,
                    "message":
                        "OAuth flow started. Please complete the connection in your browser.",
                ]
            } else {
                return ["success": false, "error": "Failed to get OAuth URL"]
            }
        } catch {
            NSLog("[AgentViewModel] Failed to connect \(provider): \(error)")
            return ["success": false, "error": error.localizedDescription]
        }
    }

    /// Capture a screenshot of the screen or active window, upload to server, return URL
    private func executeScreenshot(_ args: [String: AnyCodable]) async -> [String: Any] {
        let targetString = args.getString("target") ?? "active_window"
        let target: ScreenshotCapture.CaptureTarget =
            targetString == "fullscreen" ? .fullscreen : .activeWindow

        NSLog("[AgentViewModel] Capturing screenshot: \(targetString)")

        let result = await ScreenshotCapture.capture(target: target)

        if result.success, let imageData = result.imageData {
            NSLog(
                "[AgentViewModel] Screenshot captured successfully (\(imageData.count) bytes base64)"
            )

            // Upload to server to get a URL (keeps large base64 out of model context)
            do {
                let uploadResult = try await uploadScreenshot(imageData: imageData)

                var response: [String: Any] = [
                    "success": true,
                    "imageUrl": uploadResult.url,
                ]
                if let windowTitle = result.windowTitle {
                    response["windowTitle"] = windowTitle
                }
                if let appName = result.appName {
                    response["appName"] = appName
                }
                NSLog("[AgentViewModel] Screenshot uploaded: \(uploadResult.url)")
                return response
            } catch {
                NSLog("[AgentViewModel] Screenshot upload failed: \(error)")
                return [
                    "success": false,
                    "error": "Failed to upload screenshot: \(error.localizedDescription)",
                ]
            }
        } else {
            NSLog("[AgentViewModel] Screenshot failed: \(result.error ?? "unknown")")
            return [
                "success": false,
                "error": result.error ?? "Unknown error capturing screenshot",
            ]
        }
    }

    /// Upload screenshot image data to server and return URL
    private func uploadScreenshot(imageData: String) async throws -> (url: String, key: String) {
        guard let token = auth.accessToken else {
            throw NSError(
                domain: "AgentViewModel", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        let url = URL(string: "\(Config.serverURL)/agent/upload-image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "imageData": imageData,
            "contentType": "image/png",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AgentViewModel", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Handle 426 Upgrade Required
        if httpResponse.statusCode == 426 {
            await MainActor.run {
                UpdateManager.shared.handleForceUpdateRequired()
            }
            throw NSError(
                domain: "AgentViewModel", code: 426,
                userInfo: [NSLocalizedDescriptionKey: "Update required"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "AgentViewModel", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(httpResponse.statusCode)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let imageUrl = json["url"] as? String
        else {
            throw NSError(
                domain: "AgentViewModel", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid upload response"])
        }

        let key = json["key"] as? String ?? ""
        return (url: imageUrl, key: key)
    }

    func rejectToolCall(_ toolCall: ToolCall) {
        guard let index = pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) else {
            return
        }

        // Remove from pending UI list
        pendingToolCalls.remove(at: index)

        // Send rejection to server
        Task {
            do {
                try await sendToolApproval(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    arguments: [:],
                    approved: false
                )
                NSLog("[AgentViewModel] Sent rejection for: \(toolCall.name)")

                // Convert arguments to [String: Any]
                let argsDict = toolCall.arguments.mapValues { $0.value }

                // Add rejection result to messages (for history)
                let toolMessage = DisplayMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "",
                    timestamp: Date(),
                    toolCall: ToolCallInfo(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        arguments: argsDict
                    ),
                    toolResult: ToolResultInfo(
                        toolCallId: toolCall.id,
                        result: ["rejected": true, "reason": "User rejected this action"]
                    )
                )
                messages.append(toolMessage)

                // Check if there are more tools still awaiting approval
                let stillPendingApproval = pendingToolCalls.contains {
                    if case .awaitingApproval = $0.status { return true }
                    return false
                }

                if stillPendingApproval {
                    // More tools pending - don't continue conversation yet
                    NSLog(
                        "[AgentViewModel] More tools awaiting approval after rejection, not continuing yet"
                    )
                } else {
                    // All tools handled! Now continue the conversation
                    NSLog("[AgentViewModel] All pending tools handled, continuing conversation")
                    do {
                        try await streamFromAgentContinuation()
                    } catch {
                        errorMessage = error.localizedDescription
                        NSLog("[AgentViewModel] Error continuing after tools: \(error)")
                    }
                }
            } catch {
                errorMessage = "Failed to reject tool: \(error.localizedDescription)"
            }
        }
    }

    private func sendToolApproval(
        toolCallId: String,
        toolName: String,
        arguments: [String: AnyCodable],
        approved: Bool,
        clientResult: [String: Any]? = nil
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

        var body: [String: Any] = [
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argsDict,
            "approved": approved,
        ]

        // Include conversationId for server to update parts-based messages
        if let conversationId = serverConversationId {
            body["conversationId"] = conversationId
        }

        // Include client result for client-side tools
        if let clientResult = clientResult {
            body["clientResult"] = clientResult
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AgentViewModel", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Handle 426 Upgrade Required
        if httpResponse.statusCode == 426 {
            await MainActor.run {
                UpdateManager.shared.handleForceUpdateRequired()
            }
            throw NSError(
                domain: "AgentViewModel", code: 426,
                userInfo: [NSLocalizedDescriptionKey: "Update required"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "AgentViewModel", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }
    }

    /// Send tool approval and return the result from the server
    private func sendToolApprovalAndGetResult(
        toolCallId: String,
        toolName: String,
        arguments: [String: AnyCodable],
        approved: Bool
    ) async throws -> [String: Any] {
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

        var body: [String: Any] = [
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argsDict,
            "approved": approved,
        ]

        // Include conversationId for server to update parts-based messages
        if let conversationId = serverConversationId {
            body["conversationId"] = conversationId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AgentViewModel", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Handle 426 Upgrade Required
        if httpResponse.statusCode == 426 {
            await MainActor.run {
                UpdateManager.shared.handleForceUpdateRequired()
            }
            throw NSError(
                domain: "AgentViewModel", code: 426,
                userInfo: [NSLocalizedDescriptionKey: "Update required"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "AgentViewModel", code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }

        // Parse the response to get the result
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any]
        else {
            // Return a generic success if we can't parse the result
            return ["success": true]
        }

        return result
    }
}
