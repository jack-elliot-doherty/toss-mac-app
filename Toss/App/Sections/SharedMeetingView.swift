import SwiftUI

struct SharedMeetingView: View {
    let meetingId: String

    @State private var meeting: MeetingsApi.SharedMeetingDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                } else if let meeting {
                    header(meeting)
                    summarySection(meeting)
                    transcriptSection(meeting)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .onAppear { Task { await loadMeeting() } }
    }

    private func header(_ meeting: MeetingsApi.SharedMeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meeting.title ?? "Untitled meeting")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            Text(formattedDate(meeting.startedAt))
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)

            if let sharedBy = meeting.sharedByName ?? meeting.sharedByEmail {
                Text("Shared by \(sharedBy)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.8))
            }
        }
    }

    private func summarySection(_ meeting: MeetingsApi.SharedMeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            Text(meeting.summary ?? "No summary available.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private func transcriptSection(_ meeting: MeetingsApi.SharedMeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            Text(meeting.transcript ?? "No transcript available.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .lineSpacing(4)
        }
    }

    private func formattedDate(_ dateString: String?) -> String {
        guard let date = parseDate(dateString) else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }

    private func loadMeeting() async {
        isLoading = true
        do {
            meeting = try await MeetingsApi.shared.fetchMeeting(meetingId: meetingId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
