import SwiftUI

// MARK: - Date Parsing Helper

/// Shared utility for parsing ISO date strings, handling both with and without timezone
enum DateParsingHelper {
    static func parseISODate(_ string: String) -> Date? {
        // Try ISO8601 with timezone first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) { return date }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        // Fallback for timestamps without timezone (e.g., "2026-01-30T13:00:00")
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = fallbackFormatter.date(from: string) { return date }

        return nil
    }
}

// MARK: - Keyboard Shortcut Hint (for buttons)

/// Compact keyboard shortcut hint for use inside action buttons
private struct ButtonShortcutHint: View {
    var body: some View {
        HStack(spacing: 1) {
            Text("⌘")
                .font(.system(size: 10, weight: .medium))
            Text("↵")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Linear User Info

struct LinearUserInfo: Codable {
    let id: String
    let name: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
}

// MARK: - Linear API

final class LinearAPI {
    static let shared = LinearAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func getUserInfo(userId: String) async throws -> LinearUserInfo {
        let url = baseURL.appendingPathComponent("linear/users/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "LinearAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user info"])
        }

        return try JSONDecoder().decode(LinearUserInfo.self, from: data)
    }
}

// MARK: - Slack Channel Info

struct SlackChannelInfo: Codable {
    let id: String
    let name: String
    let type: String  // "dm", "group_dm", or "channel"
    let isPrivate: Bool

    var isDirectMessage: Bool {
        type == "dm"
    }

    var isGroupDM: Bool {
        type == "group_dm"
    }
}

// MARK: - Slack API

final class SlackAPI {
    static let shared = SlackAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func getChannelInfo(channelId: String) async throws -> SlackChannelInfo {
        let url = baseURL.appendingPathComponent("slack/channels/\(channelId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "SlackAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch channel info"])
        }

        return try JSONDecoder().decode(SlackChannelInfo.self, from: data)
    }
}

// MARK: - Notion Page Info

struct NotionPageInfo: Codable {
    let id: String
    let title: String
    let type: String  // "page" or "database"
    let url: String?
}

// MARK: - Notion API

final class NotionAPI {
    static let shared = NotionAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func getPageInfo(pageId: String) async throws -> NotionPageInfo {
        let url = baseURL.appendingPathComponent("notion/pages/\(pageId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "NotionAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch page info"])
        }

        return try JSONDecoder().decode(NotionPageInfo.self, from: data)
    }
}

// MARK: - Calendar Event Info

struct CalendarEventAttendee: Codable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
}

struct CalendarEventInfo: Codable {
    let id: String
    let summary: String?
    let description: String?
    let start: String?
    let end: String?
    let attendees: [CalendarEventAttendee]?
    let htmlLink: String?
    let meetLink: String?
}

// MARK: - Calendar API

final class CalendarAPI {
    static let shared = CalendarAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func getEventInfo(eventId: String) async throws -> CalendarEventInfo {
        let url = baseURL.appendingPathComponent("google/events/\(eventId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "CalendarAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch event info"])
        }

        return try JSONDecoder().decode(CalendarEventInfo.self, from: data)
    }
}

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
        case "linearUpdateIssue":
            LinearUpdateIssuePreview(params: wrapped, compact: compact)
        case "calendarCreateEvent":
            CalendarEventPreview(params: wrapped, compact: compact)
        case "calendarDeleteEvent":
            CalendarDeleteEventPreview(params: wrapped, compact: compact)
        case "calendarUpdateEvent":
            CalendarUpdateEventPreview(params: wrapped, compact: compact)
        case "slackSendMessage":
            EditableSlackMessagePreview(params: wrapped, compact: compact)
        case "notionCreateDatabase":
            EditableNotionCreateDatabasePreview(params: wrapped, compact: compact)
        case "notionCreatePage":
            EditableNotionCreatePagePreview(params: wrapped, compact: compact)
        case "notionAppendBlocks":
            EditableNotionAppendBlocksPreview(params: wrapped, compact: compact)
        case "createFlow":
            EditableFlowPreview(params: wrapped, compact: compact)
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
        case "linearUpdateIssue":
            LinearUpdateIssuePreview(params: wrapped, compact: compact)
        case "calendarCreateEvent":
            CalendarEventPreview(params: wrapped, compact: compact)
        case "calendarDeleteEvent":
            CalendarDeleteEventPreview(params: wrapped, compact: compact)
        case "calendarUpdateEvent":
            CalendarUpdateEventPreview(params: wrapped, compact: compact)
        case "slackSendMessage":
            EditableSlackMessagePreview(params: wrapped, compact: compact)
        case "notionCreateDatabase":
            EditableNotionCreateDatabasePreview(params: wrapped, compact: compact)
        case "notionCreatePage":
            EditableNotionCreatePagePreview(params: wrapped, compact: compact)
        case "notionAppendBlocks":
            EditableNotionAppendBlocksPreview(params: wrapped, compact: compact)
        case "createFlow":
            EditableFlowPreview(params: wrapped, compact: compact)
        case "cursorOpenPrompt":
            // Note: CursorPromptPreview needs title/context, so use GenericToolPreview as fallback
            // The full CursorPromptPreview is used directly in ActionItemCard
            GenericToolPreview(toolName: "Open in Cursor", params: wrapped)
        default:
            GenericToolPreview(toolName: toolName, params: wrapped)
        }
    }
}

