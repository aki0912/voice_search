# Voice Search 改善項目（2026-02-15）

## 方針
- ユーザーが選択した認識方式を優先し、**自動フォールバックはしない**。
- 処理失敗時は、単に失敗と出すのではなく、**原因を含めたエラー**を表示する。

## 優先度高（先に対応）
- [x] `SpeechAnalyzer` 経路で動画（`mov/mp4`）入力時に前処理不足。
  - `AudioInputPreparer` を追加し、`SpeechAnalyzer` と `SpeechURL` で共通利用。
  - 動画/多重トラック時は m4a 抽出を行い、候補トラックを優先順で試行。
- [x] `AssetInventory` の locale 予約/解放管理が不安定。
  - 既存予約の一括解除を廃止。
  - 対象 locale のみ reserve し、成功時/失敗時ともに release する実装へ変更。

## 優先度中（品質と運用）
- [x] `VoiceSearchApp` 実行形態ごとの `Info.plist` 取り込み方式を統一。
  - `VoiceSearchCLI` と同じく、実行ファイルに `__info_plist` を埋め込む方式に統一。
- [x] `SpeechURLTranscriptionService` の deprecated / sendable 警告を段階的に解消。
  - 音声抽出処理を `AudioInputPreparer` に共通化し、`load(...)` ベースで処理。
  - sendable/concurrency 境界の整理を含む構造に統一。

## 優先度低（UX改善）
- [x] 解析失敗時のエラー表示をさらに構造化。
  - `TranscriptionFailureMessageFormatter` を導入し、「失敗要因」「対処方法（設定/権限/形式）」を分けて表示。
- [ ] 失敗時の UI リセット（再生状態・ハイライト）を一貫化。

## 今回反映済み
- [x] `HybridTranscriptionService` の暗黙フォールバックを廃止。
- [x] 解析失敗時に、原因付きのエラーメッセージを表示するように変更。
- [x] オンデバイス選択時に利用不可なら自動切り替えせず、明示的エラーにする。
- [x] 音声入力前処理ロジックを共通化し、Analyzer/URL 両経路の挙動を統一。
- [x] `AudioInputPreparer` の優先順ルールに対する回帰テストを追加。
