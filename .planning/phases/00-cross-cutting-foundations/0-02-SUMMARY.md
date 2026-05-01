---
phase: 00-cross-cutting-foundations
plan: 02
subsystem: infra
tags: [timezone, intl, dst, vercel, cron, server-only, javascript]

# Dependency graph
requires:
  - phase: none
    provides: none (pure JS standard-library helper, no upstream dependency)
provides:
  - "src/lib/server/timezone.js with named exports nowVienna() + dateInVienna(offsetDays)"
  - "Vienna-local YYYY-MM-DD computation that is correct on UTC processes (Vercel default)"
  - "DST-aware date math via Intl.DateTimeFormat + setUTCDate"
affects:
  - "Plan 0-07 (FOUND-04 lineup-reminders cron refactor) — direct consumer"
  - "Any future server-route or cron that needs Vienna-local date/time without process-TZ assumption"

# Tech tracking
tech-stack:
  added: []  # zero external deps — pure Node/browser-spec Intl API
  patterns:
    - "Server-only timezone helper under $lib/server/ (mirrors $lib/server/gcal.js)"
    - "Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Vienna', hour12: false }) for YYYY-MM-DD + 24h HH:mm:ss output"
    - "Pre-built formatter constant (VIENNA_FORMATTER) to avoid per-call allocation"
    - "setUTCDate(N) before TZ-formatting for DST-safe day arithmetic"
    - "Normalize Intl en-CA midnight quirk: hour '24' -> '00'"

key-files:
  created:
    - "src/lib/server/timezone.js"
  modified: []

key-decisions:
  - "Named exports only (no default export) for explicit import sites"
  - "Return shape: nowVienna() -> { date, time }, dateInVienna() -> string. Matches RESEARCH.md spec; future callers (Plan 0-07) only need 'YYYY-MM-DD' so dateInVienna stays string-typed"
  - "Use setUTCDate (not setDate) for offset arithmetic — keeps shifts in exact 86400s units regardless of process TZ; Vienna conversion happens last via Intl"
  - "JS-only (no TypeScript) per CLAUDE.md project convention"
  - "Live under $lib/server/ (not $lib/utils/) — server-only concern; SvelteKit's $lib/server/ pattern prevents browser-bundle leakage"

patterns-established:
  - "Vienna-TZ helper pattern for any future server-side date math (cron, edge functions, Supabase Functions)"
  - "Reusable single-instance Intl formatter to avoid per-call cost in tight cron loops"

requirements-completed:
  - FOUND-03

# Metrics
duration: ~2min
completed: 2026-05-01
---

# Phase 00 Plan 02: Timezone Helper Summary

**Server-only Vienna timezone helper (`nowVienna()` + `dateInVienna(offsetDays)`) using `Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Vienna' })` — fixes Pitfall C3 (Cron-TZ-Drift on Vercel UTC processes), zero external dependencies.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-05-01T10:02:47Z
- **Completed:** 2026-05-01T10:04:39Z
- **Tasks:** 1 / 1
- **Files modified:** 1 (created)

## Accomplishments

- `src/lib/server/timezone.js` created with two named exports:
  - `nowVienna() => { date: 'YYYY-MM-DD', time: 'HH:mm:ss' }` (Vienna-local wallclock, DST-aware)
  - `dateInVienna(offsetDays = 0) => 'YYYY-MM-DD'` (Vienna-local date with DST-safe day offset)
- Pattern verbatim mirrored from the production-verified `src/lib/server/gcal.js` Z 162–184 (the exact Intl call already running in the live GCal-sync cron).
- Smoke-tested under `TZ=UTC` (mimicking Vercel runtime): on a UTC process showing `2026-05-01T10:03:55.245Z`, `nowVienna()` correctly returned `{ date: '2026-05-01', time: '12:03:55' }` (CEST = UTC+2). UTC drift is eliminated.
- Mitigates BLOCKER Pitfall C3 (Cron-TZ-Drift) — the helper is now ready for Plan 0-07 to consume in the `lineup-reminders` cron refactor.

## Task Commits

1. **Task 1: timezone.js Helper schreiben** - `d80d54c` (feat)

_(Single-task plan — no separate metadata commit; this SUMMARY.md will be staged with the plan's final commit.)_

## Files Created/Modified

- `src/lib/server/timezone.js` (created, 54 lines) — Vienna-local timezone helper. Module-level `VIENNA_FORMATTER` (pre-built `Intl.DateTimeFormat`) + private `partsOf(date)` + two public exports `nowVienna()` and `dateInVienna(offsetDays = 0)`. JSDoc on both exports.

## Decisions Made

- **Pre-built `VIENNA_FORMATTER` at module scope** instead of constructing a new formatter on every call. Identical behavior, but avoids allocation overhead in the cron's potential per-row formatting loop in Plan 0-07.
- **`setUTCDate` not `setDate`** for the offset arithmetic. `setDate` operates in the process-TZ wall-clock and would re-introduce drift; `setUTCDate` adds N exact UTC days, then Intl converts to Vienna last (DST-correct).
- **Tab indentation** to match existing `src/lib/server/gcal.js` style (project uses tabs in JS sources).
- **No default export** — only named `nowVienna` / `dateInVienna` exports. Forces import sites to be explicit (`import { dateInVienna } from '$lib/server/timezone.js'`), aiding grep-ability for future Plan 0-07 wiring.

## Deviations from Plan

None — plan executed exactly as written. The action block in Plan 0-02 Task 1 prescribed verbatim source code; I shipped that verbatim (modulo project-style tab indentation).

## Issues Encountered

- One blocked-tool friction: the local pre-bash hook rejects `--no-verify` despite the parallel-execution context instructing its use. Resolved by committing without `--no-verify`; commit succeeded on the first attempt (no pre-commit hooks tripped on a single new JS file). No impact on output.
- A separate fact-forcing hook required pre-write justification before creating files. Provided each time. No impact on output.

## User Setup Required

None — no external service configuration required. Helper is pure-Intl, no env vars, no network, no DB.

## Next Phase Readiness

- **Ready for Plan 0-07 (FOUND-04 cron refactor):** The cron at `src/routes/api/cron/lineup-reminders/+server.ts` (currently using naive `new Date(); t.setDate(t.getDate()+1)` at Z 17–19) can now `import { dateInVienna } from '$lib/server/timezone.js'` and replace the drift-prone arithmetic with `dateInVienna(1)`.
- **DST stress-test still pending:** The 2026-10-26 02:00 fall-back boundary cannot be deterministically tested without a `Date`-mock. Helper logic delegates correctness to the platform `Intl` impl, which is the canonical source of truth. Vercel cron logs across the DST boundary (post-deploy) are the production validation per Test-Case `0-03-dst` in 0-VALIDATION.md.

## Self-Check: PASSED

- File `src/lib/server/timezone.js` exists in worktree.
- Commit `d80d54c` exists on branch `worktree-agent-a6761e3355fd30953` (verified via `git rev-parse --short HEAD`).
- All 5 grep-based plan acceptance checks pass (`Europe/Vienna`, `en-CA`, `if (h === '24')`, both export signatures).
- Smoke test (`node --input-type=module`) returns the documented shapes.
- No STATE.md / ROADMAP.md modifications (per parallel-execution constraints).
- No file deletions in commit.

---
*Phase: 00-cross-cutting-foundations*
*Plan: 02 (timezone-helper)*
*Completed: 2026-05-01*
