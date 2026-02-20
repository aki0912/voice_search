# voice_search Architecture (Current)

Japanese version: `architecture.ja.md`

## Layer Structure

### 1. Core (Pure Logic)
- Module: `VoiceSearchCore`
- Responsibilities:
  - Shared models such as `TranscriptWord` / `SearchHit`
  - Search (`TranscriptSearchService`)
  - Normalization (`DefaultTokenNormalizer`)
  - Display grouping (`TranscriptDisplayGrouper`)
  - TXT formatting (`TranscriptPlainTextFormatter`)
  - Transcription pipeline (`TranscriptionPipeline`)
- Characteristics:
  - No dependency on UI or Speech frameworks

### 2. Services (OS Integration)
- Implementations:
  - `SpeechAnalyzerTranscriptionService`
  - `SpeechURLTranscriptionService`
  - `HybridTranscriptionService` (internal comparison/service-selection use)
- Responsibilities:
  - Integrate Speech/AVFoundation and produce `TranscriptionOutput`
  - Normalize data into `TimeInterval`-based values used by Core
- Policy:
  - Respect the recognition mode selected in UI
  - Do not auto-fallback in ways that change user intent

### 3. App (Presentation)
- Module: `VoiceSearchApp`
- Responsibilities:
  - SwiftUI presentation
  - Drop handling / re-run / clear
  - Playback control / seek
  - Search and highlight rendering
  - Dictionary registration and persistence
  - TXT/SRT export

## Main Data Flow
1. Acquire file URL via drag-and-drop
2. `TranscriptionViewModel` builds service by selected mode
3. Execute `TranscriptionPipeline` and obtain `TranscriptWord[]`
4. Build grouped `displayTranscript` for rendering
5. On search, generate `SearchHit[]` from `transcript`
6. On hit/line selection, seek to `startTime` and play

## Key State Management
- `TranscriptionViewModel`
  - Input state: `sourceURL`, `queue`, `isAnalyzing`
  - Playback state: `isPlaying`, `currentTime`, `sourceDuration`, `scrubPosition`
  - Display state: `transcript`, `displayTranscript`, `searchHits`
  - Settings state: `recognitionMode`, `txtPauseLineBreakThreshold`, `dictionaryEntries`

## Error Handling Policy
- Show explicit error messages on failure
- Return failure reasons for selected mode (instead of fallback)
- Persist failure logs when writable and show log path
