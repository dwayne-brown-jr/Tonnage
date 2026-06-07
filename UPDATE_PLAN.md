# Tonnage — Update Plan (post build 13)

Backlog of pro-app quality gates and deferred items, captured after the build-13 work
(security proxy, audits, 133 tests). Ordered roughly by priority. Not yet started unless noted.

## P0 — App Store blockers / required before public release
- [x] **Privacy Manifest** (`PrivacyInfo.xcprivacy`) — DONE for the main app (no-tracking,
      health/fitness/photos/name data types, UserDefaults CA92.1). Verified it bundles.
- [~] Watch app + widget extension `PrivacyInfo.xcprivacy` files CREATED (in each target's folder,
      declaring UserDefaults CA92.1). VERIFY in Xcode that each is included in its target's bundle
      before App Store submission — they didn't auto-bundle in an incremental CLI build (synchronized
      groups may need a re-sync / explicit membership for extension resources). Main-app one is confirmed.
- [ ] **App Store metadata** — privacy nutrition labels (Health + Photos → third party/Anthropic),
      screenshots, age rating, support URL, description, keywords.
- [ ] **Account deletion** — only if we add accounts (see Auth below); Apple mandates in-app deletion
      for account-based apps.

## P1 — Pro quality (high value)
- [~] **Accessibility pass** — FIRST PASS DONE: StepperField is now a VoiceOver adjustable element;
      per-muscle bars + Last 7 Days strip have labels/values (no longer color-only). REMAINING:
      charts (Swift Charts accessibilityChartDescriptor), the readiness ring + contributor bars,
      remaining icon-only buttons, Dynamic Type at accessibility sizes, Reduce Motion.
- [ ] **Performance / Instruments** (device) — Time Profiler (chart/list scroll, launch), Leaks +
      Allocations (progress-photo image memory), Hangs, SwiftData fetches in view bodies.
- [ ] **Thread Sanitizer run** (device/sim) — catch runtime data races, esp. the WatchConnectivity
      boundary (Swift 6 static checks are on, but TSan covers the rest).
- [ ] **Real-device migration test** — install build 13 over a build-7-era iCloud store; confirm data
      survives + new records (BodyMeasurement/ProgressPhoto/isWarmup) sync after the Prod schema deploy.
- [ ] **Device matrix** — iPhone SE (small) → Pro Max, large Dynamic Type, the watch app + sync.

## P2 — Product / infra decisions
- [ ] **kg / metric support** — BIGGER than it looks; deliberately deferred to its own tested pass.
      It's not just display formatting: a correct metric experience also needs the PROGRESSION
      ENGINE's increment (CoachEngine adds +5 lb), the PLATE MATH (plate inventory), and the COACH's
      "+5 lb" language to switch to kg/2.5-kg — i.e. it touches core logic + its tests, plus ~15
      display/entry sites and converted entry steppers. High regression risk to the just-shipped
      logging/progression flow, and low urgency for an all-US friends beta. Do as a focused milestone:
      keep canonical storage in lb, add a WeightUnit preference + conversion at the UI boundary, make
      the engine increment unit-aware, and add tests. NOT a half-display-only toggle (that would be
      confusing — enter in lb, see kg).
- [ ] **Telemetry / crash reporting** — none today (TestFlight/Xcode Organizer only). Add MetricKit
      (Apple-native, no SDK, no privacy-label cost) for production; Sentry if richer needed.
- [~] **iOS unit-test target** — CREATED (`PersistenceIntegrationTests`, host = Tonnage app). TonnageCore
      links; `TonnageApp` now uses an in-memory store under XCTest (env `XCTestConfigurationFilePath`) so
      the host doesn't trap on CloudKit on a fresh test clone. A single test passes via xcodebuild.
      REMAINING (deferred): the FULL app-hosted suite run reports "Executed 0 tests"/instant fails under
      `xcodebuild test` — a harness/discovery quirk to iron out (try: verify target membership/Test-action,
      a clean DerivedData, or splitting container creation). Not blocking — `swift test` (133) is the
      team command and is green; the half-wired target doesn't affect build/archive.
- [~] **Integration/persistence tests** — WRITTEN (now native XCTest in `PersistenceIntegrationTests/`):
      real container round-trips, cascade delete, backup + watch-payload fidelity, re-import dedupe.
      Logic verified by the single-test pass; full-suite run blocked on the harness item above.
- [ ] **UI-test target** — still to add (Xcode GUI) for the `TonnageUITests/` smoke flows.
- [ ] **UI tests (XCUITest)** — 0 today vs 133 unit tests. A few critical-flow smoke tests
      (log a set, send a coach message, plan a block) for CI confidence — needs the UI-test target.

### Live run-through (done this pass)
Booted the Simulator and exercised the signed build: launch OK, TRAIN (Today verdict/readiness/
stats), DATA (This Week, Adherence, PR Moments deduped, Sets-per-Muscle incl. "Other" bucket),
and **Coach replied end-to-end through the proxy**. Proxy pen-test passed (405 + three 400s; quota
header). Note: an *unsigned* (`CODE_SIGNING_ALLOWED=NO`) build crashes on launch in CloudKit setup
because it strips the iCloud entitlement — build signed for any CloudKit testing.
- Coach-context "no workouts" finding: RESOLVED as a false alarm — the reinstall (unsigned→signed)
  wiped the demo container, so DATA was empty and the coach reported accurately. No defect.
- [ ] **User authentication** — see decision below; scope depends on whether a backend/social is planned.

## P3 — Deferred polish / hardening (from the audits)
- [ ] RPE-blank nudge when a working set is completed without reps-left logged.
- [ ] Body-scan API-key error → deep link to Settings (needs cross-tab routing).
- [ ] Harden the remaining `try? context.save()` sites (mirror the import path's rollback pattern).
- [ ] Watch + phone strength double-write: deeper fix (single-owner signal) beyond the current
      overlap-skip de-dupe.
- [ ] Proxy hardening: optional `x-app-token` check + per-IP rate limiting on the Cloudflare Worker.
- [ ] Coach prompt-injection: wrap user free-text (name, notes, limitations) in delimited
      "untrusted data" sections.

## P4 — Oura-style roadmap leftovers (not yet built)
- [ ] Morning check-in + subjective tags (soreness/sleep-quality) → a 6th readiness signal.
- [ ] Strain vs. recovery balance (rolling training load charted against readiness).
- [ ] Tag ↔ performance correlations ("you lift heavier on 7.5h+ sleep nights").

## Operational (per release)
- [ ] Rotate the Anthropic key after each beta round; keep a monthly spend limit on it.
- [ ] Deploy CloudKit schema Dev→Production whenever @Model types change.
- [ ] Bump CURRENT_PROJECT_VERSION before each archive.
- [ ] Separately archive Tonnage Fuel for the goal-suggestion bridge.

---

## Decision: User authentication — DEFERRED (not needed yet)
The app is **local-first**: data lives in SwiftData mirrored to the user's **CloudKit private
database** — so the user's iCloud account already provides identity + cross-device sync with no
login. Decided to **defer** sign-in: with no backend, social features, Android app, or paid tier,
an account would be pure cost (friction + App Store account-deletion + "must offer Apple if Google"
+ maintenance) for no user benefit.

**Revisit when** any of these land: a backend for social (friends/feeds), an Android app
(CloudKit is Apple-only), or server-side per-user entitlements. **Sign in with Apple** is the
front door at that point (not Google-first; rule 4.8).

In the meantime, if reassurance about data safety is wanted: add a small **iCloud sync-status
row in Settings** (synced ✓ / iCloud off) — no accounts needed.
