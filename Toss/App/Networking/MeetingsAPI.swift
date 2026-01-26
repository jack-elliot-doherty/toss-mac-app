import Foundation

// MARK: - Action Items Models

enum ActionExecutionMode: String, Codable, Equatable {
    case direct  // One-click tool call
    case agent  // Delegate to TOS agent
}

struct ExtractedAction: Codable, Identifiable, Equatable {
    let id: String
    let mode: ActionExecutionMode
    let title: String
    let context: String
    let toolName: String?
    let toolParams: [String: AnyCodableValue]?
    let taskSpec: String?
}

// Stored action item (for local persistence, with execution tracking)
struct StoredActionItem: Codable, Identifiable, Equatable {
    let id: String
    let mode: ActionExecutionMode
    let title: String
    let context: String
    let toolName: String?
    let toolParams: [String: AnyCodableValue]?
    let taskSpec: String?
    var executedAt: Date?
    var executionSuccess: Bool?
    var executionMessage: String?

    // Convert from ExtractedAction
    init(from action: ExtractedAction) {
        self.id = action.id
        self.mode = action.mode
        self.title = action.title
        self.context = action.context
        self.toolName = action.toolName
        self.toolParams = action.toolParams
        self.taskSpec = action.taskSpec
    }

    // Convert to ExtractedAction (for UI compatibility)
    func toExtractedAction() -> ExtractedAction {
        ExtractedAction(
            id: id,
            mode: mode,
            title: title,
            context: context,
            toolName: toolName,
            toolParams: toolParams,
            taskSpec: taskSpec
        )
    }
}

// Helper for decoding arbitrary JSON values
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictionary)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Convert to Any for use with JSONSerialization
    var anyValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map { $0.anyValue }
        case .dictionary(let v): return v.mapValues { $0.anyValue }
        case .null: return NSNull()
        }
    }

    // Convenience accessor for string values
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

struct ToolApprovalResult: Codable {
    let success: Bool
    let toolCallId: String?
    let approved: Bool?
    let result: ToolExecutionResult?
    let error: String?
}

struct ToolExecutionResult: Codable {
    let success: Bool?
    let error: String?

    // Linear-specific fields
    let issueId: String?
    let identifier: String?
    let url: String?

    // Calendar-specific fields
    let eventId: String?
    let htmlLink: String?

    // Slack-specific fields
    let messageTs: String?
    let channel: String?
}

final class MeetingsApi {
    static let shared = MeetingsApi()

    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    // MARK: - Fetch recorded meetings from server

    struct ServerMeetingChunk: Codable {
        let id: String
        let meetingId: String
        let chunkIndex: Int
        let transcript: String
        let startedAt: String
        let speaker: String
    }

    struct ServerMeeting: Codable {
        let id: String
        let title: String
        let transcript: String?
        let summary: String?
        let userNotes: String?
        let startedAt: String
        let endedAt: String?
        let source: String?
        let status: String?
        let actionItems: [StoredActionItem]?
        let chunks: [ServerMeetingChunk]?
    }

    struct SharedMeetingParticipant: Codable {
        let name: String?
        let email: String?
        let avatarUrl: String?
        let companyName: String?
        let companyLogo: String?
        let responseStatus: String?
    }

    struct SharedMeetingDetail: Codable {
        let id: String
        let title: String?
        let transcript: String?
        let summary: String?
        let userNotes: String?
        let startedAt: String?
        let endedAt: String?
        let createdAt: String?
        let updatedAt: String?
        let participants: [SharedMeetingParticipant]?
        let sharedByName: String?
        let sharedByEmail: String?
    }

