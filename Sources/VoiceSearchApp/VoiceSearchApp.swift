import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
@MainActor
struct VoiceSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup("Voice Search") {
            MainView(viewModel: viewModel)
                .frame(minWidth: 940, minHeight: 760)
        }
        .windowResizability(.contentSize)
    }
}