// MARK: - Linear Issue Preview

struct LinearIssuePreview: View {
    let params: ToolParams
    let compact: Bool

    @State private var assigneeInfo: LinearUserInfo?
    @State private var isLoadingAssignee = true

    private var title: String { params.getString("title") ?? "Untitled Issue" }
    private var description: String? { params.getString("description") }
    private var priority: Int? { params.getInt("priority") }
    private var team: String? { params.getString("teamId") ?? params.getString("team") }
    private var assigneeId: String? {
        params.getString("assigneeId") ?? params.getString("assignee")
    }

    private var assigneeDisplay: String {
        if let info = assigneeInfo {
            return info.displayName.isEmpty ? info.name : info.displayName
        }
        // Still loading - show assignee ID as placeholder
        return assigneeId ?? ""
    }

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

                // Description (if available) - scrollable when content overflows
                if let desc = description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Description")
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)

                        ScrollView {
                            Text(desc)
                                .font(.system(size: compact ? 12 : 13))
                                .foregroundColor(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: compact ? 60 : 100)
                    }
                }

                // Team & Assignee row
                if team != nil || assigneeId != nil {
                    HStack(spacing: 16) {
                        if let team = team {
                            PreviewField(label: "Team", value: team, compact: compact, inline: true)
                        }
                        if assigneeId != nil {
                            HStack(spacing: 6) {
                                Text("Assignee")
                                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                                    .foregroundColor(AppTheme.secondaryText)

                                if isLoadingAssignee {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 10, height: 10)
                                }

                                Text(assigneeDisplay)
                                    .font(.system(size: compact ? 11 : 12))
                                    .foregroundColor(AppTheme.primaryText)
                            }
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
        .task {
            await fetchAssigneeInfo()
        }
    }

    private func fetchAssigneeInfo() async {
        guard let assigneeId = assigneeId, !assigneeId.isEmpty else {
            isLoadingAssignee = false
            return
        }

        do {
            assigneeInfo = try await LinearAPI.shared.getUserInfo(userId: assigneeId)
        } catch {
            NSLog("[LinearIssuePreview] Failed to fetch assignee info: \(error)")
        }
        isLoadingAssignee = false
    }
}

// MARK: - Linear Update Issue Preview

struct LinearUpdateIssuePreview: View {
    let params: ToolParams
    let compact: Bool

    @State private var assigneeInfo: LinearUserInfo?
    @State private var isLoadingAssignee = true

    private var issueId: String { params.getString("issueId") ?? "Unknown Issue" }
    private var title: String? { params.getString("title") }
    private var description: String? { params.getString("description") }
    private var priority: Int? { params.getInt("priority") }
    private var assigneeId: String? { params.getString("assigneeId") }
    private var stateId: String? { params.getString("stateId") }

    private var assigneeDisplay: String {
        if let info = assigneeInfo {
            return info.displayName.isEmpty ? info.name : info.displayName
        }
        return assigneeId ?? ""
    }

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

