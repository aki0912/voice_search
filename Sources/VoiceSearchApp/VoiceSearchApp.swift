import SwiftUI

@main
struct VoiceSearchApp: App {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup("Voice Search") {
            MainView(viewModel: viewModel)
                .frame(minWidth: 940, minHeight: 760)
        }
        .windowResizability(.contentSize)
    }
}
