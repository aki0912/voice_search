# リリース手順（macOSアプリ配布）

このドキュメントは `VoiceSearch` を **Xcode Archive 後に GitHub Release で配布**するための手順メモです。

## 前提

- 配布対象は `VoiceSearch.app`
- Apple Developer Program 加入済み
- `Developer ID Application` で署名できる状態
- macOS に `xcrun` / `hdiutil` / `gh`（任意）が入っている

## 1. （初回のみ）notarytool プロファイルを作成

1. Apple ID でアプリ専用パスワードを作成（[appleid.apple.com](https://appleid.apple.com)）。
2. キーチェーンへ保存:

```bash
xcrun notarytool store-credentials "AC_PROFILE" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

- `"AC_PROFILE"` は任意の名前で良い（例: `my-notary`）。

## 2. Xcode で Marketing Version を更新

1. Xcode で `VoiceSearch.xcodeproj` を開く
2. `TARGETS > VoiceSearch` を選択
3. `General` タブの `Identity` にある `Version`（Marketing Version）を更新（例: `1.0.1`）
4. 必要なら `Build`（Build Number, `CFBundleVersion`）も更新
5. `Product > Clean Build Folder` を実行してから次へ進む

## 3. Xcode で Archive / Distribute

1. `Product > Archive`
2. Organizer で `Distribute App`
3. `Developer ID` を選択して書き出し
4. 出力された `VoiceSearch.app` の場所を控える

## 4. DMG を作成

```bash
cd /Users/akihiro/Documents/Sources/voice_search
rm -rf dist
mkdir -p dist
cp -R "/path/to/VoiceSearch.app" dist/
ln -s /Applications dist/Applications

hdiutil create \
  -volname "VoiceSearch" \
  -srcfolder dist \
  -ov \
  -format UDZO \
  "/Users/akihiro/Desktop/VoiceSearch-v1.0.0.dmg"
```

## 5. DMG を公証（Notarization）して貼り付け（Staple）

```bash
xcrun notarytool submit "/Users/akihiro/Desktop/VoiceSearch-v1.0.0.dmg" \
  --keychain-profile "AC_PROFILE" \
  --wait

xcrun stapler staple "/Users/akihiro/Desktop/VoiceSearch-v1.0.0.dmg"
xcrun stapler validate "/Users/akihiro/Desktop/VoiceSearch-v1.0.0.dmg"
```

## 6. GitHub Release を作成して配布

1. タグ作成:

```bash
cd /Users/akihiro/Documents/Sources/voice_search
git tag v1.0.0
git push origin v1.0.0
```

2. GitHub で `Releases > Draft a new release`
3. タグ `v1.0.0` を選択
4. リリースノートを記入
5. `VoiceSearch-v1.0.0.dmg` を添付して Publish

CLI で添付する場合:

```bash
gh release upload v1.0.0 "/Users/akihiro/Desktop/VoiceSearch-v1.0.0.dmg" --clobber
```

## 7. 最終確認

- 別環境で DMG ダウンロード
- アプリ起動確認
- 初回起動時の権限ダイアログ（音声認識）確認

## トラブルシュート

- GitHub Release で `.dmg` が選べない:
  - `*.app` や `.icon`（フォルダ）は添付不可。**`.dmg` ファイルのみ**添付する。
  - Finder ではなくドラッグ&ドロップ添付を試す。
  - 0バイトや未完成ファイルでないか `ls -lh` で確認する。
