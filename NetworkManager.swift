import Foundation

// --------------------------------------------------
// API Response Model
// --------------------------------------------------

struct APIResponse: Codable {
    let isMake: Bool
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case isMake = "is_make"
        case confidence
    }
}

// --------------------------------------------------
// Network Manager
// --------------------------------------------------

final class NetworkManager {

    static let shared = NetworkManager()

    // CHANGE THIS when ngrok / deploy URL changes
    private let apiURL = URL(string: "https://YOUR_NGROK_URL.ngrok.io/predict")!

    private init() {}

    // --------------------------------------------------
    // Upload video for shot prediction
    // --------------------------------------------------

    func uploadVideo(
        _ videoURL: URL,
        completion: @escaping (Result<APIResponse, Error>) -> Void
    ) {

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Read video data
        guard let videoData = try? Data(contentsOf: videoURL) else {
            completion(.failure(NSError(
                domain: "VideoReadError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to read video file"]
            )))
            return
        }

        let filename = videoURL.lastPathComponent
        let mimeType = videoURL.pathExtension.lowercased() == "mov"
            ? "video/quicktime"
            : "video/mp4"

        // Build multipart body
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append(
            "Content-Type: \(mimeType)\r\n\r\n"
                .data(using: .utf8)!
        )
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // --------------------------------------------------
        // Execute request
        // --------------------------------------------------

        URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "NoDataError",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No response data"]
                    )))
                }
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(apiResponse))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }

        }.resume()
    }
}
