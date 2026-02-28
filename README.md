# voice_search

A macOS app for audio/video transcription, keyword search, and playback jump.

Japanese version: `README.ja.md`  
Japanese variants of project docs are available with the `.ja.md` suffix.

## Features
- Drag-and-drop import for audio/video files
- Recognition mode switch: `On-device` / `Server` (no automatic fallback)
- Search with partial-match mode (enabled by default)
- Jump playback to matched timestamps
- Search result context display + matched-term highlight
- Audio/video playback (play/pause, seek bar)
- Transcript export (`TXT` / `SRT`)
- Configurable TXT line-break threshold (seconds)
- Custom dictionary entries (canonical term + aliases)
- Cross-match between Hiragana queries and Katakana words

## Current Source Of Truth
- The actively maintained app source is under `VoiceSearch/VoiceSearch` (Xcode project).
- Swift Package Manager (`Package.swift`) also points to `VoiceSearch/VoiceSearch`.
- Legacy `Sources/` and `Tests/` directories are no longer the primary code path.

## Project Structure (Current)
- `VoiceSearch/VoiceSearch`: macOS SwiftUI app source
- `VoiceSearch/VoiceSearchTests`: package/Xcode unit tests
- `VoiceSearch/VoiceSearchUITests`: Xcode UI tests
- `VoiceSearch/VoiceSearch.xcodeproj`: Xcode project
- `AppResources`: plist files and icon assets
- `docs`: architecture/progress/roadmap/release docs

## Run

Recommended:
```bash
./scripts/run-app.sh
```

Direct package run:
```bash
swift run VoiceSearchApp
```

Xcode:
```bash
open VoiceSearch/VoiceSearch.xcodeproj
```
Then run the `VoiceSearch` scheme.

On first launch, macOS asks for speech recognition permission.  
If denied, enable `VoiceSearch` in:
`System Settings > Privacy & Security > Speech Recognition`.

## Test
```bash
swift test
```

## CLI Status
- A standalone CLI target is currently not part of the active package setup.
- `scripts/run-cli.sh` is retained as a legacy helper and is not part of the current recommended workflow.

## Related Docs
1. `docs/progress.md`
2. `docs/roadmap.md`
3. `docs/architecture.md`
4. `docs/TDD.md`
5. `docs/missing-features.md`
6. `docs/release.ja.md`
