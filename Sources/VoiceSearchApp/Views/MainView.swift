import SwiftUI
import UniformTypeIdentifiers
import VoiceSearchCore

struct MainView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var newTermCanonical: String = ""
    @State private var newTermAliases: String = ""
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case search
        case canonical
        case aliases
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                Text("Voice Search")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Text(viewModel.statusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                    VStack(spacing: 6) {
                        Text("認識方式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Picker("", selection: $viewModel.recognitionMode) {
                            ForEach(TranscriptionViewModel.RecognitionMode.allCases) { mode in
                                Text(mode.displayLabel).tag(mode)
                            }
                        }
                        .frame(maxWidth: 320)
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(viewModel.isAnalyzing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(width: 420)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .center)

                if viewModel.isAnalyzing {
                    VStack(spacing: 6) {
                        ProgressView(value: viewModel.analysisProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text("解析進捗（推定）: \(Int((viewModel.analysisProgress * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 420)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.isDropTargeted ? Color.accentColor : Color.secondary, lineWidth: 2)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .overlay(
                        VStack {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 34))
                            Text("ここに音声/動画をドラッグ&ドロップ")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                    )
                    .onDrop(of: [UTType.fileURL, UTType.movie, UTType.audio], isTargeted: $viewModel.isDropTargeted) { providers in
                        Task {
                            _ = await viewModel.handleDrop(providers: providers)
                        }
                        return true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
                .layoutPriority(2)

                if let url = viewModel.sourceURL {
                    HStack {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(viewModel.isAnalyzing ? "解析中..." : "再解析") {
                        Task {
                            await viewModel.transcribe(url: url)
                        }
                    }
                    .disabled(viewModel.isAnalyzing)
                    }
                    .padding(.horizontal)
                }

                if viewModel.isVideoSource, let playbackPlayer = viewModel.playbackPlayer {
                    PlayerView(player: playbackPlayer)
                    .frame(minHeight: 220, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

            if !viewModel.isVideoSource, viewModel.playbackPlayer != nil {
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        Button(action: { viewModel.playPause() }) {
                            Label("再生 / 停止", systemImage: "playpause.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(viewModel.sourceURL == nil)
                        Spacer()
                    }

                    HStack {
                        Text("\(formatTime(viewModel.currentTime))")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80, alignment: .leading)

                        Spacer()

                        Button("テキストを書き出し") {
                            viewModel.exportTranscriptToFile()
                        }
                        .disabled(viewModel.transcript.isEmpty || viewModel.isAnalyzing)
                    }
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Button(action: { viewModel.playPause() }) {
                        Image(systemName: "playpause.fill")
                    }
                    .disabled(viewModel.sourceURL == nil)

                    Text("\(formatTime(viewModel.currentTime))")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .leading)

                    Button("テキストを書き出し") {
                        viewModel.exportTranscriptToFile()
                    }
                    .disabled(viewModel.transcript.isEmpty || viewModel.isAnalyzing)

                    Spacer()
                }
                .padding(.horizontal)
            }

            if viewModel.playbackPlayer != nil, viewModel.sourceDuration > 0 {
                HStack(spacing: 10) {
                    Text(formatTime(viewModel.scrubPosition))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 58, alignment: .leading)

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

                    Text(formatTime(viewModel.sourceDuration))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.horizontal)
            }

            HStack {
                TextField("検索ワード", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .search)
                    .onSubmit {
                        viewModel.performSearch()
                    }
                    .onChange(of: viewModel.query) { _ in
                        viewModel.performSearch()
                    }

                Toggle("部分一致", isOn: $viewModel.isContainsMatchMode)
                    .toggleStyle(.switch)
                    .onChange(of: viewModel.isContainsMatchMode) { _ in
                        viewModel.performSearch()
                    }

                Button("検索") {
                    viewModel.performSearch()
                }
                .disabled(viewModel.query.isEmpty)
                }
                .padding(.horizontal)

                if !viewModel.searchHits.isEmpty {
                    List(viewModel.searchHits) { hit in
                    Button {
                        viewModel.jump(to: hit)
                    } label: {
                        HStack {
                            Text(hit.displayText)
                                .lineLimit(1)
                            Spacer()
                            Text("\(formatTime(hit.startTime))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    }
                    .frame(minHeight: 140)
                }

                Divider()

                ScrollViewReader { proxy in
                    List(Array(viewModel.displayTranscript.enumerated()), id: \.element.id) { index, word in
                    Button {
                        viewModel.jump(toDisplayWordAt: index)
                    } label: {
                        HStack {
                            Text(formatTime(word.startTime))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 70, alignment: .leading)
                            Text(word.text)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == viewModel.displayHighlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                        .cornerRadius(6)
                    }
                    .id(word.id)
                    .buttonStyle(.plain)
                    }
                    .frame(minHeight: 220)
                    .onChange(of: viewModel.displayHighlightedIndex) { newIndex in
                    guard focusedField == nil else { return }
                    guard let newIndex, viewModel.displayTranscript.indices.contains(newIndex) else { return }
                    let targetID = viewModel.displayTranscript[newIndex].id
                    DispatchQueue.main.async {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                Text("用語登録（精度向上）")
                    .font(.headline)

                HStack {
                    TextField("登録語（例: クラウド）", text: $newTermCanonical)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .canonical)
                    TextField("同義語（カンマ区切り）", text: $newTermAliases)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .aliases)
                    Button("追加") {
                        let added = viewModel.addDictionaryEntry(
                            canonical: newTermCanonical,
                            aliasesText: newTermAliases
                        )
                        if added {
                            newTermCanonical = ""
                            newTermAliases = ""
                        }
                    }
                    .disabled(newTermCanonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                List(viewModel.dictionaryEntries, id: \.canonical) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.canonical)
                                .font(.headline)
                            if !entry.aliases.isEmpty {
                                Text(entry.aliases.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("削除") {
                            viewModel.removeDictionaryEntry(entry)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(minHeight: 120)
                }
                .padding(.horizontal)
            }
            .padding(.top, max(36, proxy.safeAreaInsets.top + 28))
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(viewModel: TranscriptionViewModel())
            .frame(width: 900, height: 760)
    }
}
