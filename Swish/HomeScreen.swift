import SwiftUI
import Foundation
import CoreGraphics
import AVFoundation
import Combine
import Network
import StoreKit

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class HomeCameraLocalViewModel: ObservableObject {
    @Published var isRunning: Bool = false
}

#if canImport(UIKit)
class BatteryStatusViewModel: ObservableObject {
    @Published var batteryLevel: Float = UIDevice.current.batteryLevel
    @Published var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBattery),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBattery),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        updateBattery()
    }
    
    @objc private func updateBattery() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }
}
#endif

class TimeViewModel: ObservableObject {
    @Published var currentTime: String = TimeViewModel.format(Date())
    private var cancellable: AnyCancellable?

    init() {
#if DEBUG
        let runningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if runningInPreviews {
            // Don’t start timer in previews
            return
        }
#endif
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { date in
                self.currentTime = Self.format(date)
            }
    }

    deinit {
        cancellable?.cancel()
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

class NetworkStatusViewModel: ObservableObject {
    @Published var isConnected: Bool = true
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "NetworkMonitorQueue")

    init() {
#if DEBUG
        let runningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if runningInPreviews {
            // Assume connected in previews and avoid starting the monitor.
            self.isConnected = true
            return
        }
#endif
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }
}

// MARK: - Local Types (Self-Contained Build)

@MainActor
final class HomeAppGameVM: ObservableObject {
    @Published var isInGame: Bool = false
}

@MainActor
final class HomeGameVM: ObservableObject {
    @Published var madeShots: Int = 0
    @Published var missedShots: Int = 0
    var totalShots: Int { madeShots + missedShots }
    var fieldGoalPercentage: Int {
        let total = totalShots
        guard total > 0 else { return 0 }
        return Int((Double(madeShots) / Double(max(total, 1))) * 100.0)
    }
    func startGame() { isInGame = true }
    func backToMenu() { isInGame = false }
    private var isInGame: Bool = false
}

@MainActor
final class HomeShotClassificationVM: ObservableObject {
    @Published var lastInference: String? = nil
}

struct HomeInferenceAPIClient {
    func classify(sampleBuffer: Any) async throws -> String { "unknown" }
//    testing
}

struct HomeScreenWithLoader<Content: View>: View {
    let duration: TimeInterval
    let content: () -> Content
    @State private var done = false
    var body: some View {
        ZStack {
            if done {
                content()
            } else {
                ProgressView("Loading…")
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation { done = true }
            }
        }
    }
}

struct HomeSessionScreenHost: View {
    @ObservedObject var appGameVM: HomeAppGameVM
    @ObservedObject var shotVM: HomeShotClassificationVM
    let apiClient: HomeInferenceAPIClient
    let initialConfidence: Double
    @Binding var gatedCounter: Int

