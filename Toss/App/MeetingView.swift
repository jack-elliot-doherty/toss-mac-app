import SwiftUI

struct MeetingView: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository

    var meeting: MeetingModel? {
        repository.getMeeting(id: meetingId)
    }

    var chunks: [MeetingChunkModel] {
        repository.getChunks(meetingId: meetingId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                Text("Recording Meeting")
                    .font(.headline)
                Spacer()
                if let meeting = meeting {
                    Text(timeString(from: meeting.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Live transcript
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(chunks) { chunk in
                            HStack(alignment: .top, spacing: 8) {
                                Text("[\(chunk.chunkIndex)]")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)

                                Text(chunk.transcript)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .id(chunk.id)
                        }
                    }
                    .padding()
                    .onChange(of: chunks.count) { oldValue, newValue in
                        // Auto-scroll to latest chunk
                        if let last = chunks.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func timeString(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// New file or add to MeetingView.swift

struct MeetingsListView: View {
    @ObservedObject var repository: PersistentMeetingRepository
    @State private var selectedMeeting: UUID?

    var meetings: [MeetingModel] {
        repository.listMeetings()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // List of meetings
                List(meetings, selection: $selectedMeeting) { meeting in
                    NavigationLink(value: meeting.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meeting.title)
                                .font(.headline)
                            HStack {
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
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Meetings")
                .navigationDestination(for: UUID.self) { meetingId in
                    MeetingView(meetingId: meetingId, repository: repository)
                }
            }
        }
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