    /// Describes what's being updated
    private var updateSummary: String {
        var changes: [String] = []
        if assigneeId != nil { changes.append("assignee") }
        if title != nil { changes.append("title") }
        if description != nil { changes.append("description") }
        if priority != nil { changes.append("priority") }
        if stateId != nil { changes.append("status") }

        if changes.isEmpty {
            return "No changes"
        } else if changes.count == 1 {
            return "Updating \(changes[0])"
        } else {
            return "Updating \(changes.dropLast().joined(separator: ", ")) and \(changes.last!)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Linear logo
            HStack(spacing: 8) {
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

                Text("Update Linear Issue")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                // Priority badge (if being updated)
                if let _ = priority {
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
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Issue details
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                // Issue ID (always shown)
                PreviewField(label: "Issue", value: issueId, compact: compact)

                // Update summary
                Text(updateSummary)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                    .italic()

                // Title (if being updated)
                if let title = title {
                    PreviewField(label: "New Title", value: title, compact: compact)
                }

                // Description (if being updated)
                if let desc = description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Description")
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)

                        ScrollView {
                            Text(desc)
                                .font(.system(size: compact ? 12 : 13))
                                .foregroundColor(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: compact ? 60 : 100)
                    }
                }

                // Assignee (if being updated)
                if assigneeId != nil {
                    HStack(spacing: 6) {
                        Text("New Assignee")
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)

                        if isLoadingAssignee {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        }

                        Text(assigneeDisplay)
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundColor(AppTheme.primaryText)
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
        .task {
            await fetchAssigneeInfo()
        }
    }

    private func fetchAssigneeInfo() async {
        guard let assigneeId = assigneeId, !assigneeId.isEmpty else {
            isLoadingAssignee = false
            return
        }

        do {
            assigneeInfo = try await LinearAPI.shared.getUserInfo(userId: assigneeId)
        } catch {
            NSLog("[LinearUpdateIssuePreview] Failed to fetch assignee info: \(error)")
        }
        isLoadingAssignee = false
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

        guard let date = DateParsingHelper.parseISODate(start) else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        // Add duration if end time available
        if let end = endTime, let endD = DateParsingHelper.parseISODate(end) {
            let minutes = Int(endD.timeIntervalSince(date) / 60)
            if minutes == 60 {
                result += " (1 hour)"
            } else if minutes > 60 {
                result += " (\(minutes / 60)h \(minutes % 60)m)"
            } else {
                result += " (\(minutes) min)"
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

// MARK: - Calendar Delete Event Preview

struct CalendarDeleteEventPreview: View {
    let params: ToolParams
    let compact: Bool

    private var eventId: String { params.getString("eventId") ?? "Unknown Event" }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Google Calendar colors
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "EA4335"), Color(hex: "FBBC05")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .overlay(
                        Image(systemName: "calendar.badge.minus")
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Delete Calendar Event")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                // Destructive action badge
                Text("Delete")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.15))
                    )
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Event ID
            PreviewField(label: "Event ID", value: eventId, compact: compact)
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Calendar Update Event Preview

struct CalendarUpdateEventPreview: View {
    let params: ToolParams
    let compact: Bool

    private var eventId: String { params.getString("eventId") ?? "Unknown Event" }
    private var title: String? { params.getString("title") }
    private var startTime: String? { params.getString("startTime") }
    private var endTime: String? { params.getString("endTime") }
    private var description: String? { params.getString("description") }

    /// Describes what's being updated
    private var updateSummary: String {
        var changes: [String] = []
        if title != nil { changes.append("title") }
        if startTime != nil { changes.append("start time") }
        if endTime != nil { changes.append("end time") }
        if description != nil { changes.append("description") }

        if changes.isEmpty {
            return "No changes"
        } else if changes.count == 1 {
            return "Updating \(changes[0])"
        } else {
            return "Updating \(changes.dropLast().joined(separator: ", ")) and \(changes.last!)"
        }
    }

    private var formattedNewTime: String? {
        guard let start = startTime else { return nil }

        guard let date = DateParsingHelper.parseISODate(start) else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        if let end = endTime, let endD = DateParsingHelper.parseISODate(end) {
            let minutes = Int(endD.timeIntervalSince(date) / 60)
            if minutes == 60 {
                result += " (1 hour)"
            } else if minutes > 60 {
                result += " (\(minutes / 60)h \(minutes % 60)m)"
            } else {
                result += " (\(minutes) min)"
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header with Google Calendar colors
            HStack(spacing: 8) {
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
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                            .foregroundColor(.white)
                    )

                Text("Update Calendar Event")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                // Update badge
                Text("Update")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "4285F4"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "4285F4").opacity(0.15))
                    )
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Event details
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                // Event ID
                PreviewField(label: "Event", value: eventId, compact: compact)

                // Update summary
                Text(updateSummary)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                    .italic()

                // New title (if being updated)
                if let title = title {
                    PreviewField(label: "New Title", value: title, compact: compact)
                }

                // New time (if being updated)
                if let formattedTime = formattedNewTime {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                        Text(formattedTime)
                            .font(.system(size: compact ? 12 : 13))
                            .foregroundColor(AppTheme.primaryText)
                    }
                }

                // New description (if being updated)
                if let desc = description, !desc.isEmpty {
                    PreviewField(
                        label: "New Description",
                        value: desc,
                        compact: compact,
                        lineLimit: compact ? 2 : 3
                    )
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

    private var isNotionTool: Bool {
        toolName.lowercased().hasPrefix("notion")
    }

    private var isSlackTool: Bool {
        toolName.lowercased().hasPrefix("slack")
    }

    private var isLinearTool: Bool {
        toolName.lowercased().hasPrefix("linear")
    }

    private var isCalendarTool: Bool {
        toolName.lowercased().hasPrefix("calendar")
    }

    // Internal app tools (meetings, contacts, memory, screenshot)
    private var isAppTool: Bool {
        let name = toolName.lowercased()
        let appToolPrefixes = [
            "meeting", "contact", "company", "memory", "screenshot", "save", "list", "get",
            "search", "delete",
        ]
        if isSlackTool || isLinearTool || isCalendarTool || isNotionTool {
            return false
        }
        return appToolPrefixes.contains { name.hasPrefix($0) || name.contains($0) }
    }

    private var toolColor: Color {
        if isNotionTool { return Color.black }
        if isSlackTool { return Color(hex: "4A154B") }
        if isLinearTool { return Color(hex: "5E6AD2") }
        if isCalendarTool { return Color(hex: "4285F4") }
        if isAppTool { return Color.clear }  // TossLogo has its own background
        return .orange
    }

    @ViewBuilder
    private var toolIcon: some View {
        if isNotionTool {
            Image("NotionLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else if isSlackTool {
            Image("SlackLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else if isLinearTool {
            Image("LinearLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else if isCalendarTool {
            Image("GoogleCalendarLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else if isAppTool {
            Image("TossLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)  // Full size since app icon has its own styling
        } else {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // Use a purple accent for app tools
    private var appToolColor: Color {
        Color(hex: "8B5CF6")  // Purple accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isAppTool {
                    // App tools show the app icon directly
                    toolIcon
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ZStack {
                        Circle().fill(toolColor)
                        toolIcon
                    }
                    .frame(width: 24, height: 24)
                }

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
                .fill((isAppTool ? appToolColor : toolColor).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke((isAppTool ? appToolColor : toolColor).opacity(0.2), lineWidth: 1)
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

// MARK: - Cursor Prompt Preview

struct CursorPromptPreview: View {
    let params: ToolParams
    let compact: Bool
    let title: String
    let context: String
    var isExecuting: Bool = false
    var onOpenInCursor: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var didCopyLink = false

    private var prompt: String { params.getString("prompt") ?? "" }

    // Cursor brand color
    private let cursorColor = Color(hex: "00D1FF")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Cursor branding
            HStack(spacing: 10) {
                // Cursor icon
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image("CursorLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(1)

                    Text(context)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                // Secondary CTA: Copy Link
                Button {
                    onCopyLink?()
                    didCopyLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didCopyLink = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopyLink ? "checkmark" : "link")
                            .font(.system(size: 10))
                        Text(didCopyLink ? "Copied" : "Copy Link")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(didCopyLink ? .green : AppTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppTheme.subtleStroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Primary CTA: Open in Cursor
                Button {
                    onOpenInCursor?()
                } label: {
                    if isExecuting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Opening...")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(cursorColor.opacity(0.7))
                        )
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10))
                            Text("Open in Cursor")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(cursorColor)
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isExecuting)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Prompt code block
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Prompt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    Spacer()

                    if prompt.count > 300 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Collapse" : "Expand")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(cursorColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Code block style prompt display
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppTheme.primaryText.opacity(0.9))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: isExpanded ? 400 : (compact ? 100 : 150))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(cursorColor.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cursorColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // Generate Cursor deep link URL
    static func generateDeepLink(prompt: String) -> URL? {
        let baseUrl = "cursor://anysphere.cursor-deeplink/prompt"
        guard var components = URLComponents(string: baseUrl) else { return nil }
        components.queryItems = [URLQueryItem(name: "text", value: prompt)]
        return components.url
    }

    // Generate web link for sharing
    static func generateWebLink(prompt: String) -> URL? {
        let baseUrl = "https://cursor.com/link/prompt"
        guard var components = URLComponents(string: baseUrl) else { return nil }
        components.queryItems = [URLQueryItem(name: "text", value: prompt)]
        return components.url
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
    EditableSlackMessagePreview(
        params: ToolParams([
            "channelId": AnyCodable("C12345"),
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
    var isConnecting: Bool = false
    var onConnect: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String

    private var startTime: String? { initialParams.getString("startTime") }
    private var endTime: String? { initialParams.getString("endTime") }
    private var attendees: [String]? { initialParams.getStringArray("attendees") }

    private var formattedTime: String {
        guard let start = startTime else { return "No time specified" }

        guard let date = DateParsingHelper.parseISODate(start) else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        if let end = endTime, let endD = DateParsingHelper.parseISODate(end) {
            let minutes = Int(endD.timeIntervalSince(date) / 60)
            if minutes == 60 {
                result += " (1 hour)"
            } else if minutes > 60 {
                result += " (\(minutes / 60)h \(minutes % 60)m)"
            } else {
                result += " (\(minutes) min)"
            }
        }
        return result
    }

    init(
        params: ToolParams,
        compact: Bool,
        onParamsChanged: (([String: AnyCodableValue]) -> Void)? = nil,
        isExecuting: Bool = false,
        onExecute: (() -> Void)? = nil,
        isConnecting: Bool = false,
        onConnect: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute
        self.isConnecting = isConnecting
        self.onConnect = onConnect

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
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 10))
                                Text("Add to Calendar")
                                    .font(.system(size: 12, weight: .semibold))
                                ButtonShortcutHint()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                } else if let onConnect = onConnect {
                    Button {
                        onConnect()
                    } label: {
                        if isConnecting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Connecting...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                Text("Connect Google")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
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

// MARK: - Editable Calendar Delete Event Preview

struct EditableCalendarDeleteEventPreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var eventInfo: CalendarEventInfo?
    @State private var isLoadingEvent = true
    @State private var loadError: String?

    private var eventId: String { initialParams.getString("eventId") ?? "Unknown Event" }

    private var formattedTime: String? {
        guard let start = eventInfo?.start else { return nil }

        guard let date = DateParsingHelper.parseISODate(start) else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        if let end = eventInfo?.end, let endD = DateParsingHelper.parseISODate(end) {
            let minutes = Int(endD.timeIntervalSince(date) / 60)
            if minutes == 60 {
                result += " (1 hour)"
            } else if minutes > 60 {
                result += " (\(minutes / 60)h \(minutes % 60)m)"
            } else {
                result += " (\(minutes) min)"
            }
        }

        return result
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
                    Text("Delete Calendar Event")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("This event will be permanently removed from your calendar")
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
                                Text("Deleting...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.7)))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Delete Event")
                                    .font(.system(size: 12, weight: .semibold))
                                ButtonShortcutHint()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting || isLoadingEvent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Event details - use fixed minimum height to prevent layout shift
            VStack(spacing: 0) {
                if isLoadingEvent {
                    // Loading skeleton - reserve space for typical event content
                    VStack(spacing: 0) {
                        // Event title skeleton
                        FormRow(label: "Event") {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.secondaryText.opacity(0.2))
                                    .frame(width: 180, height: 16)
                                Spacer()
                            }
                        }
                        Divider().background(AppTheme.subtleStroke)
                        // Time skeleton
                        FormRow(label: "When") {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.secondaryText.opacity(0.15))
                                .frame(width: 200, height: 14)
                        }
                        Divider().background(AppTheme.subtleStroke)
                        // Guests skeleton
                        FormRow(label: "Guests") {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.secondaryText.opacity(0.15))
                                .frame(width: 150, height: 14)
                        }
                    }
                } else if let error = loadError {
                    // Error state
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                    }
                    .padding(14)
                } else if let event = eventInfo {
                    // Event title
                    FormRow(label: "Event") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(event.summary ?? "Untitled Event")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }

                    // Time
                    Divider().background(AppTheme.subtleStroke)
                    FormRow(label: "When") {
                        if let time = formattedTime {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.secondaryText)
                                Text(time)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.primaryText)
                                Spacer(minLength: 0)
                            }
                        } else {
                            Text("No time specified")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }

                    // Attendees - always show row to prevent layout shift
                    Divider().background(AppTheme.subtleStroke)
                    FormRow(label: "Guests") {
                        if let attendees = event.attendees, !attendees.isEmpty {
                            let names = attendees.compactMap { $0.displayName ?? $0.email }
                            Text(names.joined(separator: ", "))
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(2)
                        } else {
                            Text("No guests")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }

                    // Description (if available)
                    if let desc = event.description, !desc.isEmpty {
                        Divider().background(AppTheme.subtleStroke)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(desc)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .task {
            await fetchEventInfo()
        }
    }

    private func fetchEventInfo() async {
        guard !eventId.isEmpty, eventId != "Unknown Event" else {
            isLoadingEvent = false
            loadError = "No event ID provided"
            return
        }

        do {
            eventInfo = try await CalendarAPI.shared.getEventInfo(eventId: eventId)
        } catch {
            NSLog("[EditableCalendarDeleteEventPreview] Failed to fetch event info: \(error)")
            loadError = "Could not load event details"
        }
        isLoadingEvent = false
    }
}

// MARK: - Editable Calendar Update Event Preview

struct EditableCalendarUpdateEventPreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String
    @State private var eventInfo: CalendarEventInfo?
    @State private var isLoadingEvent = true
    @State private var loadError: String?

    private var eventId: String { initialParams.getString("eventId") ?? "Unknown Event" }
    private var newStartTime: String? { initialParams.getString("startTime") }
    private var newEndTime: String? { initialParams.getString("endTime") }

    /// Describes what's being updated
    private var updateSummary: String {
        var changes: [String] = []
        if !title.isEmpty || initialParams.getString("title") != nil { changes.append("title") }
        if newStartTime != nil { changes.append("time") }
        if !description.isEmpty || initialParams.getString("description") != nil {
            changes.append("description")
        }

        if changes.isEmpty {
            return "No changes specified"
        } else if changes.count == 1 {
            return "Updating \(changes[0])"
        } else {
            return "Updating \(changes.dropLast().joined(separator: ", ")) and \(changes.last!)"
        }
    }

    private func formatTime(start: String?, end: String?) -> String? {
        guard let start = start else { return nil }

        guard let date = DateParsingHelper.parseISODate(start) else { return start }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        var result = displayFormatter.string(from: date)

        if let end = end, let endD = DateParsingHelper.parseISODate(end) {
            let minutes = Int(endD.timeIntervalSince(date) / 60)
            if minutes == 60 {
                result += " (1 hour)"
            } else if minutes > 60 {
                result += " (\(minutes / 60)h \(minutes % 60)m)"
            } else {
                result += " (\(minutes) min)"
            }
        }

        return result
    }

    private var formattedCurrentTime: String? {
        formatTime(start: eventInfo?.start, end: eventInfo?.end)
    }

    private var formattedNewTime: String? {
        formatTime(start: newStartTime, end: newEndTime)
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

        _title = State(initialValue: params.getString("title") ?? "")
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
                    Text("Update Calendar Event")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    if isLoadingEvent {
                        Text("Loading event details...")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    } else {
                        Text(updateSummary)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    }
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
                                Text("Updating...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.7)))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                Text("Update Event")
                                    .font(.system(size: 12, weight: .semibold))
                                ButtonShortcutHint()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting || isLoadingEvent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Event details - use consistent row structure to prevent layout shift
            VStack(spacing: 0) {
                if isLoadingEvent {
                    // Loading skeleton - matches loaded state structure
                    VStack(spacing: 0) {
                        // Event title skeleton
                        FormRow(label: "Event") {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppTheme.secondaryText.opacity(0.2))
                                    .frame(width: 180, height: 16)
                                Spacer()
                            }
                        }
                        Divider().background(AppTheme.subtleStroke)
                        // Time skeleton
                        FormRow(label: "When") {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.secondaryText.opacity(0.15))
                                .frame(width: 200, height: 14)
                        }
                        Divider().background(AppTheme.subtleStroke)
                        // Guests skeleton
                        FormRow(label: "Guests") {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.secondaryText.opacity(0.15))
                                .frame(width: 150, height: 14)
                        }
                    }
                } else if let error = loadError {
                    // Error state
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .padding(14)
                } else if let event = eventInfo {
                    // Current event title
                    FormRow(label: "Event") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: "4285F4"))
                                .frame(width: 8, height: 8)
                            Text(event.summary ?? "Untitled Event")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }

                    // Title change (if updating)
                    if !title.isEmpty || initialParams.getString("title") != nil {
                        Divider().background(AppTheme.subtleStroke)
                        FormRow(label: "New Title") {
                            TextField("New title", text: $title)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.primaryText)
                                .onChange(of: title) { _, _ in notifyParamsChanged() }
                        }
                    }

                    // Time change (current -> new)
                    if newStartTime != nil {
                        Divider().background(AppTheme.subtleStroke)

                        // Current time (with strikethrough)
                        if let currentTime = formattedCurrentTime {
                            FormRow(label: "Current") {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.secondaryText)
                                    Text(currentTime)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.secondaryText)
                                        .strikethrough(true, color: AppTheme.secondaryText)
                                    Spacer(minLength: 0)
                                }
                            }
                        }

                        // New time
                        if let newTime = formattedNewTime {
                            FormRow(label: "New Time") {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "4285F4"))
                                    Text(newTime)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.primaryText)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    } else if let currentTime = formattedCurrentTime {
                        // Just show current time (not being changed)
                        Divider().background(AppTheme.subtleStroke)
                        FormRow(label: "When") {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.secondaryText)
                                Text(currentTime)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.primaryText)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    // Attendees - always show row to prevent layout shift
                    Divider().background(AppTheme.subtleStroke)
                    FormRow(label: "Guests") {
                        if let attendees = event.attendees, !attendees.isEmpty {
                            let names = attendees.compactMap { $0.displayName ?? $0.email }
                            Text(names.joined(separator: ", "))
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(2)
                        } else {
                            Text("No guests")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }

                    // Description change (if updating)
                    if !description.isEmpty || initialParams.getString("description") != nil {
                        Divider().background(AppTheme.subtleStroke)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("New Description")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText)

                            TextField("New description...", text: $description, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(3...6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: description) { _, _ in notifyParamsChanged() }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
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
            await fetchEventInfo()
        }
    }

    private func fetchEventInfo() async {
        guard !eventId.isEmpty, eventId != "Unknown Event" else {
            isLoadingEvent = false
            loadError = "No event ID provided"
            return
        }

        do {
            eventInfo = try await CalendarAPI.shared.getEventInfo(eventId: eventId)
        } catch {
            NSLog("[EditableCalendarUpdateEventPreview] Failed to fetch event info: \(error)")
            loadError = "Could not load event details"
        }
        isLoadingEvent = false
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        updatedParams["eventId"] = .string(eventId)
        if let start = newStartTime {
            updatedParams["startTime"] = .string(start)
        }
        if let end = newEndTime {
            updatedParams["endTime"] = .string(end)
        }
        if !title.isEmpty {
            updatedParams["title"] = .string(title)
        }
        if !description.isEmpty {
            updatedParams["description"] = .string(description)
        }
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
    var isConnecting: Bool = false
    var onConnect: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String
    @State private var assigneeInfo: LinearUserInfo?
    @State private var isLoadingAssignee = true

    private var priority: Int? { initialParams.getInt("priority") }
    private var team: String? {
        initialParams.getString("teamId") ?? initialParams.getString("team")
    }
    private var assigneeId: String? {
        initialParams.getString("assigneeId") ?? initialParams.getString("assignee")
    }

    private var assigneeDisplay: String {
        if let info = assigneeInfo {
            return info.displayName.isEmpty ? info.name : info.displayName
        }
        // Still loading - show assignee ID as placeholder
        return assigneeId ?? ""
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
        onExecute: (() -> Void)? = nil,
        isConnecting: Bool = false,
        onConnect: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute
        self.isConnecting = isConnecting
        self.onConnect = onConnect

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
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text("Create Issue")
                                    .font(.system(size: 12, weight: .semibold))
                                ButtonShortcutHint()
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
                } else if let onConnect = onConnect {
                    Button {
                        onConnect()
                    } label: {
                        if isConnecting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Connecting...")
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
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                Text("Connect Linear")
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
                    .disabled(isConnecting)
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

                if team != nil || assigneeId != nil {
                    Divider().background(AppTheme.subtleStroke)
                    HStack(spacing: 0) {
                        if let team = team {
                            FormRow(label: "Team") {
                                Text(team)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.primaryText)
                            }
                        }
                        if assigneeId != nil {
                            FormRow(label: "Assignee") {
                                HStack(spacing: 6) {
                                    if isLoadingAssignee {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .frame(width: 10, height: 10)
                                    }
                                    Text(assigneeDisplay)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.primaryText)
                                }
                            }
                        }
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Description - with scrollable content when text overflows
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    ScrollView {
                        TextField("Add a description...", text: $description, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primaryText)
                            .lineLimit(nil)
                            .onChange(of: description) { _, _ in notifyParamsChanged() }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)  // Allow scrolling if content exceeds this height
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
            await fetchAssigneeInfo()
        }
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        if let p = priority { updatedParams["priority"] = .int(p) }
        if let t = team { updatedParams["teamId"] = .string(t) }
        if let a = assigneeId { updatedParams["assigneeId"] = .string(a) }
        updatedParams["title"] = .string(title)
        updatedParams["description"] = .string(description)
        onParamsChanged?(updatedParams)
    }

    private func fetchAssigneeInfo() async {
        guard let assigneeId = assigneeId, !assigneeId.isEmpty else {
            isLoadingAssignee = false
            return
        }

        do {
            assigneeInfo = try await LinearAPI.shared.getUserInfo(userId: assigneeId)
        } catch {
            NSLog("[EditableLinearIssuePreview] Failed to fetch assignee info: \(error)")
        }
        isLoadingAssignee = false
    }
}

// MARK: - Editable Slack Message Preview

struct EditableSlackMessagePreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil
    var isConnecting: Bool = false
    var onConnect: (() -> Void)? = nil

    @State private var message: String
    @State private var channelInfo: SlackChannelInfo?
    @State private var isLoadingChannel = true

    private var channelId: String {
        initialParams.getString("channelId") ?? initialParams.getString("channel") ?? ""
    }

    private var sendAt: String? {
        initialParams.getString("sendAt")
    }

    private var isScheduled: Bool {
        sendAt != nil && !sendAt!.isEmpty
    }

    private var formattedScheduleTime: String? {
        guard let sendAt = sendAt, !sendAt.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try parsing with fractional seconds first, then without
        var date = formatter.date(from: sendAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: sendAt)
        }

        guard let parsedDate = date else { return sendAt }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: parsedDate)
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
        onExecute: (() -> Void)? = nil,
        isConnecting: Bool = false,
        onConnect: (() -> Void)? = nil
    ) {
        self.initialParams = params
        self.compact = compact
        self.onParamsChanged = onParamsChanged
        self.isExecuting = isExecuting
        self.onExecute = onExecute
        self.isConnecting = isConnecting
        self.onConnect = onConnect

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
                    Text(isScheduled ? "Schedule Slack Message" : "Send Slack Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text(
                        isScheduled
                            ? "Toss will schedule this message to Slack"
                            : "Toss will send this message to Slack"
                    )
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
                                Text(isScheduled ? "Scheduling..." : "Sending...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(
                                    Color(hex: "4A154B").opacity(0.7)))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: isScheduled ? "clock.fill" : "paperplane.fill")
                                    .font(.system(size: 10))
                                Text(isScheduled ? "Schedule Message" : "Send Message")
                                    .font(.system(size: 12, weight: .semibold))
                                ButtonShortcutHint()
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
                } else if let onConnect = onConnect {
                    Button {
                        onConnect()
                    } label: {
                        if isConnecting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Connecting...")
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
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                Text("Connect Slack")
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
                    .disabled(isConnecting)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            // Key-value rows
            VStack(spacing: 0) {
                // Channel or DM row
                FormRow(label: isLoadingChannel ? "To" : (isDirectMessage ? "To" : "Channel")) {
                    if isLoadingChannel {
                        // Skeleton loader
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.secondaryText.opacity(0.2))
                            .frame(width: 80, height: 16)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: isDirectMessage ? "person.fill" : "number")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(channelDisplay)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                        }
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Scheduled row (only shown when scheduling)
                if let scheduledTime = formattedScheduleTime {
                    FormRow(label: "Scheduled for", labelWidth: 90) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(scheduledTime)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                        }
                    }

                    Divider().background(AppTheme.subtleStroke)
                }

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

