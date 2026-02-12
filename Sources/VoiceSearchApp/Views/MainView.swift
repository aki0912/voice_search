import SwiftUI
import UniformTypeIdentifiers
import VoiceSearchCore

struct MainView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Text("Voice Search")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text(viewModel.statusText)
                    .foregroundStyle(.secondary)

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
            .padding(.horizontal)

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
            }

            HStack {
                Button(action: { viewModel.playPause() }) {
                    Image(systemName: "playpause.fill")
                }
                .disabled(viewModel.sourceURL == nil)

                Text("\(formatTime(viewModel.currentTime))")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80, alignment: .leading)

                Spacer()
            }
            .padding(.horizontal)

            HStack {
                TextField("検索ワード", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
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

            List(Array(viewModel.transcript.enumerated()), id: \.element.id) { index, word in
                Button {
                    viewModel.jump(toWordAt: index)
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
                    .background(index == viewModel.highlightedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 220)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("用語登録（精度向上）")
                    .font(.headline)

                HStack {
                    TextField("登録語（例: クラウド）", text: $viewModel.newTermCanonical)
                        .textFieldStyle(.roundedBorder)
                    TextField("同義語（カンマ区切り）", text: $viewModel.newTermAliases)
                        .textFieldStyle(.roundedBorder)
                    Button("追加") {
                        viewModel.addDictionaryEntry()
                    }
                    .disabled(viewModel.newTermCanonical.isEmpty)
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
        .padding(.vertical)
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
