import Foundation

// MARK: - Tool Call Models

enum ToolCallStatus: Equatable {
    case pending  // Server is calling the tool
    case awaitingApproval  // Needs user approval (mutations only)
    case executing  // User approved, executing
    case completed(result: String)
    case failed(error: String)
}

struct ToolCall: Identifiable, Equatable {
    let id: String
    let name: String  // e.g., "slackSendMessage", "linearCreateIssue"
    let arguments: [String: AnyCodable]
    var status: ToolCallStatus = .pending

    // Tool type detection using prefixes
    private var isSlackTool: Bool {
        name.lowercased().hasPrefix("slack")
    }

    private var isLinearTool: Bool {
        name.lowercased().hasPrefix("linear")
    }

    private var isCalendarTool: Bool {
        name.lowercased().hasPrefix("calendar")
    }

    // Check if this is a connect tool
    var isConnectTool: Bool {
        name.lowercased().hasPrefix("connect")
    }

    // Computed property for display
    var displayName: String {
        switch name {
        case "slackSendMessage":
            return "Send Slack Message"
        case "slackListChannels":
            return "List Slack Channels"
        case "slackSearch":
            return "Search Slack"
        case "slackReadHistory":
            return "Read Slack History"
        case "linearCreateIssue":
            return "Create Linear Issue"
        case "calendarCreateEvent":
            return "Create Calendar Event"
        case "calendarListEvents":
            return "List Calendar Events"
        case "screenshot":
            return "Take Screenshot"
        case "connectSlack":
            return "Connect Slack"
        case "connectLinear":
            return "Connect Linear"
        case "connectGoogleCalendar":
            return "Connect Google Calendar"
        default:
            // Convert camelCase to readable
            return
                name
                .replacingOccurrences(
                    of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression
                )
                .capitalized
        }
    }

    // Check if this tool requires user approval (mutations only)
    var requiresApproval: Bool {
        let lowerName = name.lowercased()

        // Slack send requires approval
        if lowerName.contains("send") && isSlackTool {
            return true
        }

        // Linear create requires approval
        if lowerName.contains("create") && isLinearTool {
            return true
        }

        // Calendar create requires approval
        if lowerName.contains("create") && isCalendarTool {
            return true
        }

        // Client-side tools need approval for user consent
        if lowerName == "screenshot" {
            return true
        }

        return false
    }

    /// Check if this tool executes on the client (Mac app) rather than the server
    var isClientSideTool: Bool {
        let lowerName = name.lowercased()
        return lowerName == "screenshot" || lowerName.hasPrefix("connect")
    }
}

// MARK: - AnyCodable helper for dynamic JSON

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodable"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cannot encode value"
                )
            )
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple comparison - could be improved
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// Helper to extract typed values from AnyCodable dictionary
extension Dictionary where Key == String, Value == AnyCodable {
    func getString(_ key: String) -> String? {
        self[key]?.value as? String
    }

    func getInt(_ key: String) -> Int? {
        self[key]?.value as? Int
    }

    func getBool(_ key: String) -> Bool? {
        self[key]?.value as? Bool
    }
}
