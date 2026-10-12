# Apple progress

Goal: BRIEF.md §10, branch apple-native. Read BRIEF.md in full before continuing; re-read §§2/9/10 at every session and after compaction. PLAN.md describes architecture, PARITY.md tracks all requirements, DECISIONS.md records verified discrepancies, BLOCKERS.md records exact external actions.

## Phase 0: reconnaissance and plan [CLOSED 2026-10-12]
- VERIFIED environment Mode B: `uname -s` → Linux; `xcodebuild -version` → command not found.
- VERIFIED repository: `git status --short` → clean before work; base HEAD 5ec23d3b3ac68cbc09fbe450276f6db1995c83a6. `git ls-remote --heads origin` → main only. Created apple-native after read-only inspection.
- WRITTEN binding BRIEF copied unchanged from owner upload; PLAN, PARITY, ADR-001 and discrepancy decisions.
- VERIFIED shipped catalogue count command in ADR-002 → 5,632; original dataset records retained → 1,324; language packs → 18 plus English.
- BLOCKED GitHub API → proxy CONNECT 403 (B-02); macOS oracle → Xcode unavailable (B-01).
- VERIFIED Node 22.23.3 baseline: `cd frontend && npm test -- --maxWorkers=2` → 402 files / 5,060 tests passed; `cd api && node --test --test-concurrency=2 test/*.test.js` → 596 passed, 0 skipped; `cd mcp && npm test -- --maxWorkers=1` → 95 passed. Logs: `/workspace/.opengym-setup/apple-phase0-{frontend,api,mcp}.log`.
- VERIFIED `cd frontend && npm run build` → built successfully in 3.79 s; `npm --prefix mcp run check:node-loadable` → complete MCP graph loadable.
- VERIFIED `cmp docs/apple/BRIEF.md <owner-upload>` and `git diff --check` → exit 0.
- BLOCKED self-hosted image verification: `BUILDX_CONFIG=/workspace/.docker-buildx docker build --target default -t opengym-apple-baseline-api:local ./api` → APKINDEX HTTP 403, B-07. No verification disabled. This is an additional baseline integration check; Phase 0 specified suite and web gates passed.
- Next: Phase 1 iPhone shell and macOS oracle. Re-run full suites before its closure.

## Remaining phases

Phases 1–10 have not opened at this commit. Follow PLAN.md in order. In particular no Watch, HealthKit or Oura implementation is present yet. Do not report the product or goal complete.
