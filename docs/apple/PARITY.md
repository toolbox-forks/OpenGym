# Strong parity inventory (2026-10-12)

This is the Phase 0 inventory of actual source, not a claim of iPhone/Watch validation. All rows are WRITTEN until their specific feature checks are cited; the baseline suite validates existing JS behaviour separately. No row has been deferred. Phase assignments close only with BRIEF §9/§10 evidence.

| # | Capability | Existing source / gap | Phase | Status |
|---|---|---|---|---|
| 1 | Dense Previous/load/reps table, one-tap completion | Workout.jsx, FocusView.jsx, history.js; refine density + native ergonomics | 1,6 | WRITTEN inventory |
| 2 | Library, demos, customs, ranked highlighted search | exercises.js/searchExercises, Library.jsx, Media.jsx; verify ranking/highlight and attribution | 6,10 | WRITTEN inventory |
| 3 | Templates, empty workout, folders, search | session-merge.js empty list builds freestyle; Plan/RoutineEdit; folders/search need work | 6 | WRITTEN inventory |
| 4 | Auto rest and Live Activity/Dynamic Island controls | useUI rest logic, Android RestAlert; iOS integration absent | 8 | WRITTEN inventory |
| 5 | Reps, bodyweight, assisted, weighted, duration, cardio | history.js, exercises.js, speed.js, assisted/bodyweight tests; verify native entries | 4,6 | WRITTEN inventory |
| 6 | Warm-up/failure/drop tags; warm-ups excluded from PR/volume | workout-model.js/history.js/onerm.js, FocusView; existing exclusions/tests | 2,4,6 | WRITTEN inventory |
| 7 | Supersets/grouped exercises | supersetFlow/meta, session merge; Watch support absent | 4,6 | WRITTEN inventory |
| 8 | PRs, volume, 1RM, total weight | onerm.js/history.js, Stats.jsx; add timelines/recovery context | 7 | WRITTEN inventory |
| 9 | Warm-up calculator | buildSets warm-up ramps, history.js; shared explicit calculator/UI needed | 2,6 | WRITTEN inventory |
| 10 | Plate calculator / bars / kg+lb | plates.js/bar.js inventory already present; shared Swift calculator needed | 2,6 | WRITTEN inventory |
| 11 | Body measurements and Health | measurements.js + BodyMeasurements view; iOS Health bridge absent | 3,6,7 | WRITTEN inventory |
| 12 | Mixed per-exercise kg/lb | units.js converts whole profile; no verified per-exercise override | 6 | WRITTEN inventory |
| 13 | Workout/exercise notes and local progress photos | day-notes, finish-workout note retention, ProgressPhotos, device media store; verify privacy | 6,7 | WRITTEN inventory |
| 14 | Routine/workout share sheet + image card | plan-share, mobile share + text/PDF; image summary card needed | 6,7 | WRITTEN inventory |
| 15 | CSV workouts and measurements | import-csv present, JSON export; CSV exporter needed | 6 | WRITTEN inventory |
| 16 | Self-hosted/Watch sync | sync-merge/changing revisions/file mirror present; WC transport absent | 5 | WRITTEN inventory |
| 17 | Independent Watch | no existing Watch target | 4,5 | WRITTEN inventory |
| 18 | Calendar/activity/weekly widgets | no WidgetKit extension | 8 | WRITTEN inventory |
| 19 | Siri / Shortcuts | no App Intents | 8 | WRITTEN inventory |
| 20 | History calendar and start-history date | History.jsx + Heatmap; calendar/date preference needs validation/addition | 6,7 | WRITTEN inventory |

## Watch §7.2 acceptance tracking

| Behaviour | Phase | Status / evidence required |
|---|---|---|
| 1 Start today/any/empty, complication/Smart Stack | 4,8 | WRITTEN inventory; simulator launch/UI tests required |
| 2 Confirm, Crown increments/haptics, Action/Double Tap | 4,8,10 | WRITTEN inventory; UI tests + physical hardware checklist |
| 3 Context/reason/previous/tag/effort/thumbnail | 2,4 | WRITTEN inventory; contract fixtures + UI tests |
| 4 Automatic rest, Always-On, +15/skip/haptic | 4 | WRITTEN inventory; timer state tests + device display/haptics |
| 5 Add/replace/reorder/skip, sets, superset alternation | 4 | WRITTEN inventory; reducer and UI tests |
| 6 HR/energy/zone throughout workout | 3,4,7 | WRITTEN inventory; mock tests + physical HealthKit workout |
| 7 Independent store/catalogue/previous/Health completion | 3,4 | WRITTEN inventory; offline seeded UI + Health mock test |
| 8 Crash/reboot/battery resume | 4 | WRITTEN inventory; atomic persistence and relaunch test + device |
| 9 Near-real-time bidirectional live edits | 5 | WRITTEN inventory; offline/duplicate/concurrent transport tests |

## Better than Strong acceptance tracking

| Differentiator | Phase | Status |
|---|---|---|
| Unlimited / no ads / no telemetry | 0,10 | WRITTEN inventory; retain default no-analytics build |
| Explained progression targets | 2,4 | WRITTEN inventory; same golden fixtures across platforms |
| Per-set HR, recovery, zones | 3,7 | WRITTEN inventory |
| Health/Oura recovery context | 9 | WRITTEN inventory |
| Owned data / self-host / JSON+CSV / Strong+Hevy import | 5,6 | WRITTEN inventory |
| Wrist controls/Always-On/complications | 4,8 | WRITTEN inventory |
| Muscle map / remaining weekly muscles | 7 | WRITTEN inventory |
| All existing UI languages on phone and Watch | 10 | WRITTEN inventory; 19-language requirement per ADR-002 |
