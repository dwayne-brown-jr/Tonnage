# Testing & Audit Playbook

A complete inventory of the tests, audits, and security checks run on **Tonnage**, plus a
portable, app-agnostic checklist (bottom) for vetting any other app the same way.

> How to read this: Sections 1–6 are *what was actually done on Tonnage* (use as a worked
> example). Section 7 is the *reusable checklist* — start there for a new app.

---

## 1. Automated unit tests — 138 tests / 29 suites (swift-testing)

Run: `swift test --package-path TonnageCore`. Pure-logic, no UI, millisecond-fast.

### Progression & AI-coach logic
- **Coach's Call progression** (15) — Week-1 ramp never adds load; RPE≤7→+5lb, RPE 8–8.5→+5lb hold reps, RPE 9+→hold weight chase +1 rep; Week-5 deload ~60% rounded to 5lb; cardio = no-numbers call; rep-range / per-set-RPE parsing; compound vs isolation load steps; honest about missing data.
- **Coach context** (5) — context includes program week / recovery / top sets / plan; flags sessions trained today; states empty recovery; system prompt carries philosophy + personalizes.
- **Coach profile intake** (4) — coaching clause folds in intake/equipment; starting points map to nutrition direction.
- **Coach swap suggester** (4) — parses tagged JSON from prose; de-dupes/trims/caps at 6; handles malformed JSON; folds in limitations.
- **Coaching principles** (2) — key levers present in both coach + planner prompts.
- **Block plan** (6) — Codable round-trip; tagged-JSON parsing from prose; nil on malformed; system-prompt schema rules.
- **Body scan estimator** (5) — parses tagged estimates; maps synonym type names; filters bad values; nil on bad JSON.

### Training data & analytics
- **Analytics** (8) — weekly volume sums completed sets + zero-fills; top-set series; distinct exercise names; block/week totals; sets-per-muscle bucketing; warm-ups excluded everywhere.
- **Top-set series** (3) — dup-week yields one (heavier) point, no id collision; ascending; e1RM = Epley.
- **Live session stats** (4) — only completed sets count; top set = heaviest; `hasContent` gates pruning.
- **Block adherence** (5) — counts completed slots; rest days neutral; filters other blocks; safe on empty; multiple lifts/day = one training day.
- **Personal records** (6) — baseline + improvements; cardio never PRs; incomplete sets ignored; cap N; per-exercise; no false PRs past ~12 reps.
- **PR moments (bugfix)** (4) — many beating sets → exactly one PR (no id collision); high-rep sets don't fire/seed; strict-beat; Epley.
- **Training streak / fatigue** (7) — consecutive lift days; full-rest resets; gap ends; active-rest carries; empty lift doesn't count; rest recommendation threshold.

### Readiness & recovery
- **Readiness** (4) — strong signals→high/no hold; poor→low/hold; no signals→unknown; sleep-only still bands.
- **Readiness drivers** (11) — sign never contradicts points; band boundaries; HRV clamp ±22; zero baseline excludes signal; elevated body temp penalizes; 0.1°C deadband neutral; elevated respiratory rate penalizes; sick-day profile → drained.
- **Trend engine** (7) — rising/falling/flat with deadband; stall detection; advisory deload fires on recovery-slip + stall, suppressed on deload week.
- **Insight engine (streak)** (3) — long streak surfaces rest insight; HRV-down fires only when readiness isn't also falling.

### Programming & exercise library
- **Split presets** (7) — session count matches advertised days; every session leads with a compound; specs mirror built sessions; recommends split from days/week; all exercises have how-to.
- **Exercise metric inference** (6) — strength=weight/reps/RPE; stairs=flights+time; bike=time+distance; walk/run=distance+time; unknown→time only.
- **Exercise swap suggestions** (6) — maps movement→muscle; same-muscle alternatives excluding original + in-session; unknown→manual only; compound flag correctness.
- **Plate math** (4) — correct per-side plates; mixed plates; empty bar; unreachable weight reports closest + remainder.

### Today plan, body metrics, persistence
- **Today verdict** (2) + **Today verdict (streak)** (3) — band+session-aware lift verdict; rest speaks to recovery; 6-day streak overrides primed with rest nudge.
- **Body metrics** (5) — latest per type + delta; canonical ordering; ascending series; tracked types; lower-is-better flags waist/body-fat only.
- **Backup** (1) — encode/decode round-trip incl. nested workout + activity.
- **Workout payload** (1) — watch↔phone DTO round-trip.

## 2. Integration tests — 6 (XCTest, against a REAL SwiftData container)
App-hosted so the container initializes as it does in the running app; public API only.
- `testWorkoutGraphSurvivesSaveAndFetch` — full object graph persists + re-fetches.
- `testDeletingWorkoutCascades` — cascade delete removes children, not the template.
- `testBackupRoundTrip` — export → import fidelity.
- `testBackupReimportDoesNotDuplicate` — re-import dedupes.
- `testWatchPayloadRoundTrip` — watch sync payload fidelity.
- `testWatchPayloadUpsertReplaces` — re-sent session upserts, no dupes.

