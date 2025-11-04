import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Agent")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.05))

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
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
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input (optional - for follow-up messages)
            HStack(spacing: 8) {
                TextField("Send a message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(viewModel.isProcessing)

                Button {
                    if !inputText.isEmpty {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(inputText.isEmpty ? .orange : .blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || viewModel.isProcessing)
            }
            .padding(12)
            .background(Color.black.opacity(0.02))
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
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
                            .fill(message.role == .user ? Color.blue : Color.black.opacity(0.08))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)

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
