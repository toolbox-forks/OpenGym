// Native iPhone geometry and haptics. Keep every native import behind the mobile/platform gate.
import { MOBILE } from './mobile.js'
import { setNativeHaptic } from './sound.js'
import { NATIVE_KEYBOARD_EVENT } from './native-keyboard.js'

const pixels = v => Number.isFinite(v) && v >= 0 ? v : 0

export function applyAppleEnvironment(env, win) {
  const root = win.document.documentElement
  root.style.setProperty('--native-sat', `${pixels(env.top)}px`)
  root.style.setProperty('--native-sab', `${pixels(env.bottom)}px`)
  const height = pixels(env.keyboardHeight)
  root.style.setProperty('--native-kb', `${height}px`)
  if (height > 0) root.setAttribute('data-native-kb', '')
  else root.removeAttribute('data-native-kb')
  win.dispatchEvent(new win.CustomEvent(NATIVE_KEYBOARD_EVENT, { detail: { height } }))
}

export async function startAppleShell(win = typeof window !== 'undefined' ? window : null) {
  if (!MOBILE || !win) return () => {}
  try {
    const { Capacitor, registerPlugin } = await import('@capacitor/core')
    if (Capacitor.getPlatform() !== 'ios' || !Capacitor.isPluginAvailable('AppleShell')) return () => {}
    // Never return the proxy from an async function: its synthetic `then` would never settle.
    const shell = registerPlugin('AppleShell')
    let changes = 0
    const listener = await shell.addListener('environmentChanged', env => {
      changes++
      applyAppleEnvironment(env, win)
    })
    try {
      const initial = await shell.environment()
      if (!changes) applyAppleEnvironment(initial, win)
    } catch (error) {
      await listener.remove()
      throw error
    }
    setNativeHaptic(pattern => shell.haptic({ kind: Array.isArray(pattern) && pattern.length > 1 ? 'success' : 'light' }))
    return async () => {
      setNativeHaptic(null)
      await listener.remove()
      applyAppleEnvironment({}, win)
    }
  } catch { return () => {} } // Older shell, denied bridge, or a mobile bundle in a browser.
}
