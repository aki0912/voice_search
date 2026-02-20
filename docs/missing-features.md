# voice_search Missing Features (2026-02-20)

Japanese version: `missing-features.ja.md`

## Purpose
- Organize missing features in priority order based on practical usage gaps.

## High Priority (Best immediate impact)
1. Recognition language selector UI (+ auto-detection)
- `locale` cannot be explicitly selected from UI today, which can reduce multilingual accuracy.

2. Queue management screen
- No ability to reorder/remove/retry/cancel queued files.

3. Manual transcript editing
- Correcting recognition errors before re-search/export significantly improves usability.

## Medium Priority (Usability improvement)
4. Speaker diarization (speaker labels)
- Helps track who said what in meeting audio.

5. Session save/resume
- Restore file, search conditions, dictionary, and playback position.

6. Confidence display (low-confidence highlight)
- Makes uncertain parts easier to review.

## Low Priority (Integration/operations)
7. More export formats (`VTT` / `JSON` / `CSV`)
- Improves compatibility with subtitle tools, analytics pipelines, and external systems.

8. GUI diagnosis view
- Complete log viewing/comparison/rerun flow in UI.

9. More keyboard shortcuts
- Improves playback/search navigation efficiency.

10. A/B loop playback
- Speeds up repeated listening during transcript QA.

## Recommended Implementation Order
1. Recognition language selector UI
2. Queue management screen
3. Manual transcript editing
