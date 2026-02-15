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

## 実行（推奨）
```bash
./scripts/run-app.sh
```

初回起動時に、音声認識の権限ダイアログが表示されます。  
拒否した場合は「システム設定 > プライバシーとセキュリティ > 音声認識」で `VoiceSearchApp` を許可してください。

`swift run VoiceSearchApp` は開発用の直接実行で、権限ダイアログの検証は `.app` 起動（上記スクリプト）で行ってください。

アプリUI上で、認識方式を `オンデバイス` / `サーバー` で切り替えできます（フォールバックは行いません）。
`オンデバイス` は macOS 26 以降で `SpeechAnalyzer + SpeechTranscriber` を優先して利用します。

## CLI（UIなし）
`sample2.m4a` のような音声をUIなしで処理して、オンデバイス認識の診断レポートをテキスト出力できます。

```bash
./scripts/run-cli.sh --input sample2.m4a --mode diagnose --output sample2_diagnostics.txt
```

注意:
- 実行結果レポートの `## Runtime` に `authorizationStatus(before/after)` と `bundlePath` が出ます。権限判定の切り分けに使ってください。
- `authorizationStatus` が `notDetermined` のままでも、ファイル文字起こし自体は実行される環境があります。

指定可能なモード:
- `diagnose` : オンデバイス認識とサーバー認識を両方実行して比較
- `on-device` : オンデバイスのみ
- `server` : サーバーのみ

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
