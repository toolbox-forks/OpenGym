import { expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { generateGolden } from '../../../scripts/apple/generate-golden.mjs'
it('runs the same checked-in golden corpus as OpenGymKit against production JS', () => {
  const stored=JSON.parse(readFileSync(new URL('../../../apple/OpenGymKit/Tests/OpenGymKitTests/Fixtures/golden.json',import.meta.url)))
  expect(stored.length).toBeGreaterThan(1000)
  expect(generateGolden()).toEqual(stored)
})
