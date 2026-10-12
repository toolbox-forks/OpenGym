import { it, expect } from 'vitest'
const packs = import.meta.glob('../locales/*.js', { eager: true })
const keys = ['Apple Health', 'Sync with Apple Health',
  'Save workouts, energy and body measurements. Read body measurements, heart rate and recovery. Data stays on your device and your own server.',
  'Turning this off keeps existing data in Apple Health.', 'Simulator Health store', 'Could not sync Apple Health']
it.each(Object.entries(packs))('Apple Health purpose and controls are translated in %s', (_path, pack) => {
  for (const key of keys) {
    expect(pack.default[key], key).toBeTypeOf('string')
    expect(pack.default[key].trim(), key).not.toBe('')
    if (key !== 'Apple Health') expect(pack.default[key], key).not.toBe(key)
  }
})
