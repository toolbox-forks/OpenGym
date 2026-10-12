# Apple blockers

Updated 2026-10-12. Owner reports Xcode 27.0 installed on her Mac. The goal is incomplete. Phase 0 baseline validation passed; Phase 1 is next. No speculative feature is reported as shipped.

### B-01 — macOS/Xcode build oracle
- VERIFIED `uname -s` → Linux; `xcodebuild -version` → command not found.
- Needed from owner: allow the macOS GitHub Actions workflow to run, or provide a Mac/Xcode run with the exact commit and xcresult.
- Exact steps: after apple.yml is pushed, GitHub fork → Actions → enable workflows if disabled → run Apple workflow for apple-native. Follow XCODE_SETUP.md for local Release simulator build and standalone UI checks. Return the failing logs/xcresult if any; do not declare Apple targets verified merely because files exist.
- Unblocks: Phase 1 simulator build/launch and all subsequent Apple compile gates; §10 requires macOS evidence.
- Work continuing meanwhile: Phase 0 plan and locally testable Phase 1 shell/CI preparation. Later phases remain ordered behind their predecessor gates.

### B-02 — GitHub API and Apple SDK documentation network access [RESOLVED]
- VERIFIED `gh api repos/toolbox-forks/OpenGym` → Forbidden; unauthenticated `curl -I https://api.github.com` → proxy CONNECT 403. GH_TOKEN is present (value not inspected). Git read through existing platform proxy succeeds. This is network denial, not evidence of a missing token.
- Needed from owner: review/save the environment draft adding api.github.com, developer.apple.com, dl-cdn.alpinelinux.org and maven.google.com to custom allowed destinations, publish if prompted.
- Exact steps: environment settings → review saved network additions → Save → publish if prompted; resume the goal. Agent retries the actual API/documentation request after propagation. Existing package-manager presets are preserved.
- VERIFIED runtime update: `gh api repos/toolbox-forks/OpenGym --jq .full_name` → toolbox-forks/OpenGym; native workflow is running. Official HKWorkoutSession documentation JSON downloaded successfully and confirms iOS 17 support.
- Unblocks: reading macOS CI logs, verifying SDK API availability and opening the final PR through gh. If token permissions then fail, record that specific failure; do not supply tokens in chat.
- Work continuing meanwhile: repository inspection, tests, docs and local implementation.

### B-03 — Device signing and identifiers
- Needed from owner: signing team and chosen reverse-DNS bundle prefix for real devices; defaults are com.example.opengym and group.com.example.opengym for simulator development.
- Exact steps: Xcode → Settings → Accounts → add Apple ID/select team; copy Config/Local.example.xcconfig to ignored Config/Local.xcconfig; set APPLE_TEAM_ID, BUNDLE_ID_PREFIX, APP_GROUP_ID. Enable corresponding HealthKit/app-group capabilities in the Apple account for each device target.
- Unblocks: physical-device checks. Simulator builds continue unsigned.

### B-04 — Physical iPhone and Watch acceptance
- Needed from owner: paired iPhone/Apple Watch and under-30-minute DEVICE_TEST_CHECKLIST run once integration is complete.
- Exact steps: install both schemes from Xcode with owner signing, test a workout with phone absent, rest haptics/Always-On, live HR/energy, relaunch/resume, reconnect delivery, duplicate-free Health history, Action button and Double Tap where supported; record OS/hardware/commit and outcomes.
- Unblocks: actual Health writes, live sensors, background lifetime, WC physical transport and hardware controls. Checklist will be written in Phase 10; it is not yet a completed artifact.

### B-05 — Oura OAuth configuration (optional Tier 2)
- Needed from owner: Oura OAuth2 application registration and redirect, supplied securely to the owner's exchange service / Keychain. Do not put a client secret in a distributed app binary.
- Exact steps: register the application in Oura developer settings with opengym://oura/callback; enable required official scopes after API-reference verification; set client id/secret on the self-hosted exchange service through secure configuration. Standalone owner-controlled exchange will be documented; do not invent public-client support.
- Unblocks: Tier 2 sandbox/live end-to-end authorization. Tier 1 Apple Health remains independent of credentials.

### B-06 — Distribution licence review
- Needed from owner: review NOTICE.md, Gym visual terms for the fork's intended distribution and AGPL source obligations before public distribution.
- Exact steps: retain the inherited MIT dataset and Gym visual notices, obtain any needed media licence, and publish corresponding fork source. App Store submission is outside this goal.
- Unblocks: public distribution only, not source authoring or simulator validation.

### B-07 — Build dependency egress [RESOLVED]
- VERIFIED API Docker build failed at `apk upgrade --no-cache`: dl-cdn.alpinelinux.org APKINDEX downloads returned HTTP 403. Docker itself is available (28.4.0).
- Needed from owner: review/save the network draft additions in B-02.
- Exact steps: permit dl-cdn.alpinelinux.org for signed Alpine repository indexes, maven.google.com for Android's supported Maven repository. Agent will retry the affected build after runtime propagation. Do not force missing indexes or disable checksum/TLS/signature checks.
- VERIFIED network update allowed Alpine downloads; supported cloud trust and public file modes restored the API+nginx build and smoke. Android dependency resolution now reaches Java compilation.
- Unblocks: unchanged self-hosted Docker stack build/smoke and Android dependency retrieval. Java 21 is available; Android SDK preparation continues from already allowed dl.google.com.

### B-08 — CI evidence download destination denied
- VERIFIED GitHub API metadata/status is readable, but `gh api repos/toolbox-forks/OpenGym/actions/jobs/114972808235/logs` redirects to productionresultssa3.blob.core.windows.net, which the proxy refuses. `curl -I https://productionresultssa3.blob.core.windows.net` → CONNECT HTTP 403. Signed log URLs are not recorded here.
- Needed from owner: save/apply the latest environment network draft including productionresultssa3.blob.core.windows.net, or supply the CI evidence artifact from the Apple run / a local Xcode 27.0 run.
- Exact steps: environment settings → review/add that exact artifact hostname → Save and publish if prompted. Alternatively fork Actions → Apple run 38297653898 → download iphone-evidence artifact; attach its iphone-release.log, iphone-tests.log and xcresult. For local evidence follow XCODE_SETUP.md on the owner Mac and attach the same output.
- Unblocks: inspecting actual compiler/test outcomes and confirming nonzero native tests. CI is still running; no successful Apple build is claimed.
- Remaining work behind this gate: close Phase 1 only after diagnosing native outcomes; then Phase 2 OpenGymKit, Phase 3 Health bridge, Phase 4 Watch MVP, Phase 5 sync, Phase 6 parity, Phase 7 progress, Phase 8 integrations, Phase 9 Oura and Phase 10 hardening/PR report in order. PLAN/PARITY specify the exact work and test gates; none is silently deferred or claimed implemented.
