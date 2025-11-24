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

                    if viewModel.isProcessing {
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
                Text(message.content)
                    .font(.system(size: 14))  // Slightly larger for readability
                    .padding(.horizontal, message.role == .user ? 14 : 0)
                    .padding(.vertical, message.role == .user ? 10 : 0)
                    .background(bubbleBackground)  // Conditional background
                    .foregroundColor(.white)
                    // Add corner radius if it has a background
                    .cornerRadius(message.role == .user ? 18 : 0)
            }

            if message.role == .assistant { Spacer() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            // User: Dark black/gray bubble
            Color.black.opacity(0.6)
        } else {
            // Assistant: Transparent / No background
            Color.clear
        }
    }
}

private struct ToolApprovalCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.white)
                Text(toolCall.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            Divider().background(.white.opacity(0.1))

            ForEach(Array(toolCall.arguments.keys.sorted()), id: \.self) { key in
                if let value = toolCall.arguments[key] {
                    HStack(alignment: .top) {
                        Text(key)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(String(describing: value.value))
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }
                }
            }

            if case .awaitingApproval = toolCall.status {
                HStack(spacing: 8) {
                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    Spacer()
                    Button("Approve", action: onApprove)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}
