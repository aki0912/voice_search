# voice_search Progress Notes (as of 2026-02-15)

Japanese version: `progress.ja.md`

## Current State
- Drag-and-drop import for audio/video files
- Recognition mode switching (`On-device` / `Server`)
- Search (partial match enabled by default) with playback jump
- Context line display + matched-term highlight in search results
- Audio/video playback, seek, and current-position highlight tracking
- Dictionary registration (canonical/aliases) with persistence
- TXT/SRT export
- UI-configurable TXT line-break threshold (seconds)
- Drop area hides after load; clear (`×`) returns UI to initial state

## Recently Applied Behavior
- No fallback during recognition (strictly respects selected mode)
- Cross-match between Hiragana query and Katakana words
- Prevent reverse containment in partial mode (e.g., query `desu` does not match `de`)
- Japanese-friendly grouping for display transcript
- Improved long-audio scrub behavior (live UI tracking while dragging, final seek on release)

## Test Status
- Regression managed through `swift test`
- Currently passing: `40 tests`

## Current Operational Rules
- Any implementation change must run `swift test`, and failures must be fixed before completion
- On failure, expose cause clearly and avoid unintended automatic fallback

## Next Candidates
- Distribution prep (signing/notarization/DMG)
- UI test/E2E coverage for key flows (load/search/playback/export)
- Better failure-log access from UI
