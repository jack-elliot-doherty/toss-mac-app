import Foundation

final class MeetingsApi {
    static let shared = MeetingsApi()

    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: Config.serverURL)!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - Title generation

    func generateTitle(
        for meetingId: UUID,
        transcript: String,
        token: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success("Untitled meeting"))
            return
        }

        // Server route to implement: POST /meetings/:id/title  { transcript: string }
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/title/generate")
        NSLog("[MeetingsApi] POST %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["transcript": trimmed]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[MeetingsApi] title error: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "MeetingsApi",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No data from server"]
                        )
                    )
                )
                return
            }

            if let http = response as? HTTPURLResponse {
                if http.statusCode >= 400 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let errorMsg = json["error"] as? String
                    {
                        completion(
                            .failure(
                                NSError(
                                    domain: "MeetingsApi",
                                    code: http.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: errorMsg]
                                )
                            )
                        )
                        return
                    }
                    completion(
                        .failure(
                            NSError(
                                domain: "MeetingsApi",
                                code: http.statusCode,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"
                                ]
                            )
                        )
                    )
                    return
                }
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let title = json["title"] as? String
            {
                NSLog("[MeetingsApi] generated title: %@", title)
                completion(.success(title))
                return
            }

            completion(
                .failure(
                    NSError(
                        domain: "MeetingsApi",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected response"]
                    )
                )
            )
        }
        task.resume()
    }

    // MARK: - Overview generation (placeholder for next step)

    func generateOverview(
        for meetingId: UUID,
        transcript: String,
        token: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success("No AI summary yet. Generate notes after the meeting ends."))
            return
        }

        let url = baseURL.appendingPathComponent(
            "/meetings/\(meetingId.uuidString)/overview/generate")
        NSLog("[MeetingsApi] POST %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["transcript": trimmed]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[MeetingsApi] overview error: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "MeetingsApi",
                            code: 10,
                            userInfo: [NSLocalizedDescriptionKey: "No data from server"]
                        )
                    )
                )
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let errorMsg = json["error"] as? String
                {
                    completion(
                        .failure(
                            NSError(
                                domain: "MeetingsApi",
                                code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: errorMsg]
                            )
                        )
                    )
                    return
                }
                completion(
                    .failure(
                        NSError(
                            domain: "MeetingsApi",
                            code: http.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"
                            ]
                        )
                    )
                )
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let overview = json["overview"] as? String
            {
                NSLog("[MeetingsApi] generated overview length: %d", overview.count)
                completion(.success(overview))
                return
            }

            completion(
                .failure(
                    NSError(
                        domain: "MeetingsApi",
                        code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected response"]
                    )
                )
            )
        }
        task.resume()
    }
}
