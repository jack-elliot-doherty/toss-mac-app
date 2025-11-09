import SwiftUI

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    @State private var notes: String = ""
    @State private var isRecording: Bool = false

    var meeting: MeetingModel? {
        repository.getMeeting(id: meetingId)
    }

    var chunks: [MeetingChunkModel] {
        repository.getChunks(meetingId: meetingId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content area
            HStack(spacing: 0) {
                // Left side: Notes
                notesSection
                    .frame(maxWidth: .infinity)

                Divider()

                // Right side: Transcript
                transcriptSection
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            checkIfRecording()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("OpenMeetingView"))
        ) { notification in
            if let userInfo = notification.userInfo,
                let notificationMeetingId = userInfo["meetingId"] as? UUID,
                notificationMeetingId == meetingId
            {
                // This meeting was opened, maybe refresh or scroll to bottom
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Meeting title (editable)
            if let meeting = meeting {
                Text(meeting.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Metadata pills
            HStack(spacing: 8) {
                // Date pill
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text("Today")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                // Participant pill
                HStack(spacing: 4) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 11))
                    Text("Me")
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

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Notes header
            Text("Write notes...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Notes text editor
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .scrollContentBackground(.hidden)
                .background(Color.clear)

            Spacer()

            // Bottom toolbar (like Granola's "Ask anything")
            notesToolbar
        }
    }

    private var notesToolbar: some View {
        HStack(spacing: 12) {
            // Voice input button
            Button {
                // TODO: Start voice input for notes
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)

            // Ask anything input
            HStack {
                Text("Ask anything")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(20)

            // Suggest topics button
            Button {
                // TODO: AI suggest topics
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Suggest topics")
                        .font(.system(size: 13))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Transcript header
            HStack {
                if isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Transcript on...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Transcript")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if chunks.isEmpty && isRecording {
                // Empty state while recording
                VStack(spacing: 12) {
                    Spacer()
                    Text("Transcript on...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Try saying \"Hello Granola\"")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chunks.isEmpty {
                // Empty state not recording
                VStack(spacing: 12) {
                    Spacer()
                    Text("No transcript yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Start recording to see transcript")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Transcript content
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(chunks) { chunk in
                                transcriptChunk(chunk)
                                    .id(chunk.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
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

            // Bottom disclaimer
            HStack {
                Spacer()
                Text("Always get consent when transcribing others.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("Learn more") {
                    // TODO: Open learn more
                }
                .font(.system(size: 11))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.05))
        }
    }

    private func transcriptChunk(_ chunk: MeetingChunkModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Timestamp
            Text(chunk.timestamp, style: .time)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Transcript text
            Text(chunk.transcript)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func checkIfRecording() {
        // Check if this meeting has no end time (still recording)
        isRecording = meeting?.endTime == nil
    }
}

// MARK: - Meetings List View

struct MeetingsListView: View {
    @ObservedObject var repository: PersistentMeetingRepository
    @State private var selectedMeeting: UUID?

    var meetings: [MeetingModel] {
        repository.listMeetings()
    }

    var body: some View {
        NavigationStack {
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
