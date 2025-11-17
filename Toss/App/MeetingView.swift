import SwiftUI

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    @EnvironmentObject private var pageChrome: AppScreenLayout

    @State private var selectedTab: MeetingDetailTab = .overview

    private enum MeetingDetailTab: String, CaseIterable {
        case overview = "Overview"
        case transcript = "Transcript"
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
        .background(AppTheme.windowBackground)
        .onAppear(perform: configureChrome)
        .onDisappear { pageChrome.clearOverride() }
        .onChange(of: meeting?.title) { _, _ in configureChrome() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meetingTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Created \(createdAtString)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 32) {
                metaColumn(title: "Duration", value: durationString)
                metaColumn(title: "Entries", value: "\(chunks.count)")
                Spacer()
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .black : AppTheme.secondaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(
                                    selectedTab == tab
                                        ? Color.white
                                        : Color.white.opacity(0.08)
                                )
                        )
                }
                .buttonStyle(.plain)
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

    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)

            if let notes = meeting?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.primaryText)
                    .lineSpacing(5)
            } else {
                Text("No AI summary yet. Generate notes after the meeting ends.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
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
}

private struct MeetingTranscriptView: View {
    let chunks: [MeetingChunkModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if chunks.isEmpty {
                EmptyStateCard(
                    title: "No transcript yet",
                    subtitle: "Transcript entries appear here automatically once available."
                )
            } else {
                VStack(spacing: 16) {
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
            .background(AppTheme.windowBackground)
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
