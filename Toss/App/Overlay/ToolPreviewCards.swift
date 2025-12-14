import SwiftUI

// MARK: - Tool Parameters Wrapper

/// Wrapper to provide unified access to tool parameters from different sources
struct ToolParams {
    private let getValue: (String) -> Any?
    private let keys: [String]

    /// Initialize from agent ToolCall arguments
    init(_ dict: [String: AnyCodable]) {
        self.keys = Array(dict.keys)
        self.getValue = { dict[$0]?.value }
    }

    /// Initialize from meeting action ExtractedAction params
    init(_ dict: [String: AnyCodableValue]?) {
        self.keys = dict.map { Array($0.keys) } ?? []
        self.getValue = { key in
            guard let value = dict?[key] else { return nil }
            switch value {
            case .string(let s): return s
            case .int(let i): return i
            case .double(let d): return d
            case .bool(let b): return b
            case .array(let a): return a.map { $0.anyValue }
            case .dictionary(let d): return d.mapValues { $0.anyValue }
            case .null: return nil
            }
        }
    }

    func getString(_ key: String) -> String? {
        getValue(key) as? String
    }

    func getInt(_ key: String) -> Int? {
        getValue(key) as? Int
    }

    func getBool(_ key: String) -> Bool? {
        getValue(key) as? Bool
    }

    func getDouble(_ key: String) -> Double? {
        if let d = getValue(key) as? Double { return d }
        if let i = getValue(key) as? Int { return Double(i) }
        return nil
    }

    func getStringArray(_ key: String) -> [String]? {
        if let array = getValue(key) as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return nil
    }

    func getAllKeys() -> [String] {
        keys
    }
}

// MARK: - Tool Preview Factory

struct ToolPreviewFactory {
    /// Returns the appropriate preview view for a given tool (from ToolCall)
    @ViewBuilder
    static func preview(
        for toolName: String,
        params: [String: AnyCodable],
        compact: Bool = false
    ) -> some View {
        let wrapped = ToolParams(params)
        switch toolName {
        case "linearCreateIssue":
            LinearIssuePreview(params: wrapped, compact: compact)
        case "calendarCreateEvent":
            CalendarEventPreview(params: wrapped, compact: compact)
        case "slackSendMessage":
            SlackMessagePreview(params: wrapped, compact: compact)
        default:
            GenericToolPreview(toolName: toolName, params: wrapped)
        }
    }

    /// Returns the appropriate preview view for a given tool (from ExtractedAction)
    @ViewBuilder
    static func preview(
        for toolName: String,
        params: [String: AnyCodableValue]?,
        compact: Bool = false
    ) -> some View {
        let wrapped = ToolParams(params)
        switch toolName {
        case "linearCreateIssue":
            LinearIssuePreview(params: wrapped, compact: compact)
        case "calendarCreateEvent":
            CalendarEventPreview(params: wrapped, compact: compact)
        case "slackSendMessage":
            SlackMessagePreview(params: wrapped, compact: compact)
        default:
            GenericToolPreview(toolName: toolName, params: wrapped)
        }
    }
}

// MARK: - Linear Issue Preview

struct LinearIssuePreview: View {
    let params: ToolParams
    let compact: Bool

    private var title: String { params.getString("title") ?? "Untitled Issue" }
    private var description: String? { params.getString("description") }
    private var priority: Int? { params.getInt("priority") }
    private var team: String? { params.getString("teamId") ?? params.getString("team") }
    private var assignee: String? { params.getString("assigneeId") ?? params.getString("assignee") }

