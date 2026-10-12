# openGym for iPhone and Apple Watch: Engineering Brief

> **Binding spec for the `/goal` run.** Save this file in the fork as `docs/apple/BRIEF.md`.
> Re-read sections 2, 9 and 10 at the start of every session and after every context compaction.
> When this brief and the repository disagree about what exists, the repository is right: record the difference in `docs/apple/DECISIONS.md` and continue.

---

## 1. Role and mission

You are the lead Apple-platform engineer on our fork of openGym. You own the work end to end: reconnaissance, architecture, implementation, tests, documentation.

**Mission:** turn openGym into a first-class iPhone app with a standalone Apple Watch app, built and run from Xcode, that covers everything the Strong workout tracker does and improves on it, with Apple Health, live heart rate, Oura recovery data and strong progress tracking.

**The success picture.** The owner leaves her iPhone in the locker. On her Apple Watch she picks a routine, sees last session's weight and reps prefilled, adjusts with the Digital Crown, confirms each set with one tap, feels a haptic when rest ends, and watches her heart rate the whole time. She ends the workout on the wrist. Later, the session is in Apple Health with heart rate and energy, in openGym history on the iPhone with every set, and her progress charts and personal records have updated. Every decision in this project serves that picture.

---

## 2. Operating rules

These six rules govern the whole run. Each one exists because long autonomous runs fail in a predictable way without it.

1. **Evidence before claims.** Every status you report uses exactly one of four labels:
   - `VERIFIED`: you ran a command in this session and cite the command and its result.
   - `BUILT`: it compiles, and its tests are still to be written or run.
   - `WRITTEN`: the code exists and is still to be compiled.
   - `BLOCKED`: it waits on something listed in `docs/apple/BLOCKERS.md`.
   A phase closes only when its exit criteria are `VERIFIED`, or `BLOCKED` on a device-only or owner-only item.
2. **Plan before code.** Phase 0 is read-only. Think through the architecture step by step, write it down, then build.
3. **One phase at a time.** Finish a phase's exit criteria, update the progress log, commit, then open the next phase.
4. **Keep what works working.** The baseline is 5,060 frontend, 596 API and 95 MCP tests passing on Node 22, plus a clean web build. Run the full suites before each phase closes. Test counts may only grow. The web app, the self-hosted stack and the Android build stay functional throughout.
5. **Persist state in files.** Your memory is the repository. Maintain `docs/apple/PROGRESS.md`, `DECISIONS.md` and `BLOCKERS.md` continuously so that a fresh session can resume from them alone.
6. **When blocked, record and move.** Write the blocker with the exact owner action required, then continue with the next unblocked work. Pause the goal only when every remaining item is in `BLOCKERS.md`.

---

## 3. Context: what exists today

Facts taken from the upstream README on 2026-10-12. Confirm each against the code during Phase 0.

| Area | Current state |
|---|---|
| Stack | React 19 + Vite, React Router, Zustand. Node API with WebAuthn passkeys, JSON file storage. nginx. Docker Compose. |
| Training logic | Pure functions under `frontend/src/lib/` with Vitest tests beside them: progression rules, estimated 1RM, session read-back. |
| Mobile | A Capacitor build exists. Android ships as a sideloadable APK. iOS is documented as "build onto your own device from Xcode" in `docs/MOBILE.md`. |
| Modes | Self-hosted (multi-device sync, profiles) and standalone mobile (all data on the phone, zero server). Both modes must keep working. |
| Features already present | Weekly plan and routines, guided workouts with prefilled weights, rest timer, PR detection, supersets, timed exercises, cardio, progression engine (linear, Greyskull LP, double progression), estimated 1RM, RIR/RPE per set, body-weight chart with goal line, activity heatmap, muscle map, custom exercises, equipment filter, plan sharing, importers (Strong, Hevy, FitNotes, Apple Health body-weight export), JSON export/import, 12 UI languages, light/dark themes with 8 accents. |
| Upstream roadmap gaps | Body measurements, per-exercise notes, plate calculator, 5/3/1-style programming. |
| Exercise data | `hasaneyldrm/exercises-dataset`: 1,324 records in `data/exercises.json` (schema in `data/exercises.schema.json`) with `id`, `name`, `category`, `body_part`, `equipment`, `target`, `muscle_group`, `secondary_muscles`, `instructions.<lang>`, `instruction_steps.<lang>`, `image`, `gif_url`, `attribution`. 180×180 thumbnails and GIFs. Instructions in 10 languages. Media is fetched on first launch (about 140 MB). |
| License | AGPL-3.0 for openGym. Dataset code and text under MIT. Exercise media © Gym visual with its own terms (`NOTICE.md`). |