    var body: some View {
        VStack(spacing: 16) {
            // Top bar
            HStack {
                Text("Session")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
                Toggle(isOn: Binding(get: { appGameVM.isInGame }, set: { on in
                    appGameVM.isInGame = on
                })) {
                    Text(appGameVM.isInGame ? "Camera On" : "Camera Off")
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
            }
            .padding(.horizontal)

            // Camera preview
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.4))
                HomeSessionCameraPreview(isRunning: appGameVM.isInGame)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(height: 260)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .padding(.horizontal)

            // AI status
            VStack(spacing: 6) {
                Text("AI Inference")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(shotVM.lastInference ?? "Waiting…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
            .padding(.horizontal)

            // Stats
            HStack(spacing: 12) {
                StatPill(label: "Made", value:  String(shotVMStat.made))
                StatPill(label: "Missed", value: String(shotVMStat.missed))
                StatPill(label: "FG%", value: String(shotVMStat.fg))
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onChange(of: appGameVM.isInGame) { _, running in
            if running {
                Task { await startAIStream() }
            }
        }
        .task {
            if appGameVM.isInGame {
                await startAIStream()
            }
        }
        .toolbar(.hidden)
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct ShotStats {
    var made: Int = 0
    var missed: Int = 0
    var fg: Int { let t = made + missed; return t > 0 ? Int(Double(made) / Double(t) * 100.0) : 0 }
}

extension HomeSessionScreenHost {
    // Local, simple stats store
    @MainActor private var shotVMStat: ShotStats {
        get { _stats }
    }

    // Backing store using static to avoid stored properties in View
    private static var _statsStore: ShotStats = .init()
    private var _stats: ShotStats {
        get { Self._statsStore }
        nonmutating set { Self._statsStore = newValue }
    }

    private func startAIStream() async {
        // Simulate periodic AI results off the main actor; hop to MainActor only to update UI state.
        for idx in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let made = (idx % 3 == 0)
            await MainActor.run {
                if made { _stats.made += 1 } else { _stats.missed += 1 }
                shotVM.lastInference = made ? "Shot: MADE" : "Shot: MISSED"
            }
        }
    }
}

#if canImport(UIKit)
fileprivate struct HomeSessionCameraPreview: UIViewRepresentable {
    let isRunning: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if isRunning {
            // Delay slightly to avoid clashing with navigation animations and rapid state flips.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                uiView.startSession()
            }
        } else {
            uiView.stopSession()
        }
    }

    final class PreviewView: UIView {
        private let session = AVCaptureSession()
        private var configured = false
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var isStarting = false

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        func configureIfNeeded() {
            guard !configured else { return }
            configured = true
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            session.commitConfiguration()
            if let layer = self.layer as? AVCaptureVideoPreviewLayer {
                previewLayer = layer
                layer.session = session
                layer.videoGravity = .resizeAspectFill
            }
        }

        func startSession() {
            configureIfNeeded()
            guard !session.isRunning && !isStarting else { return }
            isStarting = true
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                DispatchQueue.main.async { self.isStarting = false }
            }
        }

        func stopSession() {
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
            }
        }
    }
}
#else
fileprivate struct HomeSessionCameraPreview: View {
    let isRunning: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            Text(isRunning ? "Camera preview (simulated)" : "Camera off")
                .foregroundColor(.white.opacity(0.7))
                .font(.caption)
        }
    }
}
#endif

// MARK: - Court Components

struct HomeCourtLines: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ZStack {
                // Court boundary
                Rectangle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 4)
                    .padding(.horizontal, width * 0.1)
                    .padding(.vertical, height * 0.05)
                
                // Center line
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(height: 4)
                    .position(x: width / 2, y: height / 2)
                    .padding(.horizontal, width * 0.1)
                
                // Center circle
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .position(x: width / 2, y: height / 2)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .position(x: width / 2, y: height / 2)
                    )
                
                // Three-point lines
                HomeThreePointLine(isTop: true)
                    .position(x: width / 2, y: height * 0.1)
                
                HomeThreePointLine(isTop: false)
                    .position(x: width / 2, y: height * 0.9)
                
                // Key areas
                HomeKeyArea(isTop: true)
                    .position(x: width / 2, y: height * 0.15)
                
                HomeKeyArea(isTop: false)
                    .position(x: width / 2, y: height * 0.85)
                
                // Free throw circles
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .position(x: width / 2, y: height * 0.15)
                
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .position(x: width / 2, y: height * 0.85)
            }
        }
    }
}

struct HomeThreePointLine: View {
    let isTop: Bool
    
    var body: some View {
        HomeArc(startAngle: isTop ? 0 : 180, endAngle: isTop ? 180 : 360)
            .stroke(Color.white.opacity(0.9), lineWidth: 4)
            .frame(width: 240, height: 240)
    }
}

struct HomeKeyArea: View {
    let isTop: Bool
    
    var body: some View {
        Rectangle()
            .stroke(Color.white.opacity(0.9), lineWidth: 4)
            .frame(width: 140, height: 100)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 4)
                    .offset(y: isTop ? -50 : 50)
            )
    }
}

struct HomeBasketballHoop: View {
    var body: some View {
        ZStack {
            // Backboard
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.2))
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(hex: "34495e"), lineWidth: 3)
                )
                .offset(y: -10)
            
            // Rim
            Circle()
                .stroke(Color(hex: "e74c3c"), lineWidth: 5)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                )
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            
            // Net
            HomeNetView()
                .offset(y: 20)
        }
    }
}

