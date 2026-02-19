import SwiftUI
import VoiceSearchCore

struct TranscriptPanelView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            if !viewModel.searchHits.isEmpty {
                VSplitView {
                    searchResultsPanel
                        .frame(minHeight: 80, idealHeight: 180)

                    transcriptPanel
                        .frame(minHeight: 120)
                }
            } else {
                transcriptPanel
            }

            if viewModel.sourceURL != nil {
                Divider()
                exportBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                TextField("検索ワード", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit { viewModel.performSearch() }
                    .onChange(of: viewModel.query) { _ in
                        viewModel.performSearch()
                    }
                if !viewModel.query.isEmpty {
                    Button(action: { viewModel.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Toggle("部分一致", isOn: $viewModel.isContainsMatchMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: viewModel.isContainsMatchMode) { _ in
                    viewModel.performSearch()
                }
        }
    }

    // MARK: - Search Results Panel

    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("検索結果", systemImage: "magnifyingglass")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.searchHits.count)件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            List(viewModel.searchHits) { hit in
                Button {
                    viewModel.jump(to: hit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        highlightedContextText(for: hit)
                            .lineLimit(2)
                        HStack {
                            Spacer()
                            Text(formatTime(hit.startTime))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("文字起こし", systemImage: "text.word.spacing")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if !viewModel.displayTranscript.isEmpty {
                    Text("\(viewModel.displayTranscript.count)件")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            transcriptList
        }
    }

    // MARK: - Transcript List

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            List(
                Array(viewModel.displayTranscript.enumerated()),
                id: \.element.id
            ) { index, word in
                Button {
                    viewModel.jump(toDisplayWordAt: index)
                } label: {
                    HStack {
                        Text(formatTime(word.startTime))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text(word.text)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        index == viewModel.displayHighlightedIndex
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                    )
                    .cornerRadius(4)
                }
                .id(word.id)
                .buttonStyle(.plain)
            }
            .onChange(of: viewModel.displayHighlightedIndex) { newIndex in
                guard !isSearchFieldFocused else { return }
                guard let newIndex,
                      viewModel.displayTranscript.indices.contains(newIndex) else { return }
                let targetID = viewModel.displayTranscript[newIndex].id
                DispatchQueue.main.async {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    // MARK: - Export Bar

    private var exportBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Text("TXT改行閾値")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(
                "0.10",
                value: $viewModel.txtPauseLineBreakThreshold,
                formatter: Self.thresholdFormatter
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .frame(width: 78)
            .multilineTextAlignment(.trailing)
            .onSubmit {
                viewModel.updateTxtPauseLineBreakThreshold(viewModel.txtPauseLineBreakThreshold)
            }
            .onChange(of: viewModel.txtPauseLineBreakThreshold) { newValue in
                viewModel.updateTxtPauseLineBreakThreshold(newValue)
            }
            Text("秒")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                viewModel.exportTranscriptToFile()
            } label: {
                Label("テキスト出力", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(minWidth: 132)
            .disabled(viewModel.transcript.isEmpty || viewModel.isAnalyzing)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "--:--" }
        let totalSeconds = Int(time.rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func highlightedContextText(for hit: SearchHit) -> Text {
        let context = viewModel.displayContextText(for: hit)
        let target = hit.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty,
              let range = context.range(
                  of: target,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return Text(context)
        }
        let prefix = String(context[..<range.lowerBound])
        let matched = String(context[range])
        let suffix = String(context[range.upperBound...])
        return Text(prefix)
            + Text(matched).foregroundColor(.red).fontWeight(.semibold)
            + Text(suffix)
    }

    private static var thresholdFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
