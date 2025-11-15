import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var inputText: String = ""
    @Namespace private var scrollNamespace

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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.messages)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.pendingToolCalls)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isProcessing)
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
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.role == .user ? Color.blue : Color.white.opacity(0.08))
                    )
                    .foregroundColor(.white)

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if message.role == .assistant { Spacer() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
