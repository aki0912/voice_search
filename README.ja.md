# voice_search

macOS向けの音声/動画文字起こし・キーワード検索・再生ジャンプアプリです。

英語版: `README.md`  
他ドキュメントも `*.ja.md` で日本語版を用意しています。

## できること
- 音声/動画ファイルのドラッグ&ドロップ取り込み
- `オンデバイス` / `サーバー` の認識方式切替（自動フォールバックなし）
- 検索（部分一致がデフォルトON）
- 検索結果から該当時刻へジャンプ再生
- 検索結果に文脈テキスト表示 + マッチ語ハイライト
- 音声/動画再生（再生/停止、シークバー）
- 文字起こしテキスト書き出し（`TXT` / `SRT`）
- TXT書き出し時の改行しきい値（秒）調整
- 用語登録（代表語 + 同義語）
- ひらがな検索とカタカナ語の相互マッチ

## 現在のソース管理方針
- 現在メンテしている実装は `VoiceSearch/VoiceSearch`（Xcodeプロジェクト側）です。
- `Package.swift` も `VoiceSearch/VoiceSearch` を参照します。
- `Sources/` と `Tests/` は旧構成で、現在は主要コードパスではありません。

## 現在の構成
- `VoiceSearch/VoiceSearch`: macOS SwiftUIアプリ本体
- `VoiceSearch/VoiceSearchTests`: package/Xcode 単体テスト
- `VoiceSearch/VoiceSearchUITests`: Xcode UIテスト
- `VoiceSearch/VoiceSearch.xcodeproj`: Xcodeプロジェクト
- `AppResources`: plist とアイコン資産
- `docs`: 設計・進捗・ロードマップ・配布手順

## 実行

推奨:
```bash
./scripts/run-app.sh
```

SwiftPMから直接実行:
```bash
swift run VoiceSearchApp
```

Xcodeで開く:
```bash
open VoiceSearch/VoiceSearch.xcodeproj
```
`VoiceSearch` スキームを実行します。

初回起動時に音声認識権限ダイアログが表示されます。  
拒否した場合は「システム設定 > プライバシーとセキュリティ > 音声認識」で `VoiceSearch` を許可してください。

## テスト
```bash
swift test
```

## CLIの現状
- 独立したCLIターゲットは現在の package 構成には含まれていません。
- `scripts/run-cli.sh` は互換用の旧スクリプトで、現行の推奨フローには含めていません。

## 参考ドキュメント
1. `docs/progress.ja.md`
2. `docs/roadmap.ja.md`
3. `docs/architecture.ja.md`
4. `docs/TDD.ja.md`
5. `docs/missing-features.ja.md`
6. `docs/release.ja.md`
