import SwiftUI
import OpenGymKit

struct WatchRootView: View {
    @ObservedObject var model: WatchModel
    var body: some View {
        NavigationStack {
            Group {
                if model.active != nil { ActiveWorkoutView(model: model) }
                else if let saved = model.savedWorkout { SavedWorkoutView(model: model, workout: saved) }
                else { StartWorkoutView(model: model) }
            }
            .navigationTitle("openGym")
            .sheet(isPresented: $model.purpose) { HealthPurposeView(model: model) }
            .alert(model.t("Unable to save"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(model.t("Done")) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
        .tint(.mint)
    }
}

struct StartWorkoutView: View {
    @ObservedObject var model: WatchModel
    var body: some View {
        List {
            if let id = model.machine?.state.snapshot.rows("todayRoutineIds").first?.stringValue,
               let routine = model.machine?.routines.first(where: { $0.text("id") == id }) {
                Button { model.start(id) } label: {
                    VStack(alignment: .leading) { Text(model.t("Today")).font(.caption); Text(routine.text("name", default: routine.text("n"))).font(.headline) }
                }.accessibilityIdentifier("start-today")
            }
            Button(model.t("Freestyle workout")) { model.start(nil) }.accessibilityIdentifier("start-empty")
            Section(model.t("Routines")) {
                ForEach(Array((model.machine?.routines ?? []).enumerated()), id: \.offset) { _, routine in
                    Button(routine.text("name", default: routine.text("n"))) { model.start(routine.text("id")) }
                        .accessibilityIdentifier("routine-" + routine.text("id"))
                }
            }
            NavigationLink(model.t("History")) {
                List(Array((model.machine?.state.history ?? []).reversed().enumerated()), id: \.offset) { _, workout in
                    VStack(alignment: .leading) { Text(workout.text("name")); Text(workout.text("d")).font(.caption) }
                }
            }
        }
    }
}

struct HealthPurposeView: View {
    @ObservedObject var model: WatchModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("Apple Health")).font(.headline)
                Text(model.t("Save workouts, energy and body measurements. Read body measurements, heart rate and recovery. Data stays on your device and your own server.")).font(.caption)
                Button(model.t("Allow")) { model.allowHealth() }.accessibilityIdentifier("allow-health")
                Button(model.t("Skip")) { model.localOnly() }.accessibilityIdentifier("skip-health")
            }.padding()
        }
    }
}

struct ActiveWorkoutView: View {
    @ObservedObject var model: WatchModel
    @Environment(\.isLuminanceReduced) private var dimmed
    private var remaining: Double { model.machine?.restRemaining(now: model.now) ?? 0 }
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    Label(model.vitals.heartRate.map { String(Int($0.rounded())) } ?? "—", systemImage: "heart.fill").foregroundStyle(.red)
                        .accessibilityLabel(model.t("Heart rate"))
                    Spacer()
                    Text(model.vitals.energyKcal.map { String(Int($0.rounded())) + " kcal" } ?? "—").font(.caption)
                        .accessibilityLabel(model.t("Energy"))
                }
                if let heart = model.vitals.heartRate {
                    Text(model.t("Zone {0}", String(min(5, max(1, Int(heart / 190 * 10) - 4))))).font(.caption).foregroundStyle(.secondary)
                }
                if model.vitals.mock { Text(model.t("Simulator Health store")).font(.caption2).foregroundStyle(.secondary) }
                if remaining > 0 {
                    VStack {
                        Text(model.t("Rest")).font(.caption)
                        Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)).font(.title.monospacedDigit())
                            .accessibilityIdentifier("rest-countdown")
                        HStack {
                            Button("+15 s") { model.moreRest() }.accessibilityIdentifier("rest-add")
                            Button(model.t("Skip")) { model.skipRest() }.accessibilityIdentifier("rest-skip")
                        }
                    }.opacity(dimmed ? 0.7 : 1)
                }
                if let entry = model.currentEntry {
                    let id = entry.text("id")
                    Text(model.name(id)).font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("exercise-name")
                    if let image = model.resources.thumbnail(id) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 64)
                        Text("© Gym visual").font(.caption2)
                    }
                    if let set = model.currentSet {
                        let rows = entry.rows("sets"), index = model.machine?.currentSetIndex ?? 0
                        Text(model.t("Set {0} of {1}", String(index + 1), String(rows.count))).font(.caption).accessibilityIdentifier("set-context")
                        if let previous = entry["previous"].rows("sets").last(where: { $0.flag("done") }) {
                            Text(model.t("Previous") + ": " + number(previous.number("w")) + " " + model.unit + " × " + number(previous.number("r"))).font(.caption2)
                        }
                        let why = entry["plan"].rows("why")
                        if let source = why.first?.stringValue {
                            Text(model.resources.text(source, lang: model.language, args: why.dropFirst().map { $0.stringValue ?? number($0.doubleValue ?? 0) })).font(.caption2).foregroundStyle(.secondary)
                        }
                        SetControls(model: model, entry: entry, set: set)
                    }
                }
                Text(model.t("Sets") + ": " + String(model.machine?.completedSetCount ?? 0)).font(.caption).accessibilityIdentifier("completed-count")
                NavigationLink(model.t("Edit")) { WorkoutEditorView(model: model) }.accessibilityIdentifier("edit-workout")
                Button(model.t("Finish workout")) { model.finish() }.disabled(model.finishing || (model.machine?.completedSetCount ?? 0) == 0)
                    .accessibilityIdentifier("finish-workout")
            }.padding(.horizontal, 4)
        }
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

