import { expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { APPLE_ENVELOPE_KINDS, appleEnvelope, validateAppleEnvelope, migrateAppleEnvelope } from './apple-contract.js'
const legacy = { workouts: [{ id: 'old-short-id', entries: [{ id: '0025', sets: [{ w: 60, r: 5, done: true, customFuture: [1, true] }] }] }], unknownFuture: { x: 'preserve' } }
it.each(APPLE_ENVELOPE_KINDS)('round-trips %s without rewriting legacy ids or future fields', kind => {
  const envelope = appleEnvelope(kind, structuredClone(legacy), 1000)
  expect(validateAppleEnvelope(JSON.parse(JSON.stringify(envelope))).payload).toEqual(legacy)
})
it.each([null, [], {}, { schemaVersion: 2, kind: 'ack', payload: {}, sentAt: 0 }, { schemaVersion: 1, kind: 'other', payload: {}, sentAt: 0 }, { schemaVersion: 1, kind: 'ack', payload: [], sentAt: 0 }, { schemaVersion: 1, kind: 'ack', payload: {}, sentAt: -1 }])('rejects a malformed or unsupported envelope: %j', value => {
  expect(() => validateAppleEnvelope(value)).toThrow()
})
it.each([NaN, Infinity, undefined, () => {}])('rejects non-JSON nested payload data', value => {
  expect(() => appleEnvelope('liveEvent', { value }, 0)).toThrow()
})
it('rejects extra envelope fields rather than silently changing the contract', () => {
  expect(() => validateAppleEnvelope({ ...appleEnvelope('ack', {}, 0), extra: true })).toThrow()
})
it('migrates prototype snapshot v0 without mutating its payload', () => {
  const old = { schemaVersion: 0, kind: 'snapshot', payload: legacy, sentAt: 1000 }
  expect(migrateAppleEnvelope(old)).toEqual(appleEnvelope('snapshot', legacy, 1000))
  expect(old.schemaVersion).toBe(0)
  expect(() => migrateAppleEnvelope({ ...old, kind: 'ack' })).toThrow()
})
it('matches the shared JSON schema version/kinds', () => {
  const schema = JSON.parse(readFileSync(new URL('../../../apple/Contracts/sync-envelope.schema.json', import.meta.url)))
  expect(schema.properties.schemaVersion.const).toBe(1)
  expect(schema.properties.kind.enum).toEqual(APPLE_ENVELOPE_KINDS)
})