---

## 4. Environment: detect it first

Run `uname -s` and `xcodebuild -version` at the start of Phase 0 and record the result.

**Mode A, macOS with Xcode (full capability).** Build and test both schemes with `xcodebuild` on simulators. This is the mode where the goal can be fully verified.

**Mode B, Linux cloud container (authoring capability).** Xcode is unavailable here, so compilation of iOS and watchOS targets happens elsewhere. In this mode:
- Write all Swift and project files, and keep the pure-Swift package (`OpenGymKit`, section 6) free of Apple-only frameworks so `swift test` can run on Linux when a Swift toolchain is installable.
- Add `.github/workflows/apple.yml` on a macOS runner that builds both schemes and runs all Swift tests on every push to the working branch. Treat that workflow as the build oracle and read its results when you have access.
- Label Apple-target work `WRITTEN` until a macOS build confirms it, and list "first Xcode build on a Mac" in `BLOCKERS.md` with exact steps for the owner.

**Device-only items in both modes.** Live heart rate, real HealthKit writes, WatchConnectivity between physical devices, the Action button, Double Tap and background workout sessions need a real iPhone and Apple Watch. Prepare `docs/apple/DEVICE_TEST_CHECKLIST.md` with numbered steps and expected results so the owner can verify them in under 30 minutes.

---

## 5. Owner inputs

Use these placeholders through `.xcconfig` files so the project builds for anyone. Commit `Config/Local.example.xcconfig`; keep `Config/Local.xcconfig` in `.gitignore`.

| Placeholder | Meaning | Default until supplied |
|---|---|---|
| `{{APPLE_TEAM_ID}}` | Apple Developer team for signing | empty, simulator builds only |
| `{{BUNDLE_ID_PREFIX}}` | Reverse-DNS prefix | `com.example.opengym` |
| `{{APP_GROUP_ID}}` | Shared container for app, widgets, Live Activity | `group.{{BUNDLE_ID_PREFIX}}` |
| `{{OURA_CLIENT_ID}}` / `{{OURA_CLIENT_SECRET}}` | Oura OAuth2 application credentials | empty, Oura API tier hidden in UI |
| `{{OURA_REDIRECT_URI}}` | OAuth2 redirect | custom URL scheme `opengym://oura/callback` |

Secrets live only in git-ignored config and the Keychain.

---

## 6. Architecture

This is the default. Adopt it unless Phase 0 reconnaissance gives a concrete reason to change, in which case write `ADR-001` in `DECISIONS.md` with the reason, the alternative and the trade-off before writing code.

```
iPhone app (Capacitor shell, opened in Xcode)
├─ React UI + tested TS logic in frontend/src/lib      ← existing source of truth for app state
├─ Native Swift Capacitor plugins (in-repo)
│   ├─ HealthPlugin        HealthKit read/write, authorization
│   ├─ WatchLinkPlugin     WatchConnectivity, workout mirroring
│   ├─ LiveTimerPlugin     ActivityKit rest timer, Dynamic Island
│   └─ OuraPlugin          OAuth2 session, token storage in Keychain
├─ Widget extension        calendar, weekly activity, streak (WidgetKit, Swift Charts)
└─ App Intents             "Start workout", "Log body weight" for Siri and Shortcuts

OpenGymKit (local Swift package, pure Swift, shared by every Apple target)
├─ Codable models mirroring the openGym state schema
├─ SyncEnvelope contract (section 8)
└─ Calculators: estimated 1RM, plate loading, warm-up sets, unit conversion

Apple Watch app (native SwiftUI, standalone capable)
├─ Local store (SwiftData or JSON files, your choice with an ADR)
├─ HKWorkoutSession + HKLiveWorkoutBuilder for heart rate, energy, background runtime
├─ WatchConnectivity client
└─ Complications and Smart Stack widget
```

