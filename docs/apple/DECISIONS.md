# Apple decisions

### ADR-001 — Preserve Capacitor and the existing training engine (2026-10-12)
- Context: the fork has the existing React 19/JavaScript frontend, Capacitor 7 iOS CocoaPods shell and 5,060 frontend tests. The Watch requires standalone native runtime and HealthKit.
- Decision: adopt brief §6: keep React/Zustand on iPhone, in-repo Swift Capacitor plugins, a framework-free local OpenGymKit Swift package, and native SwiftUI Watch target. Keep the App target's existing identity internally; publish the user-facing scheme as OpenGym.
- Alternatives weighed: full SwiftUI phone rewrite (duplicates thousands of tested behaviours); a web Watch app (cannot meet independent HealthKit/background operation); replacing CocoaPods with a new project generator (unneeded churn).
- Consequence: add Swift/JS golden fixtures, additive identifiers and tests at every bridge. Apple-target code is WRITTEN until a macOS build confirms it. No new application dependency is needed in Phase 1.

### ADR-002 — Repository facts override the older brief (2026-10-12)
- VERIFIED `node --input-type=module -e "import {EXDB} from './frontend/src/lib/exercises-data.js'; console.log(EXDB.length)"` → 5,632 shipped exercise records. Source catalogue has 6,554 files including variants; 1,324 retain `textSource: exercisedb`. Preserve ids, inherited hasaneyldrm/exercises-dataset text and MIT attribution; do not replace the enlarged catalogue with 1,324 records.
- Repository ships licensed 180 px stills/clips in catalogue/media and packages them into mobile/container builds. Keep supported packaged offline media, rather than reintroducing retired first-launch downloads/CDN use.
- There are 18 translation packs plus English (20 selectable UI languages, including derived Swiss German), not 12. Preserve all of them; new strings must cover the actual supported set.
- Measurements, notes, progress photos, bar/plate loading, assisted/weighted bodyweight and warm-up/failure tags already exist. Reuse and fill gaps, rather than rebuild them because the brief calls them absent.
- Source files are JavaScript, not TypeScript. Mirror the Swift sync contract in native ESM JavaScript plus JSON schema without a new transpilation dependency.

### ADR-003 — Apple deployment and owner configuration (2026-10-12)
- Context: iOS is currently pinned to 15.5. Workout mirroring, interactive widgets and the requested integrations need iOS 17/watchOS 10.
- Decision: Apple targets use iOS 17 / watchOS 10 floors; Android/Web remain unchanged. Config/Local.example.xcconfig provides simulator-safe defaults, optional local config supplies owner identifiers.
- Consequence: SDK API availability must be confirmed by macOS compile/tests before closure. No signing team is needed for simulator Release builds. Secrets are never committed or logged; Oura secret is not a public mobile build setting.

### ADR-004 — Development build tooling (2026-10-12)
- OpenStep parser 2.0.3 (MIT, installed outside the repository) validates existing PBX syntax/references on Linux; it is validation tooling, not an app dependency. Xcode remains the compile oracle.
- CocoaPods 1.16.2 remains the existing Apple dependency manager; CI pins the tool without replacing the existing dependency declarations.
- Verified LANGS has 20 selectable languages: 18 packs + English + Swiss German derived from German. Earlier README/brief counts are stale; preserve the derived locale as well.

### ADR-005 — Distinguish owner Xcode from CI evidence (2026-10-12)
- Owner reports Xcode 27.0 installed locally. Cloud remains Linux; no local-Mac build is claimed.
- CI emits xcodebuild version/SDK availability; local instructions accept Xcode 27.0 with the same iOS 17/watchOS 10 floors. Record the actual runner version with each verified build.
- Official HKWorkoutSession documentation at developer.apple.com/tutorials/data/documentation/healthkit/hkworkoutsession.json was retrieved and confirms iOS 17, watchOS 2 availability; iPhone-side workout sessions are supported at the proposed floor.

### ADR-006 — Cloud-only build prerequisites (2026-10-12)
- Node/API/nginx images do not inherit the cloud proxy's configured root CA. Local Dockerfile overlays outside the checkout copy the platform's public trust bundle before TLS downloads; package signatures and TLS verification remain enabled. Android Gradle uses its supported Java proxy properties and a copy of the system truststore augmented with the platform CA certificates.
- Cloud checkouts have 0600/0700 source permissions. The local nginx image overlay grants its public template/static tree the read/search modes a normal Git checkout has. This corrects setup permissions, not application code; canonical Dockerfiles remain unchanged.
- Java 21 in the base machine is a JRE without javac. Temurin JDK 21.0.12.1+1 is installed outside the repository after checking its official release SHA-256. Swift 6.2.4 was verified in a Docker runtime, but a subsequent container launch exhausted the 32 GiB disk. The owned image was removed; do not pull/run that image again here. A smaller signed Swift toolchain or macOS CI is needed for Phase 2 tests.

