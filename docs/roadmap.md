# voice_search Roadmap (Updated)

Japanese version: `roadmap.ja.md`

## Phase 1: MVP (Completed)
- Core logic (normalization, search, dictionary, playback position estimation)
- Transcription pipeline
- macOS UI (drop/search/playback/dictionary/export)

## Phase 2: Practical Usability (Completed)
- Explicit recognition mode switching (on-device/server)
- No-fallback policy
- Search context display + highlight
- TXT/SRT output with TXT line-break threshold controls
- Clear action and consistent state reset
- Hiragana/Katakana query normalization support

## Phase 3: Distribution Readiness (Next Priority)
1. Lock down `Release` build procedure
2. `Developer ID` signing + notarization
3. Decide distribution format (DMG) and update strategy

## Phase 4: Quality Reinforcement (Mid-term)
1. Add UI/E2E tests
2. Continue improving playback/scroll following for long media
3. Improve UI access/sharing flow for failure logs
4. Add performance measurement and bottleneck visibility