struct SetControls: View {
    @ObservedObject var model: WatchModel
    let entry: JSONValue
    let set: JSONValue
    @State private var field = "w"
    @State private var crown = 0.0
    @FocusState private var crownFocused: Bool
    private var mode: String { entry["target"].text("mode", default: "reps") }
    private var secondary: String { mode == "time" ? "sec" : mode == "cardio" ? "min" : "r" }
    private var step: Double { field == "w" ? entry["target"].number("inc", default: model.machine?.facts(for: entry.text("id")).increment ?? 2.5) : field == "sec" ? 5 : 1 }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if mode != "cardio" { numeric("w", title: model.t("Weight"), suffix: model.unit) }
                numeric(secondary, title: model.t(mode == "time" ? "Time" : mode == "cardio" ? "Minutes" : "Reps"), suffix: mode == "time" ? "s" : "")
            }
            if mode == "cardio" {
                HStack { numeric("speed", title: model.t("Speed"), suffix: ""); numeric("incline", title: model.t("Incline"), suffix: "%") }
            }
            if let effort = model.machine?.state.snapshot.text("effort"), ["rir", "rpe"].contains(effort) {
                numeric(effort, title: effort.uppercased(), suffix: "")
            }
            Menu(model.t("Set type")) {
                Button(model.t("Normal")) { model.tag("straight") }
                Button(model.t("Warm-up")) { model.tag("warmup") }
                Button(model.t("To failure")) { model.tag("failure") }
                Button(model.t("Drop set")) { model.tag("dropset") }
            }
            Button { model.confirm(expectedUUID: set.text("uuid")) } label: {
                Label(model.t("Done"), systemImage: "checkmark.circle.fill").font(.headline).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("complete-set")
        }
        .focusable().focused($crownFocused)
        .digitalCrownRotation($crown, from: 0, through: 10000, by: max(0.1, step), sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in model.adjust(field, value) }
        .onAppear { crown = set.number(field); crownFocused = true }
        .onChange(of: set.text("uuid")) { _, _ in crown = set.number(field) }
    }
    private func numeric(_ key: String, title: String, suffix: String) -> some View {
        Button {
            field = key; crown = set.number(key); crownFocused = true
        } label: {
            VStack { Text(title).font(.caption2); Text(set.number(key).formatted(.number.precision(.fractionLength(0...1)))).font(.title3.monospacedDigit()); if !suffix.isEmpty { Text(suffix).font(.caption2) } }
        }.accessibilityLabel(title).accessibilityValue(String(set.number(key))).accessibilityIdentifier("value-" + key)
    }
}

struct WorkoutEditorView: View {
    @ObservedObject var model: WatchModel
    var body: some View {
        List {
            NavigationLink(model.t("Add exercise")) { ExercisePickerView(model: model, replacing: nil) }.accessibilityIdentifier("add-exercise")
            ForEach(Array((model.machine?.entries ?? []).enumerated()), id: \.offset) { index, entry in
                Section(model.name(entry.text("id"))) {
                    NavigationLink(model.t("Replace")) { ExercisePickerView(model: model, replacing: index) }
                    Button(model.t("Move up")) { if index > 0 { model.move(index, to: index - 1) } }.disabled(index == 0)
                    Button(model.t("Move down")) { if index + 1 < (model.machine?.entries.count ?? 0) { model.move(index, to: index + 1) } }.disabled(index + 1 >= (model.machine?.entries.count ?? 0))
                    Button(model.t("Skip exercise")) { model.skip(index) }
                    Button(model.t("Add set")) { model.addSet(index) }
                    ForEach(Array(entry.rows("sets").enumerated()), id: \.offset) { setIndex, _ in
                        Button(model.t("Delete set") + " " + String(setIndex + 1), role: .destructive) { model.deleteSet(index, set: setIndex) }
                    }
                }
            }
        }.navigationTitle(model.t("Edit"))
    }
}

struct ExercisePickerView: View {
    @ObservedObject var model: WatchModel
    let replacing: Int?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var ids: [String] {
        model.resources.catalogue.keys.sorted().filter { query.isEmpty || model.name($0).localizedCaseInsensitiveContains(query) }.prefix(60).map { $0 }
    }
    var body: some View {
        List {
            TextField(model.t("Exercises"), text: $query).accessibilityIdentifier("exercise-search")
            ForEach(ids, id: \.self) { id in
                Button(model.name(id)) { if let replacing { model.replace(replacing, id: id) } else { model.add(id) }; dismiss() }
            }
        }.navigationTitle(model.t("Exercises"))
    }
}

struct SavedWorkoutView: View {
    @ObservedObject var model: WatchModel
    let workout: JSONValue
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.mint)
                Text(model.t("Saved on Watch")).font(.headline).accessibilityIdentifier("workout-saved")
                Text(workout.text("name"))
                Text(String(workout.rows("entries").reduce(0) { $0 + $1.rows("sets").filter { $0.flag("done") }.count }) + " " + model.t("Sets"))
                Text(workout.number("vol").formatted(.number.precision(.fractionLength(0...1))) + " " + model.unit)
                Button(model.t("Done")) { model.closeSaved() }.accessibilityIdentifier("saved-done")
            }.padding()
        }
    }
}