struct HomeNetView: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 35, y: 20))
            path.addLine(to: CGPoint(x: 30, y: 0))
        }
        .stroke(
            Color.white.opacity(0.7),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3])
        )
        .frame(width: 35, height: 20)
    }
}

// MARK: - Menu Components

struct HomeLeftMenu: View {
    var body: some View {
        VStack(spacing: 10) {
            HomeMenuButton(icon: "🛒", title: "SHOP")
            HomeMenuButton(icon: "📊", title: "STATS")
            HomeMenuButton(icon: "🏆", title: "ACHIEVE")
        }
    }
}

struct HomeRightMenu: View {
    var body: some View {
        VStack(spacing: 10) {
            HomeMenuButton(icon: "👥", title: "TEAMS")
            HomeMenuButton(icon: "📈", title: "RANKS")
            HomeMenuButton(icon: "👫", title: "FRIENDS")
        }
    }
}

struct HomeMenuButton: View {
    let icon: String
    let title: String
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 3) {
                Text(icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 70, height: 70)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "34495e"), Color(hex: "2c3e50")]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color(hex: "95a5a6"), lineWidth: 2)
            )
            .opacity(isHovered ? 1 : 0.9)
            .scaleEffect(isHovered ? 1.05 : 1)
            .shadow(color: isHovered ? .white.opacity(0.2) : .clear, radius: 7)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct HomeGameModesButton: View {
    var body: some View {
        Button(action: {
            // Show game modes
        }) {
            Text("MODES")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 120, height: 50)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "3498db"), Color(hex: "2980b9")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: Color(hex: "3498db").opacity(0.3), radius: 5, y: 2)
        }
    }
}

struct HomeStartButton: View {
    @ObservedObject var gameViewModel: HomeGameVM
    
    var body: some View {
        Button(action: {
            gameViewModel.startGame()
        }) {
            Text("START")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 150, height: 50)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "27ae60"), Color(hex: "2ecc71")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: Color(hex: "2ecc71").opacity(0.3), radius: 5, y: 2)
        }
    }
}

// MARK: - Game Screen Components

struct HomeGameTopBar: View {
    @ObservedObject var gameViewModel: HomeGameVM
    
    var body: some View {
        HStack {
            Button(action: {
                gameViewModel.backToMenu()
            }) {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("BACK")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "e74c3c"), Color(hex: "c0392b")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(20)
            }
            
            Spacer()
            
            Text("SHOT TRACKER")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
}

struct HomeStatsPanel: View {
    @ObservedObject var gameViewModel: HomeGameVM
    
    var body: some View {
        VStack(spacing: 20) {
            // Session Stats
            VStack(spacing: 15) {
                Text("Session Stats")
                    .font(.title2)
                    .foregroundColor(.white)
                
                HomeStatRow(label: "Made:", value: "\(gameViewModel.madeShots)")
                HomeStatRow(label: "Missed:", value: "\(gameViewModel.missedShots)")
                HomeStatRow(label: "Total:", value: "\(gameViewModel.totalShots)")
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .backgroundBlur(radius: 10)
            
            // Percentage Circle
            VStack {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color(hex: "2c3e50"), Color(hex: "34495e")]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 75
                            )
                        )
                        .frame(width: 150, height: 150)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "2ecc71"), lineWidth: 5)
                        )
                        .shadow(color: Color(hex: "2ecc71").opacity(0.3), radius: 15)
                    
                    VStack {
                        Text("\(gameViewModel.fieldGoalPercentage)%")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(hex: "2ecc71"))
                        Text("FG%")
                            .font(.caption)
                            .foregroundColor(Color(hex: "95a5a6"))
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .backgroundBlur(radius: 10)
            
            // Shot History
            VStack {
                Text("Recent Shots")
                    .font(.title3)
                    .foregroundColor(.white)
                
                ScrollView {
                    VStack(spacing: 5) {
                        // This would show shot history
                        ForEach(0..<5) { _ in
                            HomeShotHistoryItem(made: Bool.random())
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .backgroundBlur(radius: 10)
            
            Spacer()
        }
    }
}

struct HomeStatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(Color(hex: "95a5a6"))
                .font(.system(size: 18))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.system(size: 24, weight: .bold))
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(10)
    }
}