// MARK: - Editable Flow Preview

struct EditableFlowPreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var definition: String

    private var trigger: String {
        initialParams.getString("trigger") ?? "meeting_ended"
    }

    private var enabled: Bool {
        initialParams.getBool("enabled") ?? true
    }

    private var triggerDisplay: String {
        switch trigger {
        case "meeting_ended":
            return "After every meeting"
        default:
            return trigger.replacingOccurrences(of: "_", with: " ").capitalized
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

        _definition = State(initialValue: params.getString("definition") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("TossLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Flow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will run this automation \(triggerDisplay.lowercased())")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

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
                                    Color(hex: "8B5CF6").opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("Create Flow")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color(hex: "8B5CF6")))
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

            VStack(spacing: 0) {
                // Trigger row
                FormRow(label: "Trigger", labelWidth: 70) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                        Text(triggerDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.primaryText)
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Status row
                FormRow(label: "Status", labelWidth: 70) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(enabled ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(enabled ? "Enabled" : "Disabled")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.primaryText)
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                // Definition
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to do")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("Describe what should happen...", text: $definition, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(3...8)
                        .onChange(of: definition) { _, _ in notifyParamsChanged() }
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "8B5CF6").opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        updatedParams["definition"] = .string(definition)
        updatedParams["trigger"] = .string(trigger)
        updatedParams["enabled"] = .bool(enabled)
        onParamsChanged?(updatedParams)
    }
}

