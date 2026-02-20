import SwiftUI
import AppKit
import Speech

private func requestSpeechRecognitionAuthorizationPrompt() {
    SFSpeechRecognizer.requestAuthorization { @Sendable _ in
        // No-op. This call exists to trigger the system permission prompt at app launch.
    }
}

@MainActor
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
        requestSpeechRecognitionAuthorizationIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.activateAndFocusWindow()
        }
    }

    private func requestSpeechRecognitionAuthorizationIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String
        guard !(usage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        requestSpeechRecognitionAuthorizationPrompt()
    }
}

@main
@MainActor
struct VoiceSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup(AppL10n.text("app.title")) {
            MainView(viewModel: viewModel)
                .frame(minWidth: 1020, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}