struct HomeShotHistoryItem: View {
    let made: Bool
    
    var body: some View {
        HStack {
            Text(made ? "✓ MADE" : "✗ MISSED")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: made ?
                    [Color(hex: "27ae60"), Color(hex: "2ecc71")] :
                    [Color(hex: "c0392b"), Color(hex: "e74c3c")]
                ),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(10)
    }
}

// MARK: - Helper Views

struct HomeArc: Shape {
    var startAngle: Double
    var endAngle: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: Angle(degrees: startAngle),
            endAngle: Angle(degrees: endAngle),
            clockwise: false
        )
        return path
    }
}

struct HomePolygon: Shape {
    var sides: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let radius = min(rect.width, rect.height) / 2
        
        let angle = 2 * Double.pi / Double(sides)
        let offset = -Double.pi / 2
        
        for i in 0..<sides {
            let x = center.x + radius * Foundation.cos(Double(i) * angle + offset)
            let y = center.y + radius * Foundation.sin(Double(i) * angle + offset)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

struct HomeCustomProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.2))
                .frame(height: 10)
            
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "e74c3c"), Color(hex: "e67e22")]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: CGFloat(configuration.fractionCompleted ?? 0) * 250, height: 10)
                .animation(.easeOut, value: configuration.fractionCompleted)
        }
    }
}

// MARK: - Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func backgroundBlur(radius: CGFloat) -> some View {
#if canImport(UIKit)
        return self.background(
            HomeVisualEffectBlur(blurStyle: UIBlurEffect.Style.systemUltraThinMaterial)
                .opacity(0.5)
        )
#else
        return self.background(.ultraThinMaterial.opacity(0.5))
#endif
    }
}

#if canImport(UIKit)
struct HomeVisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
#endif

private struct DockIconButton: View {
    let systemName: String
    let color: Color
    