// MARK: - Editable Notion Create Database Preview

struct EditableNotionCreateDatabasePreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var title: String
    @State private var parentPageInfo: NotionPageInfo?
    @State private var isLoadingParent = true

    private var parentPageId: String {
        initialParams.getString("parentPageId") ?? ""
    }

    // Parse properties from params
    private var propertyNames: [String] {
        // Properties is a nested object like { "Summary": { "type": "rich_text" }, ... }
        // We'll show the property names
        var names: [String] = ["Name"]  // Always includes Name
        if let allKeys = initialParams.getAllKeys().first(where: { $0 == "properties" }) {
            // For now just show that properties are defined
            names.append(contentsOf: ["(custom properties)"])
        }
        return names
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

        _title = State(initialValue: params.getString("title") ?? "Untitled Database")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("NotionLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Notion Database")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will create a new database in Notion")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

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
                                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text("Create Database")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
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

            VStack(spacing: 0) {
                FormRow(label: "Title") {
                    TextField("Database title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .onChange(of: title) { _, _ in notifyParamsChanged() }
                }

                Divider().background(AppTheme.subtleStroke)

                FormRow(label: "Parent", labelWidth: 70) {
                    if isLoadingParent {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.secondaryText.opacity(0.2))
                            .frame(width: 100, height: 16)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(parentPageInfo?.title ?? parentPageId)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(1)
                        }
                    }
                }
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
            await fetchParentPageInfo()
        }
    }

    private func fetchParentPageInfo() async {
        guard !parentPageId.isEmpty else {
            isLoadingParent = false
            return
        }

        do {
            parentPageInfo = try await NotionAPI.shared.getPageInfo(pageId: parentPageId)
        } catch {
            NSLog(
                "[EditableNotionCreateDatabasePreview] Failed to fetch parent page info: \(error)")
        }
        isLoadingParent = false
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        updatedParams["parentPageId"] = .string(parentPageId)
        updatedParams["title"] = .string(title)
        onParamsChanged?(updatedParams)
    }
}

