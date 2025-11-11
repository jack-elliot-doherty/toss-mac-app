import Foundation

// MARK: - Stream Event Types (Updated for AI SDK v6)

enum AgentStreamEvent {
    case textDelta(String)
    case textChunk(String)  // Complete text chunks from agent steps
    case toolCallAwaitingApproval(ToolCall)  // Tool needs approval (server paused)
    case toolCallApproved(id: String)  // Server confirmed approval
    case toolCallRejected(id: String)  // Server confirmed rejection
    case toolResult(id: String, result: String)
    case agentStepFinish(stepNumber: Int)
    case done
    case error(String)
}

// MARK: - AI SDK v6 Data Stream Protocol

// The AI SDK v6 uses data stream protocol (not SSE):
// FORMAT: "INDEX:JSON_DATA"
// Examples:
// 0:{"type":"agent-step","step":{"type":"text","content":"Let me help..."}}
// 1:{"type":"tool-call-awaiting-approval","toolCallId":"call_123","toolName":"send_slack_message","args":{"channel":"#eng","message":"Hi"}}
// 2:{"type":"tool-call-approved","toolCallId":"call_123"}
// 3:{"type":"tool-result","toolCallId":"call_123","result":"Success"}

struct AgentStepData: Codable {
    let type: String
    let step: StepContent?
    let stepNumber: Int?

    struct StepContent: Codable {
        let type: String
        let content: String?
    }
}

struct ToolCallAwaitingApprovalData: Codable {
    let type: String
    let toolCallId: String
    let toolName: String
    let args: [String: AnyCodable]
}

struct ToolCallStatusData: Codable {
    let type: String
    let toolCallId: String
}

struct ToolResultData: Codable {
    let type: String
    let toolCallId: String
    let result: String
}

// MARK: - Stream Parser

@MainActor
class AgentStreamParser {

    /// Parse a line from the data stream (format: "INDEX:JSON")
    func parse(_ line: String) -> AgentStreamEvent? {
        // Skip empty lines
        guard !line.isEmpty else { return nil }

        // Check for [DONE] marker or finish type
        if line.contains("[DONE]") || line.contains("\"type\":\"finish\"") {
            return .done
        }

        // Parse data stream format: "INDEX:JSON"
        // Split on first colon to get index and JSON
        guard let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }

        let jsonString = String(line[line.index(after: colonIndex)...])

        guard let data = jsonString.data(using: .utf8) else {
            return .error("Failed to parse stream data")
        }

        // Try to decode as generic JSON first to get type
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            return nil
        }

        return parseByType(type: type, data: data, json: json)
    }

    private func parseByType(type: String, data: Data, json: [String: Any]) -> AgentStreamEvent? {
        switch type {
        case "agent-step":
            // Text content from agent
            if let step = json["step"] as? [String: Any],
                let stepType = step["type"] as? String,
                stepType == "text",
                let content = step["content"] as? String
            {
                return .textChunk(content)
            }

        case "tool-call-awaiting-approval":
            // Tool needs approval - server is paused
            if let decoded = try? JSONDecoder().decode(
                ToolCallAwaitingApprovalData.self, from: data)
            {
                let toolCall = ToolCall(
                    id: decoded.toolCallId,
                    name: decoded.toolName,
                    arguments: decoded.args,
                    status: .awaitingApproval
                )
                return .toolCallAwaitingApproval(toolCall)
            }

        case "tool-call-approved":
            // Server confirmed tool was approved
            if let toolCallId = json["toolCallId"] as? String {
                return .toolCallApproved(id: toolCallId)
            }

        case "tool-call-rejected":
            // Server confirmed tool was rejected
            if let toolCallId = json["toolCallId"] as? String {
                return .toolCallRejected(id: toolCallId)
            }

        case "tool-result":
            // Tool execution result
            if let decoded = try? JSONDecoder().decode(ToolResultData.self, from: data) {
                return .toolResult(id: decoded.toolCallId, result: decoded.result)
            }

        case "agent-step-finish":
            if let stepNumber = json["stepNumber"] as? Int {
                return .agentStepFinish(stepNumber: stepNumber)
            }

        case "error":
            if let message = json["message"] as? String {
                return .error(message)
            }

        default:
            NSLog("[AgentStreamParser] Unknown event type: \(type)")
        }

        return nil
    }

    /// Parse multiple lines at once
    func parseLines(_ lines: [String]) -> [AgentStreamEvent] {
        lines.compactMap { parse($0) }
    }
}

// MARK: - Async Stream Helper

extension AgentStreamParser {
    /// Create an async stream from URLSession data
    func streamEvents(from urlRequest: URLRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.finish()
                    return
                }

                // Parse the SSE stream
                if let text = String(data: data, encoding: .utf8) {
                    let lines = text.components(separatedBy: "\n")
                    for line in lines {
                        if let event = self.parse(line) {
                            continuation.yield(event)

                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                }

                continuation.finish()
            }

            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Stream events with line-by-line parsing (better for real-time SSE)
    func streamEventsLive(from urlRequest: URLRequest) -> AsyncThrowingStream<
        AgentStreamEvent, Error
    > {
        AsyncThrowingStream { continuation in
            let session = URLSession.shared
            let task = session.dataTask(with: urlRequest)

            var buffer = ""

            // Use delegate to process data as it arrives
            let delegate = StreamDelegate { data in
                buffer += String(data: data, encoding: .utf8) ?? ""

                // Process complete lines
                let lines = buffer.components(separatedBy: "\n")
                buffer = lines.last ?? ""  // Keep incomplete line in buffer

                for line in lines.dropLast() {
                    if let event = self.parse(line) {
                        continuation.yield(event)

                        if case .done = event {
                            continuation.finish()
                            return
                        }
                    }
                }
            } completion: { error in
                if let error = error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }

            // Note: URLSession doesn't easily support streaming delegates
            // For production, consider using a dedicated SSE library
            // or implement custom socket-based streaming

            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Stream Delegate Helper

private class StreamDelegate: NSObject {
    let onData: (Data) -> Void
    let onComplete: (Error?) -> Void

    init(onData: @escaping (Data) -> Void, completion: @escaping (Error?) -> Void) {
        self.onData = onData
        self.onComplete = completion
    }
}