    var body: some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
                .shadow(color: color.opacity(0.6), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct SideMenuButtonConfig {
    let title: String
    let action: () -> Void
}

// Added BlankBlackScreen as per instruction
private struct BlankBlackScreen: View {
    let title: String
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(title)
                .foregroundColor(.white.opacity(0.6))
                .font(.headline)
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct SideMenu: View {
    enum AlignmentSide { case leading, trailing }
    let alignment: AlignmentSide
    let buttons: [SideMenuButtonConfig]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, item in
                Button(action: item.action) {
                    Text(item.title.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 44)
                        .background(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxHeight: .infinity, alignment: alignment == .leading ? .center : .center)
        .padding(alignment == .leading ? .leading : .trailing, 12)
    }
}

// MARK: - Home Screen

struct HomeScreen: View {
    @StateObject private var appGameVM = HomeAppGameVM()
    @StateObject private var cameraVM2 = HomeCameraLocalViewModel()
    @State private var showLoading = true
    @StateObject private var shotVM = HomeShotClassificationVM()

    @State private var confidenceThreshold: Double = 0.7
    @State private var gatedCounter: Int = 0
    private let apiClient = HomeInferenceAPIClient()
    
    @State private var totalXP: Int = 0
    @State private var totalGems: Int = 0

#if canImport(UIKit)
    @StateObject private var batteryVM = BatteryStatusViewModel()
    @State private var didAskBattery = false
    @State private var batteryAllowed = false
#endif
    @StateObject private var timeVM = TimeViewModel()
    @StateObject private var networkVM = NetworkStatusViewModel()
    
    // Added Demo Mode ViewModel to observe demo mode
    @StateObject private var demoModeVM = DemoModeViewModel()

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    // Background
                    Color.black
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Top bar
                        HStack {
                            // Profile button (top-left) replaced with NavigationLink to ProfileScreen
                            NavigationLink(destination: ProfileScreen()) {
                                Image(systemName: "person.crop.circle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .padding(.leading, 16)
                            
                            // Trophy road bar placeholder to the right of profile
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 10)
                                .padding(.leading, 12)
                            
                            Spacer()
                            
                            Text("Swish")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            NavigationLink(destination: SettingsSupportScreen()) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                            
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        
                        Spacer()
                        
                        // Main content with side docks and hero card
                        HStack(spacing: 24) {
                            // Left side menu (centered vertically) replaced with VStack of NavigationLinks
                            VStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    NavigationLink(destination: QuestsScreen(totalXP: $totalXP, totalGems: $totalGems)) {
                                        Text("QUESTS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    NavigationLink(destination: ShopScreen()) {
                                        Text("SHOP")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    NavigationLink(destination: StatsScreen()) {
                                        Text("STATS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                                .padding(.leading, 12)
                                Spacer()
                            }
                            
                            Spacer(minLength: 0)
                            
                            // Hero card with white fill (replaced gradient fill with white)
                            HeroCard()
                                .frame(width: 320, height: 420)
                                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                            
                            Spacer(minLength: 0)
                            
                            // Right side menu (centered vertically) replaced with VStack of NavigationLinks
                            VStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    NavigationLink(destination: TeamsScreen()) {
                                        Text("TEAMS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    NavigationLink(destination: RanksScreen()) {
                                        Text("RANKS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    NavigationLink(destination: FriendsScreen()) {
                                        Text("FRIENDS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 120, height: 44)
                                            .background(Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                                .padding(.trailing, 12)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                        
                        // Bottom bar with info tiles and start session button
                        HStack {
                            HStack(spacing: 16) {
                                InfoTile(iconName: "wifi", title: "Network", value: networkVM.isConnected ? "Connected" : "Offline")
#if canImport(UIKit)
                                if batteryAllowed {
                                    InfoTile(iconName: "battery.100", title: "Battery", value: batteryVM.batteryLevel >= 0 ? String(format: "%d%%", Int(batteryVM.batteryLevel * 100)) : "--")
                                }
#endif
                                InfoTile(iconName: "clock", title: "Time", value: timeVM.currentTime)
                                InfoTile(iconName: "star.fill", title: "XP", value: String(totalXP))
                                InfoTile(iconName: "diamond.fill", title: "Gems", value: String(totalGems))
                                
                                if demoModeVM.demoModeEnabled {
                                    Text("DEMO")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.leading, 20)
                            
                            Spacer()
                            
                            NavigationLink {
                                HomeScreenWithLoader(duration: 2.0) {
                                    HomeSessionScreenHost(appGameVM: appGameVM,
                                                         shotVM: shotVM,
                                                         apiClient: apiClient,
                                                         initialConfidence: confidenceThreshold,
                                                         gatedCounter: $gatedCounter)
                                }
                            } label: {
                                Text("Start Session")
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.red, Color(red: 0.8, green: 0.0, blue: 0.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                    .shadow(color: Color.red.opacity(0.7), radius: 10, x: 0, y: 5)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.trailing, 20)
                    }
                }
                .toolbar(.hidden)
            }
#if canImport(UIKit)
            if !didAskBattery && !showLoading {
                Color.black.opacity(0.65).ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("\"Swish\" Would Like to Access Your Battery")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.top, 32)
                    Text("This lets us show your current battery level.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    HStack(spacing: 22) {
                        Button("Don't Allow") {
                            didAskBattery = true
                            batteryAllowed = false
                        }
                        .fontWeight(.bold)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        Button("Allow") {
                            didAskBattery = true
                            batteryAllowed = true
                        }
                        .fontWeight(.bold)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: 360)
                .padding()
                .background(Color.black.opacity(0.85))
                .cornerRadius(20)
                .shadow(radius: 20)
                .padding(.top, 120)
            }
#endif
        }
        .onAppear {
            if showLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    if showLoading {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showLoading = false
                        }
                    }
                }
            }
        }
    }
}

@MainActor
final class DemoModeViewModel: ObservableObject {
    @Published var demoModeEnabled: Bool {
        didSet { UserDefaults.standard.set(demoModeEnabled, forKey: "demoModeEnabled") }
    }
    @Published var reviewerNotesAcknowledged: Bool {
        didSet { UserDefaults.standard.set(reviewerNotesAcknowledged, forKey: "reviewerNotesAcknowledged") }
    }
    init() {
        self.demoModeEnabled = UserDefaults.standard.bool(forKey: "demoModeEnabled")
        self.reviewerNotesAcknowledged = UserDefaults.standard.bool(forKey: "reviewerNotesAcknowledged")
    }
}

private struct AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-" }
}

private struct SettingsSupportScreen: View {
    @StateObject private var demoVM = DemoModeViewModel()
    @Environment(\.dismiss) private var dismiss

    private let privacyURL = URL(string: "https://example.com/privacy")!
    private let supportMail = URL(string: "mailto:support@example.com?subject=Swish%20Support")!

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Demo Mode
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Demo Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $demoVM.demoModeEnabled)
                            .labelsHidden()
                    }
                    Text("Enables a fully-featured demo experience without requiring any external accounts or hardware. Use this during TestFlight review if needed.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
                .background(Color.white.opacity(0.09))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))

                // Reviewer Notes
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reviewer Notes")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("1) From Home, tap ‘Start Session’ to load the session experience.\n2) The app works offline; network/battery tiles indicate current status.\n3) Demo Mode can be toggled above if backend access is unavailable.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Toggle("I’ve read these notes", isOn: $demoVM.reviewerNotesAcknowledged)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.09))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))

                // Privacy & Support
                VStack(spacing: 12) {
                    HStack {
                        Text("Privacy & Support")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Link(destination: privacyURL) {
                            Text("Privacy Policy")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Link(destination: supportMail) {
                            Text("Contact Support")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Button {
#if canImport(UIKit)
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                SKStoreReviewController.requestReview(in: scene)
                            }
#endif
                        } label: {
                            Text("Request Review")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
#if !canImport(UIKit)
                        // Fallback for non-UIKit platforms
                        Text("Review prompt not available on this platform")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
#endif
                    }
                }
                .padding()
                .background(Color.white.opacity(0.09))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))

                // App Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Info")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Version: \(AppInfo.version) (\(AppInfo.build))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding()
                .background(Color.white.opacity(0.09))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))

                Spacer(minLength: 8)
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings & Support")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct BadgeView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.25))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