// MARK: - Editable Notion Create Page Preview

struct EditableNotionCreatePagePreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var title: String
    @State private var content: String
    @State private var parentPageInfo: NotionPageInfo?
    @State private var isLoadingParent = true

    private var parentPageId: String {
        initialParams.getString("parentPageId") ?? initialParams.getString("databaseId") ?? ""
    }

    private var isDatabase: Bool {
        initialParams.getString("databaseId") != nil
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

        _title = State(initialValue: params.getString("title") ?? "Untitled")
        _content = State(initialValue: params.getString("content") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("NotionLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Notion Page")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text(
                        isDatabase
                            ? "Toss will add a new entry to your database"
                            : "Toss will create a new page in Notion"
                    )
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

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
                                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 10))
                                Text("Create Page")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
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

            VStack(spacing: 0) {
                FormRow(label: "Title") {
                    TextField("Page title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .onChange(of: title) { _, _ in notifyParamsChanged() }
                }

                Divider().background(AppTheme.subtleStroke)

                FormRow(label: isDatabase ? "Database" : "Parent", labelWidth: 70) {
                    if isLoadingParent {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.secondaryText.opacity(0.2))
                            .frame(width: 100, height: 16)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: isDatabase ? "tablecells" : "doc.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(parentPageInfo?.title ?? parentPageId)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(1)
                        }
                    }
                }

                if !content.isEmpty {
                    Divider().background(AppTheme.subtleStroke)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)

                        TextField("Page content...", text: $content, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.primaryText)
                            .lineLimit(3...6)
                            .onChange(of: content) { _, _ in notifyParamsChanged() }
                    }
                    .padding(14)
                }
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
            await fetchParentPageInfo()
        }
    }

    private func fetchParentPageInfo() async {
        guard !parentPageId.isEmpty else {
            isLoadingParent = false
            return
        }

        do {
            parentPageInfo = try await NotionAPI.shared.getPageInfo(pageId: parentPageId)
        } catch {
            NSLog("[EditableNotionCreatePagePreview] Failed to fetch parent page info: \(error)")
        }
        isLoadingParent = false
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        if isDatabase {
            updatedParams["databaseId"] = .string(parentPageId)
        } else {
            updatedParams["parentPageId"] = .string(parentPageId)
        }
        updatedParams["title"] = .string(title)
        updatedParams["content"] = .string(content)
        onParamsChanged?(updatedParams)
    }
}

