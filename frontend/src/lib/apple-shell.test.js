// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
const mocks = vi.hoisted(() => ({ platform: 'ios', available: true, callback: null,
  environment: vi.fn(), haptic: vi.fn(), remove: vi.fn(), register: vi.fn(), mobile: true }))
vi.mock('./mobile.js', () => ({ get MOBILE() { return mocks.mobile } }))
vi.mock('@capacitor/core', () => ({
  Capacitor: { getPlatform: () => mocks.platform, isPluginAvailable: () => mocks.available },
  registerPlugin: (...args) => {
    mocks.register(...args)
    return { environment: mocks.environment, haptic: mocks.haptic,
      addListener: async (_event, fn) => { mocks.callback = fn; return { remove: mocks.remove } } }
  }
}))
import { applyAppleEnvironment, startAppleShell } from './apple-shell.js'
import { setVibrate, vibrate, vibrateSupported, setNativeHaptic } from './sound.js'
import { nativeKeyboardHeight, visibleBottom } from './native-keyboard.js'

beforeEach(() => {
  vi.clearAllMocks(); mocks.platform = 'ios'; mocks.available = true; mocks.mobile = true
  mocks.environment.mockResolvedValue({ top: 59, bottom: 34, keyboardHeight: 0 })
  mocks.haptic.mockResolvedValue(undefined); mocks.remove.mockResolvedValue(undefined)
  setNativeHaptic(null); setVibrate(true)
  Object.defineProperty(window, 'innerHeight', { value: 852, configurable: true })
})
afterEach(() => { setNativeHaptic(null); applyAppleEnvironment({}, window) })

it('passes safe areas and keyboard occlusion into the existing sheet geometry', () => {
  applyAppleEnvironment({ top: 59, bottom: 34, keyboardHeight: 336 }, window)
  expect(document.documentElement.style.getPropertyValue('--native-sat')).toBe('59px')
  expect(nativeKeyboardHeight(document)).toBe(336)
  expect(visibleBottom(window)).toBeLessThanOrEqual(516)
  applyAppleEnvironment({ top: 59, bottom: 34, keyboardHeight: 0 }, window)
  expect(document.documentElement.hasAttribute('data-native-kb')).toBe(false)
})
it('ignores invalid geometry instead of poisoning CSS', () => {
  applyAppleEnvironment({ top: -1, bottom: Infinity, keyboardHeight: NaN }, window)
  expect(nativeKeyboardHeight(document)).toBe(0)
  expect(document.documentElement.style.getPropertyValue('--native-sab')).toBe('0px')
})
it.each(['android', 'web'])('does not register an iPhone bridge on %s', async platform => {
  mocks.platform = platform; await startAppleShell(window); expect(mocks.register).not.toHaveBeenCalled()
})
it('does nothing in a web build or an older shell', async () => {
  mocks.mobile = false; await startAppleShell(window)
  mocks.mobile = true; mocks.available = false; await startAppleShell(window)
  expect(mocks.register).not.toHaveBeenCalled()
})
it('routes enabled completion haptics to UIKit and respects the vibration setting', async () => {
  const stop = await startAppleShell(window)
  expect(vibrateSupported()).toBe(true)
  vibrate(40); expect(mocks.haptic).toHaveBeenCalledWith({ kind: 'light' })
  vibrate([50, 60, 50]); expect(mocks.haptic).toHaveBeenCalledWith({ kind: 'success' })
  setVibrate(false); vibrate(40); expect(mocks.haptic).toHaveBeenCalledTimes(2)
  await stop(); expect(mocks.remove).toHaveBeenCalledOnce()
})
it('does not overwrite a newer keyboard notification with an old initial response', async () => {
  mocks.environment.mockImplementation(async () => {
    mocks.callback({ top: 59, bottom: 34, keyboardHeight: 336 })
    return { top: 59, bottom: 34, keyboardHeight: 0 }
  })
  const stop = await startAppleShell(window)
  expect(nativeKeyboardHeight(document)).toBe(336)
  await stop(); expect(nativeKeyboardHeight(document)).toBe(0)
})
it('removes its listener when initial bridge setup fails', async () => {
  mocks.environment.mockRejectedValue(new Error('bridge unavailable'))
  await startAppleShell(window); expect(mocks.remove).toHaveBeenCalledOnce()
})