private struct HeroCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
            
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
                    .foregroundColor(.black)
                    .shadow(radius: 10)
                
                Text("Welcome to Swish")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 5)
                
                Text("Capture your moments with precision and style. Get ready to start your session!")
                    .font(.body)
                    .foregroundColor(.black.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(32)
        }
    }
}

private struct InfoTile: View {
    let iconName: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(.white)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Shop Screen (New)

private struct ShopScreen: View {
    // Example shop items
    struct ShopItem: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let price: String
    }
    
    let items: [ShopItem] = [
        .init(icon: "🔥", name: "Premium Drills & Workouts", price: "$3.99"),
        .init(icon: "📊", name: "Skill Analytics", price: "$2.49"),
        .init(icon: "⚡️", name: "Level Advancement", price: "$1.99"),
        .init(icon: "🔋", name: "Extra Tracking Credits", price: "$0.99"),
        .init(icon: "💎", name: "Monthly Pro Subscription", price: "$4.99/month")
    ]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Shop")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Spacer().frame(width: 44) // To match icon space
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 25) {
                        ForEach(items) { item in
                            ShopItemCard(item: item)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                }
                Spacer()
            }
        }
    }
}

private struct ShopItemCard: View {
    let item: ShopScreen.ShopItem
    @State private var bought = false
    
    var isPro: Bool { item.name.contains("Pro Subscription") }
    
