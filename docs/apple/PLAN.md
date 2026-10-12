# Apple implementation plan

Binding specification: [BRIEF.md](BRIEF.md), read in full on 2026-10-12. Re-read sections 2, 9 and 10 at every session and compaction. Work only on `apple-native`, using this checkout (the cloud machine is already isolated). Never reset history or remove existing features.

## Phase 0 reconnaissance

VERIFIED `uname -s` → Linux; `xcodebuild -version` → command not found. Mode B applies. `swift --version` → command not found; a verified Linux toolchain is needed for Phase 2. Node 22.23.3 is retained at `/workspace/.tools/node-v22.23.3-linux-x64/bin`; export that path before every JS command.

Read README, CONTRIBUTING, MOBILE, SELF_HOSTING, NOTICE, Capacitor config, the existing Xcode project, API/web Dockerfiles and CI. `rg --files --hidden -g AGENTS.md -g '!node_modules' -g '!.git' /workspace` found no AGENTS.md. Inspect library modules by responsibility: exercises and i18n, history, session-start/session-merge, finish-workout, progression, onerm, plates/bar/units, measurements, mobile durable storage, health-sync, native-keyboard, sound and state sync. No application code changed in this phase.

Existing source of truth is JavaScript, not TypeScript. `S.workouts` entries use compact keys (`d`, `start`, `end`, `entries`, `sets`, `w`, `r`, `sec`, `min`, `done`) and exercise `id` is a catalogue key. New UUID identity must be additive (`uuid` on entry/set), never replace the catalogue id. The finish path currently whitelists fields: new identity/HR fields must be deliberately retained there with regressions. Server mode already merges concurrent changes and converts profile units; Watch imports must pass through the same persistence path.

Capacitor 7 uses CocoaPods with an existing App target, scene lifecycle, printing plugin, local filesystem mirror and Keychain plugin. iOS deployment floor is presently 15.5. No native HealthKit, Watch target, Live Activity, widgets or Apple Intents exists. Browser vibration does not work on iOS. CSS already supports safe-area variables and native keyboard occlusion. Mobile exercise media now ships in packages; it is not fetched on first launch. Preserve this offline behaviour and the original 1,324 dataset records and notices (ADR-002).

## Architecture and order

Use the architecture in brief §6 (ADR-001). Preserve the existing CocoaPods iPhone app and React UI. Introduce an in-repo CAPBridgeViewController to register Swift plugins. Add one framework-free OpenGymKit Swift package for the contract, durable Watch state and tested calculators; keep Apple frameworks in target code. Watch is a SwiftUI single-target watchOS 10 app embedded in the phone bundle and independently launchable. Choose atomic JSON persistence with a write-before-confirm journal and an outbox, documented before Phase 4. Swift/JS fixtures use the same checked-in JSON; calculate planned values and reasons on the phone when a snapshot is produced, carry them to the Watch, and test standalone recomputation before relying on it.

| Phase | Implementation | Required validation/gate |
|---|---|---|
| 0 | This plan, full parity inventory, ADR-001, discrepancy list, blockers | Baseline 5,060 frontend / 596 API / 95 MCP and web build; commit docs |
| 1 | Named OpenGym scheme, iOS 17 config overrides, native haptics/keyboard/safe areas, macOS CI, beginner Xcode setup | Mobile web bundle; iPhone Release simulator build, standalone launch/UI smoke; baseline; Apple code remains WRITTEN until build oracle |
| 2 | Pure OpenGymKit models, validated envelope/schema, UUIDs, migrations, 1RM/plates/warmups, unit conversion, golden JS fixtures | Swift + JS fixtures including invalid inputs, rounding, progression/readback; baseline |
| 3 | Health authorization purpose UI, mappings, idempotent workout writes, unit-safe measurements and mock store | Swift mapping/idempotency tests and iPhone integration tests; real Health checks owner-only |
| 4 | Watch store and native logging, Crown, editing, supersets, timed/cardio/effort, rest, HR session | Seeded watch UI start → three sets → rest → finish and relaunch/resume; release build; device checklist for hardware |
| 5 | Application-context snapshot; user-info completion/outbox/ack; reachable live edits; thumbnail file transfer | Offline/duplicate/out-of-order/concurrent/account-isolation tests; one history row + one mock Health workout end-to-end |
| 6 | Fill all remaining Strong rows, keeping existing functionality | Focused logic/UI tests, parity evidence in PARITY, no unsupported row silently deferred |
| 7 | Progress aggregation, HR summaries, recovery overlay, body goals, image summary cards | Empty/single/five-year fixtures; measured 2,000-workout aggregation <300 ms |
| 8 | ActivityKit and lock-screen controls, WidgetKit calendar/activity/streak, App Intents, Watch complication/Smart Stack | Both release builds, extension tests, application-group integration; device controls checklist |
| 9 | Health source attribution and Oura Tier 1, OAuth2 Tier 2, Keychain tokens | Official endpoints/scopes/token lifecycle checked; sandbox tests; capability hidden without config; no public-app secret |
| 10 | Accessibility, all existing languages, privacy manifests, visible media attribution, Xcode/device docs, final report | Full suites and both Release schemes, watch→phone→Health test, parity complete, phase evidence, PR to fork main |

Every phase runs all three full JS suites before closure and commits its own changes. No later phase opens before the current gate is met or formally blocked solely by an owner/device prerequisite allowed in §2. Unknown Apple compile failures are not claimed as success. Network/config blockers and phase-gated remaining work are recorded in BLOCKERS.

## Validation strategy

Run JS suites with Node 22 and four-CPU budget: frontend `npm test -- --maxWorkers=2`, API `node --test --test-concurrency=1 test/*.test.js` separately after frontend completion (ADR-009 preserves its 150 ms TTL probe), MCP `npm test -- --maxWorkers=1`. Use `npm ci` with existing locks. Run `npm run build` for web separately from the mobile build. Stage native mobile assets using the existing stage-media script; do not let cap sync on Linux masquerade as a pod build. Build Android with Java 21 / SDK 35 and run RestTone unit tests. Build and smoke the self-hosted API+nginx images (working directory and generated outputs outside tracked paths).

macOS apple.yml must select available simulators by identifier, build Release, install/launch a standalone seeded iPhone app, and run named XCTest/UI tests. Add Watch scheme and Swift package checks when those targets exist, making them required rather than silently skipped. Archive xcresult/logs, preserve command exit status, and inspect the workflow outcome for the exact pushed commit. Physical device evidence remains in DEVICE_TEST_CHECKLIST.

## Data/privacy constraints

No server or Apple account is needed for standalone simulator tests. Health permissions are opt-in and unavailable/read-denied states are distinct from empty data. Store only summaries in app state, raw HR in HealthKit. Routine snapshots must be account-scoped and clear stale Watch data on owner change. Completed offline workouts and tombstones survive transport retries. Deduplicate by workout UUID and retain unacknowledged outbox items until the phone persists them.

Oura uses OAuth authorization code, nonce/state validation and exact redirect matching. Server-mode exchange belongs on authenticated self-hosted API with protected secret; standalone must not ship an app-wide secret in a bundle or xcconfig. Verify official public-client options; if unavailable, use the documented owner-controlled local exchange service and mark direct Tier 2 blocked. Readiness never changes progression automatically. Signing and distribution remain owner actions; App Store submission is outside this goal.
