# SpeechAnalyzer 連携方針

## 目的
`SpeechAnalyzer` を中心に、長尺音声や動画の文字起こしを行い、
時間情報付きワード列を取得する。

## 実装の基本方針
- `SpeechTranscriber` をモジュール化してインスタンス化
- `SpeechAnalyzer` を生成して `analyzeSequence(from:)` 系で投入
- 中間結果を受け取りつつ、最終結果を確定時に保存
- 各単語結果に `audioTimeRange` があれば `TranscriptWord` の時間を埋める

## 失敗時戦略
- ロケール/モデル未対応は明示エラーで早期通知
- モデル未インストール時は導入をガイド
- 処理中断時はジョブID単位で再開可能にする

## 注意事項
- AppleのAPIはOS/SDK差分が大きいため、サービス層を薄く保つ
- コアロジックへ渡す型は `String + TimeInterval` に正規化
