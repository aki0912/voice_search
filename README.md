# voice_search

macOS向けのローカル音声/動画文字起こし・検索・再生ジャンプアプリ。

## ゴール
- 音声/動画ファイルをドラッグ&ドロップで取り込み
- URLベース文字起こし
- 単語/フレーズ検索
- 検索結果の位置に再生をジャンプ
- 単語登録（辞書）で文字起こし補正（精度向上）

## 構成
- `Sources/VoiceSearchCore`
  - 検索や正規化を担うコア（TDD先行）
- `Sources/VoiceSearchApp`
  - macOS SwiftUIアプリ本体
  - ドラッグ&ドロップ、再生、辞書管理
- `Tests/VoiceSearchCoreTests`
  - コアロジックと文字起こしパイプラインのテスト

## 実行
```bash
swift run VoiceSearchApp
```

## 開発方針
- コアはTDDで固定
- UI/OS依存はサービス層（`TranscriptionService`）経由で分離
- 文字起こしエンジンは将来差し替え可能な構成

## 今後の改善
- `SpeechAnalyzer` API実装アダプタを追加して精度向上
- 長尺ファイルの進捗表示と再試行改善

## まず読む順
1. `docs/progress.md`
2. `docs/roadmap.md`
3. `docs/architecture.md`
4. `docs/TDD.md`
