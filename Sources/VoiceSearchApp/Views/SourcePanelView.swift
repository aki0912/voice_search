import SwiftUI
import UniformTypeIdentifiers
import VoiceSearchCore

struct SourcePanelView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var isClearButtonHovered = false
    @State private var clearTooltipDelayTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                if viewModel.sourceURL == nil {
                    fileDropZone
                } else {
                    loadedFileInfo
                }

                if viewModel.isVideoSource, let player = viewModel.playbackPlayer {
                    PlayerView(player: player)
                        .frame(minHeight: 200, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if viewModel.playbackPlayer != nil {
                    PlaybackControlBar(viewModel: viewModel)
                }

                Spacer(minLength: 0)

                DictionarySectionView(viewModel: viewModel)
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - File Drop Zone

    @ViewBuilder
    private var fileDropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .frame(minHeight: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28))
                    Text("ここに音声/動画を\nドラッグ&ドロップ")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
            .onDrop(
                of: [UTType.fileURL, UTType.movie, UTType.audio],
                isTargeted: $viewModel.isDropTargeted
            ) { providers in
                Task { _ = await viewModel.handleDrop(providers: providers) }
                return true
            }
    }

    // MARK: - Loaded File Info

    @ViewBuilder
    private var loadedFileInfo: some View {
        if let url = viewModel.sourceURL {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        clearButton
                    }
                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.transcribe(url: url) }
                        } label: {
                            Label(
                                viewModel.isAnalyzing ? "解析中..." : "再解析",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isAnalyzing)
                    }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Clear Button

    @ViewBuilder
    private var clearButton: some View {
        Button(action: { viewModel.clearLoadedMedia() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(isClearButtonHovered ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            clearTooltipDelayTask?.cancel()
            if hovering {
                clearTooltipDelayTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        isClearButtonHovered = true
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.08)) {
                    isClearButtonHovered = false
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isClearButtonHovered {
                Text("ファイルをクリア")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .offset(y: -28)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .help("ファイルをクリアします")
        .disabled(viewModel.isAnalyzing)
    }
}
