#if STUBS
// Temporary stubs to satisfy references from HomeScreen.swift. Replace with real implementations.
import SwiftUI
import Combine

// MARK: - View Models

final class GameViewModel: ObservableObject {
    @Published var isTracking: Bool = false
    @Published var madeShots: Int = 0
    @Published var missedShots: Int = 0
    var totalShots: Int { madeShots + missedShots }
    var fieldGoalPercentage: Int {
        let total = totalShots
        guard total > 0 else { return 0 }
        return Int((Double(madeShots) / Double(total)) * 100.0)
    }
    func startGame() {}
    func backToMenu() {}
}

final class AppGameViewModel: ObservableObject {
    @Published var madeShots: Int = 0
    @Published var missedShots: Int = 0
    var totalShots: Int { madeShots + missedShots }
    var fieldGoalPercentage: Int {
        let total = totalShots
        guard total > 0 else { return 0 }
        return Int((Double(madeShots) / Double(total)) * 100.0)
    }
}

final class CameraViewModel: ObservableObject {}

struct ShotClassificationResult {
    let isMake: Bool
    let confidence: Double
}

@MainActor
final class ShotClassificationViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var lastResult: ShotClassificationResult? = nil
    @Published var errorMessage: String? = nil
    func classifySampleVideoFromBundle() async {
        isLoading = true
        defer { isLoading = false }
        // Simulate a quick classification
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Provide a dummy result
        lastResult = ShotClassificationResult(isMake: Bool.random(), confidence: Double.random(in: 0.6...0.98))
        errorMessage = nil
    }
}

// MARK: - Views

struct ContentView: View {
    var body: some View {
        Text("ContentView placeholder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
    }
}

struct VideoLoadingView: View {
    let videoFileName: String
    let videoFileExtension: String
    let onFinished: () -> Void

    @State private var done = false

    var body: some View {
        ZStack {
            // Placeholder visual while video would play
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.white.opacity(0.9))
                        Text("Intro…")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                )
                .padding()
        }
        .task {
            // Simulate the intro video finishing
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onFinished()
        }
    }
}

#endif

