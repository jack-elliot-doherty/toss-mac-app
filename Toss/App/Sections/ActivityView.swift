import PostHog
import SwiftUI

@MainActor
struct ActivityView: View {
    @State private var dictations: [MessageModel] = []
    @State private var copiedId: UUID?
    @State private var hoveredId: UUID?
    @State private var feedbackMessage: MessageModel?  // NEW: which message is being reported
    @State private var feedbackText: String = ""  // NEW: user's feedback text

    var body: some View {
        ZStack {
            // Existing ScrollView content
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

            // Feedback modal overlay
            if feedbackMessage != nil {
                feedbackModal
            }
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

                Spacer()

                // Feedback buttons - show on hover or if already rated
                if hoveredId == message.id || message.flaggedAt != nil {
                    flagButton(for: message)
                        .transition(.opacity)
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
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredId = hovering ? message.id : nil
            }
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

    private func flagButton(for message: MessageModel) -> some View {
        Button {
            feedbackText = ""
            feedbackMessage = message
        } label: {
            Image(systemName: message.flaggedAt != nil ? "flag.fill" : "flag")
                .font(.system(size: 12))
                .foregroundColor(
                    message.flaggedAt != nil ? .orange : AppTheme.secondaryText.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help("Report bad formatting")
    }

    // NEW: Feedback modal
    private var feedbackModal: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    feedbackMessage = nil
                }

            // Modal card
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Report to Improve Model")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Spacer()

                    Button {
                        feedbackMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                // Description
                Text(
                    "Thanks for the feedback to help improve our model. Describe what you expected instead."
                )
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                // Text input
                TextEditor(text: $feedbackText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.secondaryText.opacity(0.3), lineWidth: 1)
                    )

                // Send button
                HStack {
                    Spacer()
                    Button {
                        sendFeedback()
                    } label: {
                        Text("Send report")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.5 : 1)
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: 450)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: feedbackMessage != nil)
    }

    private func sendFeedback() {
        guard let message = feedbackMessage else { return }

        // Mark as flagged in local storage
        History.shared.toggleMessageFlag(messageId: message.id)

        // Send to PostHog
        PostHogSDK.shared.capture(
            "dictation_feedback_submitted",
            properties: [
                "message_id": message.id.uuidString,
                "original_text": message.content,
                "user_feedback": feedbackText,
                "created_at": ISO8601DateFormatter().string(from: message.createdAt),
            ])

        // Close modal and reload
        feedbackMessage = nil
        feedbackText = ""
        loadDictations()
    }
}
