import { beforeEach, it, expect, vi } from 'vitest'
const m = vi.hoisted(() => ({ mobile: true, platform: 'ios', files: new Map(), writeFile: vi.fn(), rename: vi.fn(), readFile: vi.fn(),
  authorize: vi.fn(), write: vi.fn(), read: vi.fn(), status: vi.fn(), addListener: vi.fn(), remove: vi.fn(), preferences: vi.fn(), savePreferences: vi.fn() }))
vi.mock('./mobile.js', () => ({ get MOBILE() { return m.mobile } }))
vi.mock('@capacitor/core', () => ({ Capacitor: { getPlatform: () => m.platform, isPluginAvailable: () => true }, registerPlugin: () => ({ authorize: m.authorize, write: m.write, read: m.read, status: m.status, preferences: m.preferences, savePreferences: m.savePreferences }) }))
vi.mock('@capacitor/filesystem', () => ({ Directory: { Data: 'DATA' }, Encoding: { UTF8: 'utf8' }, Filesystem: { writeFile: m.writeFile, readFile: m.readFile, rename: m.rename } }))
vi.mock('@capacitor/app', () => ({ App: { addListener: m.addListener } }))
let health
const time = new Date('2026-10-12T12:00:00').getTime()
const S = { workouts: [{ id: 'old-id', name: 'Test', start: time, end: time + 60000, entries: [] }] }
beforeEach(async () => {
  vi.resetModules(); vi.clearAllMocks(); m.mobile = true; m.platform = 'ios'; m.files.clear()
  m.readFile.mockImplementation(async ({ path }) => { if (!m.files.has(path)) throw Object.assign(Error('not found'), { code: 'ENOENT' }); return { data: m.files.get(path) } })
  m.writeFile.mockImplementation(async ({ path, data }) => { m.files.set(path, data) })
  m.rename.mockImplementation(async ({ from, to }) => { m.files.set(to, m.files.get(from)); m.files.delete(from) })
  m.preferences.mockImplementation(async () => JSON.parse(m.files.get('opengym-apple-health.json') || '{}'))
  m.savePreferences.mockImplementation(async ({ preferences }) => { m.files.set('opengym-apple-health.json', JSON.stringify(preferences)) })
  m.authorize.mockResolvedValue({ mode: 'mock' }); m.write.mockResolvedValue({}); m.read.mockResolvedValue({ measurements: [] }); m.status.mockResolvedValue({ mode: 'mock' })
  m.addListener.mockResolvedValue({ remove: m.remove })
  health = await import('./apple-health.js')
})
it.each(['android', 'web'])('never calls HealthKit on %s', async platform => {
  m.platform = platform
  expect(await health.appleHealthStatus()).toEqual({ mode: 'unsupported' })
  expect(await health.enableAppleHealth(S)).toEqual({ ok: false })
  expect(m.authorize).not.toHaveBeenCalled()
})
it('does nothing in the web build', async () => {
  m.mobile = false
  expect(await health.startAppleHealth({})).toBeTypeOf('function')
  expect(m.readFile).not.toHaveBeenCalled(); expect(m.status).not.toHaveBeenCalled()
})
it('loads opt-out preferences without requesting permission or writing Health data', async () => {
  await health.loadAppleHealth(); await health.syncAppleHealth(S)
  expect(m.authorize).not.toHaveBeenCalled(); expect(m.write).not.toHaveBeenCalled()
})
it('persists the identity before native writes and sends unchanged history once', async () => {
  m.write.mockImplementation(async ({ workouts }) => {
    const saved = JSON.parse(m.files.get(health.APPLE_HEALTH_FILE))
    expect(saved.identities['old-id']).toBe(workouts[0].uuid)
  })
  expect((await health.enableAppleHealth(S)).ok).toBe(true)
  await health.syncAppleHealth(S)
  expect(m.authorize).toHaveBeenCalledOnce(); expect(m.write).toHaveBeenCalledOnce()
})
it('retries partial native writes with the same UUID and version', async () => {
  m.write.mockRejectedValueOnce(Error('interrupted'))
  expect((await health.enableAppleHealth(S)).ok).toBe(false)
  await health.syncAppleHealth(S)
  expect(m.write).toHaveBeenCalledTimes(2)
  expect(m.write.mock.calls[0][0]).toEqual(m.write.mock.calls[1][0])
})
it('fails closed when identity persistence fails', async () => {
  m.savePreferences.mockRejectedValueOnce(Error('disk full'))
  await expect(health.enableAppleHealth(S)).rejects.toThrow('disk full')
  expect(m.write).not.toHaveBeenCalled()
})
it('never treats corrupted preferences as a new empty identity map', async () => {
  m.files.set(health.APPLE_HEALTH_FILE, '{bad')
  await expect(health.loadAppleHealth()).rejects.toThrow()
  expect(m.write).not.toHaveBeenCalled()
})
it('stops future sync without removing existing samples', async () => {
  await health.enableAppleHealth(S); await health.disableAppleHealth()
  await health.syncAppleHealth({ ...S, workouts: [...S.workouts, { ...S.workouts[0], id: 'second' }] })
  expect(m.write).toHaveBeenCalledOnce()
  expect((await health.loadAppleHealth()).on).toBe(false)
})
it('coalesces changes received while a native write is pending', async () => {
  await health.enableAppleHealth({ workouts: [] })
  let release
  m.write.mockImplementationOnce(() => new Promise(resolve => { release = resolve }))
  const first = health.syncAppleHealth(S)
  await vi.waitFor(() => expect(release).toBeTypeOf('function'))
  health.syncAppleHealth({ workouts: [{ ...S.workouts[0], name: 'Changed' }] })
  release({}); await first
  expect(m.write).toHaveBeenCalledTimes(2)
  expect(m.write.mock.calls[1][0].workouts[0]).toMatchObject({ title: 'Changed', version: 2 })
})

it('rejects syntactically valid but corrupt identity maps', async () => {
  m.files.set(health.APPLE_HEALTH_FILE, JSON.stringify({ identities: { old: 'bad' } }))
  await expect(health.loadAppleHealth()).rejects.toThrow('Invalid Apple Health preferences')
  expect(m.write).not.toHaveBeenCalled()
})
