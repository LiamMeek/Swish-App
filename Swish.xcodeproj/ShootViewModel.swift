import Foundation
import Combine
import AVFoundation
import UIKit

@MainActor
final class ShootViewModel: NSObject, ObservableObject {

    // Shot counts
    @Published var madeShots: Int = 0
    @Published var missedShots: Int = 0

    // UI status
    @Published var statsText: String = "Stopped"
    @Published var isCameraOn: Bool = false
    @Published var isTracking: Bool = false

    // Recent history (true = make, false = miss)
    @Published private(set) var recentShots: [Bool] = []
    let recentLimit: Int = 50

    // Camera session / capture tools
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var frameCount = 0
    private var isSendingFrame = false

    // Derived stats
    var totalShots: Int { madeShots + missedShots }
    var fieldGoalPercentage: Int {
        let total = totalShots
        guard total > 0 else { return 0 }
        return Int((Double(madeShots) / Double(total)) * 100.0)
    }

    // Public API
    func recordMake() {
        madeShots += 1
        appendHistory(true)
    }

    func recordMiss() {
        missedShots += 1
        appendHistory(false)
    }

    func resetSession() {
        madeShots = 0
        missedShots = 0
        recentShots.removeAll()
        statsText = "Stopped"
        isTracking = false
    }

    // MARK: - Private
    private func appendHistory(_ made: Bool) {
        recentShots.append(made)
        if recentShots.count > recentLimit {
            recentShots.removeFirst(recentShots.count - recentLimit)
        }
    }

    // MARK: - Camera Toggle

    func setCamera(enabled: Bool) {
        isCameraOn = enabled
        if enabled {
            startSession()
        } else {
            stopSession()
            isTracking = false
            statsText = "Stopped"
        }
    }

    private func startSession() {
        sessionQueue.async {
            if self.captureSession.isRunning { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            // Remove previous inputs/outputs
            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.statsText = "Camera unavailable"
                }
                return
            }
            self.captureSession.addInput(input)

            self.videoOutput.setSampleBufferDelegate(self,
                                                     queue: DispatchQueue(label: "video.frame.queue"))
            self.videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    // MARK: - Tracking Control

    func startTracking() {
        guard isCameraOn else {
            statsText = "Turn Camera on first"
            return
        }
        isTracking = true
        statsText = "Tracking shot..."
    }

    func stopTracking() {
        isTracking = false
        statsText = "Stopped"
    }

    func toggleTracking() {
        isTracking ? stopTracking() : startTracking()
    }
}

// MARK: - Frame Processing + Network

extension ShootViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard isTracking else { return }

        frameCount += 1
        guard frameCount % 10 == 0, !isSendingFrame else { return }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }

        sendFrameToBackend(jpegData: jpegData)
    }

    func sendFrameToBackend(jpegData: Data) {
        guard let url = URL(string: "https://YOUR-NGROK-URL.ngrok-free.app/predict_frame") else {
            DispatchQueue.main.async {
                self.statsText = "Invalid backend URL"
            }
            return
        }

        isSendingFrame = true
        DispatchQueue.main.async {
            self.statsText = "Analyzing..."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"frame\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { data, _, error in
            defer { self.isSendingFrame = false }

            if let error = error {
                DispatchQueue.main.async {
                    self.statsText = "Network error: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { self.statsText = "Empty response" }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let prediction = json["prediction"] as? String {

                    DispatchQueue.main.async {
                        switch prediction {
                        case "make":
                            self.recordMake()
                            self.statsText = "Made"
                        case "miss":
                            self.recordMiss()
                            self.statsText = "Missed"
                        default:
                            self.statsText = prediction
                        }
                    }
                } else {
                    DispatchQueue.main.async { self.statsText = "Invalid JSON" }
                }
            } catch {
                DispatchQueue.main.async { self.statsText = "JSON error" }
            }
        }.resume()
    }
}

