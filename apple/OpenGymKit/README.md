# OpenGymKit

Pure Foundation Swift package for the shared Apple contract and training calculations. Minimum deployment: iOS 17, watchOS 10, macOS 13. No HealthKit, UIKit, WatchKit or third-party dependency is imported here.

`GymState`, `Workout`, `Routine`, `ExerciseEntry` and `SetRecord` provide typed accessors over lossless JSON. Unknown fields, original catalogue ids and legacy workout ids survive encoding; reading state is not a migration. `RecordIdentity` adds UUID/device/timestamp identity separately. `SyncEnvelope` implements the shared v1 schema in `../Contracts`; unsupported versions/kinds, extra envelope keys and invalid timestamps are rejected. Version 0 is a reserved prototype snapshot migration, not an earlier released Watch format.

`TrainingMath` supplies the seven 1RM formulas plus the weighted/RIR ensemble, kg/lb conversion with the app's rounding, load stepping, and the existing warm-up ramp. `PlateLoading.stack` handles finite plate inventories and non-greedy exact fits. `Progression.readSession` and `next` implement the existing history grading/policies and explanation templates.

Pass `ExerciseFacts` from the phone's canonical catalogue projection: assisted/loaded/bodyweight/cardio classification, default increment and owned dumbbells in the exercise's existing load meaning. Do not duplicate the exercise-id database in a native target. Workout history order matches the JavaScript state (oldest to newest); exclusions, routine slots and the plan stamps remain authoritative.

The single golden JSON corpus lives under `Tests/OpenGymKitTests/Fixtures/golden.json`. JavaScript's `apple-golden.test.js` and Swift's `GoldenTests` execute it independently. Inputs include the regression patterns exercised by the existing frontend tests. Generate/review with:

```bash
node scripts/apple/generate-golden.mjs
node scripts/apple/generate-golden.mjs --check
swift test --package-path apple/OpenGymKit
```

Run those commands from the repository root. A Mac CI job uses `scripts/apple/verify-kit.sh` and rejects zero-test results. Linux can use a signature-verified installed Swift toolchain; the large Swift Docker image exhausted this cloud machine's disk and must not be used here. See docs/apple/PROGRESS.md for exact revision/test evidence and BLOCKERS.md for the optional Linux toolchain prerequisite.
