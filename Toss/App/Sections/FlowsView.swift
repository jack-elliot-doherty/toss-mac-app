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

// MARK: - Flow Template

struct FlowTemplate: Identifiable {
	let id = UUID()
	let title: String
	let definition: String
	let icon: String
	let description: String
}

private let flowTemplates: [FlowTemplate] = [
	FlowTemplate(
		title: "Share recap to Slack",
		definition: "After the meeting ends, post a summary with key decisions and action items to #team-updates in Slack. Format it nicely with bullet points.",
		icon: "slack",
		description: "Post a formatted summary with key decisions and action items to a Slack channel after every meeting."
	),
	FlowTemplate(
		title: "Save notes to Notion",
		definition: "Save the meeting notes, summary, and action items to my Meeting Notes database in Notion. Include the date, participants, and key takeaways.",
		icon: "notion",
		description: "Save structured meeting notes with date, participants, and key takeaways to a Notion database."
	),
	FlowTemplate(
		title: "Create Linear issues",
		definition: "Review the action items from the meeting and create Linear issues for any tasks that were assigned. Include context from the discussion in the issue description.",
		icon: "linear",
		description: "Turn action items into Linear issues with relevant context from the discussion."
	),
	FlowTemplate(
		title: "Send follow-up email",
		definition: "Draft and send a follow-up email to external participants summarizing the meeting, key decisions made, and next steps with owners.",
		icon: "gmail",
		description: "Email external participants with a summary of decisions and next steps with owners."
	),
	FlowTemplate(
		title: "Schedule follow-ups",
		definition: "Check if any follow-up meetings were discussed and create Google Calendar events for them with the relevant participants.",
		icon: "calendar",
		description: "Automatically create calendar events for any follow-up meetings that were discussed."
	),
	FlowTemplate(
		title: "Slack + Notion sync",
		definition: "Post a brief summary to #team-updates in Slack, and save the full meeting notes with transcript highlights to my Meeting Notes database in Notion.",
		icon: "slack,notion",
		description: "Post a brief recap to Slack and save the full detailed notes to Notion."
	),
	FlowTemplate(
		title: "Weekly standup digest",
		definition: "If this was a standup or daily sync, extract each person's updates (what they did, what they're doing, blockers) and post a formatted digest to the team's Slack channel.",
		icon: "slack",
		description: "Extract standup updates per person and post a formatted digest to Slack."
	),
	FlowTemplate(
		title: "Client meeting CRM update",
		definition: "After a client or sales meeting, save a summary of the discussion, any commitments made, and next steps to Notion. Include the client company name and attendees.",
		icon: "notion",
		description: "Log client meeting notes, commitments, and next steps to your CRM in Notion."
	),
]

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
	@State private var showTemplatesModal = false
	@State private var editingFlow: Flow?
	@State private var editTitle: String = ""
	@State private var editText: String = ""
	@State private var newFlowText: String = ""
	@State private var hoveredId: String?
	@State private var hoveredTemplateId: UUID?
	@State private var deletingId: String?
	@State private var togglingId: String?
	@State private var creatingTemplateId: UUID?
	@State private var selectedFlowForRuns: Flow?

	var body: some View {
		ZStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
					header

					if isLoading && flows.isEmpty {
						loadingState
					} else if let error = errorMessage {
						errorState(error)
					} else if flows.isEmpty {
						emptyState
					} else {
						flowsSection
					}
				}
				.padding(.horizontal, 28)
				.padding(.vertical, 28)
			}
			.onAppear {
				loadFlows()
			}

			if showCreateModal {
				createModal
			}

			if editingFlow != nil {
				editModal
			}

			if selectedFlowForRuns != nil {
				runsModal
			}

			if showTemplatesModal {
				templatesModal
			}
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack(alignment: .center) {
			VStack(alignment: .leading, spacing: 6) {
				Text("Flows")
					.font(.system(size: 24, weight: .semibold))
					.foregroundColor(AppTheme.primaryText)

				Text("Automated actions that run after your meetings")
					.font(.system(size: 12, weight: .medium))
					.foregroundColor(AppTheme.secondaryText)
			}

			Spacer()

			if !flows.isEmpty {
				HStack(spacing: 8) {
					Button {
						showTemplatesModal = true
					} label: {
						HStack(spacing: 5) {
							Image(systemName: "square.grid.2x2")
								.font(.system(size: 11, weight: .medium))
							Text("Templates")
								.font(.system(size: 13, weight: .medium))
						}
						.foregroundColor(AppTheme.primaryText)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(
							Capsule()
								.fill(Color.white.opacity(0.08))
						)
					}
					.buttonStyle(.plain)

					Button {
						newFlowText = ""
						showCreateModal = true
					} label: {
						HStack(spacing: 5) {
							Image(systemName: "plus")
								.font(.system(size: 11, weight: .semibold))
							Text("New Flow")
								.font(.system(size: 13, weight: .medium))
						}
						.foregroundColor(AppTheme.primaryText)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(
							Capsule()
								.fill(Color.white.opacity(0.08))
						)
					}
					.buttonStyle(.plain)
				}
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

	// MARK: - Empty State (with inline templates)

	private var emptyState: some View {
		VStack(alignment: .leading, spacing: 24) {
			VStack(alignment: .leading, spacing: 6) {
				Text("Get started")
					.font(.system(size: 13, weight: .medium))
					.foregroundColor(AppTheme.secondaryText)

				Text("Pick a template to automate your post-meeting workflow, or create a custom flow.")
					.font(.system(size: 13))
					.foregroundColor(AppTheme.secondaryText.opacity(0.7))
			}

			LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
				ForEach(flowTemplates) { template in
					templateCard(template)
				}

				// Custom flow card
				Button {
					newFlowText = ""
					showCreateModal = true
				} label: {
					VStack(alignment: .leading, spacing: 10) {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.white.opacity(0.08))
							.frame(width: 36, height: 36)
							.overlay(
								Image(systemName: "plus")
									.font(.system(size: 15, weight: .medium))
									.foregroundColor(AppTheme.secondaryText)
							)

						Text("Custom flow")
							.font(.system(size: 14, weight: .semibold))
							.foregroundColor(AppTheme.primaryText)

						Text("Write your own automation in plain English.")
							.font(.system(size: 12))
							.foregroundColor(AppTheme.secondaryText)
							.lineLimit(3)
							.multilineTextAlignment(.leading)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
					.background(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.fill(Color.white.opacity(0.03))
					)
					.overlay(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.stroke(Color.white.opacity(0.06), lineWidth: 1)
					)
				}
				.buttonStyle(.plain)
			}
		}
	}

	// MARK: - Your Flows Section

	private var flowsSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Your flows")
					.font(.system(size: 13, weight: .medium))
					.foregroundColor(AppTheme.secondaryText)
				Spacer()
			}

			VStack(spacing: 0) {
				ForEach(flows) { flow in
					flowRow(flow)

					if flow.id != flows.last?.id {
						Divider()
							.background(Color.white.opacity(0.06))
					}
				}
			}
		}
	}

	// MARK: - Flow Row (meetings-style)

	private func flowRow(_ flow: Flow) -> some View {
		HStack(spacing: 12) {
			flowIconView(for: flow.icon)

			VStack(alignment: .leading, spacing: 2) {
				Text(flow.displayTitle)
					.font(.system(size: 14, weight: .medium))
					.foregroundColor(AppTheme.primaryText)
					.lineLimit(1)

				Text(flow.definition)
					.font(.system(size: 12))
					.foregroundColor(AppTheme.secondaryText)
					.lineLimit(1)
			}

			Spacer(minLength: 8)

			if hoveredId == flow.id {
				HStack(spacing: 4) {
					Button {
						selectedFlowForRuns = flow
					} label: {
						Image(systemName: "clock")
							.font(.system(size: 12))
							.foregroundColor(AppTheme.secondaryText)
							.frame(width: 28, height: 28)
							.background(Color.white.opacity(0.06))
							.clipShape(RoundedRectangle(cornerRadius: 6))
					}
					.buttonStyle(.plain)
					.help("View run history")

					Button {
						editTitle = flow.title ?? ""
						editText = flow.definition
						editingFlow = flow
					} label: {
						Image(systemName: "pencil")
							.font(.system(size: 12))
							.foregroundColor(AppTheme.secondaryText)
							.frame(width: 28, height: 28)
							.background(Color.white.opacity(0.06))
							.clipShape(RoundedRectangle(cornerRadius: 6))
					}
					.buttonStyle(.plain)
					.help("Edit flow")

					Button {
						deleteFlow(flow)
					} label: {
						if deletingId == flow.id {
							ProgressView()
								.scaleEffect(0.5)
								.frame(width: 28, height: 28)
						} else {
							Image(systemName: "trash")
								.font(.system(size: 12))
								.foregroundColor(AppTheme.secondaryText)
								.frame(width: 28, height: 28)
								.background(Color.white.opacity(0.06))
								.clipShape(RoundedRectangle(cornerRadius: 6))
						}
					}
					.buttonStyle(.plain)
					.help("Delete flow")
					.disabled(deletingId == flow.id)
				}
			} else {
				// Status pill
				HStack(spacing: 5) {
					Circle()
						.fill(flow.enabled ? Color.green : Color.gray)
						.frame(width: 6, height: 6)
					Text(flow.enabled ? "Active" : "Paused")
						.font(.system(size: 11, weight: .medium))
						.foregroundColor(flow.enabled ? Color.green : AppTheme.secondaryText)
				}
			}

			// Toggle
			Button {
				toggleFlow(flow)
			} label: {
				if togglingId == flow.id {
					ProgressView()
						.scaleEffect(0.5)
						.frame(width: 28, height: 28)
				} else {
					Image(systemName: flow.enabled ? "pause.circle" : "play.circle")
						.font(.system(size: 15))
						.foregroundColor(AppTheme.secondaryText.opacity(0.6))
				}
			}
			.buttonStyle(.plain)
			.help(flow.enabled ? "Pause flow" : "Enable flow")
			.disabled(togglingId == flow.id)
		}
		.padding(.vertical, 10)
		.padding(.horizontal, 4)
		.contentShape(Rectangle())
		.onHover { hovering in
			withAnimation(.easeInOut(duration: 0.1)) {
				hoveredId = hovering ? flow.id : nil
			}
		}
	}

	// MARK: - Template Card

	private func templateCard(_ template: FlowTemplate) -> some View {
		Button {
			addFromTemplate(template)
		} label: {
			VStack(alignment: .leading, spacing: 10) {
				HStack(spacing: 10) {
					templateIconView(for: template.icon)

					Spacer()

					if creatingTemplateId == template.id {
						ProgressView()
							.scaleEffect(0.5)
							.frame(width: 20, height: 20)
					}
				}

				Text(template.title)
					.font(.system(size: 14, weight: .semibold))
					.foregroundColor(AppTheme.primaryText)

				Text(template.description)
					.font(.system(size: 12))
					.foregroundColor(AppTheme.secondaryText)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.background(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(
						hoveredTemplateId == template.id
							? Color.white.opacity(0.06) : Color.white.opacity(0.03))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.stroke(
						hoveredTemplateId == template.id
							? Color.white.opacity(0.12) : Color.white.opacity(0.06), lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
		.disabled(creatingTemplateId != nil)
		.onHover { hovering in
			withAnimation(.easeInOut(duration: 0.1)) {
				hoveredTemplateId = hovering ? template.id : nil
			}
		}
	}

	@ViewBuilder
	private func templateIconView(for icon: String) -> some View {
		let icons = icon.split(separator: ",").map(String.init)
		if icons.count > 1 {
			HStack(spacing: -6) {
				ForEach(Array(icons.prefix(2).enumerated()), id: \.offset) { index, iconName in
					iconImage(for: iconName)
						.frame(width: 32, height: 32)
						.clipShape(RoundedRectangle(cornerRadius: 8))
						.overlay(
							RoundedRectangle(cornerRadius: 8)
								.stroke(AppTheme.cardBackground, lineWidth: 2)
						)
						.zIndex(Double(icons.count - index))
				}
			}
		} else {
			RoundedRectangle(cornerRadius: 8)
				.fill(AppTheme.secondaryText.opacity(0.1))
				.frame(width: 36, height: 36)
				.overlay(
					iconImage(for: icons.first ?? "generic")
						.frame(width: 22, height: 22)
				)
		}
	}

	// MARK: - Flow Icon Helper

	/// Displays icon(s) for a flow based on its destinations
	@ViewBuilder
	private func flowIconView(for icon: String?) -> some View {
		let icons = (icon ?? "generic").split(separator: ",").map(String.init)

		if icons.count > 1 {
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
		} else {
			RoundedRectangle(cornerRadius: 6)
				.fill(AppTheme.secondaryText.opacity(0.15))
				.frame(width: 32, height: 32)
				.overlay(
					iconImage(for: icons.first ?? "generic")
						.frame(width: 18, height: 18)
				)
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
		case "gmail":
			Image("GmailLogo")
				.resizable()
				.aspectRatio(contentMode: .fit)
		default:
			Image(systemName: "arrow.right.circle.fill")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.foregroundColor(AppTheme.secondaryText)
		}
	}

	// MARK: - Templates Modal

	private var templatesModal: some View {
		ZStack {
			Color.black.opacity(0.001)
				.onTapGesture {
					showTemplatesModal = false
				}

			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
					HStack {
						VStack(alignment: .leading, spacing: 4) {
							Text("Flow Templates")
								.font(.system(size: 20, weight: .semibold))
								.foregroundColor(AppTheme.primaryText)

							Text("Add a pre-built automation to run after your meetings.")
								.font(.system(size: 13))
								.foregroundColor(AppTheme.secondaryText)
						}

						Spacer()

						Button {
							showTemplatesModal = false
						} label: {
							Image(systemName: "xmark")
								.font(.system(size: 14, weight: .medium))
								.foregroundColor(AppTheme.secondaryText)
						}
						.buttonStyle(.plain)
					}

					LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
						ForEach(flowTemplates) { template in
							templateCard(template)
						}
					}

					HStack {
						Spacer()
						Button {
							showTemplatesModal = false
							newFlowText = ""
							showCreateModal = true
						} label: {
							HStack(spacing: 5) {
								Image(systemName: "plus")
									.font(.system(size: 11, weight: .medium))
								Text("Create custom flow instead")
									.font(.system(size: 13, weight: .medium))
							}
							.foregroundColor(AppTheme.secondaryText)
						}
						.buttonStyle(.plain)
						Spacer()
					}
				}
				.padding(28)
			}
			.frame(maxWidth: 720)
			.fixedSize(horizontal: false, vertical: true)
			.background(
				RoundedRectangle(cornerRadius: 16)
					.fill(AppTheme.cardBackground)
			)
			.clipShape(RoundedRectangle(cornerRadius: 16))
			.shadow(color: .black.opacity(0.3), radius: 20, y: 10)
			.padding(40)
		}
		.transition(.opacity)
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

				Text("Describe what should happen after your meetings end:")
					.font(.system(size: 13))
					.foregroundColor(AppTheme.secondaryText)

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
			statusIcon(for: run.status)
				.frame(width: 24)

			VStack(alignment: .leading, spacing: 4) {
				Text(run.meetingTitle ?? "Meeting")
					.font(.system(size: 13, weight: .medium))
					.foregroundColor(AppTheme.primaryText)

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

	private func addFromTemplate(_ template: FlowTemplate) {
		creatingTemplateId = template.id

		Task {
			do {
				let newFlow = try await FlowsAPI.shared.createFlow(definition: template.definition)
				withAnimation {
					flows.insert(newFlow, at: 0)
				}
				showTemplatesModal = false
			} catch {
				NSLog("[FlowsView] Failed to create flow from template: \(error)")
			}
			creatingTemplateId = nil
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
