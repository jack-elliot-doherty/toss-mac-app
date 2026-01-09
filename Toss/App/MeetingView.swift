import SwiftUI

struct MeetingParticipant: Codable, Identifiable, Equatable {
    var id: String { email }
    let name: String?
    let email: String
    let avatarUrl: String?
    let responseStatus: String?
    let companyName: String?
    let companyLogo: String?
}

struct UpcomingMeeting: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String?
    let startedAt: Date
    let endedAt: Date?
    let joinUrl: String?
    let participants: [MeetingParticipant]

    // Computed property for safe title access
    var displayTitle: String {
        title ?? "Untitled Meeting"
    }

    // Computed helpers
    var startTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startedAt)
    }

    var relativeTime: String {
        let now = Date()
        let seconds = startedAt.timeIntervalSince(now)

        // Past events
        if seconds < 0 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: startedAt, relativeTo: now)
        }

        // Round UP to nearest minute (ceiling)
        let minutes = Int(ceil(seconds / 60))

        if minutes < 1 {
            return "now"
        } else if minutes == 1 {
            return "in 1 minute"
        } else if minutes < 60 {
            return "in \(minutes) minutes"
        } else {
            let hours = Int(ceil(Double(minutes) / 60))
            if hours == 1 {
                return "in 1 hour"
            } else if hours < 24 {
                return "in \(hours) hours"
            } else {
                let days = Int(ceil(Double(hours) / 24))
                return days == 1 ? "in 1 day" : "in \(days) days"
            }
        }
    }
}

@MainActor
final class MeetingsManager: ObservableObject {
    static let shared = MeetingsManager()

    @Published var upcomingMeetings: [UpcomingMeeting] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var error: String?

    private var scheduledAlerts: [UUID: Task<Void, Never>] = [:]
    weak var pillController: PillController?

    func scheduleUpcomingAlerts() {
        // Cancel existing
        scheduledAlerts.values.forEach { $0.cancel() }
        scheduledAlerts.removeAll()

        let now = Date()
        let alertBefore: TimeInterval = 60  // 1 minute before

        for meeting in upcomingMeetings {
            let alertTime = meeting.startedAt.addingTimeInterval(-alertBefore)
            guard alertTime > now else { continue }

            let delay = alertTime.timeIntervalSince(now)

            scheduledAlerts[meeting.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.pillController?.send(.upcomingMeetingAlert(meeting))
            }
        }

        NSLog("[MeetingsManager] Scheduled \(scheduledAlerts.count) upcoming meeting alerts")
    }

    func fetchUpcoming() async {
        do {
            isLoading = true
            upcomingMeetings = try await MeetingsApi.shared.fetchUpcoming()
            isLoading = false
        } catch {
            isLoading = false
            NSLog("[MeetingsManager] Fetch error: %@", error.localizedDescription)
        }

        scheduleUpcomingAlerts()
    }

