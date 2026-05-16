import SwiftUI

/// Top-level navigation: routes between connection setup and the live stream
/// view based on the `StreamController` state. Kept lightweight so it can
/// be unit-tested as a pure transform from state to screen.
public struct RootView: View {
    @StateObject private var controller = StreamController()

    public init() {}

    public var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.connectionState {
        case .connected:
            StreamingScreen(controller: controller)
                .transition(.opacity.combined(with: .scale(scale: 1.01)))
        default:
            ConnectionScreen(controller: controller)
                .transition(.opacity)
        }
    }
}
