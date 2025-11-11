import SwiftUI

struct SlackMessageCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @State private var isExecuting = false
    @State private var error: String?
    
    private var channel: String {
        toolCall.arguments.getString("channel") ?? "#unknown"
    }
    
    private var message: String {
        toolCall.arguments.getString("message") ?? ""
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.purple)
                    )
                
                Text("Send Slack Message")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if case .executing = toolCall.status {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }
            
            Divider()
                .background(.white.opacity(0.15))
            
            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Channel
                HStack(alignment: .top, spacing: 8) {
                    Text("Channel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    
                    Text(channel)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.08))
                        )
                }
                
                // Message
                HStack(alignment: .top, spacing: 8) {
                    Text("Message")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.08))
                        )
                }
            }
            .padding(.vertical, 4)
            
            // Error display
            if let error = error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red.opacity(0.1))
                )
            }
            
            // Completion state
            if case .completed(let result) = toolCall.status {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.green.opacity(0.1))
                )
            }
            
            // Action buttons
            if case .awaitingApproval = toolCall.status {
                HStack(spacing: 8) {
                    Button {
                        onReject()
                    } label: {
                        Text("Reject")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.08))
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
                                Text("Sending...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11))
                                Text("Send Message")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
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
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SlackMessageCard(
            toolCall: ToolCall(
                id: "1",
                name: "send_slack_message",
                arguments: [
                    "channel": AnyCodable("#engineering"),
                    "message": AnyCodable("Hey team, the deployment is ready for review. Please check staging and let me know if everything looks good.")
                ],
                status: .awaitingApproval
            ),
            onApprove: { print("Approved") },
            onReject: { print("Rejected") }
        )
        
        SlackMessageCard(
            toolCall: ToolCall(
                id: "2",
                name: "send_slack_message",
                arguments: [
                    "channel": AnyCodable("#general"),
                    "message": AnyCodable("Quick update!")
                ],
                status: .executing
            ),
            onApprove: {},
            onReject: {}
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.black)
}

