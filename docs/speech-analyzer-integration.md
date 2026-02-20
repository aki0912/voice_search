# SpeechAnalyzer Integration Notes (Current)

Japanese version: `speech-analyzer-integration.ja.md`

## Current Positioning
- `On-device` mode uses `SpeechAnalyzerTranscriptionService`
- `Server` mode uses `SpeechURLTranscriptionService`
- Selected user mode is respected; behavior is not changed by automatic fallback

## Inputs/Outputs
- Input: `TranscriptionRequest`
  - `sourceURL`
  - `contextualStrings` (from dictionary entries)
  - `progressHandler`
- Output: `TranscriptionOutput`
  - `words: [TranscriptWord]`
  - `duration`
  - `diagnostics`

## Implementation Highlights
- Normalizes recognition output into `TranscriptWord(startTime/endTime)`
- Extracts audio tracks from video inputs before recognition
- Accepts partial results and returns sorted words after finalization
- Merges estimated/actual progress and publishes it to UI

## Authorization and Permissions
- `NSSpeechRecognitionUsageDescription` is required
- Authorization prompt behavior differs by execution shape (`.app` or not)
- Returns explicit errors when unauthorized

## Known Notes
- Availability depends on OS/SDK differences; rely on `isAvailable`
- Input files without valid audio tracks should fail explicitly
- On failure, show cause to users and persist logs when needed
