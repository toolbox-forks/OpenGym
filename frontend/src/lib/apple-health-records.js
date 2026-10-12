// Pure boundary shared by the phone bridge tests. App IDs and catalogue IDs remain untouched.
import { sessionType, weightRecord, recordKey } from './health-connect.js'
import { isoOf } from './format.js'

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const positive = n => Number.isFinite(n) && n > 0
const massFactor = unit => unit === 'lb' ? 2.2046226218 : 1
const importedDisplay = (r, unit) => r.kind === 'bodyMass'
  ? Math.round(r.value * massFactor(unit) * 10) / 10
  : Math.round(r.value * 1000) / 10
export function appleHealthRecords(S, identities = {}, makeUUID = () => crypto.randomUUID()) {
  const ids = { ...identities }, workouts = [], measurements = []
  for (const w of S.workouts || []) {
    if (!w.id || !positive(w.start) || !positive(w.end) || w.end <= w.start) continue
    const key = String(w.id)
    const uuid = uuidPattern.test(w.uuid || '') ? w.uuid : uuidPattern.test(ids[key] || '') ? ids[key] : makeUUID()
    if (!uuidPattern.test(uuid)) throw new Error('Invalid workout UUID')
    ids[key] = uuid.toLowerCase()
    const energy = Number.isFinite(w.energyKcal) && w.energyKcal >= 0 ? w.energyKcal : null
    workouts.push({ clientId: 'opengym-w-' + key, uuid: ids[key], title: String(w.name || ''),
      start: w.start, end: w.end, activity: w.healthActivity || sessionType(w), energyKcal: energy })
  }
  const imported = new Map(), unit = S.unit === 'lb' ? 'lb' : 'kg'
  for (const r of S.appleHealthMeasurements || []) {
    if (!positive(r.value) || !positive(r.time)) continue
    const day = r.appDay || isoOf(new Date(r.time)), key = day + '|' + r.kind
    const displayed = r.kind === 'bodyMass' && r.appUnit === unit && positive(r.appValue) ? r.appValue : importedDisplay(r, unit)
    const canonical = r.kind === 'bodyMass' ? Math.round(displayed / massFactor(unit) * 1000) / 1000 : displayed / 100
    if (!imported.has(key)) imported.set(key, new Set())
    imported.get(key).add(canonical)
  }
  const take = (row, day) => {
    if (!positive(row.value) || !positive(row.time) || row.kind === 'bodyFat' && row.value > 1) return
    // An imported sample is never echoed back into Health as a new openGym sample.
    if (imported.get(day + '|' + row.kind)?.has(row.value)) return
    measurements.push(row)
  }
  for (const b of S.bodyweight || []) {
    const r = weightRecord(b, S.unit)
    if (r) take({ clientId: r.id, kind: 'bodyMass', value: r.kg, time: r.time, source: 'openGym' }, b.d)
  }
  for (const m of S.measurements || []) {
    if (!positive(m.t)) continue
    for (const kind of ['bodyFat', 'waist']) {
      if (!positive(m[kind])) continue
      take({ clientId: 'opengym-' + kind + '-' + m.d, kind, value: m[kind] / 100, time: m.t, source: 'openGym' }, m.d)
    }
  }
  return { workouts, measurements, identities: ids }
}

export function planAppleHealth(records, written = {}) {
  const next = { ...written }, workouts = [], measurements = []
  for (const [kind, rows] of [['workouts', records.workouts], ['measurements', records.measurements]]) {
    const seen = new Set()
    for (const row of rows) {
      if (seen.has(row.clientId)) continue
      seen.add(row.clientId)
      const h = recordKey(row), old = written[row.clientId]
      const version = old?.h === h ? old.version : (old?.version || 0) + 1
      next[row.clientId] = { h, version }
      if (old?.h !== h) (kind === 'workouts' ? workouts : measurements).push({ ...row, version })
    }
  }
  // Turning off or deleting a local row retains Health data. Health has its own user-controlled history.
  return { workouts, measurements, written: next }
}

export function mergeHealthMeasurements(S, rows, ownIds = new Set()) {
  const sources = new Map((S.appleHealthMeasurements || []).map(r => [r.source + '|' + (r.sampleId || r.time) + '|' + r.kind, r]))
  const body = new Map((S.bodyweight || []).map(r => [r.d, { ...r }]))
  const measures = new Map((S.measurements || []).map(r => [r.d, { ...r }]))
  let changed = false
  for (const r of [...rows].sort((a, b) => a.time - b.time)) {
    if (!['bodyMass', 'bodyFat', 'waist'].includes(r.kind) || !positive(r.value) || !positive(r.time) || r.kind === 'bodyFat' && r.value > 1 || ownIds.has(r.clientId)) continue
    const key = String(r.source || '') + '|' + (r.sampleId || r.time) + '|' + r.kind
    if (sources.has(key)) continue
    const d = isoOf(new Date(r.time))
    sources.set(key, { ...r, appDay: d, appUnit: S.unit === 'lb' ? 'lb' : 'kg', appValue: importedDisplay(r, S.unit) }); changed = true
    if (r.kind === 'bodyMass') {
      const old = body.get(d)
      if (old && old.t >= r.time) continue
      body.set(d, { ...old, d, t: r.time, w: importedDisplay(r, S.unit) })
    } else {
      const old = measures.get(d)
      if (old && old[r.kind] != null && old.t >= r.time) continue
      measures.set(d, { ...old, d, t: Math.max(old?.t || 0, r.time), [r.kind]: importedDisplay(r, S.unit) })
    }
  }
  return changed ? { ...S, bodyweight: [...body.values()].sort((a, b) => a.d.localeCompare(b.d)),
    measurements: [...measures.values()].sort((a, b) => a.d.localeCompare(b.d)), appleHealthMeasurements: [...sources.values()] } : S
}
