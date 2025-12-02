import SwiftUI

@MainActor
struct ActivityView: View {
    @State private var dictations: [MessageModel] = []
    @State private var copiedId: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Dictations")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if dictations.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        ForEach(dictationSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                // Section header with date on right
                                HStack {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.secondaryText)

                                    Spacer()

                                    Text(section.dateString)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                                }

                                VStack(spacing: 10) {
                                    ForEach(section.messages) { message in
                                        dictationRow(message)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .onAppear {
            loadDictations()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))

            Text("No dictations yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text("Hold Fn to start dictating")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func dictationRow(_ message: MessageModel) -> some View {
        Button {
            copyToClipboard(message)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Subtle hint
                    Text("Click to copy")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                }

                // Copied feedback or time
                VStack(alignment: .trailing, spacing: 4) {
                    if copiedId == message.id {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                            Text("Copied")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        Text(formattedTime(message.createdAt))
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.cardBackground.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())  // Makes entire area tappable
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func copyToClipboard(_ message: MessageModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)

        withAnimation {
            copiedId = message.id
        }

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedId == message.id {
                    copiedId = nil
                }
            }
        }
    }

    private func loadDictations() {
        let thread = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: thread.id).reversed()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Sections

    private struct DictationSection: Identifiable {
        var id: String { title }
        let title: String
        let dateString: String
        let messages: [MessageModel]
    }

    private var dictationSections: [DictationSection] {
        let grouped = Dictionary(grouping: dictations) { sectionTitle(for: $0.createdAt) }
        let sections = grouped.map { key, messages -> DictationSection in
            DictationSection(
                title: key,
                dateString: fullDateString(messages.first?.createdAt ?? Date()),
                messages: messages.sorted { $0.createdAt > $1.createdAt }
            )
        }
        return sections.sorted { lhs, rhs in
            guard let lhsDate = lhs.messages.first?.createdAt,
                let rhsDate = rhs.messages.first?.createdAt
            else { return false }
            return lhsDate > rhsDate
        }
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

    private func fullDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
