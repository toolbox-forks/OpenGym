import { describe, it, expect } from 'vitest'
import { appleHealthRecords, planAppleHealth, mergeHealthMeasurements } from './apple-health-records.js'
const uuid = 'bd0c1f64-9e48-4a29-a81e-4dcfcf79e218'
const time = new Date('2026-10-12T12:00:00').getTime()
const workout = { id: 'legacy-short-id', name: 'Strength', start: time, end: time + 60000, energyKcal: 125, entries: [] }
const row = { clientId: 'scale', kind: 'bodyMass', value: 80.037, time, source: 'Scale', sampleId: 'sample' }
describe('Apple Health boundary', () => {
  it('adds a durable UUID without changing existing workout IDs', () => {
    const S = { workouts: [workout] }
    const first = appleHealthRecords(S, {}, () => uuid)
    const retry = appleHealthRecords(S, first.identities, () => { throw Error('regenerated') })
    expect(retry).toEqual(first)
    expect(S.workouts[0].id).toBe('legacy-short-id')
    expect(first.workouts[0]).toMatchObject({ uuid, start: time, end: time + 60000, energyKcal: 125 })
  })
  it('preserves an existing valid UUID and rejects broken generation', () => {
    expect(appleHealthRecords({ workouts: [{ ...workout, uuid }] }).workouts[0].uuid).toBe(uuid)
    expect(() => appleHealthRecords({ workouts: [workout] }, {}, () => 'bad')).toThrow()
  })
  it('never invents workout times or energy', () => {
    const result = appleHealthRecords({ workouts: [{ ...workout, start: null }, { ...workout, end: time }, { ...workout, start: Infinity }] })
    expect(result.workouts).toEqual([])
    expect(appleHealthRecords({ workouts: [{ ...workout, energyKcal: -1 }] }, {}, () => uuid).workouts[0].energyKcal).toBeNull()
  })
  it('maps pounds, percent and centimetres into Health canonical units', () => {
    const r = appleHealthRecords({ unit: 'lb', bodyweight: [{ d: '2026-10-12', t: time, w: 220.46226218 }], measurements: [{ d: '2026-10-12', t: time, bodyFat: 21, waist: 85, chest: 90 }] })
    expect(r.measurements.map(m => [m.kind, m.value])).toEqual([['bodyMass', 100], ['bodyFat', .21], ['waist', .85]])
  })
  it('skips invalid measurements and unsupported circumferences', () => {
    const r = appleHealthRecords({ measurements: [{ d: '2026-10-12', t: time, bodyFat: 101, waist: -1, chest: 90 }, { d: '2026-10-13', t: NaN, waist: 85 }] })
    expect(r.measurements).toEqual([])
  })
  it('only writes changes and increments native versions deterministically', () => {
    const records = appleHealthRecords({ workouts: [workout] }, {}, () => uuid)
    const first = planAppleHealth(records)
    expect(first.workouts[0].version).toBe(1)
    expect(planAppleHealth(records, first.written).workouts).toEqual([])
    const edited = { ...records, workouts: [{ ...records.workouts[0], title: 'Changed' }] }
    const second = planAppleHealth(edited, first.written)
    expect(second.workouts[0].version).toBe(2)
    expect(planAppleHealth(edited, first.written)).toEqual(second) // failed native write retries same version
  })
  it('retains identifiers when local history is deleted', () => {
    const prior = { x: { version: 1, h: 'hash' } }
    expect(planAppleHealth({ workouts: [], measurements: [] }, prior).written).toEqual(prior)
  })
  it('merges source samples once and preserves an unchanged state reference', () => {
    const merged = mergeHealthMeasurements({ unit: 'kg' }, [row, row])
    expect(merged.bodyweight).toEqual([{ d: '2026-10-12', t: time, w: 80 }])
    expect(merged.appleHealthMeasurements).toHaveLength(1)
    expect(mergeHealthMeasurements(merged, [row])).toBe(merged)
  })
  it('does not echo a rounded imported measurement back to Health', () => {
    for (const unit of ['kg', 'lb']) {
      const merged = mergeHealthMeasurements({ unit }, [row])
      expect(appleHealthRecords(merged).measurements).toEqual([])
    }
  })
  it('writes a subsequent manual edit to an imported weigh-in', () => {
    const merged = mergeHealthMeasurements({ unit: 'kg' }, [row])
    merged.bodyweight[0].w = 82
    expect(appleHealthRecords(merged).measurements[0].value).toBe(82)
  })
  it('keeps newer local entries and unrelated measurement fields', () => {
    const S = { bodyweight: [{ d: '2026-10-12', t: time + 1, w: 82 }], measurements: [{ d: '2026-10-12', t: time + 1, chest: 90, waist: 87 }] }
    const merged = mergeHealthMeasurements(S, [row, { ...row, kind: 'waist', value: .85, sampleId: 'waist' }])
    expect(merged.bodyweight[0].w).toBe(82)
    expect(merged.measurements[0]).toMatchObject({ chest: 90, waist: 87 })
    expect(S.appleHealthMeasurements).toBeUndefined()
  })
  it('reads different sources with attribution and skips own native writes', () => {
    const merged = mergeHealthMeasurements({}, [row, { ...row, source: 'Other' }, { ...row, clientId: 'own', kind: 'waist', sampleId: 'w' }], new Set(['own']))
    expect(merged.appleHealthMeasurements.map(r => r.source)).toEqual(['Scale', 'Other'])
    expect(merged.measurements).toEqual([])
  })
  it('reads percent and waist into existing measurement fields', () => {
    const merged = mergeHealthMeasurements({}, [{ ...row, kind: 'bodyFat', value: .213, sampleId: 'fat' }, { ...row, kind: 'waist', value: .853, sampleId: 'waist' }])
    expect(merged.measurements[0]).toMatchObject({ bodyFat: 21.3, waist: 85.3 })
    expect(appleHealthRecords(merged).measurements).toEqual([])
  })
  it('rejects malformed read rows', () => {
    const S = {}
    expect(mergeHealthMeasurements(S, [{ ...row, value: NaN }, { ...row, time: 0 }, { ...row, kind: 'chest' }, { ...row, kind: 'bodyFat', value: 2 }])).toBe(S)
  })
})
