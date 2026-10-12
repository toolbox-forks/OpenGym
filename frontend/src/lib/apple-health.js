import { MOBILE } from './mobile.js'
import { appleHealthRecords, planAppleHealth, mergeHealthMeasurements } from './apple-health-records.js'

export const APPLE_HEALTH_FILE = 'opengym-apple-health.json'
let bridgeP, cached, loading, running, pending, store
let saves = Promise.resolve()
let pendingRead = false
const listeners = new Set()
const bridge = () => bridgeP ||= (async () => {
  if (!MOBILE) return null
  const { Capacitor, registerPlugin } = await import('@capacitor/core')
  if (Capacitor.getPlatform() !== 'ios' || !Capacitor.isPluginAvailable('AppleHealth')) return null
  return { health: registerPlugin('AppleHealth') }
})()
export async function loadAppleHealth() {
  if (cached) return cached
  if (!loading) loading = (async () => {
    const raw = await (await bridge())?.health.preferences() || {}
    const object = v => v && typeof v === 'object' && !Array.isArray(v)
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!object(raw) || raw.on != null && typeof raw.on !== 'boolean' ||
        raw.identities != null && (!object(raw.identities) || Object.values(raw.identities).some(id => typeof id !== 'string' || !uuid.test(id))) ||
        raw.written != null && (!object(raw.written) || Object.values(raw.written).some(v => !object(v) || typeof v.h !== 'string' || !Number.isSafeInteger(v.version) || v.version < 1))) {
      throw new Error('Invalid Apple Health preferences')
    }
    return cached = { on: false, identities: {}, written: {}, ...raw }
  })().finally(() => { loading = null })
  return loading
}
function save(value) {
  const task = saves.catch(() => {}).then(async () => {
    const p = await bridge()
    if (!p) throw new Error('unavailable')
    await p.health.savePreferences({ preferences: value }) // Native atomic write; errors must reach the caller.
    cached = value
    for (const cb of listeners) { try { cb(value) } catch { /* closed screen */ } }
    return value
  })
  saves = task
  return task
}
export const onAppleHealthChange = cb => { listeners.add(cb); return () => listeners.delete(cb) }
export async function appleHealthStatus() { return (await bridge())?.health.status() || { mode: 'unsupported' } }
export function syncAppleHealth(S, { read = false } = {}) {
  if (!cached?.on) return Promise.resolve(cached)
  pending = S
  pendingRead ||= read
  if (running) return running
  running = (async () => {
    while (pending && cached.on) {
      const next = pending; pending = null
      const wantsRead = pendingRead; pendingRead = false
      const p = await bridge()
      if (!p) break
      try {
        const records = appleHealthRecords(next, cached.identities)
        // Persist identities before invoking native writes: a crash cannot change the retry's UUID.
        if (JSON.stringify(records.identities) !== JSON.stringify(cached.identities)) await save({ ...cached, identities: records.identities })
        if (!cached.on) break
        const plan = planAppleHealth(records, cached.written)
        if (plan.workouts.length || plan.measurements.length) await p.health.write({ workouts: plan.workouts, measurements: plan.measurements })
        if (plan.workouts.length || plan.measurements.length || cached.error) await save({ ...cached, written: plan.written, error: null, at: Date.now() })
        if (!cached.on) break
        if (!wantsRead) continue
        const read = await p.health.read({ since: 0 })
        if (store) {
          const current = store.getState().S
          const merged = mergeHealthMeasurements(current, read.measurements || [], new Set(Object.keys(cached.written)))
          if (merged !== current) store.getState().update(s => Object.assign(s, merged))
        }
      } catch (e) { await save({ ...cached, error: e?.code || 'failed' }); break }
    }
    return cached
  })().finally(() => { running = null })
  return running
}
export async function enableAppleHealth(S) {
  const p = await bridge()
  if (!p) return { ok: false }
  await p.health.authorize() // Only this explicit user action opens authorization.
  await loadAppleHealth()
  await save({ ...cached, on: true, error: null })
  const h = await syncAppleHealth(S, { read: true })
  return { ok: !h?.error, health: h }
}
export async function disableAppleHealth() {
  // Flip immediately so an in-flight write cannot schedule another pass; retain existing Health samples.
  await loadAppleHealth()
  await save({ ...cached, on: false })
  if (running) await running.catch(() => {})
  return save({ ...cached, on: false, error: null })
}
export async function startAppleHealth(nextStore) {
  const p = await bridge()
  if (!p) return () => {}
  store = nextStore
  await loadAppleHealth()
  const off = store.subscribe((state, old) => { if (state.S !== old.S) syncAppleHealth(state.S).catch(() => {}) })
  const { App } = await import('@capacitor/app')
  const listener = await App.addListener('appStateChange', ({ isActive }) => { if (isActive) syncAppleHealth(store.getState().S, { read: true }).catch(() => {}) })
  await syncAppleHealth(store.getState().S, { read: true })
  return async () => { off(); await listener.remove() }
}