**Why this shape.** The React app carries more than 5,000 tests of training logic. Reusing it for iPhone keeps that investment and keeps web, Android and iOS in step. The Watch needs native SwiftUI because standalone operation, HealthKit workout sessions and wrist ergonomics exist only there. `OpenGymKit` is the single contract both sides compile against.

**Parity between TypeScript and Swift logic.** Generate golden fixtures (inputs and expected outputs as JSON) from the existing Vitest suites for 1RM, progression targets and session read-back. The Swift tests in `OpenGymKit` load the same fixtures. One fixture set, two implementations, identical answers.

**Deployment targets.** Choose the lowest iOS and watchOS versions that support workout mirroring between Watch and iPhone, Live Activities and interactive widgets (iOS 17 and watchOS 10 are the expected floor). Confirm every API against the installed SDK documentation, and record the choice in `DECISIONS.md`.

---

## 7. Product scope

### 7.1 Strong parity matrix

Strong is the functional benchmark. Phase 0 turns this table into `docs/apple/PARITY.md`, with each row checked against the actual code and assigned to a phase.

| Strong capability | openGym today | Action |
|---|---|---|
| Fast set logging: set table with Previous, weight, reps, one-tap completion | Guided workouts with prefill | Refine to Strong's density and speed on iPhone |
| Exercise library with animated demos, custom exercises | Present (1,324) | Keep; add ranked search with match highlighting |
| Routines/templates, start an empty workout, template search | Weekly plan and routines | Add ad-hoc "empty workout", folders, search |
| Auto rest timer | Present | Add Live Activity, Dynamic Island, lock-screen controls |
| Exercise types: weight × reps, bodyweight, assisted bodyweight, weighted bodyweight, duration, cardio | Most present | Verify; add assisted and weighted bodyweight if absent |
| Set tags: warm-up, failure, drop set | Verify | Add if absent; warm-ups excluded from PR and volume stats |
| Supersets and grouped exercises | Present | Keep; support on Watch |
| Statistics: PRs, volume, 1RM progression, total weight lifted | 1RM and PRs present | Extend per section 7.5 |
| Warm-up calculator | Absent | Build in `OpenGymKit` + UI |
| Plate calculator with bar types | Absent | Build in `OpenGymKit` + UI, kg and lb plate sets, bar presets |
| Body measurements with Apple Health | Body weight only | Add measurements (waist, chest, arms, hips, thighs, body-fat %) |
| kg and lb, mixed per exercise | Verify | Add per-exercise unit override if absent |
| Workout notes, per-exercise notes, progress photos | Absent per roadmap | Add; photos stay on device |
| Share routines and workouts | Plan sharing present | Add share sheet with image summary card |
| CSV export | JSON export present | Add CSV for workouts and measurements |
| Cloud sync | Self-hosted sync | Keep; add Watch sync (section 8) |
| Apple Watch app, with or without iPhone | Absent | Build (section 7.2) |
| Widgets: calendar, activity, workouts per week | Absent | Build |
| Siri support | Absent | App Intents |
| History calendar, "start history from" date | Heatmap present | Add calendar view and the date setting |

### 7.2 Apple Watch app

The reference for wrist logging is Hevy and SmartGym: sets, reps and weight entered directly on the Watch, fully usable with the iPhone absent.

