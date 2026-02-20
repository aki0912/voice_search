# voice_search

A macOS app for audio/video transcription, search, and playback jump.

Japanese version: `README.ja.md`
Japanese variants of other docs are available with the `.ja.md` suffix.

## Features
- Drag-and-drop import for audio/video files
- Explicit recognition mode switch: `On-device` / `Server` (no automatic fallback)
- Search (partial match enabled by default)
- Jump playback to matched timestamps
- Context line display + matched-term highlight in search results
- Audio/video playback (play/pause button, seek bar)
- Transcript export (`TXT` / `SRT`)
- Configurable TXT line-break threshold (seconds) from UI
- Custom term dictionary (canonical term / aliases)
- Cross-match between Hiragana queries and Katakana words

## UI Behavior
- Shows a drag-and-drop area when no media is loaded
- Hides the drop area and shows a loaded-file card after import
- Shows a clear (`×`) button next to the file name
- Returns to initial state and re-shows the drop area after clear

## Project Structure
- `Sources/VoiceSearchCore`: core logic (normalization, search, formatters)
- `Sources/VoiceSearchApp`: macOS SwiftUI app
- `Sources/VoiceSearchCLI`: CLI tool (no UI)
- `Tests/VoiceSearchCoreTests`: tests for core logic
- `Tests/VoiceSearchAppTests`: tests around ViewModel/UI behavior
- `Tests/VoiceSearchServicesTests`: tests around recognition services

## Run (Recommended)
```bash
./scripts/run-app.sh
```

On first launch, macOS will ask for speech recognition permission.  
If denied, enable `VoiceSearchApp` in:
`System Settings > Privacy & Security > Speech Recognition`.

Direct run for development:
```bash
swift run VoiceSearchApp
```

## CLI (No UI)
```bash
./scripts/run-cli.sh --input sample2.m4a --mode diagnose --output sample2_diagnostics.txt
```

Modes:
- `diagnose`: runs both on-device and server recognition, then compares
- `on-device`: on-device only
- `server`: server only

## Adding Screenshots to README
1. Put image files under `docs/images/` (example: `docs/images/main.png`).
2. Add a Markdown image entry to `README.md`.

```md
![Main Screen](docs/images/main.png)
```

3. Use HTML if you want to fix image size.

```html
<img src="docs/images/main.png" alt="Main Screen" width="960" />
```

Notes:
- Use paths relative to `README.md`
- Prefer file names with ASCII letters/numbers/hyphens (example: `search-result-highlight.png`)
- Commit image files together with README updates

## Development Notes
- Core logic is developed with a TDD-first approach
- Recognition backends are replaceable through `TranscriptionService`

## Related Docs
1. `docs/progress.md`
2. `docs/roadmap.md`
3. `docs/architecture.md`
4. `docs/TDD.md`
5. `docs/missing-features.md`
