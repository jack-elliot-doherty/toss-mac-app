import PostHog
import SwiftUI

@MainActor
struct ActivityView: View {
    @State private var dictations: [MessageModel] = []
    @State private var copiedId: UUID?
    @State private var hoveredId: UUID?
    @State private var feedbackMessage: MessageModel?
    @State private var feedbackText: String = ""
    @State private var showingRawId: UUID?  // NEW: which message is showing raw transcript

    var body: some View {
        ZStack {
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
                                    // Section header
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.secondaryText)

                                    VStack(spacing: 2) {
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

    // MARK: - WisprFlow-style Row

    private func dictationRow(_ message: MessageModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // LEFT: Timestamp (fixed width)
            Text(formattedTime(message.createdAt))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 70, alignment: .leading)

            // MIDDLE: Content (flexible)
            VStack(alignment: .leading, spacing: 6) {
                // Show raw or formatted based on toggle
                if showingRawId == message.id, let raw = message.rawTranscript {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Raw transcript")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                        Text(raw)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.primaryText.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // RIGHT: Action buttons (fixed width, always visible)
            HStack(spacing: 8) {
                // Copy button
                Button {
                    copyToClipboard(message, copyRaw: showingRawId == message.id)
                } label: {
                    Group {
                        if copiedId == message.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(
                                    hoveredId == message.id
                                        ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.5)
                                )
                        }
                    }
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(showingRawId == message.id ? "Copy raw transcript" : "Copy to clipboard")

                // Raw transcript toggle (only show if rawTranscript exists)
                if message.rawTranscript != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if showingRawId == message.id {
                                showingRawId = nil
                            } else {
                                showingRawId = message.id
                            }
                        }
                    } label: {
                        Image(
                            systemName: showingRawId == message.id
                                ? "text.badge.checkmark" : "text.badge.minus"
                        )
                        .font(.system(size: 12))
                        .foregroundColor(
                            showingRawId == message.id
                                ? .orange
                                : (hoveredId == message.id
                                    ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.5))
                        )
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(
                        showingRawId == message.id
                            ? "Show AI formatted" : "View raw transcript (no AI editing)")
                }

                // Flag button
                Button {
                    feedbackText = ""
                    feedbackMessage = message
                } label: {
                    Image(systemName: message.flaggedAt != nil ? "flag.fill" : "flag")
                        .font(.system(size: 12))
                        .foregroundColor(
                            message.flaggedAt != nil
                                ? .orange
                                : (hoveredId == message.id
                                    ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.5))
                        )
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(message.flaggedAt != nil ? "Already flagged" : "Report formatting issue")
            }
            .frame(width: 80, alignment: .trailing)  // Fixed width prevents layout shift
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredId == message.id ? AppTheme.cardBackground.opacity(0.5) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredId = hovering ? message.id : nil
            }
        }
    }

    private func copyToClipboard(_ message: MessageModel, copyRaw: Bool = false) {
        let textToCopy: String
        if copyRaw, let raw = message.rawTranscript {
            textToCopy = raw
        } else {
            textToCopy = message.content
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)

        withAnimation {
            copiedId = message.id
        }

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

    // MARK: - Feedback Modal (updated with raw/formatted comparison)

    private var feedbackModal: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    feedbackMessage = nil
                }

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Report Formatting Issue")
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

                // Show comparison if raw transcript exists
                if let message = feedbackMessage {
                    if let raw = message.rawTranscript, raw != message.content {
                        VStack(alignment: .leading, spacing: 12) {
                            // Raw transcript
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Raw transcript")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(raw)
                                    .font(.system(size: 13))
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.1))
                                    )
                            }

                            // Formatted
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI formatted")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(message.content)
                                    .font(.system(size: 13))
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    } else {
                        Text("Content: \(message.content)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                // Feedback input
                Text("What should it have been?")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)

                TextEditor(text: $feedbackText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 100)
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
                        Text("Send Feedback")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
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
            .frame(width: 500)
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

        History.shared.toggleMessageFlag(messageId: message.id)

        PostHogSDK.shared.capture(
            "dictation_feedback_submitted",
            properties: [
                "message_id": message.id.uuidString,
                "raw_transcript": message.rawTranscript ?? "",
                "formatted_text": message.content,
                "user_feedback": feedbackText,
                "created_at": ISO8601DateFormatter().string(from: message.createdAt),
            ])

        feedbackMessage = nil
        feedbackText = ""
        loadDictations()
    }
}
