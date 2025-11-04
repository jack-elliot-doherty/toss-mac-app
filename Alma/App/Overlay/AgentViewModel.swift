import Foundation
import SwiftUI

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    struct DisplayMessage: Identifiable, Equatable {
        let id: UUID
        let role: MessageRole
        let content: String
        let timestamp: Date
    }

    private let api = AgentAPI.shared
    private let auth: AuthManager
    private var threadId: UUID?

    init(auth: AuthManager) {
        self.auth = auth
    }

    func startConversation(with initialMessage: String) {
        threadId = UUID()

        // Add user message
        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: initialMessage,
            timestamp: Date()
        )
        messages.append(userMsg)

        // Send to agent
        sendToAgent(initialMessage)
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        let userMsg = DisplayMessage(
            id: UUID(),
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMsg)

        sendToAgent(text)
    }

    private func sendToAgent(_ message: String) {
        isProcessing = true
        errorMessage = nil

        // Build history for context
        let history = messages.dropLast().map { msg in
            AgentRequest.ChatMessage(
                role: msg.role.rawValue,
                content: msg.content
            )
        }

        let token = auth.accessToken

        api.sendMessage(
            message, threadId: threadId?.uuidString, history: Array(history), token: token
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isProcessing = false

                switch result {
                case .success(let response):
                    let assistantMsg = DisplayMessage(
                        id: UUID(),
                        role: .assistant,
                        content: response.response,
                        timestamp: Date()
                    )
                    self.messages.append(assistantMsg)

                    // Handle actions if any
                    if !response.actions.isEmpty {
                        NSLog(
                            "[AgentViewModel] Actions to perform: %@",
                            response.actions.joined(separator: ", "))
                        // TODO: Execute actions
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    NSLog("[AgentViewModel] Error: %@", error.localizedDescription)
                }
            }
        }
    }

    func clearConversation() {
        messages.removeAll()
        threadId = nil
        isProcessing = false
        errorMessage = nil
    }
}
