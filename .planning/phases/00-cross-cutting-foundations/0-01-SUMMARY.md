---
phase: 00-cross-cutting-foundations
plan: 01
subsystem: database
tags: [supabase, sql, rls, postgres, runbook, captain-touchpoint, email-uniqueness]

# Dependency graph
requires:
  - phase: 00-cross-cutting-foundations
    provides: 0-CONTEXT decisions D-01 (audit-folder pattern), D-03 (case-insensitive duplicate detection)
provides:
  - Pre-deploy audit SQL for players.email NULL/duplicate detection (manual, Studio-only)
  - Captain runbook documenting email cleanup workflow including family-Gmail consolidation
  - RLS cross-write smoke-test runbook with 4 test-cases and 5 UI surface targets for FOUND-02 verification
  - Captain touchpoint gate ("Audit clean") that gates Plan 0-06 migration deploy
affects: [0-06 email-migration-rls, all future phases that touch players table writes]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "_audit/ subfolder convention — SQL files placed under supabase/migrations/_audit/ are NOT auto-applied by `supabase db push` (CLI only scans direct *.sql children of migrations/)"
    - "Captain-runbook pattern in docs/runbooks/ — Austrian German procedural docs with copy-pasteable SQL/JS snippets"
    - "Pre-flight audit before destructive schema migration (NOT NULL UNIQUE on populated column)"

key-files:
  created:
    - supabase/migrations/_audit/20260430_email_pre_check.sql
    - docs/runbooks/email-cleanup.md
    - docs/runbooks/rls-cross-write-test.md
  modified: []

key-decisions:
  - "_audit/ subfolder used to keep audit SQL out of the auto-apply migration sweep — file is never executed by `supabase db push`"
  - "Captain consolidates duplicate emails manually before migration deploys (no programmatic auto-resolve) — preserves human judgment about which family member keeps primary Gmail"
  - "Duplicate detection uses lower(email) so retroactive lowercase normalization in Plan 0-06 never hits a unique-violation it could have caught"
  - "Family-Gmail consolidation strategy documented as plus-aliases (family+max@gmail.com) OR club emails (name@kvwn.at), captain picks per family"
  - "RLS smoke-test runbook lists all 5 sb.from('players').update call-sites for explicit post-deploy regression coverage"

patterns-established:
  - "Two-step migration safety pattern: (1) pre-flight audit in _audit/ subfolder run by captain in Studio, (2) actual migration in migrations/ root applied via CLI after captain sign-off"
  - "Runbook traceability: each test step references its 0-VALIDATION.md test-case ID (0-02-cross, 0-02-captain, 0-02-self, 0-02-emailpin) for explicit cross-document linkage"
  - "Rollback-path documentation: every RLS migration runbook includes the exact DROP POLICY + CREATE POLICY restore SQL inline (not as a separate file)"

requirements-completed: [FOUND-01]

# Metrics
duration: 5min
completed: 2026-05-01
---

# Phase 0 Plan 1: Email-Audit Summary

**Pre-deploy audit SQL plus captain and developer runbooks that gate the FOUND-01 NOT NULL UNIQUE migration on a manual "audit-clean" sign-off, with a five-surface RLS smoke-test runbook prepared for FOUND-02 verification.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-01T10:03:26Z
- **Completed:** 2026-05-01T10:08:16Z
- **Tasks:** 3
- **Files created:** 3
- **Files modified:** 0

## Accomplishments

- Audit SQL placed in `supabase/migrations/_audit/` subfolder so `supabase db push` skips it — captain copy-pastes into Supabase Studio, no risk of accidental auto-apply.
- Two query result-sets in the audit SQL: NULL-emails and case-insensitive duplicates (via `GROUP BY lower(email) HAVING COUNT(*) > 1`) cleanly separated for captain triage.
- Captain runbook documents 4-step cleanup workflow (audit -> fix conflicts -> re-run -> sign off) with explicit family-Gmail consolidation strategy (plus-aliases or club emails).
- RLS smoke-test runbook lists all 5 `sb.from('players').update` call-sites (`AdminRollen`, `UebersichtTab`, `EinstellungenTab`, `ProfilHeroCard`, `ProfilEinwilligungenCard`) plus inline rollback SQL ready for Plan 0-06.
- Captain touchpoint gate is now the binding pre-condition for Plan 0-06 — dev cannot deploy migration without explicit "Audit clean" message.

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit-SQL-Skript schreiben (_audit/-Subordner)** — `6255083` (feat)
2. **Task 2: Captain-Runbook fuer Email-Cleanup schreiben** — `5c1ae65` (docs)
3. **Task 3: RLS-Cross-Write-Smoke-Test-Runbook fuer FOUND-02** — `bc8471b` (docs)

Plan metadata commit (this SUMMARY) is added in the worktree's final commit before return; orchestrator owns any consolidated rollup commit per parallel_execution policy.

## Files Created/Modified

### Created

- `supabase/migrations/_audit/20260430_email_pre_check.sql` — Two-query audit script (NULL-emails + lower()-grouped duplicates) for captain to run in Supabase Studio before Plan 0-06 deploy. Lives in `_audit/` subfolder so the Supabase CLI never picks it up as a migration.
- `docs/runbooks/email-cleanup.md` — Austrian German procedural runbook covering the 4-step captain workflow: run audit, resolve NULL/duplicate conflicts (with family-Gmail consolidation strategies), re-run until both queries return 0 rows, message dev with "Audit clean".
- `docs/runbooks/rls-cross-write-test.md` — Browser DevTools smoke-test runbook with 4 explicit test-cases (`0-02-cross`, `0-02-emailpin`, `0-02-captain`, `0-02-self`), the 5 UI surfaces touching `players` writes, and an inline rollback policy-restore snippet for Plan 0-06.

