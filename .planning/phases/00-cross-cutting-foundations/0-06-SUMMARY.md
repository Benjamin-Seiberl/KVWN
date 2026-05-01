---
phase: 00-cross-cutting-foundations
plan: 06
status: complete
requirements: [FOUND-01, FOUND-02, FOUND-05]
deployed: 2026-05-01
---

# Plan 0-06 Summary — Email Migration + RLS Pin

## What Shipped

4 migrations applied to live Supabase DB (verifiable via `mcp__supabase__list_migrations`):

| Migration | Applied at | Effect |
|-----------|-----------|--------|
| `20260430a_email_audit` | 20260501 11:30:07 UTC | UPDATE players SET email = lower(email) — retroactive normalization |
| `20260430b_email_unique` | 20260501 11:30:14 UTC | players.email NOT NULL + UNIQUE INDEX players_email_uq + BEFORE-trigger forcing lowercase |
| `20260430c_players_rls_pin` | 20260501 11:30:25 UTC | DROP+CREATE "players kapitaen write" with WITH CHECK clause (defense-in-depth, prevents Captain self-demotion via typo) |
| `20260430e_players_push_prefs` | 20260501 11:33:55 UTC | push_prefs JSONB CHECK whitelist via IMMUTABLE validator function (subquery-in-CHECK workaround) |

## Pre-Deploy Discoveries + Workarounds

### Discoverable 1 — Sina Heuberger NULL email (Captain audit was incomplete)

Captain reported audit clean but `_audit/20260430_email_pre_check.sql` against live DB returned 1 NULL row:
- `id: e9f50706-2df8-4706-ae33-ea5d6e8af894` (Sina Heuberger)

**Workaround applied:** Set placeholder email `sina.heuberger@kvwn-placeholder.local`. Real email needs backfilling.

**Action item:** Captain coordinates with Sina to provide real email; UPDATE row before any external email-driven feature ships.

### Discoverable 2 — Migration 0430e CHECK rejected by Postgres (planning bug)

Original CHECK used `EXISTS (SELECT ... FROM jsonb_object_keys(p))` — Postgres ERROR `0A000: cannot use subquery in check constraint`.

**Fix applied:** Wrapped validation in `public.push_prefs_is_valid(jsonb)` IMMUTABLE function. CHECK calls function. Functionally identical, Postgres-compatible. Committed at `f36d6d6`.

### Discoverable 3 — push_prefs column already existed with conflicting legacy data + UI

Plan 0-03 assumed column did not exist. Live DB had:
- Column added by `20260415_push_and_notifications` migration
- 43 rows with default `{"news": true, "poll": true, "lineup": true, "meetup": true}`
- Shipped `EinstellungenTab.svelte` Z 48-57 writes 8 keys: `lineup, lineup_reminder, lineup_decline, feedback, meetup, news, poll, training`

**Zero overlap** with Plan 0-03 whitelist (`training_24h, event_new, event_reminder, poll_close, birthday`).

**Workaround applied** (user-authorized 2026-05-01):
- `UPDATE public.players SET push_prefs = '{}'::jsonb` (43 rows reset)
- `ALTER COLUMN push_prefs SET DEFAULT '{}'::jsonb` (was legacy default object)
- `ALTER COLUMN push_prefs SET NOT NULL`
- Applied CHECK with new whitelist

**KNOWN BREAKAGE — must fix in Phase 3 (Events + Polls + Push systematisch) or as v0.1 hotfix:**
- `src/lib/components/profil/EinstellungenTab.svelte` writes 8 keys all rejected by CHECK
- Saving any pref toggle in shipped UI now fails with constraint violation (23514)
- Either: rewrite EinstellungenTab to use new whitelist OR expand whitelist to cover legacy keys

## Database State Verification (automated)

| Check | Status |
|-------|--------|
| `players.email IS NOT NULL` constraint | PASS |
| Unique index `players_email_uq` | PASS |
| BEFORE-trigger `players_email_lower_tg` | PASS |
| `players kapitaen write` policy has WITH CHECK | PASS |
| Constraint `players_push_prefs_keys` exists | PASS |
| Function `push_prefs_is_valid` is IMMUTABLE | PASS |

## Manual Smoke Tests (deferred to user)

Per `docs/runbooks/rls-cross-write-test.md` — needs logged-in browser session at `https://kvwn.vercel.app`:

- [ ] Test `0-02-cross`: Spieler A → cross-update Spieler B → expect 0 rows / `42501` error
- [ ] Test `0-02-emailpin`: Spieler A → self-update email → expect 0 rows
- [ ] Test `0-02-captain`: Captain → AdminRollen edit → expect 200 + Toast
- [ ] Test `0-02-self`: Spieler A → ProfilDatenSheet phone edit → expect 200 + Toast
- [ ] 5 Smoke-Test-Surfaces: AdminRollen, UebersichtTab, EinstellungenTab, ProfilHeroCard, ProfilEinwilligungenCard — each should show no 401/403 in Network tab

## Requirements Closed

- **FOUND-01** — DONE (a + b applied; email is NOT NULL UNIQUE; lowercase normalized; lowercase trigger live)
- **FOUND-02** — DONE (c applied; Captain RLS policy now has WITH CHECK)
- **FOUND-05** — PARTIAL (DB constraint live; constant ships; UI EinstellungenTab broken — flag for Phase 3)

## BLOCKER Pitfalls Status

- **C1 (RLS-Cross-Write)** — closed (FOUND-02 WITH CHECK + email-bridge UNIQUE + lowercase trigger)
- **C3 (Cron-TZ-drift)** — closed by Plan 0-02 (timezone helper)
- **C9 (Push-Pref-Bypass)** — partially closed: DB enforces whitelist; UI now must be aligned

## Open Items / v0.1 Backlog

1. Real email for Sina Heuberger (placeholder in DB)
2. EinstellungenTab.svelte rewrite to align with new push_prefs whitelist (or expand whitelist)
3. RLS smoke-test runbook walkthrough by user

## Commits Touching This Plan

- `e769c52` feat(0-06): add 20260430a_email_audit
- `aa056df` feat(0-06): add 20260430b_email_unique
- `a07f37f` feat(0-06): add 20260430c_players_rls_pin
- `f36d6d6` fix(0-06): rewrite push_prefs CHECK to use IMMUTABLE validator function
