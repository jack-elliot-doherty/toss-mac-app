import Foundation

final class MeetingsApi {
    static let shared = MeetingsApi()

    private let baseURL: URL

    init(baseURL: URL = URL(string: Config.serverURL)!) {
        self.baseURL = baseURL
    }

    // MARK: - Fetch upcoming meetings

    func fetchUpcoming() async throws -> [UpcomingMeeting] {
        let url = baseURL.appendingPathComponent("/meetings/upcoming")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch upcoming meetings"]
            )
        }

        struct Response: Codable {
            let meetings: [UpcomingMeeting]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Response.self, from: data)
        return result.meetings
    }

    // MARK: - Sync calendar

    func syncCalendar() async throws {
        let url = baseURL.appendingPathComponent("/meetings/sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sync calendar"]
            )
        }
    }

    // MARK: - Title generation

    func generateTitle(
        for meetingId: UUID,
        transcript: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success("Untitled meeting"))
            return
        }

        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/title/generate")
        NSLog("[MeetingsApi] POST %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["transcript": trimmed]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        APIClient.shared.dataTask(with: request) { data, response, error in
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
    }

    // MARK: - Overview generation

    func generateOverview(
        for meetingId: UUID,
        transcript: String,
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["transcript": trimmed]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        APIClient.shared.dataTask(with: request) { data, response, error in
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
    }
}
