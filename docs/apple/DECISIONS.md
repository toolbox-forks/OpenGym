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
