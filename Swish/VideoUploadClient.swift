import Foundation

public struct VideoUploadClient {
    
    public static func uploadVideo(fileURL: URL, endpoint: String, completion: @escaping (Result<String, Error>) -> Void) {
        let predictURLString = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) + "/predict" : endpoint + "/predict"
        guard let url = URL(string: predictURLString) else {
            DispatchQueue.main.async {
                completion(.failure(URLError(.badURL)))
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileData = try Data(contentsOf: fileURL)
                let filename = fileURL.lastPathComponent.isEmpty ? "video.mov" : fileURL.lastPathComponent
                let fileExtension = fileURL.pathExtension.lowercased()
                let mimeType: String
                switch fileExtension {
                case "mp4":
                    mimeType = "video/mp4"
                default:
                    mimeType = "video/quicktime"
                }
                let boundary = "Boundary-\(UUID().uuidString)"
                let httpBody = makeMultipartBody(boundary: boundary, fieldName: "file", filename: filename, mimeType: mimeType, fileData: fileData)
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = httpBody
                
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        DispatchQueue.main.async {
                            completion(.failure(URLError(.badServerResponse)))
                        }
                        return
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        let statusError = NSError(domain: "VideoUploadClient",
                                                  code: httpResponse.statusCode,
                                                  userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
                        DispatchQueue.main.async {
                            completion(.failure(statusError))
                        }
                        return
                    }
                    
                    if let data = data {
                        if let stringResponse = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                completion(.success(stringResponse))
                            }
                        } else if data.isEmpty {
                            let parseError = NSError(domain: "VideoUploadClient",
                                                     code: -1,
                                                     userInfo: [NSLocalizedDescriptionKey: "Response data is empty and cannot be parsed"])
                            DispatchQueue.main.async {
                                completion(.failure(parseError))
                            }
                        } else {
                            // Fallback: return raw data as string with lossy conversion
                            let fallbackString = String(decoding: data, as: UTF8.self)
                            DispatchQueue.main.async {
                                completion(.success(fallbackString))
                            }
                        }
                    } else {
                        let noDataError = NSError(domain: "VideoUploadClient",
                                                  code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "No data received from server"])
                        DispatchQueue.main.async {
                            completion(.failure(noDataError))
                        }
                    }
                }
                
                task.resume()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private static func makeMultipartBody(boundary: String, fieldName: String, filename: String, mimeType: String, fileData: Data) -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(fileData)
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        
        return body
    }
}
