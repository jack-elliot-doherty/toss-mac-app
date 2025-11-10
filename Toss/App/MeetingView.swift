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
            // Base notes interface
            VStack(spacing: 0) {
                header
                Divider()
                notesArea
                bottomToolbar
            }
            .background(Color(NSColor.windowBackgroundColor))

            // Transcript overlay (when expanded)
            if showTranscriptOverlay {
                Color.black.opacity(0.3)
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
                // Auto-open transcript when navigating to this meeting
                showTranscriptOverlay = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Meeting title (editable)
            if isEditingTitle {
                TextField(
                    "Meeting title", text: $editedTitle,
                    onCommit: {
                        saveMeetingTitle()
                    }
                )
                .font(.system(size: 20, weight: .semibold))
                .textFieldStyle(.plain)
            } else {
                Text(meeting?.title ?? "Untitled meeting")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        editedTitle = meeting?.title ?? ""
                        isEditingTitle = true
                    }
            }

            Spacer()

            // Metadata pills
            HStack(spacing: 8) {
                // Date pill
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(relativeDate)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                // Add to folder button
                Button {
                    // TODO: Add to folder
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("Add to folder")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Notes Area

    private var notesArea: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if notes.isEmpty {
                Text("Write notes...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            // Text editor
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onChange(of: notes) { oldValue, newValue in
                    autoSaveNotes()
                }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Left: Transcript indicator (only when recording)
            if isRecording {
                transcriptIndicatorButton
            }

            Spacer()

            // Right: Generate notes button
            generateNotesButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.03))
        .overlay(
            Divider(),
            alignment: .top
        )
    }

    @State private var pulseAnimation = false

    private var transcriptIndicatorButton: some View {
        Button {
            showTranscriptOverlay = true
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.8 : 1.0)
                        .opacity(pulseAnimation ? 0 : 1)
                }

                Text("Transcript on...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(20)
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
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("Generate notes")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.blue)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
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
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms debounce
            // TODO: Add updateMeetingNotes to repository
            // repository.updateMeetingNotes(id: meetingId, notes: notes)
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                List(meetings, selection: $selectedMeeting) { meeting in
                    NavigationLink(value: meeting.id) {
                        meetingRow(meeting)
                    }
                }
                .navigationTitle("Meetings")
                .navigationDestination(for: UUID.self) { meetingId in
                    MeetingView(meetingId: meetingId, repository: repository)
                }
            }
        }.onChange(of: pendingMeetingId) { oldValue, newValue in
            if let meetingId = newValue {
                // Navigate to the meeting
                navigationPath.append(meetingId)
                selectedMeeting = meetingId
                // Clear the pending ID after handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pendingMeetingId = nil
                }
            }
        }.onAppear {
            // Handle case where view appears with pending meeting
            if let meetingId = pendingMeetingId {
                navigationPath.append(meetingId)
                selectedMeeting = meetingId
                pendingMeetingId = nil
            }
        }
    }

    private func meetingRow(_ meeting: MeetingModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.system(size: 14, weight: .medium))

            HStack(spacing: 4) {
                Text(meeting.startTime, style: .date)
                Text("•")
                Text(meeting.startTime, style: .time)

                if let endTime = meeting.endTime {
                    Text("•")
                    Text(durationString(from: meeting.startTime, to: endTime))
                } else {
                    Text("• Recording...")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
