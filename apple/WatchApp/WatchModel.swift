import Foundation
import SwiftUI
import WatchKit
import OpenGymKit

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published var error: String?
    @Published private(set) var vitals = WatchVitals()
    @Published var purpose = false
    @Published private(set) var finishing = false
    @Published private(set) var savedWorkout: JSONValue?
    let resources = WatchResources.shared
    private var journal: WatchJournal?
    private var health: WatchHealth?
    private var requestedRoutine: String?
    private var ticker: Timer?
    private var lastRestDeadline = 0.0
    private var lastSummaryWrite = 0.0
    private var didAskHealth = false
    var machine: WatchSessionMachine? { journal?.machine }
    var language: String { resources.language(machine?.state.snapshot.text("lang") ?? "") }
    var unit: String { machine?.state.active?.text("unit") ?? machine?.state.snapshot.text("unit", default: "kg") ?? "kg" }
    var currentEntry: JSONValue? { machine?.currentEntry }
    var currentSet: JSONValue? { machine?.currentSet }
    var active: JSONValue? { machine?.state.active }
    var now: Double { Date().timeIntervalSince1970 * 1000 }
    func t(_ key: String, _ args: String...) -> String { resources.text(key, lang: language, args: args) }
    func name(_ id: String) -> String { resources.name(id, lang: language) }
    init() {
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            var folder = base.appendingPathComponent("training")
            var snapshot = JSONValue.object(["unit": .string("kg"), "routines": .array([])])
            #if targetEnvironment(simulator)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--ui-seed") {
                let index = args.firstIndex(of: "--ui-case")
                let label = index.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "default"
                folder = base.appendingPathComponent("acceptance-" + label)
                snapshot = WatchResources.json("seed")
                if args.contains("--ui-reset") { try? FileManager.default.removeItem(at: folder) }
            }
            #endif
            journal = try WatchJournal(folder: folder, seed: WatchTrainingState(snapshot: snapshot), catalogue: resources.catalogue)
            health = try WatchHealth(folder: folder)
            health?.onUpdate = { [weak self] value in self?.received(value) }
            if let active {
                Task { do { try await health?.start(active, recovering: true) } catch { error = t("Unable to save") } }
            }
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch { self.error = "Unable to save" }
    }
    @discardableResult private func mutate(completed: Bool = false, _ change: (inout WatchSessionMachine) throws -> Void) -> Bool {
        do {
            guard let journal else { throw WatchSessionError.corruptStore }
            try journal.perform(completed: completed, change)
            revision += 1
            return true
        } catch { self.error = t("Unable to save"); return false }
    }
    func start(_ routine: String?) {
        requestedRoutine = routine
        if !didAskHealth { purpose = true; return }
        begin(routine)
    }
    func allowHealth() {
        purpose = false
        Task {
            do { try await health?.authorize(); didAskHealth = true; begin(requestedRoutine) }
            catch { error = t("Unable to save"); didAskHealth = true; begin(requestedRoutine) }
        }
    }
    func localOnly() { purpose = false; didAskHealth = true; begin(requestedRoutine, healthEnabled: false) }
    private func begin(_ routine: String?, healthEnabled: Bool = true) {
        let time = now
        guard mutate({ try $0.start(routineId: routine, now: time) }) else { return }
        savedWorkout = nil
        if let active, healthEnabled {
            Task { do { try await health?.start(active) } catch { vitals.unavailable = true; error = t("Unable to save") } }
        }
    }
    func confirm(expectedUUID: String) {
        guard currentSet?.text("uuid") == expectedUUID else { return }
        let time = now
        if mutate({ _ = try $0.confirm(expectedSetUUID: expectedUUID, now: time) }) { WKInterfaceDevice.current().play(.click) }
    }
    func adjust(_ key: String, _ value: Double) { let time = now; mutate { try $0.adjust(field: key, value: value, now: time) } }
    func skipRest() { let time = now; mutate { try $0.rest(add: nil, now: time) } }
    func moreRest() { let time = now; mutate { try $0.rest(add: 15, now: time) } }
    func add(_ id: String) { let time = now; mutate { try $0.addExercise(id: id, now: time) } }
    func replace(_ index: Int, id: String) { let time = now; mutate { try $0.replaceExercise(at: index, id: id, now: time) } }
    func move(_ from: Int, to: Int) { let time = now; mutate { try $0.moveExercise(from: from, to: to, now: time) } }
    func skip(_ index: Int) { let time = now; mutate { try $0.skipExercise(at: index, now: time) } }
    func addSet(_ index: Int) { let time = now; mutate { try $0.addSet(at: index, now: time) } }
    func deleteSet(_ entry: Int, set: Int) { let time = now; mutate { try $0.deleteSet(entry: entry, set: set, now: time) } }
    func tag(_ value: String) { let time = now; mutate { try $0.tag(value, now: time) } }
    private func received(_ value: WatchVitals) {
        vitals = value
        let time = now
        if active != nil && time - lastSummaryWrite >= 5000 {
            lastSummaryWrite = time
            mutate { try $0.summary(heartRate: value.heartRate, energy: value.energyKcal, now: time) }
        }
    }
    private func tick() {
        let deadline = active?.number("restUntil") ?? 0
        if deadline > 0 && deadline <= now && deadline != lastRestDeadline {
            lastRestDeadline = deadline
            WKInterfaceDevice.current().play(.notification)
        }
        if active != nil { revision += 1 }
    }
    func closeSaved() { savedWorkout = nil }
    func finish() {
        guard let active, !finishing, (machine?.completedSetCount ?? 0) > 0 else { return }
        finishing = true
        Task {
            let end = now
            var savedHealth = false
            do { savedHealth = try await health?.finish(active, end: end) ?? false }
            catch { error = t("Unable to save") }
            do {
                guard let journal else { throw WatchSessionError.corruptStore }
                var done: JSONValue?
                try journal.perform(completed: true) { machine in
                    try machine.summary(heartRate: vitals.heartRate, energy: vitals.energyKcal, now: end)
                    done = try machine.finish(now: end)
                }
                savedWorkout = done
                // This is an explicit sensor/store outcome; transport integration follows in Phase 5.
                if savedHealth { WKInterfaceDevice.current().play(.success) }
                revision += 1
            } catch { self.error = t("Unable to save") }
            finishing = false
        }
    }
}