### ADR-007 — Consistent simulator architecture for ML Kit (2026-10-12)
- VERIFIED Apple run 38299276900: Release simulator build passed; Debug tests failed because AppDelegate's Capacitor import requested x86_64, but Capacitor.framework had only an arm64 simulator Swift module.
- Existing Google ML Kit 7.x transitively configures arm64 simulator exclusion for the app. The CocoaPods post-install applies the same simulator-only exclusion to every pod configuration; the app project propagates it to both test targets as well. The verify script selects the x86_64 simulator destination explicitly, avoiding mismatched Debug/test slices. Physical iPhone arm64 remains enabled.
- Alternatives weighed: overriding all SDK architectures globally (risks real-device builds); removing the existing scanner (breaks existing functionality); replacing its dependency (unneeded during this phase).
- Consequence: rerun both simulator Release and native/UI tests before closing Phase 1. Log runner architecture/Xcode version through an Actions notice as well as normal stdout. Do not claim simulator camera scans validate real-device scanning.

- VERIFIED official pinned podspec `https://cdn.cocoapods.org/Specs/b/e/b/GoogleMLKit/7.0.0/GoogleMLKit.podspec.json` → both pod_target_xcconfig and user_target_xcconfig exclude arm64 for iphonesimulator. The diagnosis follows the actual dependency declaration.

### ADR-008 — Lossless state boundary and catalogue facts (2026-10-12)
- Keep raw-backed Codable state models with typed accessors so unknown/new app fields survive round trips. Exercise `id` stays a catalogue key; additive RecordIdentity carries a separate UUID, deviceId and updatedAt. Envelope v1 has a strict four-field schema; v0 is a reserved prototype snapshot migration, not a claim about previously shipped Watch data.
- Progression receives catalogue facts (loaded/bodyweight/assisted/cardio/default step/owned weights) from the phone snapshot. Do not maintain a second hard-coded list of 5,632 exercise ids in Swift. Golden fixtures preserve the production JavaScript function outputs and reasons; Swift executes its own implementation against them.
- OpenGymKit uses Foundation only and no third-party dependency. It is linked as a local Swift package to the existing App target; future Watch/extensions will use the same product. Mac CI runs its independent tests, and no Apple-only framework is introduced into the package.

### ADR-009 — Test resource budget and cache TTL probe (2026-10-12)
- VERIFIED Phase 2's API run had one failure in server-state-cache-bounds.test.js: the immediate second poll exceeded its 150 ms cache TTL while the frontend suite also ran. API code was unchanged; the isolated cache suite passed both tests once that CPU load ended.
- Run the full API suite separately with --test-concurrency=1 in this four-CPU environment. Preserve the existing TTL assertions and all 596 tests; do not increase the test TTL or disable a check to get green results.
- Extend the Swift golden corpus before closure: real exercise classification, assistance/bodyweight, owned dumbbells, plan changes, exclusions, and timed deloads near the rounding grid. The short-duration cases revealed a Swift deload rounding discrepancy, corrected to match the existing JavaScript deloadTo behaviour.

### ADR-010 — Apple Health identity, consent and simulator store (2026-10-12)
- Keep HealthKit outside OpenGymKit. Pure records validate dates, UUIDs, quantities and decoded JSON; native HKWorkoutBuilder writes the actual workout intervals, provided energy and openGym UUID/sync version metadata. No calorie estimate or missing workout timestamp is invented. iPhone HKWorkoutSession is available at iOS 17; live/mirrored sessions and sensor summaries follow the Watch/insight phases. Imported sessions still use the builder without pretending an old session was live.
- Existing short workout ids remain unchanged. A device-private identity map is atomically persisted by native Foundation before writing Health; retries keep the UUID and version. New transport identities will also be stored on state records in Phase 5. Mock workouts deduplicate by UUID; native samples use HealthKit sync identifiers/versions. Changed records advance their version; partial write failures retry the same version.
- Health authorization is off by default, requested only after the Settings purpose row is visible and the user enables the switch. Empty Health results never imply read permission was denied. Turning sync off retains Health history. Real writes/reads and permission-denial behavior require the device checklist.
- The simulator uses an explicitly labelled persistent mock Health store. File corruption/storage failures reach the bridge caller; a corrupt identity map must not be silently replaced. Measurements use canonical kg/fraction/metres; app values remain kg/lb, percent/cm. Health supports body mass, body fat and waist; other existing circumference fields remain in openGym.
- Import deduplication preserves Health source/sample identity and existing newer user entries. Rounded imported measurements are not echoed as new openGym samples. The original Android Health Connect code is unchanged. All six new purpose/control strings cover the 18 packs, English and the derived Swiss German locale.
