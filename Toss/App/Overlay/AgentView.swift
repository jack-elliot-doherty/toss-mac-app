import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var inputText: String = ""
    @Namespace private var scrollNamespace

    @State private var isHovering = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                            .transition(
                                .move(edge: .bottom)
                                    .combined(with: .opacity)
                            )
                    }

                    ForEach(viewModel.pendingToolCalls) { call in
                        ToolApprovalCard(
                            toolCall: call,
                            onApprove: { Task { await viewModel.approveToolCall(call) } },
                            onReject: { viewModel.rejectToolCall(call) }
                        )
                        .id(call.id)
                        .transition(.opacity.combined(with: .scale))
                    }

                    // Executing tool badges (read-only tools only)
                    if !viewModel.executingTools.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(viewModel.executingTools) { tool in
                                ExecutingToolBadge(tool: tool)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Only show thinking BEFORE streaming starts
                    if viewModel.isProcessing && !viewModel.isStreaming {
                        ProcessingRow()
                            .transition(.opacity)
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBubble(text: error)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.pendingToolCalls.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isProcessing) { _ in
                scrollToBottom(proxy)
            }
            .onAppear { scrollToBottom(proxy) }
        }
        .padding(16)
        .frame(width: 650)
        .appGlass(.surface, radius: 18, opacity: 0.001)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.messages)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.85), value: viewModel.pendingToolCalls
        )
        .animation(.easeInOut(duration: 0.15), value: viewModel.isProcessing)
        .overlay(alignment: .topTrailing) {
            closeButton
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
                .padding(10)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var closeButton: some View {
        Button {
            // Post notification for controller to handle "Hide"
            NotificationCenter.default.post(
                name: NSNotification.Name("HideAgentPanel"), object: nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial)  // subtle frosted backing
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2)
        }
        .buttonStyle(.plain)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastTool = viewModel.pendingToolCalls.last {
            proxy.scrollTo(lastTool.id, anchor: .bottom)
        } else if let lastMsg = viewModel.messages.last {
            proxy.scrollTo(lastMsg.id, anchor: .bottom)
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer() }

            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: 4
            ) {
                // Use markdown for assistant, plain for user
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

            if message.role == .assistant { Spacer() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

private struct ToolApprovalCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExecuting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tool-specific preview using shared components
            ToolPreviewFactory.preview(
                for: toolCall.name, params: toolCall.arguments, compact: false)

            // Action buttons
            if case .awaitingApproval = toolCall.status {
                HStack(spacing: 10) {
                    Button {
                        onReject()
                    } label: {
                        Text("Reject")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isExecuting = true
                        onApprove()
                    } label: {
                        HStack(spacing: 6) {
                            if isExecuting {
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
                    .disabled(isExecuting)
                }
            } else if case .executing = toolCall.status {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Executing...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if case .completed(let result) = toolCall.status {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct ExecutingToolBadge: View {
    let tool: AgentViewModel.ExecutingTool

    var body: some View {
        HStack(spacing: 8) {
            toolIcon
                .frame(width: 20, height: 20)

            Text(actionText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            if tool.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            } else {
                LoadingDots()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private var toolIcon: some View {
        let name = tool.name.lowercased()
        if name.contains("slack") {
            Image(systemName: "number.square.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
        } else if name.contains("linear") {
            Image(systemName: "lineweight")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.37, green: 0.42, blue: 0.82))
        } else if name.contains("calendar") || name.contains("google") {
            Image(systemName: "calendar")
                .font(.system(size: 14))
                .foregroundColor(.blue)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var actionText: String {
        let name = tool.name.lowercased()
        if name.contains("slack") {
            if name.contains("send") { return "Sending to Slack" }
            if name.contains("search") { return "Searching Slack" }
            return "Reading Slack"
        }
        if name.contains("linear") {
            if name.contains("create") { return "Creating Linear issue" }
            if name.contains("search") { return "Searching Linear" }
            return "Reading Linear"
        }
        if name.contains("calendar") || name.contains("event") {
            return "Reading Calendar"
        }
        return tool.name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct LoadingDots: View {
    @State private var dotCount = 0

    var body: some View {
        Text(String(repeating: "•", count: dotCount + 1))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white.opacity(0.6))
            .frame(width: 24, alignment: .leading)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    dotCount = (dotCount + 1) % 3
                }
            }
    }
}
