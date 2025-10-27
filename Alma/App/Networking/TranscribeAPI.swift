import Foundation

final class TranscribeAPI {
    static let shared = TranscribeAPI()

    private let session: URLSession
    private let baseURL: URL
    private let apiKey: String?

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "http://127.0.0.1:8787")!,
         apiKey: String? = ProcessInfo.processInfo.environment["ALMA_API_KEY"]) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func transcribe(fileURL: URL, token: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/transcribe")
        NSLog("[TranscribeAPI] POST %@", url.absoluteString)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
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

        let task = session.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse {
                NSLog("[TranscribeAPI] response status %d", http.statusCode)
            }
            if let error = error { completion(.failure(error)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "TranscribeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = json["text"] as? String {
                NSLog("[TranscribeAPI] received text length %d", text.count)
                completion(.success(text)); return
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty { completion(.success(text)); return }
            completion(.failure(NSError(domain: "TranscribeAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])));
        }
        task.resume()
    }
}