    private var priorityLabel: String {
        switch priority {
        case 0: return "No Priority"
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Medium"
        case 4: return "Low"
        default: return "No Priority"
        }
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .blue
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Linear logo
            HStack(spacing: 8) {
                // Linear logo placeholder (purple square)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "5E6AD2"), Color(hex: "8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .overlay(
                        Text("Li")
                            .font(.system(size: compact ? 9 : 10, weight: .bold))
                            .foregroundColor(.white)
                    )

                Text("Create Linear Issue")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                // Priority badge
                Text(priorityLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(priorityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(priorityColor.opacity(0.15))
                    )
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Issue details
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                // Title
                PreviewField(label: "Title", value: title, compact: compact)

                // Description (if available)
                if let desc = description, !desc.isEmpty {
                    PreviewField(
                        label: "Description",
                        value: desc,
                        compact: compact,
                        lineLimit: compact ? 2 : 4
                    )
                }

                // Team & Assignee row
                if team != nil || assignee != nil {
                    HStack(spacing: 16) {
                        if let team = team {
                            PreviewField(label: "Team", value: team, compact: compact, inline: true)
                        }
                        if let assignee = assignee {
                            PreviewField(
                                label: "Assignee", value: assignee, compact: compact, inline: true)
                        }
                    }
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "5E6AD2").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "5E6AD2").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Calendar Event Preview

struct CalendarEventPreview: View {
    let params: ToolParams
    let compact: Bool

    private var title: String { params.getString("title") ?? "Untitled Event" }
    private var description: String? { params.getString("description") }
    private var startTime: String? { params.getString("startTime") }
    private var endTime: String? { params.getString("endTime") }
    private var attendees: [String]? { params.getStringArray("attendees") }

    private var formattedTime: String {
        guard let start = startTime else { return "No time specified" }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try parsing with fractional seconds first, then without
        var startDate = isoFormatter.date(from: start)
        if startDate == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            startDate = isoFormatter.date(from: start)
        }

        guard let date = startDate else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        // Add duration if end time available
        if let end = endTime {
            var endDate = isoFormatter.date(from: end)
            if endDate == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                endDate = isoFormatter.date(from: end)
            }

            if let endD = endDate {
                let minutes = Int(endD.timeIntervalSince(date) / 60)
                if minutes == 60 {
                    result += " (1 hour)"
                } else if minutes > 60 {
                    result += " (\(minutes / 60)h \(minutes % 60)m)"
                } else {
                    result += " (\(minutes) min)"
                }
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Google Calendar colors
            HStack(spacing: 8) {
                // Google Calendar-ish icon
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .overlay(
                        Image(systemName: "calendar")
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Create Calendar Event")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Event details
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                // Title
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "4285F4"))
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.system(size: compact ? 13 : 15, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                }

                // Time
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                    Text(formattedTime)
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundColor(AppTheme.secondaryText)
                }

                // Description
                if let desc = description, !desc.isEmpty {
                    PreviewField(
                        label: "Description",
                        value: desc,
                        compact: compact,
                        lineLimit: compact ? 2 : 3
                    )
                }

                // Attendees
                if let attendees = attendees, !attendees.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)

                        Text(attendees.joined(separator: ", "))
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(compact ? 1 : 2)
                    }
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "4285F4").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "4285F4").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Slack Message Preview

struct SlackMessagePreview: View {
    let params: ToolParams
    let compact: Bool

    @State private var channelInfo: SlackChannelInfo?
    @State private var isLoadingChannel = true

    private var channelId: String {
        params.getString("channelId") ?? params.getString("channel") ?? ""
    }

    private var message: String { params.getString("message") ?? "" }

    private var channelDisplay: String {
        if let info = channelInfo {
            if info.isDirectMessage {
                return "@\(info.name)"
            } else if info.isGroupDM {
                return info.name
            } else {
                return "#\(info.name)"
            }
        }
        // Still loading - show channel ID
        return channelId
    }

