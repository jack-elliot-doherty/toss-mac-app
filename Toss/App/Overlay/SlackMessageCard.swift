import SwiftUI

// MARK: - Slack Channel Info

struct SlackChannelInfo: Codable {
    let id: String
    let name: String
    let type: String  // "dm", "group_dm", or "channel"
    let isPrivate: Bool

    var isDirectMessage: Bool {
        type == "dm"
    }

    var isGroupDM: Bool {
        type == "group_dm"
    }
}

// MARK: - Slack API

final class SlackAPI {
    static let shared = SlackAPI()
    private let baseURL: URL

    init(baseURL: URL = URL(string: Config.serverURL)!) {
        self.baseURL = baseURL
    }

    func getChannelInfo(channelId: String) async throws -> SlackChannelInfo {
        let url = baseURL.appendingPathComponent("slack/channels/\(channelId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "SlackAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch channel info"])
        }

        return try JSONDecoder().decode(SlackChannelInfo.self, from: data)
    }
}

// MARK: - Slack Message Card

struct SlackMessageCard: View {
    let toolCall: ToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExecuting = false
    @State private var error: String?
    @State private var channelInfo: SlackChannelInfo?
    @State private var isLoadingChannel = true

    private var channelId: String {
        toolCall.arguments.getString("channelId") ?? toolCall.arguments.getString("channel") ?? ""
    }

    private var message: String {
        toolCall.arguments.getString("message") ?? ""
    }

    private var destinationLabel: String {
        if let info = channelInfo {
            return info.isDirectMessage ? "To" : "Channel"
        }
        return "To"
    }

    private var destinationDisplay: String {
        if let info = channelInfo {
            if info.isDirectMessage {
                return "@\(info.name)"
            } else if info.isGroupDM {
                return info.name
            } else {
                return "#\(info.name)"
            }
        }
        // Still loading - show channel ID as placeholder
        return channelId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image("SlackLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Slack Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Toss will send this message to Slack")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }

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
                // Channel/DM destination
                HStack(alignment: .top, spacing: 8) {
                    Text(destinationLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    HStack(spacing: 4) {
                        if isLoadingChannel {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else if let info = channelInfo {
                            Image(systemName: info.isDirectMessage ? "person.fill" : "number")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Text(destinationDisplay)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }
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
                                .fill(Color(hex: "4A154B"))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting || isLoadingChannel)
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
        .task {
            await fetchChannelInfo()
        }
    }

    private func fetchChannelInfo() async {
        guard !channelId.isEmpty else {
            isLoadingChannel = false
            return
        }

        do {
            channelInfo = try await SlackAPI.shared.getChannelInfo(channelId: channelId)
        } catch {
            NSLog("[SlackMessageCard] Failed to fetch channel info: \(error)")
            // Fall back to showing just the channel ID
        }
        isLoadingChannel = false
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Channel message example
        SlackMessageCard(
            toolCall: ToolCall(
                id: "1",
                name: "slackSendMessage",
                arguments: [
                    "channelId": AnyCodable("C12345678"),
                    "message": AnyCodable(
                        "Hey team, the deployment is ready for review. Please check staging and let me know if everything looks good."
                    ),
                ],
                status: .awaitingApproval
            ),
            onApprove: { print("Approved") },
            onReject: { print("Rejected") }
        )

        SlackMessageCard(
            toolCall: ToolCall(
                id: "2",
                name: "slackSendMessage",
                arguments: [
                    "channelId": AnyCodable("D98765432"),
                    "message": AnyCodable("Quick update!"),
                ],
                status: .awaitingApproval
            ),
            onApprove: {},
            onReject: {}
        )

        SlackMessageCard(
            toolCall: ToolCall(
                id: "3",
                name: "slackSendMessage",
                arguments: [
                    "channelId": AnyCodable("C12345678"),
                    "message": AnyCodable("Sending..."),
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
