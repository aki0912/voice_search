# リリース手順（macOSアプリ配布）

このドキュメントは `VoiceSearch` を **Xcode Archive 後に GitHub Release で配布**するための手順メモです。

## 前提

- 配布対象は `VoiceSearch.app`
- Apple Developer Program 加入済み
- `Developer ID Application` で署名できる状態
- macOS に `xcrun` / `hdiutil` / `gh`（任意）が入っている

## 0. 先に共通変数を設定（この1箇所だけ更新）

```bash
export APP_NAME="VoiceSearch"
export VERSION="1.0.1"
export TAG="v${VERSION}"
export REPO_ROOT="~/Documents/Sources/voice_search"
export EXPORT_APP_PATH="/path/to/${APP_NAME}.app"
export DIST_DIR="${REPO_ROOT}/dist"
export DMG_PATH="~/Desktop/${APP_NAME}-${TAG}.dmg"
export AC_PROFILE="AC_PROFILE"
```

- 次の手順はすべて上記変数を利用する。
- 次回リリース時は `VERSION` だけ変更すれば、タグ名・DMG名・アップロード先の指定を使い回せる。

## 1. （初回のみ）notarytool プロファイルを作成

1. Apple ID でアプリ専用パスワードを作成（[appleid.apple.com](https://appleid.apple.com)）。
2. キーチェーンへ保存:

```bash
xcrun notarytool store-credentials "$AC_PROFILE" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

- `AC_PROFILE` は任意の名前で良い（例: `my-notary`）。

## 2. Xcode で Marketing Version を更新

1. Xcode で `VoiceSearch.xcodeproj` を開く
2. `TARGETS > VoiceSearch` を選択
3. `General` タブの `Identity` にある `Version`（Marketing Version）を `VERSION` と同じ値に更新（例: `1.0.1`）
4. 必要なら `Build`（Build Number, `CFBundleVersion`）も更新
5. `Product > Clean Build Folder` を実行してから次へ進む

## 3. Xcode で Archive / Distribute

1. `Product > Archive`
2. Organizer で `Distribute App`
3. `Developer ID` を選択して書き出し
4. 出力された `VoiceSearch.app` の場所を控える

## 4. DMG を作成

```bash
cd "$REPO_ROOT"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$EXPORT_APP_PATH" "$DIST_DIR/"
ln -s /Applications "$DIST_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
```

## 5. DMG を公証（Notarization）して貼り付け（Staple）

```bash
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$AC_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
```

## 6. GitHub Release を作成して配布

1. タグ作成:

```bash
cd "$REPO_ROOT"
git tag "$TAG"
git push origin "$TAG"
```

2. GitHub で `Releases > Draft a new release`
3. タグ `$TAG`（例: `v1.0.1`）を選択
4. リリースノートを記入
5. `DMG_PATH` のファイル（例: `VoiceSearch-v1.0.1.dmg`）を添付して Publish

CLI で添付する場合:

```bash
gh release upload "$TAG" "$DMG_PATH" --clobber
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
