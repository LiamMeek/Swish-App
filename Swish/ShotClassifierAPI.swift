import Foundation
import Combine

struct ShotPredictionResponse: Decodable {
    let isMake: Bool
    let confidence: Double
}

final class ShotClassifierAPI {
    private let baseURL: URL

    init(baseURLString: String) {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid API base URL")
        }
        self.baseURL = url
    }

    func predict(videoData: Data, fileName: String = "shot.mp4") async throws -> ShotPredictionResponse {
        let url = baseURL.appendingPathComponent("predict")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let disposition = "form-data; name=\"file\"; filename=\"\(fileName)\""
        let contentType = "video/mp4"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: \(disposition)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ShotClassifierAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(ShotPredictionResponse.self, from: data)
    }
}

