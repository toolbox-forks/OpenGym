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
