# SpeechAnalyzer 連携メモ（現状）

英語版: `speech-analyzer-integration.md`

## 現在の位置づけ
- `オンデバイス` モードでは `SpeechAnalyzerTranscriptionService` を使用
- `サーバー` モードでは `SpeechURLTranscriptionService` を使用
- ユーザー選択モードを優先し、自動フォールバックで挙動を変えない

## 入出力
- 入力: `TranscriptionRequest`
  - `sourceURL`
  - `contextualStrings`（用語登録ベース）
  - `progressHandler`
- 出力: `TranscriptionOutput`
  - `words: [TranscriptWord]`
  - `duration`
  - `diagnostics`

## 実装上の要点
- 文字起こし結果は `TranscriptWord(startTime/endTime)` に統一
- 動画入力時は音声トラックを抽出して認識処理へ渡す
- 部分結果を受け取りつつ、最終結果確定時に整列して返す
- 進捗は推定値と実進捗を統合してUIへ通知

## 認可・権限
- `NSSpeechRecognitionUsageDescription` が必須
- 実行形態（`.app` 実行か否か）により認可ダイアログ挙動が異なる
- 未認可時は明示エラーを返す

## 既知の注意点
- OS/SDK差分で利用可否が変わるため、`isAvailable` 判定を前提にする
- 入力ファイルに有効な音声トラックがない場合はエラーにする
- 失敗時は原因をユーザーに表示し、必要に応じてログを保存する
