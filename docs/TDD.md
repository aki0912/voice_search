# TDD Guide (Operational)

Japanese version: `TDD.ja.md`

## Core Principles
- Lock behavior with tests first
- Implement the minimum needed to pass
- Refactor minimally after tests pass

## Current Test Suites
- `Tests/VoiceSearchCoreTests`
  - Search (exact/partial)
  - Dictionary and notation variance (Hiragana/Katakana)
  - Display grouping
  - TXT formatting (including line-break threshold)
  - Pipeline normalization
- `Tests/VoiceSearchServicesTests`
  - Authorization decisions
  - Service selection
  - Audio input preprocessing
  - Result aggregation
- `Tests/VoiceSearchAppTests`
  - ViewModel failure-state reset
  - Search context rendering
  - Threshold update clamping
  - Clear-action reset

## Rules During Implementation
1. Add/update test cases for behavior changes first
2. Implement
3. Run `swift test`
4. If failing, fix and rerun

## Mandatory Current Gate
- For any code change, completion requires `swift test` success
- Never mark complete while tests are failing

## Priority Candidates for New Tests
1. `MainView` UI layout regression (snapshot/UITest)
2. Perceived scrub regression on long media
3. Failure log output I/O abnormal paths
4. CLI diagnosis output format stability