    var body: some View {
        ZStack {
            if isPro {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(LinearGradient(gradient: Gradient(colors: [Color(hex: "ffd700"), Color(hex: "d4af37")]), startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                    .shadow(color: .yellow.opacity(0.15), radius: 8, y: 2)
            }
            HStack(spacing: 20) {
                Text(item.icon)
                    .font(.system(size: 38))
                    .padding(14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(item.price)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Button(action: { bought = true }) {
                    Text(bought ? "✓ Bought" : "Buy")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                        .background(
                            Group {
                                if bought {
                                    Color.green.opacity(0.75)
                                } else {
                                    LinearGradient(gradient: Gradient(colors: [Color(hex: "3498db"), Color(hex: "2980b9")]), startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
                .disabled(bought)
            }
            .padding()
            .background(Color.white.opacity(0.09))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }
}

// MARK: - Profile Screen (New)

private struct ProfileScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero header
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .frame(height: 160)
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Player Name")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            HStack(spacing: 8) {
                                BadgeView(text: "PRO")
                                BadgeView(text: "GRINDER")
                            }
                        }
                        Spacer()
                        Button {
                            // Edit profile action
                        } label: {
                            Text("Edit Profile")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(16)
                }

                // Snapshot tiles (light summary)
                HStack(spacing: 12) {
                    InfoTile(iconName: "target", title: "FG%", value: "47%")
                    InfoTile(iconName: "checkmark.seal", title: "Best Streak", value: "12")
                    InfoTile(iconName: "sum", title: "Makes", value: "1,243")
                }

                // Mini shot chart placeholder
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Shot Chart (Mini)")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        NavigationLink(destination: StatsScreen()) {
                            Text("View in Stats")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .overlay(
                            Text("Shot chart preview")
                                .foregroundColor(.white.opacity(0.6))
                        )
                }

                // Highlights carousel placeholder
                VStack(alignment: .leading, spacing: 12) {
                    Text("Highlights")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5) { idx in
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.09))
                                    .frame(width: 200, height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .overlay(
                                        Text("Clip \(idx+1)")
                                            .foregroundColor(.white.opacity(0.7))
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Profile")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Stats Screen (New)

private struct StatsScreen: View {
    @State private var selected = 0
    private let tabs = ["Overview", "Shot Chart", "Sessions", "Skills", "Goals"]

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control style tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { idx, title in
                        Button {
                            selected = idx
                        } label: {
                            Text(title)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selected == idx ? Color.white.opacity(0.22) : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            Divider().background(Color.white.opacity(0.15))

            // Content placeholder per tab
            ScrollView {
                VStack(spacing: 16) {
                    switch selected {
                    case 0:
                        StatsOverviewSection()
                    case 1:
                        StatsShotChartSection()
                    case 2:
                        StatsSessionsSection()
                    case 3:
                        StatsSkillsSection()
                    default:
                        StatsGoalsSection()
                    }
                }
                .padding()
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Stats")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct StatsCard: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.09))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
        )
    }
}

private struct StatsOverviewSection: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatsCard(title: "FG%", subtitle: "47% this week (+3%)")
                StatsCard(title: "Makes", subtitle: "126 this week")
            }
            StatsCard(title: "Trend", subtitle: "Your 7-day moving average is improving")
        }
    }
}

private struct StatsShotChartSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Shot Chart")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .frame(height: 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )
                .overlay(Text("Interactive chart placeholder").foregroundColor(.white.opacity(0.6)))
        }
    }
}

private struct StatsSessionsSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<5) { idx in
                StatsCard(title: "Session #\(idx+1)", subtitle: "12/\(10+idx)/2025 • 55 makes • 45% FG")
            }
        }
    }
}

private struct StatsSkillsSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Skill Breakdown")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatsCard(title: "Catch & Shoot", subtitle: "52% • Up 2% this month")
            StatsCard(title: "Off Dribble", subtitle: "41% • Flat this month")
            StatsCard(title: "Free Throws", subtitle: "83% • Down 1% this month")
        }
    }
}

private struct StatsGoalsSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Goals")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatsCard(title: "500 Makes in December", subtitle: "Progress: 320/500 (64%)")
            StatsCard(title: "10-Day Streak", subtitle: "Current: 7 days")
        }
    }
}

// MARK: - Quests Screen (New)

private struct QuestsScreen: View {
    @Binding var totalXP: Int
    @Binding var totalGems: Int
    
