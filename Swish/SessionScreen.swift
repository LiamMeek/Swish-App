import SwiftUI

enum InferenceUIState { case idle, uploading, processing, result, uncertain }

struct SessionScreen: View {
    @ObservedObject var appGameVM: AppGameViewModel
    @ObservedObject var shotVM: ShotClassificationViewModel
    let apiClient: InferenceAPIClient

    @State var uiState: InferenceUIState = .idle
    @State var confidenceThreshold: Double
    @Binding var gatedCounter: Int

    init(appGameVM: AppGameViewModel, shotVM: ShotClassificationViewModel, apiClient: InferenceAPIClient, initialConfidence: Double, gatedCounter: Binding<Int>) {
        self.appGameVM = appGameVM
        self.shotVM = shotVM
        self.apiClient = apiClient
        self._gatedCounter = gatedCounter
        self._confidenceThreshold = State(initialValue: initialConfidence)
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeCameraContainer(cameraViewModel: HomeCameraViewModel(), gameViewModel: GameViewModel())
                .background(Color.black.opacity(0.8))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "34495e"), lineWidth: 3))
                .padding()

            HStack(spacing: 16) {
                Button {
                    guard uiState == .idle || uiState == .result || uiState == .uncertain else { return }
                    uiState = .uploading
                    Task {
                        let sampleData = Data(repeating: 0x00, count: 1024)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        uiState = .processing
                        do {
                            let response = try await apiClient.uploadVideo(data: sampleData)
                            let confidence = response.confidence ?? 0
                            let normalizedConf = max(0, min(1, confidence))
                            if response.status == "ok", let resultStr = response.result {
                                if normalizedConf >= confidenceThreshold {
                                    uiState = .result
                                    if resultStr == "made_shot" { gatedCounter += 1 }
                                } else {
                                    uiState = .uncertain
                                }
                            } else {
                                uiState = .uncertain
                            }
                        } catch {
                            uiState = .uncertain
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        switch uiState {
                        case .uploading:
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Uploading…").fontWeight(.bold)
                        case .processing:
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Processing…").fontWeight(.bold)
                        case .result:
                            Text("Classify Again").fontWeight(.bold)
                        case .uncertain:
                            Text("Couldn’t tell — try again").fontWeight(.bold)
                        case .idle:
                            Text("Classify Sample").fontWeight(.bold)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .disabled(uiState == .uploading || uiState == .processing)

                if let result = shotVM.lastResult {
                    HStack(spacing: 8) {
                        Text(result.isMake ? "Make ✅" : "Miss ❌")
                            .font(.footnote)
                            .foregroundColor(result.isMake ? .green : .red)
                        Text(String(format: "%.0f%%", result.confidence * 100))
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.9))
                        if result.confidence < confidenceThreshold {
                            Text("(below threshold)")
                                .font(.footnote)
                                .foregroundColor(.yellow)
                        }
                    }
                }

                if let err = shotVM.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.5))

            Divider().background(Color.white.opacity(0.25)).padding(.horizontal)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conf. threshold: " + String(format: "%.0f%%", confidenceThreshold * 100))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $confidenceThreshold, in: 0.5...0.95, step: 0.05)
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gated Makes")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(gatedCounter)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.5))
        }
        .navigationTitle("Session")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

struct SessionScreenHost: View {
    @ObservedObject var appGameVM: AppGameViewModel
    @ObservedObject var shotVM: ShotClassificationViewModel
    let apiClient: InferenceAPIClient
    let initialConfidence: Double
    @Binding var gatedCounter: Int

    var body: some View {
        SessionScreen(appGameVM: appGameVM,
                      shotVM: shotVM,
                      apiClient: apiClient,
                      initialConfidence: initialConfidence,
                      gatedCounter: $gatedCounter)
    }
}
