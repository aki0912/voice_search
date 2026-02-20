import SwiftUI
import VoiceSearchCore

struct MainView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            Divider()
            HSplitView {
                SourcePanelView(viewModel: viewModel)
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 500)

                TranscriptPanelView(viewModel: viewModel)
                    .frame(minWidth: 400, idealWidth: 600)
            }
        }
    }

    // MARK: - Header Bar

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 16) {
            Text(AppL10n.text("app.title"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            VStack(spacing: 2) {
                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if viewModel.isAnalyzing {
                    ProgressView(value: viewModel.analysisProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Text(AppL10n.text("header.recognitionMode"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.recognitionMode) {
                    ForEach(TranscriptionViewModel.RecognitionMode.allCases) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .fixedSize()
            }
            .disabled(viewModel.isAnalyzing)

            HStack(spacing: 8) {
                Text(AppL10n.text("header.recognitionLanguage"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.recognitionLanguage) {
                    ForEach(TranscriptionViewModel.RecognitionLanguage.allCases) { language in
                        Text(language.displayLabel).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.regular)
                .frame(width: 170)
            }
            .disabled(viewModel.isAnalyzing)
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(viewModel: TranscriptionViewModel())
            .frame(width: 1020, height: 640)
    }
}
