import SwiftUI

// MARK: - Flow Models

struct Flow: Codable, Identifiable, Equatable {
    let id: String
    var title: String?
    var definition: String
    var icon: String?
    let trigger: String
    var enabled: Bool
    let createdAt: String
    let updatedAt: String

    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }

    var triggerDisplayName: String {
        switch trigger {
        case "meeting_ended":
            return "After meetings"
        default:
            return trigger
        }
    }

    /// Display title - uses title if set, otherwise truncated definition
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        let maxLength = 30
        return definition.count > maxLength
            ? String(definition.prefix(maxLength)) + "..."
            : definition
    }
}

struct FlowsResponse: Codable {
    let flows: [Flow]
}

struct FlowResponse: Codable {
    let flow: Flow
}

struct FlowRun: Codable, Identifiable {
    let id: String
    let status: String
    let resultSummary: String?
    let errorMessage: String?
    let startedAt: String
    let completedAt: String?
    let meetingId: String?
    let meetingTitle: String?

    var startedAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: startedAt)
    }
}

// Flow execution step for detailed history playback (Cofounder-style)
struct FlowExecutionStep: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let type: String  // "thinking", "tool_call", "tool_result", "text"
    let content: String
    let toolName: String?
    let toolInput: [String: AnyCodableValue]?
    let toolOutput: AnyCodableValue?
    let timestamp: String

    var icon: String {
        switch type {
        case "tool_call":
            return "arrow.right.circle"
        case "tool_result":
            return "checkmark.circle"
        case "text":
            return "text.bubble"
        case "thinking":
            return "brain"
        default:
            return "circle"
        }
    }

    var iconColor: Color {
        switch type {
        case "tool_call":
            return .blue
        case "tool_result":
            return .green
        case "text":
            return .primary
        case "thinking":
            return .purple
        default:
            return .secondary
        }
    }
}

// Flow run with full execution details (for meeting flow runs)
struct MeetingFlowRun: Codable, Identifiable {
    let id: String
    let flowId: String
    let flowTitle: String?
    let flowDefinition: String
    let flowIcon: String?
    let status: String
    let resultSummary: String?
    let errorMessage: String?
    let toolCalls: [FlowToolCall]?
    let steps: [FlowExecutionStep]?
    let startedAt: String
    let completedAt: String?

    var startedAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: startedAt)
    }

    var statusIcon: String {
        switch status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.circle.fill"
        case "running":
            return "circle.dotted"
        default:
            return "questionmark.circle"
        }
    }

    var statusColor: Color {
        switch status {
        case "completed":
            return .green
        case "failed":
            return .red
        case "running":
            return .blue
        default:
            return .secondary
        }
    }

    /// Display title - uses title if set, otherwise truncated definition
    var displayTitle: String {
        if let title = flowTitle, !title.isEmpty {
            return title
        }
        let maxLength = 30
        return flowDefinition.count > maxLength
            ? String(flowDefinition.prefix(maxLength)) + "..."
            : flowDefinition
    }
}

struct FlowToolCall: Codable {
    let toolName: String
    let args: [String: AnyCodableValue]?
    let result: AnyCodableValue?
    let timestamp: String
}

struct FlowRunsResponse: Codable {
    let runs: [FlowRun]
}

struct MeetingFlowRunsResponse: Codable {
    let runs: [MeetingFlowRun]
}

// MARK: - Flows API

final class FlowsAPI {
    static let shared = FlowsAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func listFlows() async throws -> [Flow] {
        let url = baseURL.appendingPathComponent("flows")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await APIClient.shared.perform(request)
        let response = try JSONDecoder().decode(FlowsResponse.self, from: data)
        return response.flows
    }

