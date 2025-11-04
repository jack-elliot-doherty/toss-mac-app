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
        baseURL: URL = URL(string: "http://127.0.0.1:8787")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func sendMessage(
        _ message: String,
        threadId: String? = nil,
        history: [AgentRequest.ChatMessage]? = nil,
        token: String?,
        completion: @escaping (Result<AgentResponse, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/agent/message")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

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
