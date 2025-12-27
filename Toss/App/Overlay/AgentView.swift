import PostHog
import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @Namespace private var scrollNamespace

    // Listen for focus notification
    private let focusNotification = NotificationCenter.default.publisher(
        for: NSNotification.Name("FocusAgentInput"))

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isCompactMode {
                // MARK: - Compact Mode (Input Only)
                CompactInputView(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    onSend: {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else {
                            return
                        }
                        let message = inputText
                        inputText = ""
                        // Transition to full mode, then send
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            viewModel.isCompactMode = false
                        }
                        // Small delay to let animation start
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            viewModel.sendMessage(message)
                        }
                    },
                    onClose: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("HideAgentPanel"), object: nil)
                    }
                )
                .onReceive(focusNotification) { _ in
                    isInputFocused = true
                }
            } else {
                // MARK: - Full Mode
                // Header
                AgentHeader()

                Divider()
                    .background(Color.white.opacity(0.08))

                // Messages
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg, viewModel: viewModel)
                                    .id(msg.id)
                                    .transition(
                                        .move(edge: .bottom)
                                            .combined(with: .opacity)
                                    )
                            }

                            // Show only ONE pending approval at a time (sequential UX)
                            // This avoids scroll chaos and matches natural workflow
                            if let call = viewModel.currentPendingApproval {
                                if call.isConnectTool {
                                    ConnectToolCard(
                                        toolCall: call,
                                        onApprove: {
                                            Task { await viewModel.approveToolCall(call) }
                                        }
                                    )
                                    .id(call.id)
                                    .transition(.opacity.combined(with: .scale))
                                } else {
                                    ToolApprovalCard(
                                        toolCall: call,
                                        onApprove: {
                                            Task { await viewModel.approveToolCall(call) }
                                        },
                                        onReject: { viewModel.rejectToolCall(call) }
                                    )
                                    .id(call.id)
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }

                            if viewModel.isProcessing && !viewModel.isStreaming {
                                ProcessingRow()
                                    .transition(.opacity)
                            }

                            if let error = viewModel.errorMessage {
                                ErrorBubble(text: error)
                                    .transition(.opacity)
                            }

                            // Invisible anchor for reliable scroll-to-bottom
                            Color.clear
                                .frame(height: 1)
                                .id("bottom-anchor")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.messages.last?.content) { _ in
                        // Scroll as streaming content grows
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.currentPendingApproval?.id) { _ in
                        // Scroll when the current pending approval changes
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.isProcessing) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.isStreaming) { _ in
                        scrollToBottom(proxy)
                    }
                    .onAppear { scrollToBottom(proxy) }
                }

                Divider()
                    .background(Color.white.opacity(0.08))

                // Footer
                AgentFooter(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    isProcessing: viewModel.isProcessing,
                    onSend: {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else {
                            return
                        }
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                )
            }
        }
        .frame(width: viewModel.isCompactMode ? 500 : 650)
        .appGlass(.surface, radius: 18, opacity: 0.001)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.messages)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.85),
            value: viewModel.currentPendingApproval?.id
        )
        .animation(.easeInOut(duration: 0.15), value: viewModel.isProcessing)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isCompactMode)
        .onAppear {
            // Focus input when appearing in compact mode
            if viewModel.isCompactMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Small delay to ensure view has rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }
}

// MARK: - Compact Input View (Input Only Mode)

private struct CompactInputView: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onClose: () -> Void

    @State private var isHoveringClose = false

    var body: some View {
        VStack(spacing: 8) {
            // Input row
            HStack(spacing: 12) {
                // Text input
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .focused(isInputFocused)
                    .onSubmit {
                        if !inputText.isEmpty {
                            onSend()
                        }
                    }

                // Send button
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(inputText.isEmpty ? .white.opacity(0.4) : .white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(inputText.isEmpty ? Color.white.opacity(0.08) : Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)

                // Close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(isHoveringClose ? 0.8 : 0.5))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isHoveringClose ? 0.15 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
            }

            // Voice hint
            HStack(spacing: 4) {
                Text("Hold")
                    .foregroundColor(.white.opacity(0.4))
                KeyboardShortcutHint(keys: ["fn", "⌘"])
                Text("to speak to Toss")
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            // Auto-focus the text field when compact view appears (backup, main trigger is notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isInputFocused.wrappedValue = true
            }
        }
    }
}

