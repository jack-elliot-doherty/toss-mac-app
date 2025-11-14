import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { MessageBubble(message: $0).id($0.id) }

                    // Tool approval cards
                    ForEach(viewModel.pendingToolCalls) { toolCall in
                        ToolApprovalCard(
                            toolCall: toolCall,
                            onApprove: {
                                Task {
                                    await viewModel.approveToolCall(toolCall)
                                }
                            },
                            onReject: {
                                viewModel.rejectToolCall(toolCall)
                            }
                        )
                        .id(toolCall.id)
                    }

                    if viewModel.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 12)
                    }

                    if let error = viewModel.errorMessage {
                        Text("Error: \(error)")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 450)
            .layoutPriority(1)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.pendingToolCalls.count) { _ in
                scrollToBottom(proxy)
            }

        }
        .frame(width: 400)
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.3))
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastToolCall = viewModel.pendingToolCalls.last {
            withAnimation {
                proxy.scrollTo(lastToolCall.id, anchor: .bottom)
            }
        } else if let lastMessage = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: AgentViewModel.DisplayMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.role == .user ? Color.blue : Color.white.opacity(0.08))
                    )
                    .foregroundColor(message.role == .user ? .white : .white)

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

private struct ToolApprovalCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        switch toolCall.name {
        case "send_slack_message":
            SlackMessageCard(
                toolCall: toolCall,
                onApprove: onApprove,
                onReject: onReject
            )
        case "create_linear_issue":
            // TODO: Create LinearIssueCard component
            GenericToolCard(
                toolCall: toolCall,
                onApprove: onApprove,
                onReject: onReject
            )
        default:
            GenericToolCard(
                toolCall: toolCall,
                onApprove: onApprove,
                onReject: onReject
            )
        }
    }
}

// Generic fallback for tools without custom UI
private struct GenericToolCard: View {
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

            Divider()
                .background(.white.opacity(0.1))

            // Show arguments
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

            // Action buttons
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