    struct Quest: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let reward: String
        let xpReward: Int
        let gemsReward: Int
        let progress: Double // 0...1
        let category: Category
        enum Category { case daily, weekly, seasonal }
    }

    // Sample data; replace with model data later
    let quests: [Quest] = [
        .init(title: "50 Makes", description: "Make 50 shots today.", reward: "+50 XP", xpReward: 50, gemsReward: 0, progress: 0.64, category: .daily),
        .init(title: "Corner Specialist", description: "Make 10 corner threes.", reward: "+25 XP, +1 Gem", xpReward: 25, gemsReward: 1, progress: 0.3, category: .daily),
        .init(title: "Consistency", description: "3 sessions this week.", reward: "+150 XP", xpReward: 150, gemsReward: 0, progress: 0.33, category: .weekly),
        .init(title: "December Grind", description: "2,000 makes this month.", reward: "+500 XP, +3 Gems", xpReward: 500, gemsReward: 3, progress: 0.12, category: .seasonal)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Streak + Trophy Road header
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Streak: 7 days")
                                .foregroundColor(.white)
                                .font(.headline)
                            Text("Trophy Road")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.caption)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 10)
                                .overlay(
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(
                                                colors: [Color.red, Color(red: 0.8, green: 0, blue: 0)],
                                                startPoint: .leading, endPoint: .trailing))
                                            .frame(width: geo.size.width * 0.55)
                                    }
                                )
                        }
                        Spacer()
                        Button {
                            // Claim all action
                        } label: {
                            Text("Claim All")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.09))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.18), lineWidth: 1.5))

                // Daily
                QuestSection(title: "Daily Quests", quests: quests.filter { $0.category == .daily }, totalXP: $totalXP, totalGems: $totalGems)

                // Weekly
                QuestSection(title: "Weekly Quests", quests: quests.filter { $0.category == .weekly }, totalXP: $totalXP, totalGems: $totalGems)

                // Seasonal
                QuestSection(title: "Seasonal Quest", quests: quests.filter { $0.category == .seasonal }, totalXP: $totalXP, totalGems: $totalGems)
            }
            .padding()
        }
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .navigationTitle("Quests")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct QuestSection: View {
    let title: String
    let quests: [QuestsScreen.Quest]
    @Binding var totalXP: Int
    @Binding var totalGems: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    // See all action
                } label: {
                    Text("See All")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            ForEach(quests) { quest in
                QuestRow(quest: quest, totalXP: $totalXP, totalGems: $totalGems)
            }
        }
    }
}

private struct QuestRow: View {
    let quest: QuestsScreen.Quest
    @Binding var totalXP: Int
    @Binding var totalGems: Int
    @State private var claimed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(quest.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text(quest.reward)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 10)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: Gradient(colors: [Color(hex: "3498db"), Color(hex: "2980b9")]),
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * quest.progress, height: 10)
                }
                .frame(height: 10)
            }
            HStack {
                Button {
                    // Start quest action: deep link into session
                } label: {
                    Text("Start")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    if !claimed {
                        claimed = true
                        totalXP += quest.xpReward
                        totalGems += quest.gemsReward
                    }
                } label: {
                    Text(claimed ? "Claimed ✓" : "Claim")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(claimed ? Color.green.opacity(0.7) : Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .disabled(claimed)
            }
        }
        .padding()
        .background(Color.white.opacity(0.09))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1.5))
    }
}

// MARK: - Placeholder Screens (Teams, Ranks, Friends)

private struct ComingSoonView: View {
    let title: String
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "222b36")]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Coming Soon")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 4)
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )
                    .overlay(
                        Text("We're building this experience.")
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle(title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct TeamsScreen: View {
    var body: some View {
        ComingSoonView(title: "Teams")
    }
}

private struct RanksScreen: View {
    var body: some View {
        ComingSoonView(title: "Ranks")
    }
}

private struct FriendsScreen: View {
    var body: some View {
        ComingSoonView(title: "Friends")
    }
}

// MARK: - Preview

#Preview {
    HomeScreen()
}

#Preview("Skeleton") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            Text("Skeleton Preview")
                .foregroundColor(.white)
                .font(.headline)
            Text("Use this to verify the canvas renders.")
                .foregroundColor(.white.opacity(0.7))
                .font(.caption)
        }
    }
}
