import SwiftUI

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    @EnvironmentObject private var pageChrome: AppScreenLayout

    @State private var selectedTab: MeetingDetailTab = .summary

    private enum MeetingDetailTab: String, CaseIterable {
        case summary = "Summary"
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
            VStack(alignment: .leading, spacing: 28) {
                header
                tabSwitcher
                tabContent
            }
            .padding(.bottom, 48)
        }
        .onAppear {
            configureChrome()
        }
        .onDisappear {
            pageChrome.clearOverride()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meetingTitle)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text("Created \(createdAtString)")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Divider()
                .background(AppTheme.subtleStroke)

            HStack(spacing: 24) {
                metaColumn(title: "Duration", value: durationString)
                metaColumn(title: "Entries", value: "\(chunks.count)")
                Spacer()
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
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
        HStack(spacing: 6) {
            ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    selectedTab == tab
                                        ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
                        )
                        .foregroundColor(
                            selectedTab == tab ? AppTheme.primaryText : AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .summary:
            summaryView
        case .transcript:
            MeetingTranscriptView(chunks: chunks)
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)

            if let notes = meeting?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.primaryText)
                    .lineSpacing(6)
            } else {
                Text("No AI summary yet. Generate notes after the meeting ends.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
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
        if chunks.isEmpty {
            VStack(spacing: 12) {
                Text("No transcript yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text("Transcript entries will appear here automatically once available.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(chunks) { chunk in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chunk.timestamp, style: .time)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(chunk.transcript)
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.primaryText)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(24)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Meetings List View (unchanged from previous design)

struct MeetingsListView: View {
    @ObservedObject var repository: PersistentMeetingRepository
    @Binding var pendingMeetingId: UUID?
    @State private var selectedMeeting: UUID?
    @State private var navigationPath = NavigationPath()

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
