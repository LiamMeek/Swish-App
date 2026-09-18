import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import CoreImage
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        view.layer.masksToBounds = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.session = session
        previewLayer.frame = uiView.bounds
    }
}

#elseif canImport(AppKit)
import AppKit

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.wantsLayer = true
        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.session = session
        previewLayer.frame = nsView.bounds
    }
}
#endif

final class ShootViewModel: NSObject, ObservableObject {
    // Camera session and state
    let captureSession: AVCaptureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()

    @Published var isCameraOn: Bool = false
    @Published var isTracking: Bool = false
    @Published var lastBackendResult: String? = nil

    // Burst capture state
    private var isCapturingBurst = false
    private var burstFramesCG: [CGImage] = []
    private var burstStartTime: CFAbsoluteTime = 0
    private let burstDuration: CFTimeInterval = 1.5

    override init() {
        super.init()
    }

    // Public API: toggle camera after requesting permission
    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setCamera(enabled: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.setCamera(enabled: granted) }
            }
        default:
            // Consider surfacing an alert to guide user to Settings
            self.isCameraOn = false
        }
    }

    func setCamera(enabled: Bool) {
        isCameraOn = enabled
        if enabled {
            configureSessionIfNeeded()
            if !captureSession.isRunning {
                sessionQueue.async { self.captureSession.startRunning() }
            }
        } else {
            if captureSession.isRunning {
                sessionQueue.async { self.captureSession.stopRunning() }
            }
        }
    }

    private func configureSessionIfNeeded() {
        guard captureSession.inputs.isEmpty else { return }
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            // Input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            // Output
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            let outputQueue = DispatchQueue(label: "video.output.queue")
            self.videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            if let connection = self.videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Shot capture
    func captureShot() {
        guard isCameraOn else { return }
        burstFramesCG.removeAll()
        isCapturingBurst = true
        burstStartTime = CFAbsoluteTimeGetCurrent()
    }

    private func finishBurstAndSend() {
        let frames = self.burstFramesCG
        self.burstFramesCG.removeAll()
        Task { await self.sendFramesToBackend(frames) }
    }

    // MARK: - Networking
    private struct ShotResult: Decodable { let result: String }

    private func sendFramesToBackend(_ frames: [CGImage]) async {
        guard !frames.isEmpty else { return }

        // Convert frames to JPEG data, platform-specific
        #if canImport(UIKit)
        let images: [UIImage] = frames.map { UIImage(cgImage: $0) }
        let jpegDataArray: [Data] = images.compactMap { $0.jpegData(compressionQuality: 0.6) }
        #elseif canImport(AppKit)
        let jpegDataArray: [Data] = frames.compactMap { cg in
            let rep = NSBitmapImageRep(cgImage: cg)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        }
        #else
        let jpegDataArray: [Data] = []
        #endif

        guard !jpegDataArray.isEmpty else { return }

        // Build multipart request
        guard let url = URL(string: "https://your-backend.example.com/api/shot") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        for (index, data) in jpegDataArray.prefix(10).enumerated() { // cap to 10 frames
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"frame\(index)\"; filename=\"frame\(index).jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(data)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let decoded = try? JSONDecoder().decode(ShotResult.self, from: data) {
                    DispatchQueue.main.async { self.lastBackendResult = decoded.result }
                } else {
                    DispatchQueue.main.async { self.lastBackendResult = "Unknown response" }
                }
            } else {
                DispatchQueue.main.async { self.lastBackendResult = "Server error" }
            }
        } catch {
            DispatchQueue.main.async { self.lastBackendResult = "Error: \(error.localizedDescription)" }
        }
    }
}

extension ShootViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isCapturingBurst else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - burstStartTime
        if elapsed > burstDuration {
            isCapturingBurst = false
            finishBurstAndSend()
            return
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: nil)
        if let cg = context.createCGImage(ciImage, from: ciImage.extent) {
            burstFramesCG.append(cg)
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

final class AppGameViewModel: ObservableObject {
    @Published var isRunning: Bool = false
}


struct CourtLines: View {
    var body: some View {
        Rectangle()
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            .background(Color.clear)
    }
}

struct GameTopBar: View {
    @ObservedObject var viewModel: ShootViewModel
    var body: some View {
        HStack {
            Text("Game Tracker")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Circle()
                .fill(viewModel.isTracking ? Color.green : Color.red)
                .frame(width: 10, height: 10)
        }
        .padding()
    }
}

struct LeftMenu: View {
    var body: some View {
        VStack(spacing: 12) {
        }
        .padding()
    }
}

struct RightMenu: View {
    var body: some View {
        VStack(spacing: 12) {
        }
        .padding()
    }
}

struct CameraContainer: View {
    @ObservedObject var viewModel: ShootViewModel

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.captureSession)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Text(viewModel.isCameraOn ? "Camera Active" : "Camera Preview")
                        .foregroundColor(.white)
                )

            VStack {
                Spacer()
                HStack {
                    Toggle(isOn: $viewModel.isCameraOn) {
                        Text("Camera").foregroundColor(.white)
                    }
                    .onChange(of: viewModel.isCameraOn) { newValue in
                        if newValue {
                            viewModel.requestAndStart()
                        } else {
                            viewModel.setCamera(enabled: false)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(8)

                    Button {
                        viewModel.captureShot()
                    } label: {
                        Label("Capture Shot", systemImage: "camera.shutter.button")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Spacer()
                }

                if let result = viewModel.lastBackendResult {
                    Text("Result: \(result)")
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: 240)
    }
}

struct GameModesButton: View {
    var body: some View {
        Menu {
            Button("Mode A") {}
            Button("Mode B") {}
            Button("Mode C") {}
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("Modes")
            }
        }
        .menuStyle(.automatic)
        .foregroundStyle(.white)
    }
}

struct StartButton: View {
    @ObservedObject var gameViewModel: AppGameViewModel
    var body: some View {
        Button(action: {
            gameViewModel.isRunning.toggle()
        }) {
            Label(gameViewModel.isRunning ? "Stop" : "Start", systemImage: gameViewModel.isRunning ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
    }
}

struct StatsPanel: View {
    @ObservedObject var gameViewModel: AppGameViewModel
    var body: some View {
        HStack(spacing: 8) {
            Text("Stats:")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(gameViewModel.isRunning ? "Running" : "Stopped")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1))
                )
        )
    }
}

#Preview {
    CourtLines()
        .background(Color.black)
        .frame(width: 300, height: 200)
}
