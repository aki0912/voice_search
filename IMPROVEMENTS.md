# Voice Search Improvements (2026-02-15)

Japanese version: `IMPROVEMENTS.ja.md`

## Policy
- Respect the user-selected recognition mode and **do not auto-fallback**.
- On failure, show an error with **clear cause information**, not just a generic failure.

## High Priority (Address First)
- [x] Insufficient preprocessing for video input (`mov/mp4`) in the `SpeechAnalyzer` path.
  - Added `AudioInputPreparer` and shared it across `SpeechAnalyzer` and `SpeechURL`.
  - For video/multi-track input, extract m4a and try candidate tracks in priority order.
- [x] Unstable locale reserve/release behavior in `AssetInventory`.
  - Removed blanket release of all reserved locales.
  - Updated behavior to reserve only target locales and release on both success/failure paths.

## Medium Priority (Quality and Operations)
- [x] Unified `Info.plist` embedding across `VoiceSearchApp` run shapes.
  - Aligned with `VoiceSearchCLI` by embedding `__info_plist` into the executable.
- [x] Incrementally resolved deprecated/sendable warnings in `SpeechURLTranscriptionService`.
  - Shared audio extraction logic via `AudioInputPreparer` using `load(...)`-based handling.
  - Unified structure around sendable/concurrency boundaries.

## Low Priority (UX Enhancements)
- [x] Structured transcription failure messaging.
  - Introduced `TranscriptionFailureMessageFormatter` and separated output into cause/hint sections.
- [x] Consistent UI reset on failure (playback state/highlights).
  - Centralized in `TranscriptionViewModel.resetUIStateAfterTranscriptionFailure()`.
  - Added regression tests in `VoiceSearchAppTests` for failure-state reset.

## Implemented in This Iteration
- [x] Removed implicit fallback behavior in `HybridTranscriptionService`.
- [x] Switched failure display to include structured cause information.
- [x] When on-device mode is selected but unavailable, return explicit error (no auto-switch).
- [x] Unified audio input preprocessing across Analyzer/URL paths.
- [x] Added regression tests for `AudioInputPreparer` track-priority rules.
