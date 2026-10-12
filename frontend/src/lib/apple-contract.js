// This boundary mirrors OpenGymKit/SyncEnvelope and apple/Contracts/sync-envelope.schema.json.
export const APPLE_SCHEMA_VERSION = 1
export const APPLE_ENVELOPE_KINDS = ['snapshot', 'workoutCompleted', 'liveEvent', 'ack']
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x)

export function validateAppleEnvelope(value) {
  if (!object(value)) throw new TypeError('Envelope must be an object')
  if (value.schemaVersion !== APPLE_SCHEMA_VERSION) throw new TypeError('Unsupported Apple schema version')
  if (!APPLE_ENVELOPE_KINDS.includes(value.kind)) throw new TypeError('Unsupported envelope kind')
  if (!object(value.payload)) throw new TypeError('Payload must be an object')
  if (!Number.isFinite(value.sentAt) || value.sentAt < 0) throw new TypeError('Invalid envelope timestamp')
  if (Object.keys(value).some(k => !['schemaVersion', 'kind', 'payload', 'sentAt'].includes(k))) throw new TypeError('Unknown envelope field')
  // Guarantee a transportable JSON payload; reject NaN/Infinity/undefined/functions/cycles.
  const encoded = JSON.stringify(value, (_key, v) => {
    if (typeof v === 'number' && !Number.isFinite(v)) throw new TypeError('Non-finite payload number')
    if (typeof v === 'undefined' || typeof v === 'function' || typeof v === 'bigint' || typeof v === 'symbol') throw new TypeError('Non-JSON payload value')
    return v
  })
  const out = JSON.parse(encoded)
  if (!object(out.payload)) throw new TypeError('Payload must serialize as an object')
  return out
}
export function appleEnvelope(kind, payload, sentAt = Date.now()) {
  return validateAppleEnvelope({ schemaVersion: APPLE_SCHEMA_VERSION, kind, payload, sentAt })
}
export function migrateAppleEnvelope(value) {
  if (object(value) && value.schemaVersion === 0) {
    if (value.kind !== 'snapshot') throw new TypeError('Only prototype snapshots may migrate')
    return appleEnvelope('snapshot', value.payload, value.sentAt)
  }
  return validateAppleEnvelope(value)
}
