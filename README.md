# voice_search

macOS向けの音声/動画文字起こし・検索・再生ジャンプアプリです。

## できること
- 音声/動画ファイルのドラッグ&ドロップ取り込み
- `オンデバイス` / `サーバー` の認識方式切替（自動フォールバックなし）
- 検索（部分一致がデフォルトON）
- 検索結果から該当時刻へジャンプ再生
- 検索結果に文脈テキスト表示 + マッチ語ハイライト
- 音声/動画再生（再生/停止ボタン、シークバー）
- 文字起こしテキスト書き出し（TXT / SRT）
- TXT書き出し時の改行しきい値（秒）をUIから調整
- 用語登録（登録語/同義語）
- ひらがな検索とカタカナ語の相互マッチ

## 画面の挙動
- メディア未読み込み時はドラッグ&ドロップ領域を表示
- 読み込み後はドロップ領域を隠し、ファイル情報カードを表示
- ファイル名の横に `×`（クリア）ボタン
- クリア後は初期状態に戻り、ドロップ領域を再表示

## 構成
- `Sources/VoiceSearchCore`: 正規化・検索・フォーマッタなどコア
- `Sources/VoiceSearchApp`: macOS SwiftUIアプリ本体
- `Sources/VoiceSearchCLI`: UIなし実行用CLI
- `Tests/VoiceSearchCoreTests`: コアロジックのテスト
- `Tests/VoiceSearchAppTests`: ViewModel周辺のテスト
- `Tests/VoiceSearchServicesTests`: 認識サービス周辺のテスト

## 実行（推奨）
```bash
./scripts/run-app.sh
```

初回起動時に音声認識権限ダイアログが表示されます。拒否した場合は「システム設定 > プライバシーとセキュリティ > 音声認識」で `VoiceSearchApp` を許可してください。

開発用の直接実行:
```bash
swift run VoiceSearchApp
```

## CLI（UIなし）
```bash
./scripts/run-cli.sh --input sample2.m4a --mode diagnose --output sample2_diagnostics.txt
```

モード:
- `diagnose`: オンデバイス認識とサーバー認識を両方実行して比較
- `on-device`: オンデバイスのみ
- `server`: サーバーのみ

## スクリーンショットをREADMEに追加する方法
1. 画像を `docs/images/` に置く（例: `docs/images/main.png`）。
2. `README.md` にMarkdownで追記する。

```md
![メイン画面](docs/images/main.png)
```

3. 画像サイズを固定したい場合はHTMLタグを使う。

```html
<img src="docs/images/main.png" alt="メイン画面" width="960" />
```

ポイント:
- パスはREADMEからの相対パスで書く
- ファイル名は英数字とハイフン推奨（例: `search-result-highlight.png`）
- 画像ファイルもREADMEと一緒にコミットする

## 開発メモ
- コアロジックはTDD中心
- 認識機能は `TranscriptionService` 経由で差し替え可能

## 参考ドキュメント
1. `docs/progress.md`
2. `docs/roadmap.md`
3. `docs/architecture.md`
4. `docs/TDD.md`
