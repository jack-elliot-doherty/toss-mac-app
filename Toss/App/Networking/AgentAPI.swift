import Foundation

struct AgentRequest: Codable {
    let message: String
    let threadId: String?
    let history: [ChatMessage]?

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }
}

struct AgentResponse: Codable {
    let response: String
    let actions: [String]
}

final class AgentAPI {
    static let shared = AgentAPI()

    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = Config.serverBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Stream messages from the agent using SSE (AI SDK v6 protocol)
    func streamMessage(
        _ message: String,
        threadId: String? = nil,
        history: [AgentRequest.ChatMessage]? = nil,
        token: String?
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let url = baseURL.appendingPathComponent("/agent/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request = request.configured(token: token)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")  // Important for SSE

        // Construct prompt with system context if needed
        // Or just rely on the server's system prompt
        var messages: [AgentRequest.ChatMessage] = []
        if let history = history {
            messages.append(contentsOf: history)
        }
        messages.append(AgentRequest.ChatMessage(role: "user", content: message))

        let payload = ["messages": messages]

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        NSLog("[AgentAPI] Streaming message: \"%@\"", message)

        // Use the existing parser's helper
        // Note: You might need to instantiate parser here or use a static helper
        let parser = AgentStreamParser()
        return parser.streamEvents(from: request)
    }

    func sendMessage(
        _ message: String,
        threadId: String? = nil,
        history: [AgentRequest.ChatMessage]? = nil,
        token: String?,
        completion: @escaping (Result<AgentResponse, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/agent/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Apply standard headers
        request = request.configured(token: token)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AgentRequest(message: message, threadId: threadId, history: history)

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        NSLog("[AgentAPI] Sending message: \"%@\"", message)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[AgentAPI] Request error: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "AgentAPI", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                NSLog("[AgentAPI] Response status: %d", httpResponse.statusCode)

                // Handle 426 Upgrade Required
                if httpResponse.statusCode == 426 {
                    NSLog("[AgentAPI] Server requires app update (426)")
                    DispatchQueue.main.async {
                        UpdateManager.shared.handleForceUpdateRequired()
                    }
                    completion(
                        .failure(
                            NSError(
                                domain: "AgentAPI", code: 426,
                                userInfo: [NSLocalizedDescriptionKey: "Update required"])))
                    return
                }

                if httpResponse.statusCode != 200 {
                    completion(
                        .failure(
                            NSError(
                                domain: "AgentAPI", code: httpResponse.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "Server error"])))
                    return
                }
            }

            do {
                let decoded = try JSONDecoder().decode(AgentResponse.self, from: data)
                NSLog("[AgentAPI] Received response: \"%@\"", decoded.response)
                completion(.success(decoded))
            } catch {
                NSLog("[AgentAPI] Decode error: %@", error.localizedDescription)
                completion(.failure(error))
            }
        }

        task.resume()
    }
}
