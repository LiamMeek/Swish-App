import SwiftUI
import AVFoundation
import Combine

class HomeCameraViewModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var preview = AVCaptureVideoPreviewLayer()
    @Published var isAuthorized = false

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted {
                        self.setUp()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func requestAuthorizationAndSetup() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    self.setUp()
                }
            }
        }
    }

    func setUp() {
        do {
            session.beginConfiguration()
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            session.startRunning()
        } catch {
            print(error.localizedDescription)
        }
    }
}

#if canImport(UIKit)
struct HomeCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
#endif

struct HomeCameraContainer: View {
    @StateObject var cameraViewModel: HomeCameraViewModel
    @ObservedObject var gameViewModel: GameViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
#if canImport(UIKit)
                if cameraViewModel.isAuthorized {
                    HomeCameraPreview(session: cameraViewModel.session)
                        .frame(height: 450)
                        .background(Color.black)
                } else {
                    VStack(spacing: 8) {
                        Text("Camera permission required")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                        Button("Enable Camera") { cameraViewModel.requestAuthorizationAndSetup() }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.5))
                }
#else
                Color.black
                    .frame(height: 450)
                    .background(Color.black)
#endif
                GeometryReader { geometry in
                    VStack {
                        Spacer().frame(height: geometry.size.height * 0.3)
                        ZStack {
                            Rectangle().fill(Color.yellow.opacity(0.6)).frame(height: 2).shadow(color: .yellow.opacity(0.8), radius: 5)
                            Text("DETECTION LINE")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.yellow.opacity(0.8))
                                .offset(x: -geometry.size.width / 2 + 60, y: -15)
                        }
                        Spacer()
                    }
                }
            }
            HStack(spacing: 10) {
                Button(action: { gameViewModel.isTracking = true }) {
                    Text("START TRACKING")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .background(LinearGradient(gradient: Gradient(colors: [Color(hex: "3498db"), Color(hex: "2980b9")]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(20)
                }
                Button(action: { gameViewModel.isTracking = false }) {
                    Text("STOP")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .background(LinearGradient(gradient: Gradient(colors: [Color(hex: "3498db"), Color(hex: "2980b9")]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(20)
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "34495e"), lineWidth: 3))
        .onAppear { cameraViewModel.checkAuthorization() }
    }
}