// MARK: - Editable Notion Append Blocks Preview

struct EditableNotionAppendBlocksPreview: View {
    let initialParams: ToolParams
    let compact: Bool
    var onParamsChanged: (([String: AnyCodableValue]) -> Void)?
    var isExecuting: Bool = false
    var onExecute: (() -> Void)? = nil

    @State private var content: String
    @State private var pageInfo: NotionPageInfo?
    @State private var isLoadingPage = true

    private var pageId: String {
        initialParams.getString("pageId") ?? ""
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

        _content = State(initialValue: params.getString("content") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("NotionLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Append to Notion Page")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Toss will add content to an existing page")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Spacer()

                if let onExecute = onExecute {
                    Button {
                        onExecute()
                    } label: {
                        if isExecuting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Adding...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "text.badge.plus")
                                    .font(.system(size: 10))
                                Text("Add Content")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
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

            VStack(spacing: 0) {
                FormRow(label: "Page", labelWidth: 70) {
                    if isLoadingPage {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.secondaryText.opacity(0.2))
                            .frame(width: 100, height: 16)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(pageInfo?.title ?? pageId)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.primaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Divider().background(AppTheme.subtleStroke)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Content")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("Content to append...", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(3...8)
                        .onChange(of: content) { _, _ in notifyParamsChanged() }
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
            await fetchPageInfo()
        }
    }

    private func fetchPageInfo() async {
        guard !pageId.isEmpty else {
            isLoadingPage = false
            return
        }

        do {
            pageInfo = try await NotionAPI.shared.getPageInfo(pageId: pageId)
        } catch {
            NSLog("[EditableNotionAppendBlocksPreview] Failed to fetch page info: \(error)")
        }
        isLoadingPage = false
    }

    private func notifyParamsChanged() {
        var updatedParams: [String: AnyCodableValue] = [:]
        updatedParams["pageId"] = .string(pageId)
        updatedParams["content"] = .string(content)
        onParamsChanged?(updatedParams)
    }
}

// Helper view for key-value form rows
private struct FormRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 70
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: labelWidth, alignment: .leading)

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
