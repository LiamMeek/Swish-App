import SwiftUI
import AVKit
import AVFoundation

struct VideoLoadingView: View {
    let videoFileName: String
    let videoFileExtension: String
    let onFinished: () -> Void
    
    @State private var player: AVPlayer? = nil
    @State private var observerAdded = false
    @State private var fileNotFound = false
    
    init(videoFileName: String = "LoadingIntro", videoFileExtension: String = "mov", onFinished: @escaping () -> Void) {
        self.videoFileName = videoFileName
        self.videoFileExtension = videoFileExtension
        self.onFinished = onFinished
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .overlay(Color.clear) // hide controls
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            guard let url = Bundle.main.url(forResource: videoFileName, withExtension: videoFileExtension) else {
                fileNotFound = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onFinished()
                }
                return
            }
            
            player = AVPlayer(url: url)
            player?.isMuted = true
            
            if !observerAdded {
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: player?.currentItem,
                                                       queue: .main) { _ in
                    onFinished()
                }
                observerAdded = true
            }
            
            player?.play()
        }
        .onDisappear {
            if observerAdded {
                NotificationCenter.default.removeObserver(self,
                                                          name: .AVPlayerItemDidPlayToEndTime,
                                                          object: player?.currentItem)
                observerAdded = false
            }
            player?.pause()
            player = nil
        }
    }
}
