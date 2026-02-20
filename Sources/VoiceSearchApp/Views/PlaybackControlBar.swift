import SwiftUI
import VoiceSearchCore

struct PlaybackControlBar: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: { viewModel.playPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isPlaying ? .orange : .accentColor)
                    .disabled(viewModel.sourceURL == nil)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isPlaying ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(
                            viewModel.isPlaying
                                ? AppL10n.text("playback.playing")
                                : AppL10n.text("playback.stopped")
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.sourceDuration))")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if viewModel.sourceDuration > 0 {
                    Slider(
                        value: Binding(
                            get: { viewModel.scrubPosition },
                            set: { viewModel.updateScrubPosition($0) }
                        ),
                        in: 0...viewModel.sourceDuration,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                viewModel.beginScrubbing()
                            } else {
                                viewModel.endScrubbing()
                            }
                        }
                    )
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "--:--" }
        let totalSeconds = Int(time.rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