    private var isDirectMessage: Bool {
        channelInfo?.isDirectMessage ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Slack colors
            HStack(spacing: 8) {
                Image("SlackLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)

                Text("Send Slack Message")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Message details
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                // Channel or DM
                HStack(spacing: 6) {
                    if isLoadingChannel {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: isDirectMessage ? "person.fill" : "number")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                    }

                    Text(channelDisplay)
                        .font(.system(size: compact ? 12 : 13, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "4A154B").opacity(0.1))
                        )
                }

                // Message
                Text(message)
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(compact ? 3 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 8 : 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppTheme.subtleStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "4A154B").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "4A154B").opacity(0.2), lineWidth: 1)
                )
        )
        .task {
            await fetchChannelInfo()
        }
    }

    private func fetchChannelInfo() async {
        guard !channelId.isEmpty else {
            isLoadingChannel = false
            return
        }

        do {
            channelInfo = try await SlackAPI.shared.getChannelInfo(channelId: channelId)
        } catch {
            NSLog("[SlackMessagePreview] Failed to fetch channel info: \(error)")
        }
        isLoadingChannel = false
    }
}

// MARK: - Generic Tool Preview (fallback)

struct GenericToolPreview: View {
    let toolName: String
    let params: ToolParams

    private var displayName: String {
        toolName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.orange))

                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Show all parameters
            ForEach(params.getAllKeys().sorted(), id: \.self) { key in
                if let value = params.getString(key) {
                    PreviewField(label: key, value: value, compact: true)
                } else if let value = params.getInt(key) {
                    PreviewField(label: key, value: String(value), compact: true)
                } else if let value = params.getBool(key) {
                    PreviewField(label: key, value: value ? "Yes" : "No", compact: true)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Agent Task Preview

struct AgentTaskPreview: View {
    let taskSpec: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(hex: "F59E0B")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Multi-step Task")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                Text("Agent")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.15))
                    )
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Task description
            Text(taskSpec)
                .font(.system(size: compact ? 12 : 13))
                .foregroundColor(AppTheme.secondaryText)
                .lineLimit(compact ? 4 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Helper Components

private struct PreviewField: View {
    let label: String
    let value: String
    var compact: Bool = false
    var lineLimit: Int? = nil
    var inline: Bool = false

    private var displayLabel: String {
        label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }

    var body: some View {
        if inline {
            HStack(spacing: 4) {
                Text(displayLabel)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                Text(value)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundColor(AppTheme.primaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayLabel)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                Text(value)
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(lineLimit)
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview("Linear Issue") {
    VStack(spacing: 20) {
        LinearIssuePreview(
            params: ToolParams([
                "title": AnyCodable("Fix authentication bug in login flow"),
                "description": AnyCodable(
                    "Users are reporting intermittent login failures when using SSO."),
                "priority": AnyCodable(2),
            ]),
            compact: false
        )

        LinearIssuePreview(
            params: ToolParams([
                "title": AnyCodable("Add dark mode support"),
                "description": AnyCodable(""),
                "priority": AnyCodable(4),
            ]),
            compact: true
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.black)
}

#Preview("Calendar Event") {
    VStack(spacing: 20) {
        CalendarEventPreview(
            params: ToolParams([
                "title": AnyCodable("Weekly Team Sync"),
                "description": AnyCodable("Review sprint progress and blockers"),
                "startTime": AnyCodable("2024-01-15T10:00:00Z"),
                "endTime": AnyCodable("2024-01-15T11:00:00Z"),
                "attendees": AnyCodable(["john@example.com", "jane@example.com"]),
            ]),
            compact: false
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.black)
}

#Preview("Slack Message") {
    SlackMessagePreview(
        params: ToolParams([
            "channel": AnyCodable("#engineering"),
            "message": AnyCodable("Hey team! The deployment is ready for review."),
        ]),
        compact: false
    )
    .padding()
    .frame(width: 400)
    .background(Color.black)
}

#Preview("Agent Task") {
    AgentTaskPreview(
        taskSpec:
            "Update the existing Linear issue PROJ-123 to add the new requirements discussed in the meeting.",
        compact: false
    )
    .padding()
    .frame(width: 400)
    .background(Color.black)
}

// MARK: - Editable Calendar Event Preview

struct EditableCalendarEventPreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?

    // Button state (optional - for inline button in header)
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String

    private var startTime: String? { initialParams.getString("startTime") }
    private var endTime: String? { initialParams.getString("endTime") }
    private var attendees: [String]? { initialParams.getStringArray("attendees") }

    private var formattedTime: String {
        guard let start = startTime else { return "No time specified" }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var startDate = isoFormatter.date(from: start)
        if startDate == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            startDate = isoFormatter.date(from: start)
        }

        guard let date = startDate else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        if let end = endTime {
            var endDate = isoFormatter.date(from: end)
            if endDate == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                endDate = isoFormatter.date(from: end)
            }
            if let endD = endDate {
                let minutes = Int(endD.timeIntervalSince(date) / 60)
                if minutes == 60 {
                    result += " (1 hour)"
                } else if minutes > 60 {
                    result += " (\(minutes / 60)h \(minutes % 60)m)"
                } else {
                    result += " (\(minutes) min)"
                }
            }
        }
        return result
    }

    init(
        params: ToolParams,
        compact: Bool,
        onParamsChanged: (([String: AnyCodableValue]) -> Void)? = nil,
        isExecuting: Bool = false,
        onExecute: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute

        _title = State(initialValue: params.getString("title") ?? "Untitled Event")
        _description = State(initialValue: params.getString("description") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with logo, title, and action button
            HStack(spacing: 10) {
                Image("GoogleCalendarLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Calendar Event")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will create this event in your Google Calendar")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

                // Action button in header
                if let onExecute = onExecute {
                    Button {
                        onExecute()
                    } label: {
                        if isExecuting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Creating...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 10))
                                Text("Add to Calendar")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Key-value rows
            VStack(spacing: 0) {
                FormRow(label: "Title") {
                    TextField("Event title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .onChange(of: title) { _, _ in notifyParamsChanged() }
                }

                Divider().background(AppTheme.subtleStroke)

                FormRow(label: "When") {
                    Text(formattedTime)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                }

                if let attendees = attendees, !attendees.isEmpty {
                    Divider().background(AppTheme.subtleStroke)
                    FormRow(label: "Guests") {
                        Text(attendees.joined(separator: ", "))
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primaryText)
                            .lineLimit(2)
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("Add a description...", text: $description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(3...6)
                        .onChange(of: description) { _, _ in notifyParamsChanged() }
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        if let start = initialParams.getString("startTime") {
            updatedParams["startTime"] = .string(start)
        }
        if let end = initialParams.getString("endTime") {
            updatedParams["endTime"] = .string(end)
        }
        if let att = initialParams.getStringArray("attendees") {
            updatedParams["attendees"] = .array(att.map { .string($0) })
        }
        updatedParams["title"] = .string(title)
        updatedParams["description"] = .string(description)
        onParamsChanged?(updatedParams)
    }
}

// MARK: - Editable Linear Issue Preview

struct EditableLinearIssuePreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String

    private var priority: Int? { initialParams.getInt("priority") }
    private var team: String? {
        initialParams.getString("teamId") ?? initialParams.getString("team")
    }
    private var assignee: String? {
        initialParams.getString("assigneeId") ?? initialParams.getString("assignee")
    }

    private var priorityLabel: String {
        switch priority {
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Medium"
        case 4: return "Low"
        default: return "No Priority"
        }
    }

    private var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .blue
        default: return .gray
        }
    }

    init(
        params: ToolParams,
        compact: Bool,
        onParamsChanged: (([String: AnyCodableValue]) -> Void)? = nil,
        isExecuting: Bool = false,
        onExecute: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute

        _title = State(initialValue: params.getString("title") ?? "Untitled Issue")
        _description = State(initialValue: params.getString("description") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with logo, title, and action button
            HStack(spacing: 10) {
                // Linear logo
                Image("LinearLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Linear Issue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will create this issue in Linear")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

                // Action button in header
                if let onExecute = onExecute {
                    Button {
                        onExecute()
                    } label: {
                        if isExecuting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Creating...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(
                                    Color(hex: "5E6AD2").opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text("Create Issue")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "5E6AD2")))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Key-value rows
            VStack(spacing: 0) {
                FormRow(label: "Title") {
                    TextField("Issue title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .onChange(of: title) { _, _ in notifyParamsChanged() }
                }

                Divider().background(AppTheme.subtleStroke)

                FormRow(label: "Priority") {
                    Text(priorityLabel)
                        .font(.system(size: 13))
                        .foregroundColor(priorityColor)
                }

                if team != nil || assignee != nil {
                    Divider().background(AppTheme.subtleStroke)
                    HStack(spacing: 0) {
                        if let team = team {
                            FormRow(label: "Team") {
                                Text(team)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.primaryText)
                            }
                        }
                        if let assignee = assignee {
                            FormRow(label: "Assignee") {
                                Text(assignee)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.primaryText)
                            }
                        }
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("Add a description...", text: $description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(3...6)
                        .onChange(of: description) { _, _ in notifyParamsChanged() }
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        if let p = priority { updatedParams["priority"] = .int(p) }
        if let t = team { updatedParams["teamId"] = .string(t) }
        if let a = assignee { updatedParams["assigneeId"] = .string(a) }
        updatedParams["title"] = .string(title)
        updatedParams["description"] = .string(description)
        onParamsChanged?(updatedParams)
    }
}

// MARK: - Editable Slack Message Preview

struct EditableSlackMessagePreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var message: String
    @State private var channelInfo: SlackChannelInfo?
    @State private var isLoadingChannel = true

    private var channelId: String {
        initialParams.getString("channelId") ?? initialParams.getString("channel") ?? ""
    }

    private var channelDisplay: String {
        if let info = channelInfo {
            if info.isDirectMessage {
                return "@\(info.name)"
            } else if info.isGroupDM {
                return info.name
            } else {
                return "#\(info.name)"
            }
        }
        return channelId
    }

    private var isDirectMessage: Bool {
        channelInfo?.isDirectMessage ?? false
    }

    init(
        params: ToolParams,
        compact: Bool,
        onParamsChanged: (([String: AnyCodableValue]) -> Void)? = nil,
        isExecuting: Bool = false,
        onExecute: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute

        _message = State(initialValue: params.getString("message") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with logo, title, and action button
            HStack(spacing: 10) {
                Image("SlackLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Slack Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will send this message to Slack")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

                // Action button in header
                if let onExecute = onExecute {
                    Button {
                        onExecute()
                    } label: {
                        if isExecuting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Sending...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(
                                    Color(hex: "4A154B").opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10))
                                Text("Send Message")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "4A154B")))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting || isLoadingChannel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Key-value rows
            VStack(spacing: 0) {
                // Channel or DM row
                FormRow(label: isDirectMessage ? "To" : "Channel") {
                    HStack(spacing: 4) {
                        if isLoadingChannel {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: isDirectMessage ? "person.fill" : "number")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                        }
                        Text(channelDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.primaryText)
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Message - editable text area
                VStack(alignment: .leading, spacing: 6) {
                    Text("Message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("Write your message...", text: $message, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(3...8)
                        .onChange(of: message) { _, _ in notifyParamsChanged() }
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .task {
            await fetchChannelInfo()
        }
    }

    private func fetchChannelInfo() async {
        guard !channelId.isEmpty else {
            isLoadingChannel = false
            return
        }

        do {
            channelInfo = try await SlackAPI.shared.getChannelInfo(channelId: channelId)
        } catch {
            NSLog("[EditableSlackMessagePreview] Failed to fetch channel info: \(error)")
        }
        isLoadingChannel = false
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        // Preserve channel ID
        if let chId = initialParams.getString("channelId") {
            updatedParams["channelId"] = .string(chId)
        } else if let ch = initialParams.getString("channel") {
            updatedParams["channelId"] = .string(ch)
        }
        updatedParams["message"] = .string(message)
        onParamsChanged?(updatedParams)
    }
}

// Helper view for key-value form rows
private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 70, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// Helper: Removable attendee chip
private struct AttendeeChip: View {
    let email: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(email)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.primaryText)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.cardBackground)
        )
    }
}
