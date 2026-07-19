# Tonnage

Native iOS + watchOS strength-training app with an AI progression engine that recommends load and rep changes from your logged RPE.

**Status:** near release · **~138 unit tests** · security-audited

---

## Features

- **Coach's Call** — progression engine that recommends load/rep changes from RPE
- **Readiness ring** — recovery signal surfaced before you train
- **Per-muscle volume** tracking
- **Plate math** — what to actually put on the bar
- Apple Watch app, widgets, and two-way phone↔watch sync

## Engineering notes

- **Logic lives in a dedicated, tested package** — the progression math is separated from the UI layer and covered by ~138 unit tests, so training recommendations are verifiable rather than vibes
- **Security-audited** — reviewed for data handling and storage before release
- **AI runs behind a serverless proxy** — no API key ships in the app binary
- **SwiftData + CloudKit** — offline-first with sync across devices

## Stack

Swift 6 · SwiftUI · SwiftData + CloudKit · HealthKit · WatchKit · widgets · serverless AI proxy
