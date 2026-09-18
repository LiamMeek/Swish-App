import SwiftUI

struct ScreenWithLoader<Content: View>: View {
    var duration: TimeInterval = 1.8
    @ViewBuilder var content: () -> Content

    @State private var showLoader = true

    var body: some View {
        ZStack {
            if !showLoader {
                content()
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
            }
            if showLoader {
                SwishLoadingView(duration: duration) {
                    withAnimation(.easeInOut(duration: 0.35)) { showLoader = false }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showLoader)
        .onAppear {
            // Safety fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.6) {
                if showLoader { withAnimation(.easeInOut(duration: 0.35)) { showLoader = false } }
            }
        }
    }
}

#Preview {
    ScreenWithLoader {
        Color.blue
            .overlay(Text("Destination").foregroundColor(.white))
            .ignoresSafeArea()
    }
}