    func createFlow(definition: String, trigger: String = "meeting_ended") async throws -> Flow {
        let url = baseURL.appendingPathComponent("flows")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "definition": definition,
            "trigger": trigger,
            "enabled": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw URLError(.badServerResponse)
        }
        let flowResponse = try JSONDecoder().decode(FlowResponse.self, from: data)
        return flowResponse.flow
    }

    func updateFlow(
        id: String,
        title: String? = nil,
        definition: String? = nil,
        enabled: Bool? = nil
    ) async throws -> Flow {
        let url = baseURL.appendingPathComponent("flows/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let title = title {
            body["title"] = title
        }
        if let definition = definition {
            body["definition"] = definition
        }
        if let enabled = enabled {
            body["enabled"] = enabled
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let flowResponse = try JSONDecoder().decode(FlowResponse.self, from: data)
        return flowResponse.flow
    }

    func deleteFlow(id: String) async throws {
        let url = baseURL.appendingPathComponent("flows/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    func getFlowRuns(flowId: String) async throws -> [FlowRun] {
        let url = baseURL.appendingPathComponent("flows/\(flowId)/runs")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await APIClient.shared.perform(request)
        let response = try JSONDecoder().decode(FlowRunsResponse.self, from: data)
        return response.runs
    }

    /// Get all flow runs for a specific meeting (for the Flows tab in MeetingView)
    func getMeetingFlowRuns(meetingId: UUID) async throws -> [MeetingFlowRun] {
        let url = baseURL.appendingPathComponent(
            "flows/meeting/\(meetingId.uuidString.lowercased())/runs")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await APIClient.shared.perform(request)
        let response = try JSONDecoder().decode(MeetingFlowRunsResponse.self, from: data)
        return response.runs
    }

    /// Trigger flows for a meeting (called after meeting sync completes)
    /// Returns the number of flows triggered, or nil if already triggered
    func triggerFlows(for meetingId: UUID) async throws -> TriggerFlowsResponse {
        let url = baseURL.appendingPathComponent(
            "flows/trigger/\(meetingId.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(TriggerFlowsResponse.self, from: data)
    }
}

struct TriggerFlowsResponse: Codable {
    let triggered: Bool
    let flowCount: Int?
    let message: String?
    let flows: [TriggeredFlow]?
}

/// Minimal flow info returned when triggering flows (for notifications)
struct TriggeredFlow: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
}

// MARK: - Flows View

@MainActor
struct FlowsView: View {
    @State private var flows: [Flow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateModal = false
    @State private var editingFlow: Flow?
    @State private var editTitle: String = ""
    @State private var editText: String = ""
    @State private var newFlowText: String = ""
    @State private var hoveredId: String?
    @State private var deletingId: String?
    @State private var togglingId: String?
    @State private var selectedFlowForRuns: Flow?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Flows")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AppTheme.primaryText)

                            Text("Automated actions that run after your meetings")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.secondaryText)
                        }

                        Spacer()

                        Button {
                            newFlowText = ""
                            showCreateModal = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("New Flow")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if isLoading && flows.isEmpty {
                        loadingState
                    } else if let error = errorMessage {
                        errorState(error)
                    } else if flows.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(flows) { flow in
                                flowCard(flow)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
            }
            .onAppear {
                loadFlows()
            }

            // Create modal overlay
            if showCreateModal {
                createModal
            }

            // Edit modal overlay
            if editingFlow != nil {
                editModal
            }

            // Runs modal overlay
            if selectedFlowForRuns != nil {
                runsModal
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading flows...")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Failed to load flows")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)

            Button("Try Again") {
                loadFlows()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.accentColor))
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "command")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))

            Text("No flows yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            Text(
                "Create a flow to automatically run actions after your meetings — like syncing notes to Notion or sharing to Slack."
            )
            .font(.system(size: 13))
            .foregroundColor(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)

            Button {
                newFlowText = ""
                showCreateModal = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Create your first flow")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Flow Card (Cofounder-inspired)

    private func flowCard(_ flow: Flow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: icon, title, and status
            HStack(spacing: 10) {
                // Flow icon(s)
                flowIconView(for: flow.icon)

                // Title
                Text(flow.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(flow.enabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(flow.enabled ? "Auto" : "Paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(flow.enabled ? Color.green : AppTheme.secondaryText)
                }
            }

            // Definition text (secondary)
            Text(flow.definition)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .lineLimit(2)

            // Bottom row: actions
            HStack(spacing: 12) {
                // Toggle button
                Button {
                    toggleFlow(flow)
                } label: {
                    if togglingId == flow.id {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: flow.enabled ? "pause.circle" : "play.circle")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .help(flow.enabled ? "Pause flow" : "Enable flow")
                .disabled(togglingId == flow.id)

                // View runs button
                Button {
                    selectedFlowForRuns = flow
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("View run history")

                // Edit button
                Button {
                    editTitle = flow.title ?? ""
                    editText = flow.definition
                    editingFlow = flow
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Edit flow")

                Spacer()

                // Delete button
                Button {
                    deleteFlow(flow)
                } label: {
                    if deletingId == flow.id {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(
                                hoveredId == flow.id
                                    ? .red.opacity(0.8) : AppTheme.secondaryText.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .help("Delete flow")
                .disabled(deletingId == flow.id)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    hoveredId == flow.id
                        ? Color.white.opacity(0.15) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredId = hovering ? flow.id : nil
            }
        }
    }

    // MARK: - Flow Icon Helper

    /// Displays icon(s) for a flow based on its destinations
    @ViewBuilder
    private func flowIconView(for icon: String?) -> some View {
        let icons = (icon ?? "generic").split(separator: ",").map(String.init)

        HStack(spacing: -6) {
            ForEach(Array(icons.prefix(2).enumerated()), id: \.offset) { index, iconName in
                iconImage(for: iconName)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.cardBackground, lineWidth: 2)
                    )
                    .zIndex(Double(icons.count - index))
            }
        }
    }

    /// Returns the appropriate image for an icon identifier
    @ViewBuilder
    private func iconImage(for icon: String) -> some View {
        switch icon.trimmingCharacters(in: .whitespaces) {
        case "slack":
            Image("SlackLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case "notion":
            Image("NotionLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case "linear":
            Image("LinearLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case "calendar":
            Image("GoogleCalendarLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        default:
            Image(systemName: "arrow.right.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    // MARK: - Create Modal

    @FocusState private var isNewFlowFocused: Bool

    private var createModal: some View {
        ZStack {
            Color.black.opacity(0.001)
                .onTapGesture {
                    showCreateModal = false
                }

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("New Flow")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Spacer()

                    Button {
                        showCreateModal = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                // Info text
                Text("Describe what should happen after your meetings end:")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)

                // Text editor
                TextEditor(text: $newFlowText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isNewFlowFocused
                                    ? Color.accentColor : AppTheme.secondaryText.opacity(0.3),
                                lineWidth: isNewFlowFocused ? 2 : 1
                            )
                    )
                    .focused($isNewFlowFocused)

                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    ForEach(
                        [
                            "Save notes to my Meeting Notes database in Notion",
                            "Share a summary to #team-updates in Slack",
                            "Create a follow-up task in Linear for any action items",
                        ], id: \.self
                    ) { example in
                        Button {
                            newFlowText = example
                        } label: {
                            Text(example)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Buttons
                HStack {
                    Button("Cancel") {
                        showCreateModal = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.secondaryText)

                    Spacer()

                    Button {
                        createFlow()
                    } label: {
                        Text("Create Flow")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(newFlowText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        newFlowText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.5 : 1)
                }
            }
            .padding(24)
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .transition(.opacity)
        .onAppear {
            isNewFlowFocused = true
        }
    }

    // MARK: - Edit Modal

    @FocusState private var isEditFlowFocused: Bool

    private var editModal: some View {
        ZStack {
            Color.black.opacity(0.001)
                .onTapGesture {
                    editingFlow = nil
                }

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Edit Flow")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Spacer()

                    Button {
                        editingFlow = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                // Title field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextField("e.g., Sync to Notion", text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.secondaryText.opacity(0.3), lineWidth: 1)
                        )
                }

                // Definition field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)

                    TextEditor(text: $editText)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primaryText)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isEditFlowFocused
                                        ? Color.accentColor : AppTheme.secondaryText.opacity(0.3),
                                    lineWidth: isEditFlowFocused ? 2 : 1
                                )
                        )
                        .focused($isEditFlowFocused)
                }

                // Buttons
                HStack {
                    Button("Cancel") {
                        editingFlow = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.secondaryText)

                    Spacer()

                    Button {
                        saveEdit()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
            .padding(24)
            .frame(width: 450)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .transition(.opacity)
        .onAppear {
            isEditFlowFocused = true
        }
    }

    // MARK: - Runs Modal

    @State private var flowRuns: [FlowRun] = []
    @State private var loadingRuns = false

    private var runsModal: some View {
        ZStack {
            Color.black.opacity(0.001)
                .onTapGesture {
                    selectedFlowForRuns = nil
                }

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Run History")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Spacer()

                    Button {
                        selectedFlowForRuns = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if loadingRuns {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if flowRuns.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                        Text("No runs yet")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(flowRuns) { run in
                                runRow(run)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .padding(24)
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .transition(.opacity)
        .onAppear {
            loadRuns()
        }
    }

    private func runRow(_ run: FlowRun) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            statusIcon(for: run.status)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                // Meeting title or generic label
                Text(run.meetingTitle ?? "Meeting")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)

                // Result summary or error
                if let error = run.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(2)
                } else if let summary = run.resultSummary {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Time
            if let date = run.startedAtDate {
                Text(formattedTime(date))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case "running":
            ProgressView()
                .scaleEffect(0.6)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    // MARK: - Actions

    private func loadFlows() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                flows = try await FlowsAPI.shared.listFlows()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func createFlow() {
        let definition = newFlowText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else { return }

        Task {
            do {
                let newFlow = try await FlowsAPI.shared.createFlow(definition: definition)
                withAnimation {
                    flows.insert(newFlow, at: 0)
                }
                showCreateModal = false
            } catch {
                NSLog("[FlowsView] Failed to create flow: \(error)")
            }
        }
    }

    private func saveEdit() {
        guard let flow = editingFlow else { return }
        let newTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDefinition = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newDefinition.isEmpty else { return }

        Task {
            do {
                let updated = try await FlowsAPI.shared.updateFlow(
                    id: flow.id,
                    title: newTitle.isEmpty ? nil : newTitle,
                    definition: newDefinition
                )
                if let index = flows.firstIndex(where: { $0.id == flow.id }) {
                    flows[index] = updated
                }
                editingFlow = nil
            } catch {
                NSLog("[FlowsView] Failed to update flow: \(error)")
            }
        }
    }

    private func toggleFlow(_ flow: Flow) {
        togglingId = flow.id

        Task {
            do {
                let updated = try await FlowsAPI.shared.updateFlow(
                    id: flow.id, enabled: !flow.enabled)
                if let index = flows.firstIndex(where: { $0.id == flow.id }) {
                    flows[index] = updated
                }
            } catch {
                NSLog("[FlowsView] Failed to toggle flow: \(error)")
            }
            togglingId = nil
        }
    }

    private func deleteFlow(_ flow: Flow) {
        deletingId = flow.id

        Task {
            do {
                try await FlowsAPI.shared.deleteFlow(id: flow.id)
                withAnimation {
                    flows.removeAll { $0.id == flow.id }
                }
            } catch {
                NSLog("[FlowsView] Failed to delete flow: \(error)")
            }
            deletingId = nil
        }
    }

    private func loadRuns() {
        guard let flow = selectedFlowForRuns else { return }
        loadingRuns = true
        flowRuns = []

        Task {
            do {
                flowRuns = try await FlowsAPI.shared.getFlowRuns(flowId: flow.id)
            } catch {
                NSLog("[FlowsView] Failed to load runs: \(error)")
            }
            loadingRuns = false
        }
    }

    // MARK: - Helpers

    private func formattedTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