    func fetchRecordedMeetings(limit: Int = 50, offset: Int = 0, since: Date? = nil) async throws -> [ServerMeeting] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/meetings/recorded"),
            resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]

        // Add `since` parameter for incremental sync
        if let since = since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch recorded meetings"]
            )
        }

        struct Response: Codable {
            let meetings: [ServerMeeting]
        }

        let decoder = JSONDecoder()

        // Debug: log raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            NSLog("[MeetingsApi] Raw JSON response (first 2000 chars): \(String(jsonString.prefix(2000)))")
        }

        let result = try decoder.decode(Response.self, from: data)

        // Debug: log chunk counts for each meeting
        for meeting in result.meetings {
            let chunkCount = meeting.chunks?.count ?? 0
            NSLog("[MeetingsApi] Meeting '\(meeting.title)' (id: \(meeting.id)) has \(chunkCount) chunks")
            if let chunks = meeting.chunks, !chunks.isEmpty {
                let firstChunk = chunks[0]
                NSLog("[MeetingsApi]   First chunk: id=\(firstChunk.id), speaker=\(firstChunk.speaker), transcript=\(String(firstChunk.transcript.prefix(100)))...")
            }
        }

        NSLog("[MeetingsApi] Fetched \(result.meetings.count) recorded meetings from server (since: \(since?.description ?? "all"))")
        return result.meetings
    }

    func fetchMeeting(meetingId: String) async throws -> SharedMeetingDetail {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch meeting"]
            )
        }

        struct Response: Codable {
            let ok: Bool
            let meeting: SharedMeetingDetail
        }

        return try JSONDecoder().decode(Response.self, from: data).meeting
    }

    func fetchMeetingFolders(meetingId: UUID) async throws -> [FolderSummary] {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/folders")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch meeting folders"]
            )
        }

        struct Response: Codable { let folders: [FolderSummary] }
        return try JSONDecoder().decode(Response.self, from: data).folders
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
        userNotes: String = "",  // Add this parameter
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

        // Include userNotes in the body
        var body: [String: String] = ["transcript": trimmed]
        if !userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["userNotes"] = userNotes
        }

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

    // MARK: - Action Items Extraction

    func extractActions(
        for meetingId: UUID,
        transcript: String
    ) async throws -> [ExtractedAction] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let url = baseURL.appendingPathComponent(
            "/meetings/\(meetingId.uuidString)/actions/extract")
        NSLog("[MeetingsApi] POST %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["transcript": trimmed]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract actions"]
            )
        }

        struct Response: Codable {
            let actions: [ExtractedAction]
        }

        let result = try JSONDecoder().decode(Response.self, from: data)
        NSLog("[MeetingsApi] extracted %d actions", result.actions.count)
        return result.actions
    }

    // MARK: - Execute Direct Action (via approve-tool endpoint)

    func executeAction(action: ExtractedAction) async throws -> ToolApprovalResult {
        guard action.mode == .direct,
            let toolName = action.toolName,
            let toolParams = action.toolParams
        else {
            throw NSError(
                domain: "MeetingsApi",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Invalid action for direct execution"]
            )
        }

        let url = Config.serverBaseURL.appendingPathComponent("/agent/approve-tool")
        NSLog("[MeetingsApi] POST %@ (tool: %@)", url.absoluteString, toolName)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the approve-tool payload
        let payload: [String: Any] = [
            "toolCallId": UUID().uuidString,
            "toolName": toolName,
            "arguments": toolParams.mapValues { $0.anyValue },
            "approved": true,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to execute action"]
            )
        }

        let result = try JSONDecoder().decode(ToolApprovalResult.self, from: data)
        NSLog("[MeetingsApi] action executed: success=%@", String(describing: result.success))
        return result
    }

    // MARK: - Meeting Sync to Server

    /// Sync a local meeting to the server (creates or updates)
    func syncMeeting(
        meeting: MeetingModel,
        chunks: [MeetingChunkModel],
        actionItems: [ExtractedAction]? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("/meetings")
        NSLog("[MeetingsApi] POST %@ (sync meeting %@)", url.absoluteString, meeting.id.uuidString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the request body
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var body: [String: Any] = [
            "id": meeting.id.uuidString,
            "title": meeting.title,
            "startedAt": formatter.string(from: meeting.startTime),
            "source": serverSource(for: meeting.source),
        ]

        if let endTime = meeting.endTime {
            body["endedAt"] = formatter.string(from: endTime)
        }

        if !meeting.notes.isEmpty {
            body["summary"] = meeting.notes
        }

        if !meeting.userNotes.isEmpty {
            body["userNotes"] = meeting.userNotes
        }
        
        // Note: userNoteImages are NOT synced here - they're managed via dedicated
        // upload/delete endpoints (/meetings/:id/images) to handle presigned URLs correctly

        // Build transcript from chunks
        let transcript =
            chunks
            .sorted { $0.startedAt < $1.startedAt }
            .map { $0.transcript }
            .joined(separator: " ")
        if !transcript.isEmpty {
            body["transcript"] = transcript
        }

        // Add action items if provided
        if let actions = actionItems {
            body["actionItems"] = actions.map { action -> [String: Any] in
                var dict: [String: Any] = [
                    "id": action.id,
                    "mode": action.mode.rawValue,
                    "title": action.title,
                    "context": action.context,
                ]
                if let toolName = action.toolName {
                    dict["toolName"] = toolName
                }
                if let toolParams = action.toolParams {
                    dict["toolParams"] = toolParams.mapValues { $0.anyValue }
                }
                if let taskSpec = action.taskSpec {
                    dict["taskSpec"] = taskSpec
                }
                return dict
            }
        }

        // Add chunks
        body["chunks"] = chunks.map { chunk -> [String: Any] in
            [
                "id": chunk.id.uuidString,
                "chunkIndex": chunk.chunkIndex,
                "transcript": chunk.transcript,
                "startedAt": formatter.string(from: chunk.startedAt),
                "speaker": chunk.speaker.rawValue,
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[MeetingsApi] sync error response: %@", body)
            }
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sync meeting"]
            )
        }

        NSLog("[MeetingsApi] Meeting %@ synced successfully", meeting.id.uuidString)
    }

    private func serverSource(for source: MeetingSource) -> String {
        switch source {
        case .calendar:
            return "google_calendar"
        case .adhoc:
            return "adhoc"
        }
    }

    /// Update action items for a meeting
    func updateMeetingActionItems(
        meetingId: UUID,
        actionItems: [ExtractedAction]
    ) async throws {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)")
        NSLog("[MeetingsApi] PUT %@ (update action items)", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "actionItems": actionItems.map { action -> [String: Any] in
                var dict: [String: Any] = [
                    "id": action.id,
                    "mode": action.mode.rawValue,
                    "title": action.title,
                    "context": action.context,
                ]
                if let toolName = action.toolName {
                    dict["toolName"] = toolName
                }
                if let toolParams = action.toolParams {
                    dict["toolParams"] = toolParams.mapValues { $0.anyValue }
                }
                if let taskSpec = action.taskSpec {
                    dict["taskSpec"] = taskSpec
                }
                return dict
            }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to update action items"]
            )
        }

        NSLog("[MeetingsApi] Action items updated for meeting %@", meetingId.uuidString)
    }

    /// Generate share link for a meeting
    func generateShareLink(meetingId: UUID) async throws -> String {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/share")
        NSLog("[MeetingsApi] POST %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate share link"]
            )
        }

        struct Response: Codable {
            let shareUrl: String
        }

        let result = try JSONDecoder().decode(Response.self, from: data)
        return result.shareUrl
    }

    /// Delete a meeting from the server
    func deleteMeetingFromServer(meetingId: UUID) async throws {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)")
        NSLog("[MeetingsApi] DELETE %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MeetingsApi",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
        }

        // 200 = deleted, 404 = already gone (acceptable), anything else = error
        guard http.statusCode == 200 || http.statusCode == 404 else {
            throw NSError(
                domain: "MeetingsApi",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to delete meeting: \(http.statusCode)"
                ]
            )
        }

        NSLog("[MeetingsApi] Meeting %@ deleted from server", meetingId.uuidString)
    }

    // MARK: - Note Images

    /// Upload an image to attach to meeting notes
    /// Returns the NoteImage with URL from server
    func uploadNoteImage(meetingId: UUID, imageData: Data) async throws -> NoteImage {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/images")
        NSLog("[MeetingsApi] POST %@ (upload note image)", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Data = imageData.base64EncodedString()
        let body: [String: Any] = [
            "imageData": base64Data,
            "contentType": "image/png",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[MeetingsApi] upload image error response: %@", body)
            }
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to upload image"]
            )
        }

        struct UploadResponse: Codable {
            let success: Bool
            let image: ImageData

            struct ImageData: Codable {
                let id: String
                let url: String
                let uploadedAt: String
            }
        }

        let result = try JSONDecoder().decode(UploadResponse.self, from: data)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let uploadedAt = formatter.date(from: result.image.uploadedAt) ?? Date()

        NSLog("[MeetingsApi] Image uploaded: %@ url: %@", result.image.id, result.image.url)

        return NoteImage(id: result.image.id, url: result.image.url, uploadedAt: uploadedAt)
    }

    /// Delete an image from meeting notes
    func deleteNoteImage(meetingId: UUID, imageId: String) async throws {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/images/\(imageId)")
        NSLog("[MeetingsApi] DELETE %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await APIClient.shared.perform(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[MeetingsApi] delete image error response: %@", body)
            }
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete image"]
            )
        }

        NSLog("[MeetingsApi] Image %@ deleted from meeting %@", imageId, meetingId.uuidString)
    }
    
    /// Fetch fresh presigned URLs for meeting images
    /// Call this when displaying meeting images or when URLs have expired
    func fetchNoteImageUrls(meetingId: UUID) async throws -> [NoteImage] {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/images")
        NSLog("[MeetingsApi] GET %@ (fetch image URLs)", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await APIClient.shared.perform(request)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[MeetingsApi] fetch images error response: %@", body)
            }
            throw NSError(
                domain: "MeetingsApi",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch image URLs"]
            )
        }
        
        struct ImageInfo: Decodable {
            let id: String
            let url: String
            let uploadedAt: String
        }
        
        struct Response: Decodable {
            let success: Bool
            let images: [ImageInfo]
        }
        
        let result = try JSONDecoder().decode(Response.self, from: data)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let noteImages = result.images.map { img -> NoteImage in
            let uploadedAt = formatter.date(from: img.uploadedAt) ?? Date()
            return NoteImage(id: img.id, url: img.url, uploadedAt: uploadedAt)
        }
        
        NSLog("[MeetingsApi] Fetched %d image URLs for meeting %@", noteImages.count, meetingId.uuidString)
        return noteImages
    }
}
