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

        static func == (lhs: DisplayMessage, rhs: DisplayMessage) -> Bool {
            lhs.id == rhs.id && lhs.role == rhs.role && lhs.content == rhs.content
                && lhs.isMemorySave == rhs.isMemorySave
                && lhs.isToolExecution == rhs.isToolExecution
                && lhs.toolExecutionComplete == rhs.toolExecutionComplete
                && lhs.isToolApprovalWaiting == rhs.isToolApprovalWaiting
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

        // Build messages array for API using AI SDK v6 UIMessage protocol format
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            // Skip system messages that are just for UI
            if msg.role == .system && msg.toolCall == nil { continue }
            if msg.role == .tool { continue }

            // For messages with tool call + result (completed tool invocations)
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
                // Tool call without result yet
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
                // Regular text message
                apiMessages.append([
                    "id": msg.id.uuidString,
                    "role": msg.role.rawValue,
                    "parts": [
                        ["type": "text", "text": msg.content]
                    ],
                ])
            }
        }

        // Include pending tool calls that are still awaiting approval
        // This prevents the model from re-requesting tools it already called
        for pendingCall in pendingToolCalls where pendingCall.status == .awaitingApproval {
            let argsDict = pendingCall.arguments.mapValues { $0.value }
            apiMessages.append([
                "id": UUID().uuidString,
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-\(pendingCall.name)",
                        "toolCallId": pendingCall.id,
                        "state": "input-available",
                        "input": argsDict,
                    ]
                ],
            ])
            NSLog(
                "[AgentViewModel] Including pending tool call in context: \(pendingCall.name) (\(pendingCall.id))"
            )
        }

        do {
            try await streamFromAgentWithParts(messages: apiMessages)
        } catch {
            errorMessage = error.localizedDescription
            NSLog("[AgentViewModel] Streaming error: \(error)")
        }

        isProcessing = false
    }

    func clearConversation() {
        messages.removeAll()
        pendingToolCalls.removeAll()
        executingTools.removeAll()
        threadId = nil
        isProcessing = false
        isStreaming = false
        errorMessage = nil
        currentAssistantMessage = nil
        isCompactMode = false
    }

    /// Continue the agent conversation after all tool executions are complete
    /// Uses the AI SDK v6 UIMessage protocol format with proper tool parts
    private func streamFromAgentContinuation() async throws {
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

        // Build messages array using AI SDK v6 UIMessage protocol format
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            // Skip system messages (UI only)
            if msg.role == .system { continue }
            if msg.role == .tool { continue }

            // For messages with tool call + result (completed tool invocations)
            if let toolCall = msg.toolCall, let toolResult = msg.toolResult {
                // AI SDK v6 format: type is "tool-{toolName}" with state "output-available"
                // See: https://v6.ai-sdk.dev/docs/ai-sdk-ui/stream-protocol
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
                // Tool call without result yet (shouldn't happen in continuation, but handle it)
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
            } else {
                // Regular text message
                apiMessages.append([
                    "id": msg.id.uuidString,
                    "role": msg.role.rawValue,
                    "parts": [
                        ["type": "text", "text": msg.content]
                    ],
                ])
            }
        }

        // CRITICAL: Include pending tool calls that are still awaiting approval
        // This prevents the model from re-requesting tools it already called
        for pendingCall in pendingToolCalls where pendingCall.status == .awaitingApproval {
            let argsDict = pendingCall.arguments.mapValues { $0.value }
            apiMessages.append([
                "id": UUID().uuidString,
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-\(pendingCall.name)",
                        "toolCallId": pendingCall.id,
                        "state": "input-available",
                        "input": argsDict,
                    ]
                ],
            ])
            NSLog(
                "[AgentViewModel] Including pending tool call in context: \(pendingCall.name) (\(pendingCall.id))"
            )
        }

        let payload: [String: Any] = ["messages": apiMessages]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        // Debug log (truncate base64 data for readability)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            let truncated =
                jsonString.count > 500
                ? String(jsonString.prefix(500)) + "... [truncated]"
                : jsonString
            NSLog("[AgentViewModel] JSON Body (continuation): %@", truncated)
        }

        request.httpBody = jsonData

        // Stream events
        for try await event in streamParser.streamEvents(from: request) {
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

        let payload: [String: Any] = ["messages": messages]
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
        guard let token = auth.accessToken else {
            return ["success": false, "error": "Not authenticated"]
        }

        guard let url = URL(string: "\(Config.serverURL)\(endpoint)") else {
            return ["success": false, "error": "Invalid URL"]
        }

        NSLog("[AgentViewModel] Initiating \(provider) connection")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(
                domain: "AgentViewModel", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(statusCode)"])
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

        // Include client result for client-side tools
        if let clientResult = clientResult {
            body["clientResult"] = clientResult
        }

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

        let body: [String: Any] = [
            "toolCallId": toolCallId,
            "toolName": toolName,
            "arguments": argsDict,
            "approved": approved,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw NSError(
                domain: "AgentViewModel", code: 500,
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
