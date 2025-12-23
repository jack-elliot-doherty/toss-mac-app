import Foundation

struct TranscriptionResponse: Decodable {
    let text: String
    let rawText: String?  // Raw Whisper output, optional for backwards compat
    let segments: [TranscriptionSegment]?
}

struct TranscriptionSegment: Decodable {
    let start: Double
    let end: Double
    let text: String
}

final class TranscribeAPI {
    static let shared = TranscribeAPI()

    private let baseURL: URL

    init(baseURL: URL = URL(string: Config.serverURL)!) {
        self.baseURL = baseURL
    }

    func transcribe(
        fileURL: URL,
        mode: DictationMode = .plain,
        completion: @escaping (Result<TranscriptionResponse, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/transcribe")
        NSLog("[TranscribeAPI] POST %@ (mode: %@)", url.absoluteString, mode.rawValue)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        
        // Add mode field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        append("\(mode.rawValue)\r\n")
        
        // Add file field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        do {
            let data = try Data(contentsOf: fileURL)
            NSLog("[TranscribeAPI] attaching file (%d bytes)", data.count)
            body.append(data)
        } catch {
            NSLog("[TranscribeAPI] failed to read file: %@", error.localizedDescription)
            completion(.failure(error))
            return
        }
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        APIClient.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[TranscribeAPI] network error: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "TranscribeAPI", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            if let http = response as? HTTPURLResponse {
                NSLog("[TranscribeAPI] response status %d", http.statusCode)

                if http.statusCode >= 400 {
                    // Try to parse error message from JSON
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let errorMsg = json["error"] as? String
                    {
                        completion(
                            .failure(
                                NSError(
                                    domain: "TranscribeAPI",
                                    code: http.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: errorMsg]
                                )))
                        return
                    }

                    completion(
                        .failure(
                            NSError(
                                domain: "TranscribeAPI",
                                code: http.statusCode,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"
                                ]
                            )))
                    return
                }
            }

            do {
                let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                NSLog("[TranscribeAPI] received text length %d", response.text.count)
                completion(.success(response))
                return
            } catch {
                NSLog("[TranscribeAPI] decode error: %@", error.localizedDescription)
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                completion(.success(TranscriptionResponse(text: text, rawText: nil, segments: [])))
                return
            }
            completion(
                .failure(
                    NSError(
                        domain: "TranscribeAPI", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])))
        }
    }

    func transcribeMeetingChunk(
        meetingId: UUID,
        chunkIndex: Int,
        speaker: MeetingSpeaker,
        fileURL: URL,
        completion: @escaping (Result<TranscriptionResponse, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/meetings/\(meetingId.uuidString)/chunks")
            .appending(queryItems: [
                URLQueryItem(name: "index", value: "\(chunkIndex)"),
                URLQueryItem(name: "speaker", value: speaker.rawValue),
            ])

        NSLog("[TranscribeAPI] POST %@ (chunk #%d)", url.absoluteString, chunkIndex)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")

        do {
            let data = try Data(contentsOf: fileURL)
            NSLog("[TranscribeAPI] attaching chunk file (%d bytes)", data.count)
            body.append(data)
        } catch {
            NSLog("[TranscribeAPI] failed to read chunk file: %@", error.localizedDescription)
            completion(.failure(error))
            return
        }
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        APIClient.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[TranscribeAPI] chunk upload error: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "TranscribeAPI", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }

            if let http = response as? HTTPURLResponse {
                NSLog("[TranscribeAPI] chunk response status %d", http.statusCode)

                if http.statusCode >= 400 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let errorMsg = json["error"] as? String
                    {
                        completion(
                            .failure(
                                NSError(
                                    domain: "TranscribeAPI", code: http.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                        return
                    }
                    completion(
                        .failure(
                            NSError(
                                domain: "TranscribeAPI", code: http.statusCode,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"
                                ])))
                    return
                }
            }

            do {
                // Try to decode the full verbose JSON response
                let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                NSLog("[TranscribeAPI] transcribed: %d chars", result.text.count)
                completion(.success(result))
            } catch {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let text = json["text"] as? String
                {
                    NSLog("[TranscribeAPI] chunk #%d transcribed: %d chars", chunkIndex, text.count)
                    completion(
                        .success(TranscriptionResponse(text: text, rawText: nil, segments: [])))
                    return
                }

                completion(
                    .failure(
                        NSError(
                            domain: "TranscribeAPI", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])))
            }
        }
    }
}
