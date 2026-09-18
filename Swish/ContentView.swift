import SwiftUI

struct ContentView: View {
    @EnvironmentObject var shootVM: ShootViewModel
    @StateObject private var gameViewModel: AppGameViewModel = AppGameViewModel()

    var body: some View {
        ZStack {
            // Background court
            CourtLines()
                .foregroundColor(.white)
                .padding()

            // Top bar
            VStack {
                GameTopBar(viewModel: shootVM)
                Spacer()
            }

            // Side menus
            HStack {
                LeftMenu()
                Spacer()
                RightMenu()
            }
            .padding()

            // Center content: camera container + controls
            VStack(spacing: 20) {
                Spacer()
                CameraContainer(viewModel: shootVM)
                    .padding(.horizontal)
                ZStack {
                    // Stats centered vertically between camera and bottom, aligned to leading
                    VStack {
                        Spacer()
                        StatsPanel(gameViewModel: gameViewModel)
                            .padding(.leading)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 12) {
                        GameModesButton()
                        StartButton(gameViewModel: gameViewModel)
                            .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// Keep the preview simple or use ContentView() if your scheme is iOS
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDisplayName("Main")
    }
}

import AVFoundation
import PhotosUI

// Minimal stub to satisfy compiler; replace with your real implementation
struct CameraPickerPlaceholder: View {
    var mediaTypes: [String]
    var onPick: (URL?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("CameraPicker placeholder")
                .font(.headline)
            Button("Simulate Pick") {
                onPick(nil)
            }
            Button("Close") {
                // No-op: parent should dismiss the sheet
                onPick(nil)
            }
        }
        .padding()
    }
}

