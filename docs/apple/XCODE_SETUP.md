# Build the iPhone app from Xcode

WRITTEN setup guide — Release simulator build and all 6 native/UI tests passed in Apple CI run 38301101740 on Xcode 16.4 after the simulator architecture correction. Linux web checks alone do not prove an Xcode build. Phase 1 supplies OpenGym; OpenGym Watch App will be introduced in Phase 4. App Store submission is outside this goal.

Owner reports Xcode **27.0** installed locally on 2026-10-12. Local availability/version is owner-reported; run `xcodebuild -version` on that Mac and retain the result with simulator evidence. CI records its own installed Xcode version and may differ.

## Prerequisites

1. Use a Mac with Xcode 16 or later, command-line tools selected in Xcode → Settings → Locations, and an iOS simulator runtime installed under Settings → Components. Minimum supported iPhone OS is iOS 17. Future Watch targets use watchOS 10.
2. Clone the fork and check out `apple-native`. Use Node 22 (the same major as CI) and CocoaPods 1.16.2. Install CocoaPods with `gem install --user-install cocoapods --version 1.16.2 --no-document`, then add `$(ruby -e 'puts Gem.user_dir')/bin` to PATH. `pod --version` must return 1.16.2.
3. From the repository root run:

```bash
cd frontend
npm ci
VITE_MOBILE=1 npm run build
node ../scripts/catalogue/stage-media.mjs dist
npx cap sync ios
node scripts/check-mobile-bundle.mjs
cd ..
```

The build is standalone: no API, sign-in account or Oura credentials required. Exercise media comes from the inherited catalogue and is bundled offline, retaining NOTICE.md. `cap sync ios` copies assets, discovers installed plugins and runs pod install; this is not an iPhone simulator build by itself. CocoaPods produces Podfile.lock; retain the resolved lock when the first Mac build confirms it. Do not commit generated public assets, Pods or owner secrets.

## Simulator

1. Open `frontend/ios/App/App.xcworkspace` (the workspace includes CocoaPods). Choose the **OpenGym** scheme. Its native target remains named App for compatibility with Capacitor/CocoaPods.
2. Select an iPhone simulator in the destination menu. Simulator builds need no Apple team or credentials. Product → Run.
3. At first launch select **Use on this device**. Open Plan, Stats and Exercises; search the library, begin a freestyle workout, add an exercise, tick a set, edit reps/load, finish and inspect History. Relaunch and confirm the data stayed. Exercise media works without network because the package carries it.
4. Check notch/home-indicator spacing in both orientations and a numeric input above the keyboard. Haptic hardware is unavailable in a simulator; keep that check in the device checklist.
5. To run the Release build and registered native/UI tests from Terminal:

```bash
bash scripts/apple/verify-iphone.sh
```

The inherited Google ML Kit 7.x SDK uses x86_64 simulator slices. On Apple Silicon select a Rosetta iPhone simulator destination if Xcode offers separate native/Rosetta choices. Device builds remain arm64. The script selects an available simulator by UDID with its x86_64 destination, builds Release, runs five native geometry tests and one standalone navigation/relaunch test, and saves logs/xcresult under ignored `frontend/ios/App/output`. Delete or move a previous iphone-tests.xcresult before repeating; xcodebuild requires a new result path. Treat compile failures as failures to fix, not as verification. Product → Test runs the same scheme in Xcode.

## Personal device

Copy Config/Local.example.xcconfig to ignored Config/Local.xcconfig. Set APPLE_TEAM_ID to the team in Xcode → Settings → Accounts, BUNDLE_ID_PREFIX to your own reverse-DNS identifier, and APP_GROUP_ID to the matching group identifier. Defaults use com.example.opengym for simulator work. Select the device and configure Signing & Capabilities for the App target. Config files chain the CocoaPods Debug/Release settings before the owner overrides; do not replace those includes.

CocoaPods may report a custom base configuration because the target uses Config/Debug.xcconfig and Config/Release.xcconfig. They include Pods-App.*.xcconfig explicitly. Never remove those includes to suppress a warning.

No Oura client secret belongs in a distributed mobile xcconfig/binary. Tier 2 exchange configuration will live on the owner's exchange service, and user tokens will live in the Keychain.

## CI and evidence

GitHub fork → Actions → Apple → choose apple-native (enable workflows if the fork disabled them). Each push runs Release and native/UI simulator checks on macos-15. Download iphone-evidence-<commit> and record the actual test counts and result in PROGRESS.md. The workflow covers the iPhone shell in Phase 1; later phases must add the Swift package and Watch build/UI gates before claiming those exist.

## Preserve web and Android

Building mobile reuses frontend/dist. Run `npm --prefix frontend run build` again before using dist for self-hosted web deployment. Android keeps its existing SDK, package id, Java 21, storage and native plugins. Do not change frontend/capacitor.config.json's shared appId to personalize iOS: Apple bundle identifiers are overridden in Config/Local.xcconfig instead.
