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
    let name: String  // e.g., "send_slack_message", "create_linear_issue"
    let arguments: [String: AnyCodable]
    var status: ToolCallStatus = .pending

    // Computed property for display
    var displayName: String {
        switch name {
        case "send_slack_message":
            return "Send Slack Message"
        case "create_linear_issue":
            return "Create Linear Issue"
        case "get_granola_notes":
            return "Get Granola Notes"
        default:
            return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // Check if this tool requires user approval
    var requiresApproval: Bool {
        switch name {
        case "send_slack_message", "create_linear_issue":
            return true
        case "get_granola_notes":
            return false
        default:
            return false
        }
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
