import { useEffect, useState } from 'react'
import { Section, Row, Switch } from './ui.jsx'
import { t } from '../lib/i18n.js'
import { appleHealthStatus, loadAppleHealth, onAppleHealthChange, enableAppleHealth, disableAppleHealth } from '../lib/apple-health.js'

export default function AppleHealthCard({ S, toast }) {
  const [mode, setMode] = useState('unsupported')
  const [health, setHealth] = useState(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    let closed = false
    Promise.allSettled([appleHealthStatus(), loadAppleHealth()]).then(([s, h]) => {
      if (!closed) {
        setMode(s.status === 'fulfilled' ? s.value.mode : 'unsupported')
        setHealth(h.status === 'fulfilled' ? h.value : { on: false, error: 'storage' })
      }
    })
    const off = onAppleHealthChange(h => { if (!closed) setHealth(h) })
    return () => { closed = true; off() }
  }, [])
  if (mode === 'unsupported' || !health) return null
  const change = async on => {
    setBusy(true)
    try {
      if (on) {
        const result = await enableAppleHealth(S)
        if (!result.ok) toast(t('Could not sync Apple Health'))
      } else await disableAppleHealth()
    } catch { toast(t('Could not sync Apple Health')) }
    setBusy(false)
  }
  return <Section title={t('Apple Health')}
    footer={t('Turning this off keeps existing data in Apple Health.')}>
    <Row icon="heart" iconTint="var(--red)" title={t('Sync with Apple Health')}
      subtitle={t('Save workouts, energy and body measurements. Read body measurements, heart rate and recovery. Data stays on your device and your own server.')}>
      <Switch aria-label={t('Sync with Apple Health')} checked={!!health.on} disabled={busy} onChange={change} />
    </Row>
    {mode === 'mock' && <Row icon="info" title={t('Simulator Health store')} />}
    {health.error && <Row icon="warning" title={t('Could not sync Apple Health')} accessory="chevron" onClick={() => change(true)} />}
  </Section>
}
