import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private func activateAndFocusWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) ?? NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activateAndFocusWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.activateAndFocusWindow()
        }
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
