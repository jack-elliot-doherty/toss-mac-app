import SwiftUI

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository

    @State private var notes: String = ""
    @State private var showTranscriptOverlay: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""
    @State private var saveTask: Task<Void, Never>?

    var meeting: MeetingModel? {
        repository.getMeeting(id: meetingId)
    }

    var chunks: [MeetingChunkModel] {
        repository.getChunks(meetingId: meetingId)
    }

    var isRecording: Bool {
        meeting?.endTime == nil
    }

    var recordingDuration: TimeInterval? {
        guard let meeting = meeting else { return nil }
        let end = meeting.endTime ?? Date()
        return end.timeIntervalSince(meeting.startTime)
    }

    var relativeDate: String {
        guard let meeting = meeting else { return "Today" }
        let calendar = Calendar.current
        if calendar.isDateInToday(meeting.startTime) {
            return "Today"
        } else if calendar.isDateInYesterday(meeting.startTime) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: meeting.startTime)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.windowBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                notesArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomToolbar
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)

            if showTranscriptOverlay {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showTranscriptOverlay = false
                        }
                    }

                TranscriptOverlayView(
                    chunks: chunks,
                    isRecording: isRecording,
                    duration: recordingDuration,
                    onClose: {
                        withAnimation {
                            showTranscriptOverlay = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showTranscriptOverlay)
        .preferredColorScheme(.dark)
        .onAppear {
            loadNotes()
            checkIfRecording()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("OpenMeetingView"))
        ) { notification in
            if let userInfo = notification.userInfo,
                let notificationMeetingId = userInfo["meetingId"] as? UUID,
                notificationMeetingId == meetingId
            {
                showTranscriptOverlay = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                if isEditingTitle {
                    TextField(
                        "Meeting title",
                        text: $editedTitle,
                        onCommit: {
                            saveMeetingTitle()
                        }
                    )
                    .font(.system(size: 22, weight: .semibold))
                    .textFieldStyle(.plain)
                    .foregroundColor(AppTheme.primaryText)
                } else {
                    Text(meeting?.title ?? "Untitled meeting")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                        .onTapGesture {
                            editedTitle = meeting?.title ?? ""
                            isEditingTitle = true
                        }
                }

                Spacer()

                Button {
                    // TODO: Share meeting
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.secondaryText)
            }

            HStack(spacing: 10) {
                pill(icon: "calendar", text: relativeDate)

                pill(icon: "person.3.sequence", text: "\(chunks.count) entries")

                Button {
                    // TODO: Add to folder
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add to folder")
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.pillBackground())
                .cornerRadius(18)
                .foregroundColor(AppTheme.primaryText)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Notes Area

    private var notesArea: some View {
        ZStack(alignment: .topLeading) {
            if notes.isEmpty {
                Text("Write notes…")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            TextEditor(text: $notes)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onChange(of: notes) { _, _ in
                    autoSaveNotes()
                }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            if isRecording {
                transcriptIndicatorButton
            }

            Spacer()

            generateNotesButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    @State private var pulseAnimation = false

    private var transcriptIndicatorButton: some View {
        Button {
            showTranscriptOverlay = true
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.destructive)
                        .frame(width: 8, height: 8)

                    Circle()
                        .stroke(AppTheme.destructive.opacity(0.3), lineWidth: 4)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.8 : 1.0)
                        .opacity(pulseAnimation ? 0 : 1)
                }

                Text("Transcript on…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.pillBackground())
            .cornerRadius(24)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }

    private var generateNotesButton: some View {
        Button {
            // TODO: Generate notes with AI
            print("Generate notes tapped")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("Generate notes")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(AppTheme.primaryText)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(AppTheme.accent)
            .cornerRadius(24)
        }
        .buttonStyle(.plain)
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.pillBackground())
        .cornerRadius(18)
    }

    // MARK: - Helpers

    private func loadNotes() {
        notes = meeting?.notes ?? ""
    }

    private func checkIfRecording() {
        // Recording status is computed from meeting.endTime
    }

    private func saveMeetingTitle() {
        guard !editedTitle.isEmpty else {
            isEditingTitle = false
            return
        }
        // TODO: Add updateMeetingTitle to repository
        // repository.updateMeetingTitle(id: meetingId, title: editedTitle)
        isEditingTitle = false
    }

    private func autoSaveNotes() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            // TODO: Add updateMeetingNotes to repository
        }
    }
}

// MARK: - Transcript Overlay

struct TranscriptOverlayView: View {
    let chunks: [MeetingChunkModel]
    let isRecording: Bool
    let duration: TimeInterval?
    let onClose: () -> Void

    @State private var searchText: String = ""
    @State private var userHasScrolledUp: Bool = false

    var formattedDuration: String {
        guard let duration = duration else { return "00:00" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()
                .background(Color.white.opacity(0.1))

            transcriptContent

            Divider()
                .background(Color.white.opacity(0.1))

            bottomBar
        }
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(20)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                TextField("Search transcript...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    // TODO: Settings
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    // TODO: Notifications
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Transcript Content

    private var transcriptContent: some View {
        Group {
            if chunks.isEmpty && isRecording {
                emptyRecordingState
            } else if chunks.isEmpty {
                emptyState
            } else {
                transcriptTimeline
            }
        }
    }

    private var emptyRecordingState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))

            Text("Transcript on...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Text("Listening...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("No transcript yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Text("Start recording to see transcript")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptTimeline: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chunks) { chunk in
                        transcriptChunk(chunk)
                            .id(chunk.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .onChange(of: chunks.count) { oldValue, newValue in
                    // Auto-scroll to latest chunk
                    if let last = chunks.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func transcriptChunk(_ chunk: MeetingChunkModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Timestamp
            Text(chunk.timestamp, style: .time)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // Transcript text
            Text(chunk.transcript)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Resume button
            Button {
                // TODO: Resume/pause recording
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                    Text("Resume")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)

            Spacer()

            // Timer
            Text(formattedDuration)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundColor(.white)

            Spacer()

            // Language selector
            Button {
                // TODO: Language picker
            } label: {
                HStack(spacing: 6) {
                    Text("English")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Meetings List View

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
                        Text("Meetings")
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
            .navigationTitle("Meetings")
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
