# Tonnage — Update Plan (post build 13)

Backlog of pro-app quality gates and deferred items, captured after the build-13 work
(security proxy, audits, 133 tests). Ordered roughly by priority. Not yet started unless noted.

## P0 — App Store blockers / required before public release
- [ ] **Privacy Manifest** (`PrivacyInfo.xcprivacy`) — Apple requires it. Declare required-reason
      API usage (UserDefaults, file timestamps) + collected data types (health, photos, identifiers).
      Not needed for TestFlight, required for App Store submission.
- [ ] **App Store metadata** — privacy nutrition labels (Health + Photos → third party/Anthropic),
      screenshots, age rating, support URL, description, keywords.
- [ ] **Account deletion** — only if we add accounts (see Auth below); Apple mandates in-app deletion
      for account-based apps.

## P1 — Pro quality (high value)
- [ ] **Accessibility pass** — only ~18 a11y modifiers app-wide. Add VoiceOver labels/traits/values
      (steppers, cue chip, charts), non-color cues for the green/orange volume + contributor bars,
      Dynamic Type checks at accessibility sizes, Reduce Motion.
- [ ] **Performance / Instruments** (device) — Time Profiler (chart/list scroll, launch), Leaks +
      Allocations (progress-photo image memory), Hangs, SwiftData fetches in view bodies.
- [ ] **Thread Sanitizer run** (device/sim) — catch runtime data races, esp. the WatchConnectivity
      boundary (Swift 6 static checks are on, but TSan covers the rest).
- [ ] **Real-device migration test** — install build 13 over a build-7-era iCloud store; confirm data
      survives + new records (BodyMeasurement/ProgressPhoto/isWarmup) sync after the Prod schema deploy.
- [ ] **Device matrix** — iPhone SE (small) → Pro Max, large Dynamic Type, the watch app + sync.

## P2 — Product / infra decisions
- [ ] **kg / metric support** — app is lb-only (hardcoded in ~11 places, no toggle). Real limitation
      for international users. Add a unit preference + conversion at display/entry.
- [ ] **Telemetry / crash reporting** — none today (TestFlight/Xcode Organizer only). Add MetricKit
      (Apple-native, no SDK, no privacy-label cost) for production; Sentry if richer needed.
- [ ] **UI tests (XCUITest)** — 0 today vs 133 unit tests. A few critical-flow smoke tests
      (log a set, send a coach message, plan a block) for CI confidence.
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

## Decision needed: User authentication
The app is **local-first**: data lives in SwiftData mirrored to the user's **CloudKit private
database** — so the user's iCloud account already provides identity + cross-device sync with no
login. Before building sign-in, decide what it must accomplish (this changes the work from a
~1-hour Settings addition to a multi-week backend project):

- **Sync / "don't lose my data"** → already handled by iCloud/CloudKit. A login adds nothing here.
- **Social features (friends, shared feed, cross-platform/Android)** → needs a backend + accounts.
  Sign in with Apple is the front door; this is the big project.
- **Stable identity for the Coach proxy** (quota survives reinstall) → lightweight Sign in with Apple.
- App Store rule 4.8: if we offer Google/Facebook login, we **must** also offer Sign in with Apple.
