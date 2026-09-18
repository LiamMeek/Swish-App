import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct InferenceResponse: Decodable {
    let result: String?
    let confidence: Double?
    let status: String?
    let error_code: String?
    let error_message: String?
}

struct MultipartFormDataBuilder {
    let boundary: String
    private let lineBreak = "\r\n"
    private var body = Data()

    init(boundary: String) { self.boundary = boundary }

    mutating func addFile(fieldName: String, filename: String, mimeType: String, fileData: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append(lineBreak.data(using: .utf8)!)
    }

    func finalize() -> Data {
        var data = body
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

actor InferenceAPIClient {
    private let baseURL = URL(string: "https://swish-backend1.onrender.com")!

    func uploadVideo(data: Data, fieldName: String = "file") async throws -> InferenceResponse {
        let url = baseURL.appendingPathComponent("predict")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var form = MultipartFormDataBuilder(boundary: boundary)
        form.addFile(
            fieldName: fieldName,
            filename: "clip.mov",
            mimeType: "video/quicktime",
            fileData: data
        )

        let body = form.finalize()
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(InferenceResponse.self, from: respData)
        } else if let decoded = try? JSONDecoder().decode(InferenceResponse.self, from: respData) {
            return decoded
        } else {
            throw URLError(.badServerResponse)
        }
    }
}
