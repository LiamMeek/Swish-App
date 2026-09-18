import Foundation
import SwiftUI
import Combine

final class ShotClassificationViewModel: ObservableObject {
    @Published var lastResult: ShotPredictionResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var api: ShotClassifierAPI

    // Replace with your live ngrok URL printed by Colab, ensure trailing slash
    nonisolated(unsafe) static let defaultBaseURL: String = "https://0a8263a91c28.ngrok-free.app/"

    init(apiBaseURL: String = ShotClassificationViewModel.defaultBaseURL) {
        self.api = ShotClassifierAPI(baseURLString: apiBaseURL)
    }

    func classifySampleVideoFromBundle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = Bundle.main.url(forResource: "sample_shot", withExtension: "mp4") else {
                errorMessage = "Missing sample_shot.mp4 in bundle."
                return
            }
            let data = try Data(contentsOf: url)
            let result = try await api.predict(videoData: data, fileName: "sample_shot.mp4")
            lastResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func classify(videoData: Data) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.predict(videoData: videoData, fileName: "shot.mp4")
            lastResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