Required behaviours:
1. **Start** today's planned routine, any routine, or an empty workout, from the app, a complication or the Smart Stack.
2. **Log a set** in at most two interactions when the prefilled values are right: glance, confirm. Weight and reps adjust with the Digital Crown in the exercise's own increment, with haptic detents. Support the Action button and Double Tap as "complete set" where the hardware offers them.
3. **See context**: exercise name and thumbnail, set number, target with its progression reason, previous performance, set tag, RIR/RPE entry when the owner has enabled it.
4. **Rest timer** starts automatically, shows on the wrist-down Always-On display, ends with a distinct haptic, and offers +15 s / skip.
5. **Edit mid-workout**: add, replace, reorder or skip an exercise; add or delete a set; supersets alternate automatically.
6. **Heart rate and energy** live on screen for the whole session through `HKWorkoutSession`, including the current zone.
7. **Standalone**: the Watch keeps its own copy of routines, the exercise catalogue (text for all 1,324, thumbnails for exercises in the owner's routines) and the last performance per exercise. A workout completes and saves to HealthKit entirely on the Watch.
8. **Resilience**: an interrupted session (crash, reboot, battery) resumes exactly where it stopped.
9. **Live sync** when the iPhone is reachable: the same workout is visible and editable on both devices in near real time.

Timed exercises, cardio entries and all 12 UI languages work on the Watch as they do on the phone.

### 7.3 Apple Health and heart rate

- **Authorization** requested in context, with a clear purpose screen first. Write types: workouts, active energy, body mass, body-fat percentage, waist circumference. Read types: heart rate, resting heart rate, heart-rate variability, sleep analysis, active energy, body mass and the measurement types above, workouts.
- **Write each session** as an `HKWorkout` with the right activity type (traditional strength training by default, functional strength, HIIT or the cardio type when the session calls for it), start and end, active energy, associated heart-rate samples, and metadata carrying the openGym workout UUID so repeated syncs stay idempotent.
- **Sessions logged on iPhone only** still write a workout to Health. Evaluate iPhone-side workout sessions in the current SDK for this.
- **Heart-rate insights** stored in openGym state as summaries only: average and maximum per workout and per set, time in zones, and recovery (beats dropped in the first 60 s of rest). Raw sample series stay in HealthKit.
- **Effort**: when the owner logs RPE, evaluate writing a workout effort score to Health.
- **Body measurements** sync both ways with de-duplication by source and timestamp. Replace the file-based Apple Health body-weight importer with the live HealthKit read on iOS, keeping the file importer for web.
- Health data stays on the device and in the owner's own self-hosted instance. Include usage descriptions and a privacy manifest.

### 7.4 Oura Ring

Oura rings report recovery data rather than live workout heart rate, so the Watch remains the live sensor and Oura enriches readiness.

- **Tier 1, through Apple Health (always available).** The Oura app writes sleep, resting heart rate, HRV and more into Apple Health. Read those and attribute them by source. This tier needs zero Oura credentials.
- **Tier 2, Oura Cloud API v2 (when credentials are supplied).** OAuth2 authorization-code flow, since Oura retired personal access tokens in December 2025. Read `daily_readiness`, `daily_sleep`, `daily_activity` and `workout`. Verify endpoints, scopes and the token-refresh behaviour against the official reference at `https://cloud.ouraring.com/v2/docs` and develop against the sandbox routes. Store tokens in the Keychain. Perform the code-for-token exchange where the client secret is protected: the self-hosted API in server mode, and a documented device-only option for standalone mode.
- **What the owner sees.** A readiness card on the home screen and on the workout summary (readiness score, sleep, HRV trend, resting HR), plus an overlay of readiness on progress charts. Present it as information for her judgement. The progression engine stays driven by logged performance.
- **Write-back.** Finished workouts reach Oura through Apple Health, which the Oura app can import. Document that path in the settings screen.

### 7.5 Progress tracking

Progress is the reason the app exists, so this area gets the highest polish.

- Per exercise: estimated 1RM curve, best set, volume per session, rep PRs at each weight, PR timeline.
- Per muscle group: weekly hard sets and volume, using the existing muscle map.
- Global: workouts per week, streaks, training time, total volume, calendar and heatmap.
- Body: weight and every measurement with goal lines, alongside progress photos.
- Recovery overlays: resting HR, HRV, sleep and Oura readiness against training load.
- A weekly summary and a "since you started" summary, both shareable as an image card.
- Every chart handles an empty state, a single data point and five years of history gracefully, and loads within 300 ms on 2,000 stored workouts.

### 7.6 Better than Strong

Deliver these as the differentiators, in this priority order:
1. Everything unlocked: unlimited routines, zero subscription, zero ads, zero telemetry.
2. Targets that explain themselves: the existing progression engine shows why today's weight is what it is, on both devices.
3. Heart rate woven into the log: per-set HR, recovery between sets, zones per workout.
4. Recovery-aware context from Apple Health and Oura.
5. True data ownership: self-hosting, JSON and CSV export, importers from Strong and Hevy that also run on iOS.
6. Wrist ergonomics: Crown entry with haptics, Action button, Double Tap, Always-On rest timer, complications.
7. Muscle map and "muscles still to train this week" on the workout summary.
8. Twelve languages on iPhone and Watch.

### 7.7 Design language

Strong's App Store listing (`https://apps.apple.com/ca/app/strong-workout-tracker-gym-log/id464254577`) is the reference for interaction quality: one dense, calm set table, large numeric targets, minimal chrome, everything reachable with one thumb. Match that clarity and speed with openGym's own identity: its existing themes, accent colours and hand-drawn icon set, plus original layouts and assets. Follow Apple's Human Interface Guidelines for iOS and watchOS, support Dynamic Type, VoiceOver, Dark Mode and the system's current material style, and target 60 fps scrolling in history.

---

## 8. Data and sync contract

- **Source of truth:** the existing openGym state on the iPhone (and the self-hosted server in server mode). The Watch holds a working copy.
- **Identity:** every workout, exercise entry and set carries a UUID created on the device that recorded it, plus `updatedAt` and `deviceId`.
- **`SyncEnvelope`** (defined once in `OpenGymKit`, mirrored in TypeScript with a shared JSON schema and round-trip tests): `schemaVersion`, `kind` (`snapshot`, `workoutCompleted`, `liveEvent`, `ack`), `payload`, `sentAt`.
- **Transport:** application context for the latest routines-and-catalogue snapshot; queued user-info transfers for completed workouts (guaranteed delivery); interactive messages for live sync when reachable; file transfer for thumbnails.
- **Merge rules:** completed workouts are append-only and idempotent by UUID. Live edits resolve per set by latest `updatedAt`. A workout finished on the Watch while offline is delivered on the next connection and appears in history exactly once.
- **Migrations:** bump `schemaVersion` on every contract change and keep a migration with a test for each bump. Existing users' state files open unchanged.

---

## 9. Phases and exit criteria

Work in this order on branch `apple-native`. Each phase ends with: suites green, `PROGRESS.md` updated, one or more focused commits.

| # | Phase | Exit criteria |
|---|---|---|
| 0 | **Reconnaissance and plan (read-only)** | Read `README.md`, `CONTRIBUTING.md`, `docs/MOBILE.md`, `docs/SELF_HOSTING.md`, `NOTICE.md`, any `AGENTS.md`, the Capacitor config and `frontend/src/lib/`. Baseline suites `VERIFIED`. `docs/apple/PLAN.md`, `PARITY.md` and `ADR-001` written. Environment mode recorded. |
| 1 | **iPhone shell in Xcode** | Capacitor iOS project builds and launches in the simulator with all existing features working in standalone mode. Safe areas, keyboard and haptics behave natively. `apple.yml` CI in place. `docs/apple/XCODE_SETUP.md` written for a first-time Xcode user. |
| 2 | **`OpenGymKit`** | Models, `SyncEnvelope`, 1RM, plate and warm-up calculators implemented. Golden-fixture tests pass in Swift and TypeScript. |
| 3 | **Apple Health bridge** | `HealthPlugin` requests authorization, writes a finished workout with energy and metadata, reads and writes body mass and measurements, with unit tests around mapping and idempotency and a mock store for simulator runs. |
| 4 | **Watch standalone MVP** | Behaviours 1 to 8 of section 7.2 work in the watchOS simulator with a seeded store. UI tests cover start, log three sets, rest timer, finish, relaunch-and-resume. |
| 5 | **Phone and Watch sync** | Snapshot, completed-workout delivery and live sync implemented against the contract, with tests for offline completion, duplicate delivery and concurrent edits. |
| 6 | **Strong parity on iPhone** | Every row of `PARITY.md` is `VERIFIED` or carries a dated ADR explaining its deferral. |
| 7 | **Progress and heart-rate insights** | Section 7.5 delivered with tests on the aggregation functions and the performance budget measured. |
| 8 | **System integrations** | Live Activity and Dynamic Island rest timer, three widgets, App Intents, Watch complications and Smart Stack. |
| 9 | **Oura** | Tier 1 delivered. Tier 2 delivered against the sandbox, hidden cleanly when credentials are absent. |
| 10 | **Hardening and handover** | Accessibility pass, all 12 languages complete on new screens, privacy manifest, licences and attribution screen, `DEVICE_TEST_CHECKLIST.md`, updated `README.md` and `docs/MOBILE.md`, final report. |

---

## 10. Definition of done

The goal is achieved when all of these hold:

1. Both schemes (`OpenGym` for iPhone, `OpenGym Watch App`) build in Release configuration, `VERIFIED` by `xcodebuild` locally or by the macOS CI workflow.
2. All suites pass: frontend, API, MCP at or above their baseline counts, `OpenGymKit`, iOS plugin tests and watchOS UI tests.
3. Every row in `PARITY.md` and every numbered behaviour in section 7.2 is `VERIFIED`, or `BLOCKED` solely on a device-only check listed in `DEVICE_TEST_CHECKLIST.md`.
4. A workout completed in the watchOS simulator appears once in iPhone history and once in the (mock or simulator) Health store.
5. `PROGRESS.md` shows every phase closed with evidence, and `BLOCKERS.md` contains only owner actions, each with exact steps.
6. A pull request from `apple-native` to the fork's `main` is open with the final report as its description.

---

## 11. Quality bars

- **Tests first for logic.** Calculators, mapping, merge rules and aggregations get tests before or with their implementation. UI gets focused UI tests on the critical path.
- **Git.** Small, descriptive commits (`feat(watch): crown weight entry with haptic detents`). Additive changes that keep the fork easy to rebase on upstream. History is preserved as written.
- **Dependencies.** Prefer Apple frameworks and in-repo code. Each new third-party dependency gets one line of justification in `DECISIONS.md` and an AGPL-compatible licence.
- **Licensing.** The fork stays AGPL-3.0. Keep the dataset's `attribution` value visible wherever exercise media appears and in an Acknowledgements screen. Keep fetching media at runtime as upstream does, and note in `BLOCKERS.md` that public distribution of the app requires the owner to review Gym visual's media terms and AGPL obligations.
- **Privacy.** Zero analytics. Health data stays on device and in the owner's own instance. Secrets stay in the Keychain and git-ignored config.
- **Accessibility and localisation.** VoiceOver labels on every control, Dynamic Type, sufficient contrast in all 8 accents, and every new string present in all 12 languages.
- **Performance.** Cold launch to "start workout" under 2 s on iPhone, set confirmation on Watch under 100 ms perceived, battery use on Watch in line with a system strength workout.

---

## 12. Reporting formats

Follow these examples exactly. They are the interface between you and the owner.

**`PROGRESS.md` entry**

```markdown
## Phase 3: Apple Health bridge   [CLOSED 2026-10-19]
- VERIFIED  HealthPlugin authorization flow
  `xcodebuild test -scheme OpenGym -only-testing:HealthPluginTests` → 14 passed, 0 failed
- VERIFIED  Workout write is idempotent by openGym UUID
  `HealthMappingTests/testRepeatedSyncWritesOnce` → passed
- BLOCKED   Real heart-rate samples attached to workout (device-only, checklist item 7)
- Suites: frontend 5,112 · API 596 · MCP 95 · OpenGymKit 61
- Next: Phase 4, starting with the Watch local store ADR
```

**`BLOCKERS.md` entry**

```markdown
### B-04  Signing identity needed for device builds
- Needed from owner: Apple Team ID
- Exact steps: Xcode ▸ Settings ▸ Accounts ▸ select team ▸ copy Team ID into Config/Local.xcconfig as APPLE_TEAM_ID
- Unblocks: device-only checklist items 1 to 12
- Work continuing meanwhile: Phase 6 parity rows 3, 5, 9
```

**`DECISIONS.md` entry (ADR)**

```markdown
### ADR-003  Watch local store: SwiftData
- Context: the Watch needs crash-safe persistence for an in-progress workout.
- Decision: SwiftData with one model container, autosave on every set confirmation.
- Alternatives weighed: JSON files (simpler, weaker for partial writes).
- Consequence: watchOS 10 becomes the floor.
```

**Final report (pull-request description):** what shipped by phase, evidence summary, parity table, the device checklist, open blockers, and the three most valuable next steps.

---

## 13. Reserved for a later goal

App Store submission and review assets, iPad and Mac layouts, social feed, AI coaching, Wear OS, and direct Watch-to-server sync. Keep the architecture open to them and leave them unbuilt in this run.
