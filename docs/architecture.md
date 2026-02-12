# voice_search アーキテクチャ

## 3層構成
- Core (純粋層)
  - `VoiceSearchCore` モジュール
  - 依存: Swift標準ライブラリ
  - 役割: 文字列処理・検索・辞書・再生位置推定

- Service (OS連携層)
  - `SpeechAnalyzer`・`SFSpeech`・AVFoundation・ファイルIO
  - Coreから独立した`TranscriptionService`実装

- Presentation (UI層)
  - SwiftUI/Mac AppKit
  - ドラッグ&ドロップ受付、進捗表示、検索結果表示、再生制御

## データフロー
1. ドラッグ&ドロップで`file URL`取得
2. Transcription Service（`HybridTranscriptionService`）で分析ジョブ実行
3. 結果を`TranscriptWord`に変換
4. Core の `TranscriptSearchService` に渡して検索可能状態化
5. UIでヒット選択 → `startTime` でAVPlayer seek/play

## 重要な境界
- CoreはUI/AppleSpeech非依存
- Serviceは時間形式（`CMTime`/`TimeInterval`）をCoreで共通化した形へ変換
- 文字起こしイベントを順序保証した配列にまとめてUIへ渡す
- 辞書登録はUI層で保持し、検索時にCoreへ反映

## サービス切替レイヤ
- `VoiceSearchApp/Services/SpeechAnalyzerTranscriptionService.swift`
  - SpeechAnalyzer実装の有無と利用可否を管理
- `VoiceSearchApp/Services/HybridTranscriptionService.swift`
  - `SpeechAnalyzer`優先 or `SFSpeech`フォールバックの切替
- `VoiceSearchApp/Services/SpeechURLTranscriptionService.swift`
  - 現在の実運用バックアップ経路