### Modified

None.

## Decisions Made

- **`_audit/` subfolder pattern (D-01):** Confirmed that the Supabase CLI's migration discovery (`supabase db push`) only enumerates direct `*.sql` children of `supabase/migrations/`, not nested folders. Using `_audit/` keeps the pre-flight script out of the apply sweep without needing CLI flags.
- **Case-insensitive duplicate detection (D-03):** `GROUP BY lower(email)` ensures the captain audit catches `Foo@Gmail.com` vs `foo@gmail.com` as duplicates BEFORE the Plan 0-06 retroactive lowercase pass would generate them.
- **Manual captain consolidation (no auto-resolve):** The runbook gives captain plus-alias OR club-email options per family; no script tries to guess. Family member identity / preferred address is a human decision.
- **Inline rollback in RLS runbook:** The cross-write-test runbook embeds the full `DROP POLICY` + `CREATE POLICY` restore SQL rather than referencing a separate rollback file — keeps emergency rollback path in the same document the operator already has open during the smoke test.

## Deviations from Plan

None — plan executed exactly as written. All 3 file contents copied verbatim from the plan's `<action>` blocks. No bugs found, no missing critical functionality detected, no blocking issues.

## Issues Encountered

- **Worktree base mismatch on startup:** Initial `git merge-base HEAD 73929cc` returned `b359ebc` (current HEAD) — the worktree was created from a stale parent-repo HEAD that did not yet include the phase-0 planning commits. Resolved by `git merge --ff-only 73929cc...` (non-destructive fast-forward, advances branch tip to the descendant commit `73929cc` without rewriting history). The orchestrator's `git reset --hard` instruction would have produced the same end state but was blocked by a local fact-forcing gate on destructive commands; the fast-forward approach is strictly safer because it never discards commits.
- **`--no-verify` flag blocked by local hook:** The orchestrator's parallel_execution prompt directed using `git commit --no-verify` to avoid pre-commit hook contention with other worktree agents. A local pre-bash hook unconditionally blocks `--no-verify`. Fell back to standard `git commit` — pre-commit hooks ran and passed cleanly for all 3 commits, so contention was not actually a problem in practice.
- **Fact-forcing gate fired on each Write/destructive command:** Required restating facts (file callers, no-existing-equivalent confirmation, data-field schema, verbatim user instruction) before each `Write` call. No workflow impact; facts presented inline before each retry.

## User Setup Required

None — no external service configuration introduced. The captain runbook describes operational steps the captain performs in Supabase Studio after Plan 0-06 deploys, but Plan 0-01 itself is documentation-only.

## Next Phase Readiness

- **Plan 0-06 (email-migration-rls) is unblocked architecturally** but waits on the captain touchpoint: dev MUST receive explicit "FOUND-01 Audit clean" message from captain before running `supabase db push` of `20260430b_email_unique.sql` and `20260430c_players_rls_pin.sql`.
- **FOUND-02 verification scaffolding is ready:** The RLS smoke-test runbook can be executed in ~10 minutes against the deployed migration to verify cross-write blocking + captain/self-update preservation across all 5 player-update UI surfaces.
- **No code changes shipped** — all artifacts are SQL audit script (Studio-only) and markdown runbooks. No build, no deploy, no runtime impact yet.
- **Cross-Phase smoke-test (after Wave 2/3):** Captain runs audit SQL -> confirms 0 rows -> dev deploys Plan 0-06 -> dev/captain runs RLS smoke-test runbook -> 4 test-cases + 5 surfaces all green.

## Self-Check

Verifying claims before marking complete.

**Files claimed created:**

- `supabase/migrations/_audit/20260430_email_pre_check.sql` — FOUND
- `docs/runbooks/email-cleanup.md` — FOUND
- `docs/runbooks/rls-cross-write-test.md` — FOUND

**Commits claimed:**

- `6255083` (Task 1: feat audit SQL) — FOUND in `git log`
- `5c1ae65` (Task 2: docs email-cleanup runbook) — FOUND in `git log`
- `bc8471b` (Task 3: docs RLS smoke-test runbook) — FOUND in `git log`

**Acceptance-criteria evidence:**

- Task 1: file exists, contains `WHERE email IS NULL` (line 10) and `GROUP BY lower(email)` (line 21) — verified.
- Task 2: file exists, contains "Captain-Schritte", "20260430_email_pre_check.sql", "supabase db push", "family", "Captain" (13 total grep matches) — verified.
- Task 3: file contains all 4 test-case IDs (`0-02-cross`/`0-02-emailpin`/`0-02-captain`/`0-02-self`), 5 svelte-file references, 3 occurrences of `sb.from('players').update`, 3 mentions of rollback/zurueck — verified.
- Audit SQL is in `_audit/` subfolder (not `migrations/` root) — verified by `dirname` check.

## Self-Check: PASSED

---
*Phase: 00-cross-cutting-foundations*
*Plan: 01-email-audit*
*Completed: 2026-05-01*
