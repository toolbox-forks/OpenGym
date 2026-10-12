// @vitest-environment happy-dom
import React, { act } from 'react'
import { createRoot } from 'react-dom/client'
import { beforeEach, afterEach, it, expect, vi } from 'vitest'
import AppleHealthCard from './AppleHealthCard.jsx'
const m = vi.hoisted(() => ({ status: vi.fn(), load: vi.fn(), enable: vi.fn(), disable: vi.fn(), off: vi.fn(), changed: null }))
vi.mock('../lib/apple-health.js', () => ({ appleHealthStatus: m.status, loadAppleHealth: m.load, enableAppleHealth: m.enable, disableAppleHealth: m.disable,
  onAppleHealthChange: cb => { m.changed = cb; return m.off } }))
vi.mock('../lib/i18n.js', () => ({ t: s => s }))
globalThis.IS_REACT_ACT_ENVIRONMENT = true
let host, root, toast
beforeEach(() => {
  vi.clearAllMocks(); m.changed = null
  m.status.mockResolvedValue({ mode: 'mock' }); m.load.mockResolvedValue({ on: false })
  m.enable.mockResolvedValue({ ok: true }); m.disable.mockResolvedValue({ on: false })
  host = document.createElement('div'); document.body.append(host); root = createRoot(host); toast = vi.fn()
})
afterEach(() => { act(() => root.unmount()); host.remove() })
async function render() { await act(async () => root.render(<AppleHealthCard S={{ workouts: [] }} toast={toast} />)) }
it('shows purpose and mock label before an explicit authorization action', async () => {
  await render()
  expect(host.textContent).toContain('Save workouts, energy and body measurements.')
  expect(host.textContent).toContain('Data stays on your device and your own server.')
  expect(host.textContent).toContain('Simulator Health store')
  expect(m.enable).not.toHaveBeenCalled()
  const control = host.querySelector('[role="switch"]')
  expect(control).not.toBeNull()
  await act(async () => control.click())
  expect(m.enable).toHaveBeenCalledWith({ workouts: [] })
})
it('hides the card on unsupported platforms', async () => {
  m.status.mockResolvedValue({ mode: 'unsupported' }); await render()
  expect(host.textContent).toBe('')
})
it('offers retry after a failed native write and unsubscribes on close', async () => {
  await render()
  await act(async () => m.changed({ on: true, error: 'permission' }))
  expect(host.textContent).toContain('Could not sync Apple Health')
  const row = [...host.querySelectorAll('.lrow')].find(r => r.textContent.includes('Could not sync Apple Health'))
  await act(async () => row.click())
  expect(m.enable).toHaveBeenCalledOnce()
  act(() => root.render(null)); expect(m.off).toHaveBeenCalledOnce()
})
it('stops sync explicitly and reports failures', async () => {
  m.load.mockResolvedValue({ on: true }); m.disable.mockRejectedValue(Error('disk'))
  await render(); await act(async () => host.querySelector('[role="switch"]').click())
  expect(m.disable).toHaveBeenCalledOnce()
  expect(toast).toHaveBeenCalledWith('Could not sync Apple Health')
})

it('keeps the purpose and error visible if stored identities cannot be loaded', async () => {
  m.load.mockRejectedValue(Error('corrupt preferences'))
  await render()
  expect(host.textContent).toContain('Sync with Apple Health')
  expect(host.textContent).toContain('Could not sync Apple Health')
  expect(m.enable).not.toHaveBeenCalled()
})
