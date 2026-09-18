import SwiftUI

struct RootView: View {
    @State private var showLoader = true

    var body: some View {
        ZStack {
            if !showLoader {
                HomeScreen()
                    .transition(.opacity)
            }
            if showLoader {
                SwishLoadingView(duration: 2.0) {
                    withAnimation(.easeInOut(duration: 0.35)) { showLoader = false }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showLoader)
        .onAppear {
            // Safety fallback in case completion isn't called
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                if showLoader { withAnimation(.easeInOut(duration: 0.35)) { showLoader = false } }
            }
        }
    }
}

#Preview {
    RootView()
}
