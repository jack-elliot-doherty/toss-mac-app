import SwiftUI

struct MeetingParticipant: Codable, Identifiable {
    var id: String { email }
    let name: String?
    let email: String
    let avatarUrl: String?
    let responseStatus: String?
    let companyName: String?
    let companyLogo: String?
}

struct UpcomingMeeting: Codable, Identifiable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let joinUrl: String?
    let participants: [MeetingParticipant]

    // Computed helpers
    var startTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startedAt)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: startedAt, relativeTo: Date())
    }
}

@MainActor
final class MeetingsManager: ObservableObject {
    static let shared = MeetingsManager()

    @Published var upcomingMeetings: [UpcomingMeeting] = []
    @Published var isLoading = false
    @Published var error: String?

    func fetchUpcoming() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/meetings/upcoming") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            isLoading = true
            let (data, response) = try await URLSession.shared.data(for: request)
            isLoading = false

            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoder = JSONDecoder()
                // Handle custom date format if needed, usually ISO8601 is default
                decoder.dateDecodingStrategy = .iso8601

                struct Response: Codable {
                    let meetings: [UpcomingMeeting]
                }

                let result = try decoder.decode(Response.self, from: data)
                self.upcomingMeetings = result.meetings
            }
        } catch {
            isLoading = false
            NSLog("[MeetingsManager] Fetch error: %@", error.localizedDescription)
        }
    }

    func syncCalendar() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/meetings/sync") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Refetch after sync
                await fetchUpcoming()
            }
        } catch {
            NSLog("[MeetingsManager] Sync error: %@", error.localizedDescription)
        }
    }
}

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    @EnvironmentObject private var pageChrome: AppScreenLayout
    @ObservedObject private var auth = AuthManager.shared

    @State private var selectedTab: MeetingDetailTab = .overview
    @Namespace private var tabAnimation
    @State private var tabFrames: [MeetingDetailTab: CGRect] = [:]

    @State private var isRegeneratingSummary = false
    @State private var didCopySummary = false

    private enum MeetingDetailTab: String, CaseIterable {
        case overview = "Overview"
        case transcript = "Transcript"

        var icon: String {
            switch self {
            case .overview: return "list.bullet.rectangle"
            case .transcript: return "text.alignleft"
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
        repository.getChunks(meetingId: meetingId)
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
            VStack(spacing: 32) {
                header
                tabSection
            }
            .frame(maxWidth: 960)  // matches Aside-style width
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)  // center when window wider
        }
        .onAppear(perform: configureChrome)
        .onDisappear { pageChrome.clearOverride() }
        .onChange(of: meeting?.title) { _, _ in configureChrome() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(meetingTitle)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 28) {
                metaColumn(title: "Created", value: createdAtString)
                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.12))
        }
    }

    private var tabSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            tabSwitcher
            tabContent
        }
    }

    private func metaColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.primaryText)
        }
    }

    private var tabSwitcher: some View {
        VStack(spacing: 6) {
            HStack(spacing: 24) {
                ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedTab = tab
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
            MeetingTranscriptView(chunks: chunks)
        }
    }

    private func regenerateSummary() {
        guard !isRegeneratingSummary else { return }

        let transcript = repository.getFullTranscript(meetingId: meetingId)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isRegeneratingSummary = true
        let token = auth.accessToken

        MeetingsApi.shared.generateOverview(
            for: meetingId,
            transcript: trimmed,
            token: token
        ) { [weak repository] result in
            DispatchQueue.main.async {
                self.isRegeneratingSummary = false
                switch result {
                case .success(let summary):
                    repository?.updateMeetingNotes(meetingId: self.meetingId, notes: summary)
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

    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: title + actions
            HStack(spacing: 10) {
                Text("Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Spacer()

                // Regenerate
                Button {
                    regenerateSummary()
                } label: {
                    Image(
                        systemName: isRegeneratingSummary
                            ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle"
                    )
                    .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.secondaryText)
                .disabled(isRegeneratingSummary)

                // Copy
                Button {
                    copySummary()
                } label: {
                    Image(systemName: didCopySummary ? "checkmark.square" : "square.on.square")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.secondaryText)
                .disabled((meeting?.notes ?? "").isEmpty)
            }

            if let notes = meeting?.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownSummaryView(markdown: notes)
                }
                .padding(20)
            } else if isRegeneratingSummary {
                Text("Generating summary…")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            } else {
                Text("No AI summary yet. Generate notes after the meeting ends.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func configureChrome() {
        let crumbs = [
            Breadcrumb(title: "Calls"),
            Breadcrumb(title: meetingTitle),
        ]
        let action = AppScreenAction(title: "Share", systemImage: "square.and.arrow.up") {
            shareMeeting()
        }
        pageChrome.override(with: AppScreenLayoutState(breadcrumb: crumbs, action: action))
    }

    private func shareMeeting() {
        // TODO: Implement actual share
        NSLog("[MeetingView] Share tapped for \(meetingTitle)")
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
    @State private var didCopyTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if chunks.isEmpty {
                EmptyStateCard(
                    title: "No transcript yet",
                    subtitle: "Transcript entries appear here automatically once available."
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Transcript")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        Button {
                            copyTranscript()
                        } label: {
                            Label(
                                didCopyTranscript ? "Copied" : "Copy transcript",
                                systemImage: didCopyTranscript ? "checkmark" : "doc.on.doc"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(didCopyTranscript ? 0.18 : 0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(chunks) { chunk in
                        HStack(alignment: .top, spacing: 12) {
                            if chunk.speaker == .user {
                                speakerBadge(text: "You", accent: .blue)
                            } else {
                                speakerBadge(text: "Them", accent: .green)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(chunk.startedAt, style: .time)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.secondaryText)
                                Text(chunk.transcript)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.primaryText)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.02))
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)

            }
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

    // Add Manager
    @StateObject private var meetingsManager = MeetingsManager.shared

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

                    // --- NEW: Upcoming Section ---
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Upcoming")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                                .textCase(.uppercase)

                            Spacer()

                            Button {
                                Task { await meetingsManager.syncCalendar() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }

                        if meetingsManager.upcomingMeetings.isEmpty {
                            // Empty State / Connect CTA
                            // You can check IntegrationsManager.shared.googleStatus.connected here if you want
                            // For now, a simple card
                            HStack {
                                Text("No upcoming meetings found.")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.secondaryText)
                                Spacer()
                            }
                            .padding()
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calls")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppTheme.primaryText)
                        Text("Your recent recordings")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }

                    LazyVStack(alignment: .leading, spacing: 28, pinnedViews: []) {
                        ForEach(meetingSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.secondaryText)
                                    .textCase(.uppercase)

                                VStack(spacing: 12) {
                                    ForEach(section.meetings) { meeting in
                                        NavigationLink(value: meeting.id) {
                                            meetingCard(
                                                meeting, isSelected: selectedMeeting == meeting.id)
                                        }
                                        .buttonStyle(.plain)
                                        .simultaneousGesture(
                                            TapGesture().onEnded {
                                                selectedMeeting = meeting.id
                                            }
                                        )
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
            // Fetch upcoming on appear
            Task { await meetingsManager.fetchUpcoming() }

            if let meetingId = pendingMeetingId {
                navigationPath.append(meetingId)
                selectedMeeting = meetingId
                pendingMeetingId = nil
            }
        }
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

    private struct MeetingSection: Identifiable {
        var id: String { title }
        let title: String
        let meetings: [MeetingModel]
    }
}

private struct UpcomingMeetingCard: View {
    let meeting: UpcomingMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.startTimeFormatted)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                    Text(meeting.relativeTime)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
                if meeting.joinUrl != nil {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Text(meeting.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(2)
                .frame(height: 40, alignment: .topLeading)

            // Participants
            HStack(spacing: -8) {
                ForEach(meeting.participants.prefix(4)) { p in
                    if let url = p.avatarUrl, let u = URL(string: url) {
                        AsyncImage(url: u) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(p.name?.prefix(1) ?? p.email.prefix(1))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                    }
                }
                if meeting.participants.count > 4 {
                    Circle()
                        .fill(AppTheme.elevatedBackground)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("+\(meeting.participants.count - 4)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppTheme.secondaryText)
                        )
                        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                }
            }

            HStack {
                if let urlStr = meeting.joinUrl, let url = URL(string: urlStr) {
                    Link("Join", destination: url)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.blue)
                }

                Button("Record") {
                    // TODO: Start recording
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppTheme.accent)
            }
        }
        .padding(16)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

private struct SummarySection: Identifiable {
    let id = UUID()
    let title: String
    let bullets: [String]
}

private struct MarkdownSummaryView: View {
    let markdown: String

    private var sections: [SummarySection] {
        parseSummary(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    // Section title
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    // Bullets
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(section.bullets.indices, id: \.self) { i in
                            let bullet = section.bullets[i]
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppTheme.primaryText)

                                // Bullet with inline markdown (respects **bold**, _italic_, etc.)
                                textFromMarkdown(bullet)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.primaryText)
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
            }
        }
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

// Very simple markdown-ish parser: pulls out "## Heading" + "- bullet" lines
private func parseSummary(_ markdown: String) -> [SummarySection] {
    var sections: [SummarySection] = []
    var currentTitle: String?
    var currentBullets: [String] = []

    func flush() {
        if let title = currentTitle, !currentBullets.isEmpty {
            sections.append(SummarySection(title: title, bullets: currentBullets))
        }
        currentTitle = nil
        currentBullets = []
    }

    let lines = markdown.split(whereSeparator: \.isNewline).map {
        $0.trimmingCharacters(in: .whitespaces)
    }

    for line in lines {
        if line.hasPrefix("## ") {
            flush()
            currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- ") {
            let bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            currentBullets.append(bullet)
        } else if !line.isEmpty {
            // Continuation of previous bullet: append text
            if !currentBullets.isEmpty {
                currentBullets[currentBullets.count - 1] += " " + line
            }
        }
    }

    flush()
    return sections
}