    func syncCalendar() async {
        isSyncing = true
        do {
            try await MeetingsApi.shared.syncCalendar()
            await fetchUpcoming()
        } catch {
            NSLog("[MeetingsManager] Sync error: %@", error.localizedDescription)
        }
        isSyncing = false
    }
}

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    @EnvironmentObject private var pageChrome: AppScreenLayout
    @ObservedObject private var auth = AuthManager.shared

    @SceneStorage private var selectedTabRaw: String  // Store raw value for persistence
    @Namespace private var tabAnimation
    @State private var tabFrames: [MeetingDetailTab: CGRect] = [:]

    @State private var isRegeneratingSummary = false
    @State private var didCopySummary = false
    @SceneStorage private var showingAISummary: Bool
    @State private var editableUserNotes: String = ""
    @State private var editableTitle: String = ""
    @State private var isEditingTitle: Bool = false
    @FocusState private var isTitleFocused: Bool
    @State private var isAwaitingAutoSummary = false  // Waiting for post-call summary generation
    @State private var hasPendingSummary = false  // Summary ready but user hasn't viewed yet
    @State private var summaryDotPulse = false  // For pulsing animation

    // Action items state
    @State private var extractedActions: [ExtractedAction] = []
    @State private var isExtractingActions = false
    @State private var executingActionId: String?
    @State private var actionExecutionResult: (id: String, success: Bool, message: String)?
    @State private var showingApprovalFor: ExtractedAction?

    // Flow runs state (for Flows tab)
    @State private var flowRuns: [MeetingFlowRun] = []
    @State private var userFlows: [Flow] = []  // All user's enabled flows (shown during recording)
    @State private var isLoadingFlows = false
    @State private var expandedFlowRunId: String?

    // Computed property to convert between raw string and enum
    private var selectedTab: MeetingDetailTab {
        get { MeetingDetailTab(rawValue: selectedTabRaw) ?? .overview }
        set { selectedTabRaw = newValue.rawValue }
    }

    // Add this helper method
    private func setSelectedTab(_ tab: MeetingDetailTab) {
        selectedTabRaw = tab.rawValue
    }

    // Initialize SceneStorage with meeting-specific keys
    init(meetingId: UUID, repository: PersistentMeetingRepository) {
        self.meetingId = meetingId
        self.repository = repository
        _showingAISummary = SceneStorage(
            wrappedValue: false, "showingAISummary_\(meetingId.uuidString)")
        _selectedTabRaw = SceneStorage(
            wrappedValue: MeetingDetailTab.overview.rawValue, "selectedTab_\(meetingId.uuidString)")
    }

    private enum MeetingDetailTab: String, CaseIterable {
        case overview = "Overview"
        case transcript = "Transcript"
        case flows = "Flows"

        var icon: String {
            switch self {
            case .overview: return "list.bullet.rectangle"
            case .transcript: return "text.alignleft"
            case .flows: return "command"
            }
        }

        var index: Int {
            Self.allCases.firstIndex(of: self) ?? 0
        }
    }

    private var meeting: MeetingModel? {
        repository.getMeeting(id: meetingId)
    }

    private var chunks: [MeetingChunkModel] {
        let result = repository.getChunks(meetingId: meetingId)
        NSLog("[MeetingDetailView] getChunks for \(meetingId): returned \(result.count) chunks")
        return result
    }

    private var meetingTitle: String {
        let title = meeting?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled call" : title
    }

    private var createdAtString: String {
        guard let start = meeting?.startTime else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: start)
    }

    private var durationString: String {
        guard let start = meeting?.startTime else { return "—" }
        let end = meeting?.endTime ?? start
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: start, to: end) ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                tabSection
            }
            .frame(maxWidth: 960, alignment: .leading)  // Content left-aligned within 960px block
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .center)  // Center the block in the window
        }
        .clipped()
        .onAppear(perform: configureChrome)
        .onDisappear { pageChrome.clearOverride() }
        .onChange(of: meeting?.title) { _, _ in configureChrome() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Editable title - click to edit
            if isEditingTitle {
                TextField("Meeting title", text: $editableTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onSubmit {
                        saveTitle()
                    }
                    .onExitCommand {
                        cancelEditingTitle()
                    }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused {
                            saveTitle()
                        }
                    }
                    .onDisappear {
                        if isEditingTitle {
                            saveTitle()
                        }
                    }
            } else {
                Text(meetingTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startEditingTitle()
                    }
            }

            // Horizontal metadata with colon
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Created:")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                    Text(createdAtString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                }

                // Join Call button (only shown if meeting has a join URL)
                if let joinUrl = meeting?.joinUrl, let url = URL(string: joinUrl) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Join Call")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Removed Divider
        }
    }

    private var tabSection: some View {
        VStack(alignment: .leading, spacing: 18) {  // Add spacing back
            tabSwitcher
            tabContent
        }
    }

    private var tabSwitcher: some View {
        VStack(spacing: 6) {
            HStack(spacing: 24) {
                ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            setSelectedTab(tab)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : AppTheme.secondaryText)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: TabWidthPreference.self,
                                        value: [tab: proxy.frame(in: .named("tabRow"))]
                                    )
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .coordinateSpace(name: "tabRow")
            .onPreferenceChange(TabWidthPreference.self) { value in
                tabFrames = value
            }

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                if let frame = tabFrames[selectedTab] {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: frame.width, height: 2)
                        .offset(x: frame.minX)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewView
        case .transcript:
            MeetingTranscriptView(
                chunks: chunks,
                meetingStartTime: meeting?.startTime ?? Date()
            )
        case .flows:
            flowsTabView
        }
    }

    private func regenerateSummary() {
        guard !isRegeneratingSummary else { return }

        let transcript = repository.getFullTranscript(meetingId: meetingId)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userNotes = meeting?.userNotes ?? ""

        isRegeneratingSummary = true

        MeetingsApi.shared.generateOverview(
            for: meetingId,
            transcript: trimmed,
            userNotes: userNotes
        ) { [weak repository] result in
            Task { @MainActor in
                self.isRegeneratingSummary = false
                switch result {
                case .success(let summary):
                    repository?.updateMeetingNotes(meetingId: self.meetingId, notes: summary)
                    self.showingAISummary = true
                case .failure(let error):
                    NSLog("[MeetingView] Regenerate summary failed: \(error)")
                }
            }
        }
    }

    private func copySummary() {
        guard let notes = meeting?.notes, !notes.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes, forType: .string)

        didCopySummary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            didCopySummary = false
        }
    }

    private var isRecording: Bool {
        meeting?.endTime == nil
    }

    private var hasAISummary: Bool {
        !(meeting?.notes ?? "").isEmpty
    }

    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toggle on the left + actions on the right
            HStack(spacing: 12) {
                // Mode toggle (only show if we have AI summary)
                if hasAISummary {
                    summaryToggle
                }

                Spacer()

                // Regenerate
                if showingAISummary || !hasAISummary {
                    Button {
                        regenerateSummary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(isRegeneratingSummary ? 360 : 0))
                            .animation(
                                isRegeneratingSummary
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default, value: isRegeneratingSummary)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.secondaryText)
                    .disabled(isRegeneratingSummary)
                }

                // Copy
                Button {
                    if showingAISummary {
                        copySummary()
                    } else {
                        copyUserNotes()
                    }
                } label: {
                    Image(systemName: didCopySummary ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(didCopySummary ? .green : AppTheme.secondaryText)
            }

            // Content area
            if showingAISummary && hasAISummary {
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownSummaryView(markdown: meeting?.notes ?? "")
                }
            } else if isRegeneratingSummary && !hasAISummary {
                Text("Generating summary…")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            } else {
                userNotesEditor
            }

            // Action Items Section (only show when viewing AI summary, not user notes)
            if hasAISummary && !isRecording && showingAISummary {
                actionItemsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            editableUserNotes = meeting?.userNotes ?? ""
            // Load stored actions on appear
            loadStoredActions()

            // If meeting just ended and no summary yet, show loading state
            if !isRecording && !hasAISummary {
                // Check if meeting ended recently (within last 2 minutes) - likely still generating
                if let endTime = meeting?.endTime,
                    Date().timeIntervalSince(endTime) < 120
                {
                    isAwaitingAutoSummary = true
                }
            }

            // Auto-show AI summary post-call if user took no notes
            if !isRecording && hasAISummary && (meeting?.userNotes ?? "").isEmpty {
                showingAISummary = true
            }

            // Extract actions if viewing AI summary and none stored
            if hasAISummary && showingAISummary {
                extractActionsIfNeeded()
            }
        }
        .onChange(of: meeting?.userNotes) { _, newValue in
            if editableUserNotes != newValue {
                editableUserNotes = newValue ?? ""
            }
        }
        .onChange(of: showingAISummary) { _, newValue in
            // Extract actions when switching to AI summary view
            if newValue && hasAISummary {
                extractActionsIfNeeded()
                // Clear the pending summary indicator when user views the summary
                hasPendingSummary = false
            }
        }
        .onChange(of: meeting?.notes) { oldValue, newValue in
            // Summary just arrived - show indicator if user isn't already viewing it
            let wasEmpty = (oldValue ?? "").isEmpty
            let nowHasContent = !(newValue ?? "").isEmpty
            
            if wasEmpty && nowHasContent && !showingAISummary {
                hasPendingSummary = true
            }
        }
        .sheet(item: $showingApprovalFor) { action in
            ActionApprovalSheet(
                action: action,
                isExecuting: executingActionId == action.id,
                onCancel: { showingApprovalFor = nil },
                onConfirm: { editedAction in
                    executeDirectAction(editedAction)
                }
            )
        }
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Actions")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                if isExtractingActions {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Spacer()

                Button {
                    extractActions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(isExtractingActions)
            }

            if extractedActions.isEmpty && !isExtractingActions {
                Text("No actions detected in this meeting.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(extractedActions) { action in
                        ActionItemCard(
                            action: action,
                            isExecuting: executingActionId == action.id,
                            executionResult: actionExecutionResult?.id == action.id
                                ? actionExecutionResult : nil,
                            onExecute: { editedAction in
                                if editedAction.mode == .direct {
                                    executeDirectAction(editedAction)
                                } else {
                                    delegateToAgent(editedAction)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Flows Tab

    private var flowsTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Automations")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                if isLoadingFlows {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Spacer()

                Button {
                    if isRecording {
                        loadUserFlows()
                    } else {
                        loadFlowRuns()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingFlows)
            }

            // Different subtitle based on recording state
            if isRecording {
                Text("These flows will run automatically when this meeting ends.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            } else {
                Text("These flows ran automatically when this meeting ended.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }

            // Show different content based on recording state
            if isRecording {
                // During recording: show user's enabled flows
                if userFlows.isEmpty && !isLoadingFlows {
                    emptyFlowsStateDuringRecording
                } else {
                    VStack(spacing: 12) {
                        ForEach(userFlows.filter { $0.enabled }) { flow in
                            pendingFlowCard(flow)
                        }
                    }
                }
            } else {
                // After meeting: show flow runs
                if flowRuns.isEmpty && !isLoadingFlows {
                    emptyFlowsState
                } else {
                    VStack(spacing: 12) {
                        ForEach(flowRuns) { run in
                            flowRunCard(run)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isRecording {
                loadUserFlows()
            } else {
                loadFlowRuns()
            }
        }
        .onChange(of: isRecording) { _, newValue in
            // When recording stops, switch to loading flow runs
            if !newValue {
                loadFlowRuns()
            }
        }
    }

    private var emptyFlowsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))

            Text("No flows ran for this meeting")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text("Set up flows to automatically sync notes to Notion, share to Slack, and more.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyFlowsStateDuringRecording: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))

            Text("No flows configured")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text(
                "Set up flows to automatically sync notes to Notion, share to Slack, and more when this meeting ends."
            )
            .font(.system(size: 13))
            .foregroundColor(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func pendingFlowCard(_ flow: Flow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Pending icon (clock)
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 18))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                // Flow definition
                Text(flow.definition)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(2)

                // Status
                Text("Will run when meeting ends")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            // TODO: Future - add toggle to disable for this meeting
            // Toggle to enable/disable for this meeting
            // Toggle(isOn: .constant(true)) {}
            //     .labelsHidden()
            //     .scaleEffect(0.8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private func flowRunCard(_ run: MeetingFlowRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: status icon + definition + expand button
            HStack(alignment: .top, spacing: 12) {
                // Status icon
                Image(systemName: run.statusIcon)
                    .font(.system(size: 18))
                    .foregroundColor(run.statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    // Flow definition
                    Text(run.flowDefinition)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(expandedFlowRunId == run.id ? nil : 2)

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
                            .lineLimit(expandedFlowRunId == run.id ? nil : 2)
                    }
                }

                Spacer()

                // Expand/collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedFlowRunId == run.id {
                            expandedFlowRunId = nil
                        } else {
                            expandedFlowRunId = run.id
                        }
                    }
                } label: {
                    Image(systemName: expandedFlowRunId == run.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            // Expanded: show execution steps
            if expandedFlowRunId == run.id, let steps = run.steps, !steps.isEmpty {
                Divider()
                    .background(AppTheme.subtleStroke)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Execution Steps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)

                    ForEach(steps) { step in
                        flowStepRow(step)
                    }
                }
                .padding(.top, 4)
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
                    run.status == "failed" ? Color.red.opacity(0.3) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private func flowStepRow(_ step: FlowExecutionStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Step type icon
            Image(systemName: step.icon)
                .font(.system(size: 12))
                .foregroundColor(step.iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.content)
                    .font(.system(size: 13))
                    .foregroundColor(
                        step.type == "tool_result" ? AppTheme.secondaryText : AppTheme.primaryText
                    )
                    .lineLimit(3)

                // Show tool name for tool calls
                if let toolName = step.toolName, step.type == "tool_call" {
                    Text(toolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
    }

    private func loadFlowRuns() {
        guard !isLoadingFlows else { return }
        isLoadingFlows = true

        Task {
            do {
                flowRuns = try await FlowsAPI.shared.getMeetingFlowRuns(meetingId: meetingId)
            } catch {
                NSLog("[MeetingView] Failed to load flow runs: \(error)")
            }
            isLoadingFlows = false
        }
    }

    private func loadUserFlows() {
        guard !isLoadingFlows else { return }
        isLoadingFlows = true

        Task {
            do {
                userFlows = try await FlowsAPI.shared.listFlows()
            } catch {
                NSLog("[MeetingView] Failed to load user flows: \(error)")
            }
            isLoadingFlows = false
        }
    }

    private func loadStoredActions() {
        // Load action items from the meeting model if available
        if let meeting = meeting, !meeting.actionItems.isEmpty {
            extractedActions = meeting.actionItems.map { $0.toExtractedAction() }
            NSLog("[MeetingView] Loaded %d stored action items", extractedActions.count)
        }
    }

    private func extractActionsIfNeeded() {
        // First try to load from stored
        if extractedActions.isEmpty {
            loadStoredActions()
        }
        // Only extract if still empty and not currently extracting
        guard extractedActions.isEmpty && !isExtractingActions else { return }
        extractActions()
    }

    private func extractActions() {
        let transcript = repository.getFullTranscript(meetingId: meetingId)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExtractingActions = true

        Task {
            do {
                let actions = try await MeetingsApi.shared.extractActions(
                    for: meetingId,
                    transcript: trimmed
                )
                await MainActor.run {
                    extractedActions = actions
                    isExtractingActions = false

                    // Store to repository so we don't re-extract
                    let storedItems = actions.map { StoredActionItem(from: $0) }
                    repository.updateMeetingActionItems(
                        meetingId: meetingId, actionItems: storedItems)
                    NSLog("[MeetingView] Stored %d action items to repository", storedItems.count)
                }
            } catch {
                NSLog("[MeetingView] Extract actions failed: \(error)")
                await MainActor.run {
                    isExtractingActions = false
                }
            }
        }
    }

    private func executeDirectAction(_ action: ExtractedAction) {
        executingActionId = action.id
        actionExecutionResult = nil

        Task {
            do {
                let result = try await MeetingsApi.shared.executeAction(action: action)
                await MainActor.run {
                    executingActionId = nil
                    showingApprovalFor = nil
                    if result.success {
                        actionExecutionResult = (
                            id: action.id, success: true, message: "Action completed successfully"
                        )
                        // Mark action as executed in local storage
                        markActionExecuted(actionId: action.id, success: true)
                    } else {
                        actionExecutionResult = (
                            id: action.id, success: false,
                            message: result.error ?? "Action failed"
                        )
                        markActionExecuted(actionId: action.id, success: false)
                    }
                    // Clear result after delay (longer for success so user sees confirmation)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        if actionExecutionResult?.id == action.id {
                            actionExecutionResult = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    executingActionId = nil
                    showingApprovalFor = nil
                    actionExecutionResult = (
                        id: action.id, success: false, message: error.localizedDescription
                    )
                    markActionExecuted(actionId: action.id, success: false)
                }
            }
        }
    }

    private func markActionExecuted(actionId: String, success: Bool) {
        // Update local action items
        if var meeting = meeting {
            var updatedActionItems = meeting.actionItems
            if let index = updatedActionItems.firstIndex(where: { $0.id == actionId }) {
                updatedActionItems[index].executedAt = Date()
                updatedActionItems[index].executionSuccess = success
            }
            repository.updateMeetingActionItems(
                meetingId: meetingId, actionItems: updatedActionItems)

            // Sync to server
            Task { await MeetingSyncManager.shared.syncMeeting(meetingId) }
        }
    }

    private func delegateToAgent(_ action: ExtractedAction) {
        guard let taskSpec = action.taskSpec else { return }

        // Include context for the agent
        let fullMessage = """
            Task from meeting "\(meetingTitle)":

            \(taskSpec)

            Context: \(action.context)
            """

        // Post notification to show agent panel with the task
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowAgentPanel"),
            object: nil,
            userInfo: ["message": fullMessage]
        )
    }

    private var summaryToggle: some View {
        HStack(spacing: 8) {
            toggleChip(title: "My Notes", icon: "note.text", isSelected: !showingAISummary) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingAISummary = false
                }
            }
            
            // Summary chip with notification badge
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingAISummary = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                    Text("Summary")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(showingAISummary ? .white : AppTheme.secondaryText.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showingAISummary ? Color.white.opacity(0.12) : Color.clear)
                )
                .overlay(alignment: .topTrailing) {
                    // Pulsing notification badge
                    if hasPendingSummary {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .scaleEffect(summaryDotPulse ? 1.15 : 1.0)
                            .opacity(summaryDotPulse ? 0.7 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: summaryDotPulse
                            )
                            .offset(x: 1, y: -1)
                            .onAppear { summaryDotPulse = true }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleChip(
        title: String, icon: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : AppTheme.secondaryText.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var userNotesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Inline placeholder when empty and recording
                if editableUserNotes.isEmpty && isRecording {
                    Text("Take notes here... these will be used to guide the overview.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                        .padding(.top, 1)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $editableUserNotes)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 200)
                    .padding(.leading, -5)  // Align with placeholder
                    .onChange(of: editableUserNotes) { _, newValue in
                        saveUserNotes(newValue)
                    }
            }

        }
    }

    private var generatingSummaryView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating summary…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Text("This usually takes a few seconds")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 32)
    }

    private func saveUserNotes(_ notes: String) {
        // Save immediately to local storage
        repository.updateMeetingUserNotes(meetingId: meetingId, userNotes: notes)
        // Debounced sync to server (wait 2 seconds after user stops typing)
        MeetingSyncManager.shared.debouncedSync(meetingId)
    }

    private func copyUserNotes() {
        guard let notes = meeting?.userNotes, !notes.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes, forType: .string)
        didCopySummary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            didCopySummary = false
        }
    }

    private func configureChrome() {
        let crumbs = [
            Breadcrumb(title: "Calls"),
            Breadcrumb(title: meetingTitle),
        ]
        pageChrome.override(
            with: AppScreenLayoutState(
                breadcrumb: crumbs,
                action: nil,
                meetingActionsId: meetingId
            ))
    }

    private func startEditingTitle() {
        editableTitle = meeting?.title ?? ""
        isEditingTitle = true
        // Small delay to ensure the TextField is rendered before focusing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTitleFocused = true
        }
    }

    private func saveTitle() {
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            repository.updateMeetingTitle(meetingId: meetingId, title: trimmed)
            // Sync title change to server
            Task { await MeetingSyncManager.shared.syncMeeting(meetingId) }
        }
        isEditingTitle = false
        isTitleFocused = false
    }

    private func cancelEditingTitle() {
        isEditingTitle = false
        isTitleFocused = false
    }

    private struct TabWidthPreference: PreferenceKey {
        static var defaultValue: [MeetingDetailTab: CGRect] = [:]

        static func reduce(
            value: inout [MeetingDetailTab: CGRect],
            nextValue: () -> [MeetingDetailTab: CGRect]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
}

private struct MeetingTranscriptView: View {
    let chunks: [MeetingChunkModel]
    let meetingStartTime: Date  // Add this
    @State private var didCopyTranscript = false
    @State private var showingTimeline = false  // false = Transcript, true = Timeline

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if chunks.isEmpty {
                EmptyStateCard(
                    title: "No transcript yet",
                    subtitle: "Transcript entries appear here automatically once available."
                )
            } else {
                // Header row: toggle on left, copy on right
                HStack(spacing: 12) {
                    transcriptToggle

                    Spacer()

                    Button {
                        copyTranscript()
                    } label: {
                        Image(systemName: didCopyTranscript ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(didCopyTranscript ? .green : AppTheme.secondaryText)
                }

                // Content
                if showingTimeline {
                    timelineView
                } else {
                    transcriptListView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptToggle: some View {
        HStack(spacing: 8) {
            toggleChip(title: "Transcript", icon: "text.alignleft", isSelected: !showingTimeline) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingTimeline = false
                }
            }
            toggleChip(title: "Timeline", icon: "clock", isSelected: showingTimeline) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingTimeline = true
                }
            }
        }
    }

    private func toggleChip(
        title: String, icon: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : AppTheme.secondaryText.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var transcriptListView: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(chunks) { chunk in
                VStack(alignment: .leading, spacing: 6) {
                    // Header: avatar + name + timestamp
                    HStack(spacing: 8) {
                        // Avatar circle with initial
                        Circle()
                            .fill(chunk.speaker == .user ? Color.blue : Color.green)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(chunk.speaker == .user ? "Y" : "C")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                            )

                        // Name
                        Text(chunk.speaker == .user ? "You" : "Colleague")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.primaryText)

                        // Timestamp
                        Text(formatTime(chunk.startedAt))
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                    }

                    // Transcript text - indented to align with name
                    Text(chunk.transcript)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.primaryText.opacity(0.9))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.leading, 32)  // Align with text after avatar
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        // Calculate elapsed seconds from meeting start
        let elapsed = max(0, date.timeIntervalSince(meetingStartTime))
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var timelineView: some View {
        // Placeholder for timeline view - you can implement this later
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline view coming soon")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private func copyTranscript() {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let text =
            chunks
            .sorted(by: { $0.startedAt < $1.startedAt })
            .map { chunk in
                let speaker = chunk.speaker == .user ? "You" : "Them"
                let timestamp = formatter.string(from: chunk.startedAt)
                return "[\(speaker) \(timestamp)] \(chunk.transcript)"
            }
            .joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopyTranscript = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            didCopyTranscript = false
        }
    }

    private func speakerBadge(text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(accent.opacity(0.8))
            .clipShape(Capsule())
            .frame(width: 60, alignment: .center)
    }
}

private struct EmptyStateCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

struct MeetingsListView: View {
    @ObservedObject var repository: PersistentMeetingRepository
    @Binding var pendingMeetingId: UUID?
    @Binding var navigationPath: NavigationPath
    @State private var selectedMeeting: UUID?
    @State private var refreshTrigger = false
    @State private var showUpcomingPopover = false

    // Add Manager
    @StateObject private var meetingsManager = MeetingsManager.shared
    @StateObject private var integrations = IntegrationsManager.shared

    private var isCalendarConnected: Bool {
        integrations.googleStatus?.connected == true
    }

    /// True if we have cached meetings to display
    private var hasCachedMeetings: Bool {
        !meetingsManager.upcomingMeetings.isEmpty
    }

    /// Show loading only when we don't have cached meetings AND we're still determining what to show
    private var isLoadingUpcoming: Bool {
        // If we have cached meetings, never show loading - just show them
        guard !hasCachedMeetings else { return false }

        // If we don't know Google status yet, show loading
        guard integrations.googleStatus != nil else { return true }

        // If calendar is connected and we're still fetching meetings, show loading
        if isCalendarConnected && meetingsManager.isLoading {
            return true
        }

        return false
    }

    /// Only show connect calendar if we explicitly know Google is NOT connected
    private var showConnectCalendar: Bool {
        guard let status = integrations.googleStatus else { return false }
        return !status.connected
    }

    var meetings: [MeetingModel] {
        repository.listMeetings()
    }

    private var meetingSections: [MeetingSection] {
        let grouped = Dictionary(grouping: meetings) { sectionTitle(for: $0.startTime) }
        let sections = grouped.map { key, meetings -> MeetingSection in
            MeetingSection(
                title: key,
                meetings: meetings.sorted(by: { $0.startTime > $1.startTime })
            )
        }
        return sections.sorted { lhs, rhs in
            guard let lhsDate = lhs.meetings.first?.startTime,
                let rhsDate = rhs.meetings.first?.startTime
            else { return false }
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // --- Upcoming Section ---
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Upcoming")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AppTheme.primaryText)

                            if meetingsManager.isSyncing {
                                Text("Syncing...")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                            } else if isCalendarConnected {
                                Button {
                                    Task { await meetingsManager.syncCalendar() }
                                } label: {
                                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .help("Sync calendar")
                            }

                            Spacer()

                            Button {
                                showUpcomingPopover = true
                            } label: {
                                Text("Show more")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }

                        if isLoadingUpcoming {
                            // Show skeleton cards while loading
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    UpcomingMeetingSkeletonCard()
                                }
                            }
                        } else if meetingsManager.upcomingMeetings.isEmpty {
                            if showConnectCalendar {
                                // Calendar not connected - show connect affordance
                                HStack(spacing: 12) {
                                    Image("GoogleCalendarLogo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Connect your calendar")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(AppTheme.primaryText)
                                        Text("See upcoming meetings and auto-join calls")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.secondaryText)
                                    }

                                    Spacer()

                                    Button {
                                        Task { await integrations.connectGoogle() }
                                    } label: {
                                        Text("Connect")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding()
                                .background(AppTheme.cardBackground)
                                .cornerRadius(12)
                            } else {
                                // Calendar connected but no upcoming meetings
                                HStack {
                                    Text("No upcoming meetings found.")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.secondaryText)
                                    Spacer()
                                }
                                .padding()
                                .background(AppTheme.cardBackground)
                                .cornerRadius(12)
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(meetingsManager.upcomingMeetings) { meeting in
                                        UpcomingMeetingCard(meeting: meeting)
                                    }
                                }
                            }
                        }
                    }
                    // -----------------------------

                    // --- Calls Section ---
                    Text("Calls")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.top, 8)

                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        ForEach(meetingSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                // Section header with date on right
                                HStack {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.secondaryText)

                                    Spacer()

                                    if let firstMeeting = section.meetings.first {
                                        Text(fullDateString(firstMeeting.startTime))
                                            .font(.system(size: 13))
                                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                                    }
                                }

                                VStack(spacing: 0) {
                                    ForEach(section.meetings) { meeting in
                                        NavigationLink(value: meeting.id) {
                                            meetingRow(meeting)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 28)
            }
            .navigationDestination(for: UUID.self) { meetingId in
                MeetingView(meetingId: meetingId, repository: repository)
            }
        }
        .clipped()  // Prevent NavigationStack content from extending into header
        .onChange(of: pendingMeetingId) { _, newValue in
            if let meetingId = newValue {
                navigationPath.append(meetingId)
                selectedMeeting = meetingId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pendingMeetingId = nil
                }
            }
        }
        .onAppear {
            // Fetch cached upcoming on appear (fast)
            Task { await meetingsManager.fetchUpcoming() }

            // Fetch Google Calendar connection status
            Task { await integrations.fetchGoogleStatus() }

            // Fetch recorded meetings from server (to get Zapier/external meetings)
            Task { await fetchRecordedMeetingsFromServer() }

            if let meetingId = pendingMeetingId {
                navigationPath.append(meetingId)
                selectedMeeting = meetingId
                pendingMeetingId = nil
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            // Sync calendar when app becomes active (only if connected)
            if isCalendarConnected {
                Task { await meetingsManager.syncCalendar() }
            }
            refreshTrigger.toggle()
        }
        // Make computed properties depend on refreshTrigger
        .id(refreshTrigger)
        .overlay {
            if showUpcomingPopover {
                // Invisible tap target to dismiss (no dim)
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        showUpcomingPopover = false
                    }

                // Centered dialog
                UpcomingMeetingsPopover(
                    meetings: meetingsManager.upcomingMeetings,
                    onDismiss: { showUpcomingPopover = false }
                )
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showUpcomingPopover)
    }

    private func meetingCard(_ meeting: MeetingModel, isSelected: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(AppTheme.accent.opacity(0.16))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Text("\(formattedDate(meeting.startTime)) • \(formattedTime(meeting.startTime))")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if isRecording(meeting) {
                    recordingPill
                } else if let endTime = meeting.endTime {
                    Text(durationString(from: meeting.startTime, to: endTime))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Text(relativeTimeString(from: meeting.startTime))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            isSelected ? AppTheme.accent : AppTheme.subtleStroke,
                            lineWidth: isSelected ? 1.5 : 1)
                )
        )
    }

    private var recordingPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.destructive)
                .frame(width: 8, height: 8)
            Text("Recording")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(AppTheme.destructive)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.destructive.opacity(0.15))
        .cornerRadius(16)
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func isRecording(_ meeting: MeetingModel) -> Bool {
        meeting.endTime == nil
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private func meetingRow(_ meeting: MeetingModel) -> some View {
        HStack(spacing: 12) {
            // Icon based on meeting source
            Group {
                if meeting.source == .calendar {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.secondaryText.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.secondaryText.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        )
                }
            }

            // Title + optional status badge
            HStack(spacing: 8) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)

                if isRecording(meeting) {
                    statusBadge("REC", color: .red)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // User avatar
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.secondaryText)
                )

            // Time
            Text(formattedTime(meeting.startTime))
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 70, alignment: .trailing)

            // 3-dot dropdown menu
            Menu {
                Button {
                    copyShareLink(for: meeting)
                } label: {
                    Label("Copy link", systemImage: "link")
                }

                Button {
                    shareMeeting(meeting)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    deleteMeeting(meeting)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()  // Preserve intrinsic size in release builds
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func fullDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func copyShareLink(for meeting: MeetingModel) {
        Task {
            do {
                // Ensure meeting is synced first
                await MeetingSyncManager.shared.syncMeeting(meeting.id)
                // Generate proper share link via API
                let shareUrl = try await MeetingsApi.shared.generateShareLink(meetingId: meeting.id)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(shareUrl, forType: .string)
                }
                NSLog("[MeetingView] Copied share link for meeting: \(meeting.id)")
            } catch {
                NSLog("[MeetingView] Failed to generate share link: \(error)")
            }
        }
    }

    private func shareMeeting(_ meeting: MeetingModel) {
        Task {
            do {
                // Ensure meeting is synced first
                await MeetingSyncManager.shared.syncMeeting(meeting.id)
                // Generate proper share link via API
                let shareUrl = try await MeetingsApi.shared.generateShareLink(meetingId: meeting.id)
                await MainActor.run {
                    let picker = NSSharingServicePicker(items: [shareUrl])
                    if let window = NSApp.keyWindow {
                        picker.show(
                            relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
                    }
                }
            } catch {
                NSLog("[MeetingView] Failed to share meeting: \(error)")
            }
        }
    }

    private func deleteMeeting(_ meeting: MeetingModel) {
        repository.deleteMeeting(id: meeting.id)
        NSLog("[MeetingView] Deleted meeting: \(meeting.id)")
        // Also delete from server (fire and forget - queue handles retries)
        Task { await MeetingSyncManager.shared.deleteMeetingFromServer(meeting.id) }
    }

    private static let lastServerSyncKey = "lastMeetingsServerSync"

    private func fetchRecordedMeetingsFromServer() async {
        // Fetch only meetings created after our last sync to avoid fetching everything
        let lastSync = UserDefaults.standard.object(forKey: Self.lastServerSyncKey) as? Date

        if let lastSync = lastSync {
            NSLog("[MeetingsListView] Fetching meetings since: \(lastSync)")
        } else {
            NSLog("[MeetingsListView] Fetching all meetings (no lastSync)")
        }

        do {
            let serverMeetings = try await MeetingsApi.shared.fetchRecordedMeetings(since: lastSync)

            NSLog("[MeetingsListView] Server returned \(serverMeetings.count) meetings")

            if !serverMeetings.isEmpty {
                await MainActor.run {
                    repository.importFromServer(serverMeetings)
                }
                NSLog("[MeetingsListView] Imported \(serverMeetings.count) new meetings from server")
            }

            // Update last sync time
            UserDefaults.standard.set(Date(), forKey: Self.lastServerSyncKey)
        } catch {
            NSLog("[MeetingsListView] Failed to fetch meetings from server: \(error.localizedDescription)")
        }
    }

    private struct MeetingSection: Identifiable {
        var id: String { title }
        let title: String
        let meetings: [MeetingModel]
    }
}

private struct UpcomingMeetingCard: View {
    let meeting: UpcomingMeeting

    private var isLive: Bool {
        let now = Date()
        return meeting.startedAt <= now && (meeting.endedAt ?? .distantFuture) > now
    }

    private var smartTimeString: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(meeting.startedAt) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: meeting.startedAt)
        } else if calendar.isDateInTomorrow(meeting.startedAt) {
            formatter.dateFormat = "h:mm a"
            return "Tomorrow \(formatter.string(from: meeting.startedAt))"
        } else {
            formatter.dateFormat = "EEEE h:mm a"
            return formatter.string(from: meeting.startedAt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(meeting.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(1)

            // Time or LIVE badge
            if isLive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            } else {
                Text(smartTimeString)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            // Bottom row: participants + Start button
            HStack {
                // Participants
                if !meeting.participants.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(meeting.participants.prefix(3)) { p in
                            participantAvatar(p)
                        }
                        if meeting.participants.count > 3 {
                            Text("+\(meeting.participants.count - 3)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText)
                                .padding(.leading, 8)
                        }
                    }
                }

                Spacer()

                // Start button
                Button("Start") {
                    // TODO: implement join & record
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.elevatedBackground)
                .cornerRadius(6)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 180, height: 140)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }

    private func participantAvatar(_ p: MeetingParticipant) -> some View {
        Group {
            if let url = p.avatarUrl, let u = URL(string: url) {
                AsyncImage(url: u) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.6))
                    .overlay(
                        Text(
                            p.name?.prefix(1).uppercased() ?? String(p.email.prefix(1)).uppercased()
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    )
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
    }
}

private struct UpcomingMeetingSkeletonCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.secondaryText.opacity(0.15))
                .frame(width: 120, height: 16)

            // Time skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.secondaryText.opacity(0.1))
                .frame(width: 70, height: 14)

            Spacer()

            // Bottom row skeleton
            HStack {
                // Participant avatars skeleton
                HStack(spacing: -6) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(AppTheme.secondaryText.opacity(0.12))
                            .frame(width: 22, height: 22)
                    }
                }

                Spacer()

                // Button skeleton
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.secondaryText.opacity(0.1))
                    .frame(width: 50, height: 28)
            }
        }
        .padding(16)
        .frame(width: 180, height: 140)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

