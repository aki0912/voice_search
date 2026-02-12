# voice_search 開発方針・進捗メモ

## 方針
- macOSアプリとして、音声/動画ファイルのドラッグ&ドロップで文字起こしし、検索して再生をジャンプ。
- 単語辞書で抽出精度を補正。
- コアはTDDで固定し、OS/API依存層は薄く分離。

## 現在の実装（2026-02-12）
- SwiftPMプロジェクトを以下の2ターゲットに拡張
  - `VoiceSearchCore`（テスト可能コア）
  - `VoiceSearchApp`（macOS SwiftUIアプリ）

### コア側（TDD完了）
- `Sources/VoiceSearchCore/VoiceSearchCore.swift`
  - `TranscriptWord`
  - `TranscriptSearchService`
  - `UserDictionary`
  - `PlaybackLocator`
- `Sources/VoiceSearchCore/TranscriptionService.swift`
  - `TranscriptionService`（インターフェース）
  - `TranscriptionPipeline`
  - `TranscriptWordNormalizer`
  - `TranscriptionOutput`

### テスト
- `Tests/VoiceSearchCoreTests/VoiceSearchCoreTests.swift`
- `Tests/VoiceSearchCoreTests/TranscriptionServiceTests.swift`

### UIアプリ
- `Sources/VoiceSearchApp/Services/SpeechURLTranscriptionService.swift`
  - URLベース文字起こし（現状 `SFSpeechURLRecognitionRequest`）
- `Sources/VoiceSearchApp/ViewModels/TranscriptionViewModel.swift`
  - ドロップ受け取り、解析、検索、シーク、辞書保存を担当
- `Sources/VoiceSearchApp/Views/MainView.swift`
  - ドラッグ&ドロップ、検索UI、検索ヒット再生、字幕一覧、辞書登録UI
- `Sources/VoiceSearchApp/Utils/ItemProvider+URL.swift`
  - NSItemProvider→URL変換
- `Sources/VoiceSearchApp/VoiceSearchApp.swift`
  - macOS App entry

## 実行
- `swift run VoiceSearchApp`

## 次の改善（アプリ実運用化）
- `SpeechAnalyzer` API 実装を追加し精度改善
- 長尺ファイル向け進捗表示とキャンセル対応
- 処理失敗時のリトライ/再解析導線
- UIテスト追加（検索・辞書・シーク）
