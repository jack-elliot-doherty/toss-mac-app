import SwiftUI

struct FolderMeetingsView: View {
    let folderId: String
    @ObservedObject var repository: PersistentMeetingRepository

    @StateObject private var foldersManager = FoldersManager.shared
    @State private var meetings: [FolderMeeting] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let errorMessage, meetings.isEmpty, !isLoading {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    } else if meetings.isEmpty && !isLoading {
                        Text("No meetings in this folder yet.")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    } else {
                        meetingsList
                    }
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 28)
            }
            .navigationDestination(for: String.self) { meetingId in
                FolderMeetingDetailView(
                    meetingId: meetingId,
                    repository: repository
                )
            }
            .onAppear { Task { await loadFolder() } }
            .onChange(of: folderId) { _, _ in
                Task { await loadFolder() }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let cachedFolder = foldersManager.folders.first(where: { $0.id == folderId })
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(cachedFolder?.name ?? "Folder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if let accessType = cachedFolder?.accessType {
                Text(accessType.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
    }

    private var meetingsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedMeetings, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                    }

                    VStack(spacing: 0) {
                        ForEach(group.meetings) { meeting in
                            NavigationLink(value: meeting.id) {
                                folderMeetingRow(meeting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func folderMeetingRow(_ meeting: FolderMeeting) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.secondaryText.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                )

            Text(meeting.title ?? "Untitled meeting")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(formattedTime(meeting.startedAt))
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var groupedMeetings: [MeetingGroup] {
        let sorted = meetings.sorted { meetingDate($0) > meetingDate($1) }
        let grouped = Dictionary(grouping: sorted) { sectionTitle(for: meetingDate($0)) }
        return grouped.map { key, values in
            MeetingGroup(
                title: key,
                meetings: values,
                sortDate: meetingDate(values.first!)
            )
        }.sorted { $0.sortDate > $1.sortDate }
    }

    private func meetingDate(_ meeting: FolderMeeting) -> Date {
        parseDate(meeting.startedAt) ?? Date.distantPast
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formattedTime(_ dateString: String?) -> String {
        guard let date = parseDate(dateString) else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }

    private func loadFolder() async {
        isLoading = true
        do {
            meetings = try await FoldersAPI.shared.fetchFolderMeetings(folderId: folderId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct MeetingGroup: Identifiable {
    let id = UUID()
    let title: String
    let meetings: [FolderMeeting]
    let sortDate: Date
}

private struct FolderMeetingDetailView: View {
    let meetingId: String
    @ObservedObject var repository: PersistentMeetingRepository

    var body: some View {
        if let uuid = UUID(uuidString: meetingId),
           repository.getMeeting(id: uuid) != nil {
            MeetingView(meetingId: uuid, repository: repository)
        } else {
            SharedMeetingView(meetingId: meetingId)
        }
    }
}
