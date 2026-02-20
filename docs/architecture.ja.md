# voice_search アーキテクチャ（現状）

英語版: `architecture.md`

## レイヤ構成

### 1. Core（純粋ロジック）
- モジュール: `VoiceSearchCore`
- 役割:
  - `TranscriptWord` / `SearchHit` などの共通モデル
  - 検索 (`TranscriptSearchService`)
  - 正規化 (`DefaultTokenNormalizer`)
  - 表示グルーピング (`TranscriptDisplayGrouper`)
  - TXT整形 (`TranscriptPlainTextFormatter`)
  - 文字起こしパイプライン (`TranscriptionPipeline`)
- 特徴:
  - UI / Speech framework 依存なし

### 2. Services（OS連携）
- 実装:
  - `SpeechAnalyzerTranscriptionService`
  - `SpeechURLTranscriptionService`
  - `HybridTranscriptionService`（内部比較やサービス選択用途）
- 役割:
  - Speech/AVFoundationと連携して `TranscriptionOutput` を生成
  - Coreで扱える `TimeInterval` ベースへ正規化
- 方針:
  - UIで選択された認識方式を尊重
  - ユーザー意図を変える自動フォールバックはしない

### 3. App（Presentation）
- モジュール: `VoiceSearchApp`
- 役割:
  - SwiftUI表示
  - ドロップ受付 / 再解析 / クリア
  - 再生制御 / シーク
  - 検索とハイライト表示
  - 用語登録と永続化
  - TXT/SRT書き出し

## 主なデータフロー
1. ドラッグ&ドロップでファイルURLを取得
2. `TranscriptionViewModel` が選択モードに応じたサービスを構築
3. `TranscriptionPipeline` 実行で `TranscriptWord[]` を取得
4. 表示用に `displayTranscript`（グルーピング）を生成
5. 検索時は `transcript` を対象に `SearchHit[]` を生成
6. ヒット/行選択で `startTime` へ seek して再生

## 主要な状態管理
- `TranscriptionViewModel`
  - 入力状態: `sourceURL`, `queue`, `isAnalyzing`
  - 再生状態: `isPlaying`, `currentTime`, `sourceDuration`, `scrubPosition`
  - 表示状態: `transcript`, `displayTranscript`, `searchHits`
  - 設定状態: `recognitionMode`, `txtPauseLineBreakThreshold`, `dictionaryEntries`

## エラー処理方針
- 失敗時は明示的にエラーメッセージを表示
- フォールバックではなく、選択モードの失敗理由を返す
- 失敗ログは書き込み可能な場合に保存し、パスを表示