private struct UpcomingMeetingsPopover: View {
    let meetings: [UpcomingMeeting]
    let onDismiss: () -> Void

    private var groupedMeetings: [(date: String, meetings: [UpcomingMeeting])] {
        let grouped = Dictionary(grouping: meetings) { meeting in
            dateGroupKey(meeting.startedAt)
        }
        return grouped.map { (date: $0.key, meetings: $0.value) }
            .sorted { lhs, rhs in
                lhs.meetings.first?.startedAt ?? .distantPast < rhs.meetings.first?.startedAt
                    ?? .distantPast
            }
    }

    private func dateGroupKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date).uppercased()
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close button
            HStack {
                Text("Upcoming Meetings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.elevatedBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .background(AppTheme.subtleStroke)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedMeetings, id: \.date) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            // Date header
                            Text(group.date)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                                .padding(.horizontal, 16)

                            // Meetings for this date
                            ForEach(group.meetings) { meeting in
                                meetingRow(meeting)

                                if meeting.id != group.meetings.last?.id {
                                    Divider()
                                        .background(AppTheme.subtleStroke)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 480, height: 500)
    }

    private func meetingRow(_ meeting: UpcomingMeeting) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)

                Text(timeString(meeting.startedAt))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            // Participants
            if !meeting.participants.isEmpty {
                HStack(spacing: -6) {
                    ForEach(meeting.participants.prefix(2)) { p in
                        participantAvatar(p)
                    }
                    if meeting.participants.count > 2 {
                        Text("+\(meeting.participants.count - 2)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.leading, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func participantAvatar(_ p: MeetingParticipant) -> some View {
        Group {
            if let url = p.avatarUrl, let u = URL(string: url) {
                AsyncImage(url: u) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.6))
                    .overlay(
                        Text(
                            p.name?.prefix(1).uppercased() ?? String(p.email.prefix(1)).uppercased()
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    )
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
    }
}

private struct BulletItem: Identifiable {
    let id = UUID()
    let text: String
    var children: [BulletItem] = []
}

private struct SummarySection: Identifiable {
    let id = UUID()
    let title: String
    let bullets: [BulletItem]
}

private struct MarkdownSummaryView: View {
    let markdown: String

    private var sections: [SummarySection] {
        parseSummary(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {  // Increased from 16 to 24 for more section spacing
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {  // Increased from 6 to 8
                    // Section title
                    Text(section.title)
                        .font(.system(size: 15, weight: .bold))  // Increased from 14 semibold to 15 bold
                        .foregroundColor(AppTheme.primaryText)

                    // Bullets
                    VStack(alignment: .leading, spacing: 6) {  // Increased from 4 to 6
                        ForEach(section.bullets) { bullet in
                            bulletView(bullet, depth: 0)
                        }
                    }
                }
            }
        }
    }

    private func bulletView(_ item: BulletItem, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {  // Slightly more spacing
                HStack(alignment: .top, spacing: 8) {  // Increased from 6 to 8
                    // Use different bullet characters for different depths
                    Text(depth == 0 ? "•" : "◦")
                        .font(.system(size: depth == 0 ? 14 : 12))
                        .foregroundColor(depth == 0 ? AppTheme.primaryText : AppTheme.secondaryText)

                    textFromMarkdown(item.text)
                        .font(.system(size: depth == 0 ? 14 : 13))
                        .foregroundColor(depth == 0 ? AppTheme.primaryText : AppTheme.secondaryText)
                        .lineSpacing(3)
                }
                .padding(.leading, CGFloat(depth) * 20)  // Increased from 16 to 20 for more indent

                // Render children
                ForEach(item.children) { child in
                    bulletView(child, depth: depth + 1)
                }
            }
        )
    }

    private func textFromMarkdown(_ string: String) -> Text {
        if let attr = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        } else {
            return Text(string)
        }
    }
}

// Updated parser that handles nested bullets
private func parseSummary(_ markdown: String) -> [SummarySection] {
    var sections: [SummarySection] = []
    var currentTitle: String?
    var currentBullets: [BulletItem] = []

    func flush() {
        if let title = currentTitle, !currentBullets.isEmpty {
            sections.append(SummarySection(title: title, bullets: currentBullets))
        }
        currentTitle = nil
        currentBullets = []
    }

    let lines = markdown.components(separatedBy: .newlines)

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("## ") {
            flush()
            currentTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("  - ") || line.hasPrefix("   - ") || line.hasPrefix("    - ") {
            // Sub-bullet (indented with 2-4 spaces)
            let bulletText = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !currentBullets.isEmpty {
                // Add as child of the last top-level bullet
                currentBullets[currentBullets.count - 1].children.append(
                    BulletItem(text: bulletText))
            }
        } else if trimmed.hasPrefix("- ") {
            // Top-level bullet
            let bulletText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            currentBullets.append(BulletItem(text: bulletText))
        } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") {
            // Continuation of previous bullet
            if !currentBullets.isEmpty {
                let lastIndex = currentBullets.count - 1
                if !currentBullets[lastIndex].children.isEmpty {
                    // Append to last child
                    let childIndex = currentBullets[lastIndex].children.count - 1
                    currentBullets[lastIndex].children[childIndex] = BulletItem(
                        text: currentBullets[lastIndex].children[childIndex].text + " " + trimmed
                    )
                } else {
                    // Append to parent bullet
                    currentBullets[lastIndex] = BulletItem(
                        text: currentBullets[lastIndex].text + " " + trimmed,
                        children: currentBullets[lastIndex].children
                    )
                }
            }
        }
    }

    flush()
    return sections
}

// MARK: - Action Items UI Components

private struct ActionItemCard: View {
    let action: ExtractedAction
    let isExecuting: Bool
    let executionResult: (id: String, success: Bool, message: String)?
    let onExecute: (ExtractedAction) -> Void

    @State private var editedParams: [String: AnyCodableValue]?
    @State private var showSuccessPulse = false
    @State private var isConnecting = false
    @ObservedObject private var integrationsManager = IntegrationsManager.shared

    // Check if the required integration is connected
    private var isIntegrationConnected: Bool {
        guard let toolName = action.toolName else { return true }
        switch toolName {
        case "slackSendMessage", "slackListChannels":
            return integrationsManager.slackStatus?.connected ?? false
        case "linearCreateIssue":
            return integrationsManager.linearStatus?.connected ?? false
        case "calendarCreateEvent", "calendarListEvents":
            return integrationsManager.googleStatus?.connected ?? false
        default:
            return true
        }
    }

    private var integrationName: String {
        guard let toolName = action.toolName else { return "" }
        switch toolName {
        case "slackSendMessage", "slackListChannels":
            return "Slack"
        case "linearCreateIssue":
            return "Linear"
        case "calendarCreateEvent", "calendarListEvents":
            return "Google Calendar"
        default:
            return ""
        }
    }

    private var integrationIcon: String {
        guard let toolName = action.toolName else { return "" }
        switch toolName {
        case "slackSendMessage", "slackListChannels":
            return "SlackLogo"
        case "linearCreateIssue":
            return "LinearLogo"
        case "calendarCreateEvent", "calendarListEvents":
            return "GoogleCalendarLogo"
        default:
            return ""
        }
    }

    private var integrationColor: Color {
        guard let toolName = action.toolName else { return .blue }
        switch toolName {
        case "slackSendMessage", "slackListChannels":
            return Color(hex: "4A154B") ?? .purple
        case "linearCreateIssue":
            return Color(hex: "5E6AD2") ?? .indigo
        case "calendarCreateEvent", "calendarListEvents":
            return Color(hex: "4285F4") ?? .blue
        default:
            return .blue
        }
    }

    private var currentAction: ExtractedAction {
        guard let edited = editedParams else { return action }
        return ExtractedAction(
            id: action.id,
            mode: action.mode,
            title: action.title,
            context: action.context,
            toolName: action.toolName,
            toolParams: edited,
            taskSpec: action.taskSpec
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolPreview

            // Execution result feedback
            if let result = executionResult {
                HStack(spacing: 8) {
                    Image(
                        systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(showSuccessPulse ? 1.2 : 1.0)

                    Text(result.message)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    if result.success {
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                            )
                    }
                }
                .foregroundColor(result.success ? .green : .red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(result.success ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    result.success
                                        ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                                    lineWidth: 1)
                        )
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .onAppear {
                    if result.success {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            showSuccessPulse = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                showSuccessPulse = false
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: executionResult?.id)
        .onAppear {
            // Fetch integration status on appear
            Task {
                await integrationsManager.fetchSlackStatus()
                await integrationsManager.fetchLinearStatus()
                await integrationsManager.fetchGoogleStatus()
            }
        }
    }

    private func connectIntegration() {
        isConnecting = true
        Task {
            switch action.toolName {
            case "slackSendMessage", "slackListChannels":
                await integrationsManager.connectSlack()
            case "linearCreateIssue":
                await integrationsManager.connectLinear()
            case "calendarCreateEvent", "calendarListEvents":
                await integrationsManager.connectGoogle()
            default:
                break
            }
            isConnecting = false
        }
    }

    @ViewBuilder
    private var toolPreview: some View {
        if action.mode == .agent, let taskSpec = action.taskSpec {
            AgentTaskPreview(taskSpec: taskSpec, compact: false)
        } else if let toolName = action.toolName, let params = action.toolParams {
            switch toolName {
            case "calendarCreateEvent":
                EditableCalendarEventPreview(
                    params: ToolParams(params),
                    compact: false,
                    onParamsChanged: { editedParams = $0 },
                    isExecuting: isExecuting,
                    onExecute: isIntegrationConnected ? { onExecute(currentAction) } : nil,
                    isConnecting: isConnecting,
                    onConnect: isIntegrationConnected ? nil : { connectIntegration() }
                )
            case "linearCreateIssue":
                EditableLinearIssuePreview(
                    params: ToolParams(params),
                    compact: false,
                    onParamsChanged: { editedParams = $0 },
                    isExecuting: isExecuting,
                    onExecute: isIntegrationConnected ? { onExecute(currentAction) } : nil,
                    isConnecting: isConnecting,
                    onConnect: isIntegrationConnected ? nil : { connectIntegration() }
                )
            case "slackSendMessage":
                EditableSlackMessagePreview(
                    params: ToolParams(params),
                    compact: false,
                    onParamsChanged: { editedParams = $0 },
                    isExecuting: isExecuting,
                    onExecute: isIntegrationConnected ? { onExecute(currentAction) } : nil,
                    isConnecting: isConnecting,
                    onConnect: isIntegrationConnected ? nil : { connectIntegration() }
                )
            case "cursorOpenPrompt":
                CursorPromptPreview(
                    params: ToolParams(params),
                    compact: false,
                    title: action.title,
                    context: action.context,
                    isExecuting: isExecuting,
                    onOpenInCursor: {
                        openInCursor(params: params)
                    },
                    onCopyLink: {
                        copyCursorLink(params: params)
                    }
                )
            default:
                ToolPreviewFactory.preview(for: toolName, params: params, compact: false)
            }
        } else {
            Text("Action details unavailable")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
                .italic()
        }
    }

    private func openInCursor(params: [String: AnyCodableValue]) {
        guard let prompt = params["prompt"]?.stringValue else { return }
        guard let url = CursorPromptPreview.generateDeepLink(prompt: prompt) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyCursorLink(params: [String: AnyCodableValue]) {
        guard let prompt = params["prompt"]?.stringValue else { return }
        guard let url = CursorPromptPreview.generateWebLink(prompt: prompt) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

private struct ActionApprovalSheet: View {
    let action: ExtractedAction
    let isExecuting: Bool
    let onCancel: () -> Void
    let onConfirm: (ExtractedAction) -> Void  // Changed: now passes the edited action

    @State private var editedParams: [String: AnyCodableValue]?

    private var currentAction: ExtractedAction {
        // Return action with edited params if available
        guard let edited = editedParams else { return action }
        return ExtractedAction(
            id: action.id,
            mode: action.mode,
            title: action.title,
            context: action.context,
            toolName: action.toolName,
            toolParams: edited,
            taskSpec: action.taskSpec
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Confirm Action")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)
                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppTheme.cardBackground))
                }
                .buttonStyle(.plain)
                .disabled(isExecuting)
            }

            // Action title and context
            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Text(action.context)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Divider()
                .background(AppTheme.subtleStroke)

            // Tool-specific preview - use editable version for calendar
            if let toolName = action.toolName, let params = action.toolParams {
                editablePreview(for: toolName, params: params)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.subtleStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isExecuting)

                Button {
                    onConfirm(currentAction)
                } label: {
                    if isExecuting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Creating...")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.7))
                        )
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 12))
                            Text(buttonText(for: action.toolName))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isExecuting)
            }
        }
        .padding(24)
        .frame(width: 420)
        .frame(minHeight: 400)
        .background(AppTheme.cardBackground)
    }

    @ViewBuilder
    private func editablePreview(for toolName: String, params: [String: AnyCodableValue])
        -> some View
    {
        let wrapped = ToolParams(params)
        switch toolName {
        case "calendarCreateEvent":
            EditableCalendarEventPreview(
                params: wrapped,
                compact: false,
                onParamsChanged: { newParams in
                    editedParams = newParams
                }
            )
        default:
            // Fall back to read-only preview for other tools
            ToolPreviewFactory.preview(for: toolName, params: params, compact: false)
        }
    }

    private func buttonText(for toolName: String?) -> String {
        switch toolName {
        case "calendarCreateEvent":
            return "Add to Calendar"
        case "slackSendMessage":
            return "Send Message"
        case "linearCreateIssue":
            return "Create Issue"
        default:
            return "Execute"
        }
    }
}