## 3. UI smoke tests — 4 (XCUITest, `-uitesting` launch arg)
DEBUG launch hook bypasses first-run gates + seeds demo data for deterministic runs.
- `testLaunchesToTrainWithoutCrashing` — cold launch lands on TRAIN.
- `testAllTabsNavigate` — all 5 tabs reachable.
- `testDataShowsSeededContent` — DATA renders seeded history.
- `testCoachComposerPresent` — Coach chat input present.

## 4. Audits (analytical passes)
- **Data-integrity audit** — data-loss/corruption paths; swallowed `try? save()`; multi-wearable double-counting (sleep summing, HRV/HR blending across sources); session date attribution (open-time vs train-time); re-import dedupe.
- **Resilience audit** — graceful degradation: Health denied/empty, CloudKit→local→in-memory fallback, AI/network failure + retry, every empty state honest (no false "Connected").
- **Test-coverage audit** — found 3 latent logic bugs, added 19 regression tests.
- **Heuristic UX audit (Nielsen)** — visibility of system status; error prevention; confirm destructive actions; surface silent actions; no dead-ends.
- **Accessibility sweep** — VoiceOver labels/values on charts/bars/cards; adjustable steppers; Dynamic Type; color never the sole signal.

## 5. Security & vulnerability checks
- **Secret-in-binary scan** — `strings` over the built binary to confirm no API key ships (verified 0 occurrences after moving the key server-side).
- **Server proxy pen-test** — method allowlist (non-POST→405); malformed/oversized/forbidden-model payloads→400; per-device daily quota enforcement; `max_tokens` cap; model allowlist; quota-remaining header.
- **Prompt-injection hardening** — system prompt treats all user free-text (name, notes, limitations, custom names) as *data, never instructions*.
- **Privacy** — `PrivacyInfo.xcprivacy` required-reason API declarations (UserDefaults CA92.1); `NSPrivacyTracking=false`; on-device-only telemetry (MetricKit, no third-party SDK); no PII in URLs.
- **Key-rotation discipline** — rotate the shared key each beta round; keep a monthly spend cap.

## 6. Build & runtime verification cadence
- Release compile gate: `xcodebuild -scheme … -configuration Release build` (Swift 6 strict concurrency on).
- Live Simulator run-throughs (launch, all tabs, log a set, coach reply end-to-end through the proxy, Recovery screen).
- Built-bundle inspection (confirm `PrivacyInfo.xcprivacy` embeds in the app **and every extension**).
- ⚠️ `CODE_SIGNING_ALLOWED=NO` strips the iCloud entitlement → CloudKit traps at runtime. Use it for *compile* gates only; run/test with a signed build.

---

## 7. PORTABLE CHECKLIST (use this for any app)

App-agnostic version, in priority order.

### Tests to stand up
- [ ] **Pure-logic unit tests** for every calculation/decision (the bulk; fast, no UI). Cover happy path **+ boundaries, empty inputs, malformed inputs, and a regression test for every bug you fix**.
- [ ] **Integration tests** against the real persistence layer — DB round-trip, cascade deletes, backup/restore fidelity, sync-payload upsert/dedupe.
- [ ] **UI smoke tests** for critical flows — launch-without-crash, navigate every screen, perform the core action. Use a launch arg that seeds deterministic data.
- [ ] **Build gate** — strict-concurrency Release build green before every release; a real device/sim run-through of the core loop.

### Audits to run
- [ ] **Resilience** — every external dependency denied / empty / failing degrades gracefully and never shows a false-positive status ("Connected" when it isn't).
- [ ] **Data integrity** — double-counting across sources; swallowed save errors (don't silently `try?`); timestamp/attribution correctness; dedupe on re-import; aggregates match the underlying records.
- [ ] **Heuristic UX (Nielsen)** — confirm destructive actions; surface silent ones; honest empty/error states; no dead-ends; visibility of system status.
- [ ] **Accessibility** — VoiceOver labels + values (esp. charts/color-coded UI), Dynamic Type, color never the sole signal, ≥44pt tap targets.

### Security & privacy
- [ ] **No secrets in the binary** — `strings`/`grep` the built product for API keys/tokens; move shared secrets behind a server proxy.
- [ ] **Endpoint pen-test** (if you have a backend) — method allowlist, reject malformed/oversized payloads, auth/rate-limit/quota, output caps, no verbose error leakage.
- [ ] **Treat all external text as untrusted** — user input, third-party API responses, file contents: data, never instructions (prompt-injection if LLM-backed; injection/escaping generally).
- [ ] **Privacy manifest + labels** — required-reason API declarations; tracking flag honest; no PII in URLs/logs; verify the manifest bundles into **every** target (app + extensions).
- [ ] **Secret rotation** — rotate shared keys per release/beta; spend caps on paid APIs.

### Platform-specific gotchas worth a dedicated check
- [ ] Multi-source data (e.g. two wearables, multiple sync sources) — dedupe before sum/average.
- [ ] Event/record timestamps reflect *when it happened*, not *when the row was created*.
- [ ] Offline / first-launch / migration-over-old-data paths.
- [ ] Background↔foreground refresh (does data update when the user returns, or only on cold launch?).

---
*Generated from the Tonnage testing effort. Section 7 is the reusable part.*