// MARK: - Keyboard Shortcut Hint

private struct KeyboardShortcutHint: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Agent Header

private struct AgentHeader: View {
    @State private var isHoveringMinimize = false
    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            // Minimize button
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MinimizeAgentPanel"), object: nil)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(isHoveringMinimize ? 1.0 : 0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHoveringMinimize ? 0.15 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringMinimize = $0 }
            .help("Minimize (keep session active)")

            // Close button
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("HideAgentPanel"), object: nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(isHoveringClose ? 1.0 : 0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHoveringClose ? 0.15 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help("End session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Agent Footer

private struct AgentFooter: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let isProcessing: Bool
    let onSend: () -> Void

    @State private var isHoveringSend = false

    var body: some View {
        HStack(spacing: 12) {
            // Text input
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(1...4)
                .focused(isInputFocused)
                .onSubmit {
                    if !inputText.isEmpty {
                        onSend()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )

            // Send button
            Button {
                onSend()
            } label: {
                Group {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundColor(inputText.isEmpty ? .white.opacity(0.4) : .white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(inputText.isEmpty ? Color.white.opacity(0.08) : Color.blue)
                )
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isProcessing)
            .onHover { isHoveringSend = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        // Keyboard hints
        HStack(spacing: 16) {
            // Voice hint
            HStack(spacing: 4) {
                Text("Hold")
                    .foregroundColor(.white.opacity(0.35))
                KeyboardShortcutHint(keys: ["fn", "⌘"])
                Text("to speak to Toss")
                    .foregroundColor(.white.opacity(0.35))
            }
            .font(.system(size: 10))

            Spacer()

            // Close hint
            HStack(spacing: 4) {
                KeyboardShortcutHint(keys: ["esc"])
                Text("to close")
                    .foregroundColor(.white.opacity(0.35))
            }
            .font(.system(size: 10))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct ProcessingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Thinking…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.vertical, 4)
    }
}

private struct ErrorBubble: View {
    let text: String

    var body: some View {
        Text("Error: \(text)")
            .font(.system(size: 12))
            .foregroundColor(.red)
            .padding(10)
            .background(Color.red.opacity(0.08))
            .cornerRadius(10)
    }
}

private struct MessageBubble: View {
    let message: AgentViewModel.DisplayMessage
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var feedbackGiven: String? = nil  // "positive" or "negative"

    var body: some View {
        // Special handling for different notification types
        if message.isMemorySave {
            MemorySaveNotification(message: message, isExpanded: $isExpanded)
        } else if message.isToolExecution {
            ToolExecutionNotification(message: message, isExpanded: $isExpanded)
        } else if message.isToolApprovalWaiting {
            ToolApprovalWaitingNotification(message: message, isExpanded: $isExpanded)
        } else {
            regularMessageView
        }
    }

    private var regularMessageView: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if message.role == .user { Spacer() }

                VStack(
                    alignment: message.role == .user ? .trailing : .leading,
                    spacing: 4
                ) {
                    if isEditing {
                        // Edit mode for user messages
                        editModeView
                    } else {
                        // Normal display
                        if message.role == .assistant {
                            Text(markdownAttributedString)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                        } else {
                            Text(message.content)
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(bubbleBackground)
                                .foregroundColor(.white)
                                .cornerRadius(18)
                        }
                    }
                }

                if message.role == .assistant { Spacer() }
            }

            // Action bar - always present to reserve space, just fade opacity
            if !isEditing && !message.content.isEmpty {
                MessageActionBar(
                    message: message,
                    viewModel: viewModel,
                    feedbackGiven: $feedbackGiven,
                    onEdit: {
                        editText = message.content
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isEditing = true
                        }
                    }
                )
                .opacity(isHovering ? 1 : 0)
            }
        }
        .contentShape(Rectangle())  // Make entire VStack hoverable
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var editModeView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Edit message...", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(1...10)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                )

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isEditing = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newContent.isEmpty {
                        viewModel.editAndResend(messageId: message.id, newContent: newContent)
                    }
                    isEditing = false
                } label: {
                    Text("Submit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var markdownAttributedString: AttributedString {
        do {
            var result = try AttributedString(
                markdown: message.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            // Style bold text
            for run in result.runs {
                if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                    result[run.range].foregroundColor = .white
                }
            }
            return result
        } catch {
            return AttributedString(message.content)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            Color.black.opacity(0.6)
        } else {
            Color.clear
        }
    }
}

// MARK: - Message Action Bar

private struct MessageActionBar: View {
    let message: AgentViewModel.DisplayMessage
    @ObservedObject var viewModel: AgentViewModel
    @Binding var feedbackGiven: String?
    let onEdit: () -> Void

    @State private var copiedFeedback = false

    var body: some View {
        HStack(spacing: 2) {
            // Copy button (for both user and assistant)
            ActionButton(icon: copiedFeedback ? "checkmark" : "doc.on.doc", tooltip: "Copy") {
                copyToClipboard()
            }

            if message.role == .assistant {
                // Thumbs up
                ActionButton(
                    icon: "hand.thumbsup",
                    tooltip: "Good response",
                    isActive: feedbackGiven == "positive"
                ) {
                    submitFeedback(rating: "positive")
                }

                // Thumbs down
                ActionButton(
                    icon: "hand.thumbsdown",
                    tooltip: "Poor response",
                    isActive: feedbackGiven == "negative"
                ) {
                    submitFeedback(rating: "negative")
                }

                // Retry (regenerate from this point)
                ActionButton(icon: "arrow.clockwise", tooltip: "Regenerate") {
                    viewModel.retryFromMessage(message.id)
                }
            } else if message.role == .user {
                // Edit button
                ActionButton(icon: "pencil", tooltip: "Edit") {
                    onEdit()
                }

                // Retry (resend from this point)
                ActionButton(icon: "arrow.clockwise", tooltip: "Retry from here") {
                    viewModel.retryFromMessage(message.id)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)

        // Show feedback
        withAnimation {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copiedFeedback = false
            }
        }
    }

    private func submitFeedback(rating: String) {
        feedbackGiven = rating

        PostHogSDK.shared.capture(
            "agent_feedback",
            properties: [
                "rating": rating,
                "message_id": message.id.uuidString,
                "message_role": message.role.rawValue,
                "message_content": String(message.content.prefix(500)),
                "conversation_length": viewModel.messages.count,
            ])
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .blue : (isHovering ? .white : .white.opacity(0.6)))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(
                            isActive
                                ? Color.blue.opacity(0.2)
                                : (isHovering ? Color.white.opacity(0.1) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

// MARK: - Memory Save Notification (subtle reasoning-trace style)

private struct MemorySaveNotification: View {
    let message: AgentViewModel.DisplayMessage
    @Binding var isExpanded: Bool

    private var memoryText: String {
        if let details = message.memoryDetails,
            let memory = details["memory"] as? String
        {
            return memory
        }
        // Fallback: extract from content (format: "💭 Remembered: ...")
        let content = message.content
        if content.hasPrefix("💭 Remembered: ") {
            return String(content.dropFirst("💭 Remembered: ".count))
        }
        return content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Collapsed: subtle inline text with chevron
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))

                    Text("Added to memory")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .italic()
                }
            }
            .buttonStyle(.plain)

            // Expanded: show the actual memory
            if isExpanded {
                Text(memoryText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.leading, 15)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tool Execution Notification (subtle style with tool logo)

private struct ToolExecutionNotification: View {
    let message: AgentViewModel.DisplayMessage
    @Binding var isExpanded: Bool

    private var toolName: String {
        message.toolExecutionName ?? "Unknown"
    }

    private var isSlackTool: Bool {
        toolName.lowercased().hasPrefix("slack")
    }

    private var isLinearTool: Bool {
        toolName.lowercased().hasPrefix("linear")
    }

    private var isCalendarTool: Bool {
        toolName.lowercased().hasPrefix("calendar")
    }

    private var isNotionTool: Bool {
        toolName.lowercased().hasPrefix("notion")
    }

    // Internal app tools (meetings, contacts, memory, screenshot)
    private var isAppTool: Bool {
        let name = toolName.lowercased()
        let appToolPrefixes = [
            "meeting", "contact", "company", "memory", "screenshot", "save", "list", "get",
            "search", "delete",
        ]
        // Check if it's an app tool (not an integration tool)
        if isSlackTool || isLinearTool || isCalendarTool || isNotionTool {
            return false
        }
        // Check common app tool patterns
        return appToolPrefixes.contains { name.hasPrefix($0) || name.contains($0) }
    }

    private var actionText: String {
        let name = toolName.lowercased()
        if isSlackTool {
            if name.contains("send") { return "Sent to Slack" }
            return "Read Slack"
        }
        if isLinearTool {
            if name.contains("create") { return "Created Linear issue" }
            if name.contains("search") { return "Searched Linear" }
            return "Read from Linear"
        }
        if isCalendarTool {
            if name.contains("create") { return "Created calendar event" }
            if name.contains("list") { return "Listed calendar events" }
            return "Read from Calendar"
        }
        if isNotionTool {
            if name.contains("createdatabase") { return "Created Notion database" }
            if name.contains("create") { return "Created Notion page" }
            if name.contains("append") { return "Added to Notion page" }
            if name.contains("search") { return "Searched Notion" }
            if name.contains("list") { return "Listed Notion databases" }
            return "Read from Notion"
        }
        if isAppTool {
            if name.contains("meeting") {
                if name.contains("list") { return "Listed meetings" }
                if name.contains("search") { return "Searched meetings" }
                if name.contains("share") { return "Shared meeting" }
                return "Loaded meeting"
            }
            if name.contains("contact") || name.contains("company") {
                if name.contains("search") { return "Searched contacts" }
                return "Loaded contacts"
            }
            if name.contains("memory") || name.contains("save") {
                if name.contains("save") { return "Saved memory" }
                if name.contains("delete") { return "Deleted memory" }
                return "Loaded memories"
            }
            if name.contains("screenshot") { return "Took screenshot" }
        }
        // Convert snake_case to readable
        return toolName.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var inProgressText: String {
        let name = toolName.lowercased()
        if isSlackTool {
            if name.contains("send") { return "Sending to Slack..." }
            return "Reading Slack..."
        }
        if isLinearTool {
            if name.contains("create") { return "Creating Linear issue..." }
            if name.contains("search") { return "Searching Linear..." }
            return "Reading from Linear..."
        }
        if isCalendarTool {
            if name.contains("create") { return "Creating calendar event..." }
            if name.contains("list") { return "Listing calendar events..." }
            return "Reading from Calendar..."
        }
        if isNotionTool {
            if name.contains("createdatabase") { return "Creating Notion database..." }
            if name.contains("create") { return "Creating Notion page..." }
            if name.contains("append") { return "Adding to Notion page..." }
            if name.contains("search") { return "Searching Notion..." }
            if name.contains("list") { return "Listing Notion databases..." }
            return "Reading from Notion..."
        }
        if isAppTool {
            if name.contains("meeting") {
                if name.contains("list") { return "Loading meetings..." }
                if name.contains("search") { return "Searching meetings..." }
                if name.contains("share") { return "Sharing meeting..." }
                return "Loading meeting..."
            }
            if name.contains("contact") || name.contains("company") {
                if name.contains("search") { return "Searching contacts..." }
                return "Loading contacts..."
            }
            if name.contains("memory") || name.contains("save") {
                if name.contains("save") { return "Saving memory..." }
                if name.contains("delete") { return "Deleting memory..." }
                return "Loading memories..."
            }
            if name.contains("screenshot") { return "Taking screenshot..." }
        }
        return toolName.replacingOccurrences(of: "_", with: " ").capitalized + "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Collapsed: subtle inline text with tool icon and chevron
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))

                    toolIcon
                        .frame(width: 14, height: 14)

                    Text(message.toolExecutionComplete ? actionText : inProgressText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .italic()

                    if message.toolExecutionComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded: show args and result
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let args = message.toolExecutionArgs, !args.isEmpty {
                        Text("Input:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                        Text(formatJSON(args))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .textSelection(.enabled)
                    }

                    if let result = message.toolExecutionResult, message.toolExecutionComplete {
                        Text("Output:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green.opacity(0.5))
                        Text(formatJSON(result))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green.opacity(0.6))
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 15)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var toolIcon: some View {
        if isSlackTool {
            Image("SlackLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isLinearTool {
            Image("LinearLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isCalendarTool {
            Image("GoogleCalendarLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isNotionTool {
            Image("NotionLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isAppTool {
            Image("TossLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func formatJSON(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
            let str = String(data: data, encoding: .utf8)
        {
            return str
        }
        return String(describing: dict)
    }
}

// MARK: - Tool Approval Waiting Notification (subtle style)

private struct ToolApprovalWaitingNotification: View {
    let message: AgentViewModel.DisplayMessage
    @Binding var isExpanded: Bool

    private var toolName: String {
        message.toolExecutionName ?? "Unknown"
    }

    private var isSlackTool: Bool {
        toolName.lowercased().hasPrefix("slack")
    }

    private var isLinearTool: Bool {
        toolName.lowercased().hasPrefix("linear")
    }

    private var isCalendarTool: Bool {
        toolName.lowercased().hasPrefix("calendar")
    }

    private var isNotionTool: Bool {
        toolName.lowercased().hasPrefix("notion")
    }

    private var isFlowTool: Bool {
        toolName.lowercased() == "createflow"
    }

    // Internal app tools (meetings, contacts, memory, screenshot, flows)
    private var isAppTool: Bool {
        let name = toolName.lowercased()
        let appToolPrefixes = [
            "meeting", "contact", "company", "memory", "screenshot", "save", "list", "get",
            "search", "delete",
        ]
        if isSlackTool || isLinearTool || isCalendarTool || isNotionTool {
            return false
        }
        if isFlowTool {
            return true
        }
        return appToolPrefixes.contains { name.hasPrefix($0) || name.contains($0) }
    }

    private var waitingText: String {
        let name = toolName.lowercased()
        if isSlackTool && name.contains("send") {
            return "Waiting to send Slack message"
        }
        if isLinearTool && name.contains("create") {
            return "Waiting to create Linear issue"
        }
        if isCalendarTool && name.contains("create") {
            return "Waiting to create calendar event"
        }
        if isNotionTool {
            if name.contains("createdatabase") { return "Waiting to create Notion database" }
            if name.contains("create") { return "Waiting to create Notion page" }
            if name.contains("append") { return "Waiting to add to Notion page" }
        }
        if isFlowTool {
            return "Waiting to create flow"
        }
        return "Waiting for approval"
    }

    private var completedText: String {
        let name = toolName.lowercased()
        if isSlackTool && name.contains("send") {
            return "Sent Slack message"
        }
        if isLinearTool && name.contains("create") {
            return "Created Linear issue"
        }
        if isCalendarTool && name.contains("create") {
            return "Created calendar event"
        }
        if isNotionTool {
            if name.contains("createdatabase") { return "Created Notion database" }
            if name.contains("create") { return "Created Notion page" }
            if name.contains("append") { return "Added to Notion page" }
        }
        if isFlowTool {
            return "Created flow"
        }
        return "Completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Collapsed: subtle inline text with tool icon and chevron
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))

                    toolIcon
                        .frame(width: 14, height: 14)

                    Text(message.toolExecutionComplete ? completedText : waitingText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .italic()

                    if message.toolExecutionComplete {
                        // Green checkmark when complete
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.6))
                    } else {
                        // Orange dot to indicate waiting
                        Circle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded: show args and result
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let args = message.toolExecutionArgs, !args.isEmpty {
                        Text("Input:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                        Text(formatJSON(args))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .textSelection(.enabled)
                    }

                    if let result = message.toolExecutionResult, message.toolExecutionComplete {
                        Text("Output:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green.opacity(0.5))
                        Text(formatJSON(result))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green.opacity(0.6))
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 15)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var toolIcon: some View {
        if isSlackTool {
            Image("SlackLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isLinearTool {
            Image("LinearLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isCalendarTool {
            Image("GoogleCalendarLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isNotionTool {
            Image("NotionLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if isAppTool {
            Image("TossLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func formatJSON(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
            let str = String(data: data, encoding: .utf8)
        {
            return str
        }
        return String(describing: dict)
    }
}

private struct ToolApprovalCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExecuting = false

    private var isAwaitingApproval: Bool {
        if case .awaitingApproval = toolCall.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reject button row (only when awaiting approval)
            if isAwaitingApproval {
                HStack {
                    Spacer()
                    Button {
                        onReject()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Reject")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }

            // Use the unified editable preview components
            toolPreviewContent

            // Status feedback (executing, completed, failed)
            statusOverlay
        }
    }

    @ViewBuilder
    private var toolPreviewContent: some View {
        let params = ToolParams(toolCall.arguments)
        let executing =
            isExecuting
            || {
                if case .executing = toolCall.status { return true }
                return false
            }()

        switch toolCall.name {
        case "slackSendMessage":
            EditableSlackMessagePreview(
                params: params,
                compact: false,
                onParamsChanged: nil,  // No editing in agent panel
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "linearCreateIssue":
            EditableLinearIssuePreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "calendarCreateEvent":
            EditableCalendarEventPreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "connectSlack":
            ConnectIntegrationCard(
                provider: "Slack",
                icon: "SlackLogo",
                color: Color(hex: "4A154B"),
                isExecuting: executing,
                onConnect: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "connectLinear":
            ConnectIntegrationCard(
                provider: "Linear",
                icon: "LinearLogo",
                color: Color(hex: "5E6AD2"),
                isExecuting: executing,
                onConnect: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "connectGoogleCalendar":
            ConnectIntegrationCard(
                provider: "Google Calendar",
                icon: "GoogleCalendarLogo",
                color: Color(hex: "4285F4"),
                isExecuting: executing,
                onConnect: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "connectNotion":
            ConnectIntegrationCard(
                provider: "Notion",
                icon: "NotionLogo",
                color: Color.black,
                isExecuting: executing,
                onConnect: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "notionCreateDatabase":
            EditableNotionCreateDatabasePreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "notionCreatePage":
            EditableNotionCreatePagePreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "notionAppendBlocks":
            EditableNotionAppendBlocksPreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        case "createFlow":
            EditableFlowPreview(
                params: params,
                compact: false,
                onParamsChanged: nil,
                isExecuting: executing,
                onExecute: isAwaitingApproval
                    ? {
                        isExecuting = true
                        onApprove()
                    } : nil
            )

        default:
            // Fallback to generic preview with separate approve button
            VStack(alignment: .leading, spacing: 12) {
                ToolPreviewFactory.preview(
                    for: toolCall.name, params: toolCall.arguments, compact: false)

                if isAwaitingApproval {
                    Button {
                        isExecuting = true
                        onApprove()
                    } label: {
                        HStack(spacing: 6) {
                            if executing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Executing...")
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Approve")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(executing)
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.subtleStroke, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if case .completed(let result) = toolCall.status {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(result)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer()
            }
            .foregroundColor(.green)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.top, 10)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if case .failed(let error) = toolCall.status {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer()
            }
            .foregroundColor(.red)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.top, 10)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Connect Tool Card (for connect tools in chat - observes IntegrationsManager)

private struct ConnectToolCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void

    @ObservedObject private var integrationsManager = IntegrationsManager.shared
    @State private var isConnecting = false
    @State private var hasApproved = false

    private var provider: String {
        switch toolCall.name {
        case "connectSlack": return "Slack"
        case "connectLinear": return "Linear"
        case "connectGoogleCalendar": return "Google Calendar"
        case "connectNotion": return "Notion"
        default: return "Integration"
        }
    }

    private var icon: String {
        switch toolCall.name {
        case "connectSlack": return "SlackLogo"
        case "connectLinear": return "LinearLogo"
        case "connectGoogleCalendar": return "GoogleCalendarLogo"
        case "connectNotion": return "NotionLogo"
        default: return "gearshape"
        }
    }

    private var color: Color {
        switch toolCall.name {
        case "connectSlack": return Color(hex: "4A154B")
        case "connectLinear": return Color(hex: "5E6AD2")
        case "connectGoogleCalendar": return Color(hex: "4285F4")
        case "connectNotion": return Color.black
        default: return .blue
        }
    }

    private var isConnected: Bool {
        switch toolCall.name {
        case "connectSlack":
            return integrationsManager.slackStatus?.connected == true
        case "connectLinear":
            return integrationsManager.linearStatus?.connected == true
        case "connectGoogleCalendar":
            return integrationsManager.googleStatus?.connected == true
        case "connectNotion":
            return integrationsManager.notionStatus?.connected == true
        default:
            return false
        }
    }

    private var connectedInfo: String? {
        switch toolCall.name {
        case "connectSlack":
            return integrationsManager.slackStatus?.teamName
        case "connectLinear":
            return integrationsManager.linearStatus?.organizationName
        case "connectGoogleCalendar":
            return integrationsManager.googleStatus?.email
        case "connectNotion":
            return integrationsManager.notionStatus?.workspaceName
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    if isConnected {
                        Text("\(provider) Connected")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.green)

                        if let info = connectedInfo {
                            Text(info)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        Text("Connect \(provider)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Connect your \(provider) account to enable this feature")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .padding(16)

            // Connect button (only when not connected)
            if !isConnected {
                Divider()
                    .background(.white.opacity(0.1))

                HStack {
                    Spacer()

                    Button {
                        startConnection()
                    } label: {
                        HStack(spacing: 8) {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Opening browser...")
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Connect \(provider)")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)

                    Spacer()
                }
                .padding(16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isConnected ? Color.green.opacity(0.3) : color.opacity(0.3),
                            lineWidth: 1)
                )
        )
        .onChange(of: isConnected) { connected in
            // Auto-approve and restore when connection completes
            if connected && !hasApproved {
                hasApproved = true

                // Restore the agent panel first
                NotificationCenter.default.post(
                    name: NSNotification.Name("RestoreAgentPanel"),
                    object: nil
                )

                // Small delay to show the connected state before continuing
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onApprove()
                }
            }
        }
        .onAppear {
            // Fetch current status
            Task {
                switch toolCall.name {
                case "connectSlack":
                    await integrationsManager.fetchSlackStatus()
                case "connectLinear":
                    await integrationsManager.fetchLinearStatus()
                case "connectGoogleCalendar":
                    await integrationsManager.fetchGoogleStatus()
                case "connectNotion":
                    await integrationsManager.fetchNotionStatus()
                default:
                    break
                }
            }
        }
    }

    private func startConnection() {
        isConnecting = true

        // Minimize the agent panel so user can complete OAuth in browser
        NotificationCenter.default.post(
            name: NSNotification.Name("MinimizeAgentPanel"),
            object: nil
        )

        Task {
            switch toolCall.name {
            case "connectSlack":
                await integrationsManager.connectSlack()
            case "connectLinear":
                await integrationsManager.connectLinear()
            case "connectGoogleCalendar":
                await integrationsManager.connectGoogle()
            case "connectNotion":
                await integrationsManager.connectNotion()
            default:
                break
            }
            // Keep isConnecting true - the card will update when OAuth completes
        }
    }
}

// MARK: - Connect Integration Card (for tool previews)

private struct ConnectIntegrationCard: View {
    let provider: String
    let icon: String
    let color: Color
    var isExecuting: Bool = false
    var onConnect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(provider)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Connect your \(provider) account to enable this feature")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(16)

            Divider()
                .background(.white.opacity(0.1))

            // Connect button
            HStack {
                Spacer()

                if let onConnect = onConnect {
                    Button {
                        onConnect()
                    } label: {
                        HStack(spacing: 8) {
                            if isExecuting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Connecting...")
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Connect \(provider)")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                }

                Spacer()
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
