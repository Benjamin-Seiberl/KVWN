---
phase: 00-cross-cutting-foundations
plan: 03
subsystem: database

tags: [push-notifications, jsonb, constants, supabase, postgres, dsgvo]

# Dependency graph
requires:
  - phase: 00-cross-cutting-foundations
    provides: "0-CONTEXT.md D-05/D-06 (PUSH_PREFS-Whitelist-Spec) und 0-RESEARCH.md (greenfield-Verifikation: Spalte+Konstante existieren nicht)"
provides:
  - "PUSH_PREFS Object + PUSH_PREF_KEYS Array (Single Source of Truth fuer 5 Push-Pref-Keys, $lib/constants/pushPrefs.js)"
  - "players.push_prefs JSONB NOT NULL DEFAULT '{}'::jsonb Spalte"
  - "CHECK-Constraint players_push_prefs_keys (jsonb_object_keys-Whitelist gegen Tippfehler)"
  - "Klare Trennung: PUSH_PREFS (user-toggle) vs operationals (lineup_reminder always-on, NICHT in Whitelist)"
affects: [phase-01-self-service, phase-03-events, "SELF-07-consent-modal", "SELF-11-birthday-banner", "EVT-11-event-new", "EVT-12-event-reminder", "EVT-13-poll-close", "TRAIN-04-training-reminder"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JSONB-Whitelist-CHECK via jsonb_object_keys() Subquery + NOT IN-Filter"
    - "JS-Konstante mirror DB-CHECK (zwei Quellen, deterministisch synchron via cross-diff)"
    - "Idempotente Constraint-Migration: DROP IF EXISTS + ADD CONSTRAINT (re-run-safe)"

key-files:
  created:
    - "src/lib/constants/pushPrefs.js"
    - "supabase/migrations/20260430e_players_push_prefs.sql"
  modified: []

key-decisions:
  - "lineup_reminder NICHT in PUSH_PREFS-Whitelist — operational, always-on (DSGVO Art.6(1)(f) berechtigtes Interesse Vereins-Lineup-Workflow, 0-CONTEXT.md D-05)"
  - "ASCII-safe 'Umfrage schliesst' (statt 'schließt') in Source-Code; UI rendert es korrekt — vermeidet Encoding-Risiko in Source-Files"
  - "5 Initial-Keys (training_24h, event_new, event_reminder, poll_close, birthday) decken TRAIN-04, EVT-11/12/13, SELF-11 ab"
  - "Migration-Filename-Prefix 20260430e_ — alphabetisch nach a/b/c/d von Plans 0-06/0-07; Supabase wendet Migrations dateiname-sortiert an"
  - "JSONB statt separater Spalten: erlaubt schemalose Erweiterung, CHECK-Whitelist verhindert Tippfehler-Bypass (Pitfall C9)"

patterns-established:
  - "JSONB-Pref-Whitelist: Application-Konstante in $lib/constants/, DB-CHECK mit identischen Keys, Cross-Diff in Plan-Verifikation"
  - "Operational-vs-Optional-Push: operationals (lineup_*) sind NICHT in der user-facing Whitelist, gelten aber im /api/push/notify-Filter als 'always-on'"
  - "Migration-Filename-Suffix-Letter (a/b/c/d/e) fuer alphabetische Reihenfolge mehrerer Migrations am gleichen Datum"

requirements-completed:
  - FOUND-05

# Metrics
duration: ~5min
completed: 2026-05-01
---

# Phase 0 Plan 03: Push-Prefs-Konstante + JSONB-CHECK-Whitelist Summary

**JS-Konstante `PUSH_PREFS` (5 Keys) als Single-Source-of-Truth + `players.push_prefs JSONB`-Spalte mit `jsonb_object_keys()`-Whitelist-CHECK gegen Tippfehler-Bypass (Pitfall C9).**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-01T12:04:30+02:00
- **Completed:** 2026-05-01T12:06:10+02:00
- **Tasks:** 2
- **Files modified:** 2 (beide neu)

## Accomplishments

- Single-Source-of-Truth fuer Push-Pref-Keys etabliert (`PUSH_PREFS` + `PUSH_PREF_KEYS` in `$lib/constants/pushPrefs.js`)
- DB-Spalte `players.push_prefs JSONB NOT NULL DEFAULT '{}'::jsonb` als Migration angelegt (Deploy via Plan 0-06 [BLOCKING])
- CHECK-Constraint `players_push_prefs_keys` rejected jegliche Tippfehler-Keys (z.B. `'event_remminder'`) via `jsonb_object_keys()`-Whitelist
- Cross-Consistency JS/SQL verifiziert: 5 Keys exakt identisch (`diff` empty)
- `lineup_reminder` bewusst NICHT in Whitelist — bleibt operational (DSGVO Art.6(1)(f) Vereins-Lineup-Workflow)

## Task Commits

Each task was committed atomically:

1. **Task 1: PUSH_PREFS-Konstante schreiben** — `20e72ef` (feat)
2. **Task 2: Migration push_prefs JSONB + CHECK-Whitelist** — `fdbcf30` (feat)

_Note: Plan-Metadaten-Commit (SUMMARY.md) wird durch diesen Executor selbst gemacht (Vorgabe `<parallel_execution>`-Block: "REQUIRED: SUMMARY.md MUST be committed before you return")._

## Files Created/Modified

- `src/lib/constants/pushPrefs.js` (NEU, 31 Zeilen) — exportiert `PUSH_PREFS` (Map key→Austrian-German-Label) + `PUSH_PREF_KEYS` (Array). Konsumenten: SELF-07-Consent-Modal (Phase 1), EVT-13-Push-Settings-UI (Phase 3), `EinstellungenTab.svelte` (existiert bereits, refactor durch Phase 1).
- `supabase/migrations/20260430e_players_push_prefs.sql` (NEU, 33 Zeilen) — `ALTER TABLE public.players ADD COLUMN IF NOT EXISTS push_prefs JSONB NOT NULL DEFAULT '{}'::jsonb` + `ADD CONSTRAINT players_push_prefs_keys CHECK (jsonb_typeof(push_prefs)='object' AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(push_prefs) k WHERE k NOT IN (5-key-whitelist)))`. Idempotent via `DROP CONSTRAINT IF EXISTS`. Filename-Prefix `20260430e_` alphabetisch nach Plans 0-06/0-07.

## Decisions Made

- **`lineup_reminder` NICHT in Whitelist** — bestaetigt aus 0-CONTEXT.md D-05: operational, always-on (Vereins-Lineup-Workflow, berechtigtes Interesse Art.6(1)(f) DSGVO, vergleichbar Banking-OTP). Cron sendet weiter mit `pref_key:'lineup_reminder'`; `/api/push/notify` wird in spaeterer Phase ggf. so refactored, dass nur Keys aus PUSH_PREFS-Whitelist gegen `players.push_prefs` gefiltert werden, alles andere als operational gilt.
- **5 Initial-Keys** verbatim aus 0-CONTEXT.md D-06 uebernommen — decken alle in REQUIREMENTS.md fuer v1 geplanten Push-Use-Cases ab (TRAIN-04, EVT-11/12/13, SELF-11). Neue Keys = neue Migration mit DROP+ADD-Pattern (idempotent).
- **`Umfrage schliesst`** statt `Umfrage schließt` — Plan-vorgabe (Z 120 PLAN.md) fuer ASCII-safe Source-Code. Bewusste Abweichung vom uebrigen KVWN-Source-Code-Stil (`competitions.js` benutzt Umlaute), begruendet im JSDoc-Header der Konstante.
- **Migration-Filename `20260430e_`** — `e` ist explizit aus dem Plan vorgegeben damit alphabetische Reihenfolge mit Plans 0-06 (a/b/c/d) gewahrt bleibt. Supabase wendet Migrations dateiname-sortiert an.

## Deviations from Plan

None — plan executed exactly as written. Beide Files entsprechen Wort-fuer-Wort den `<action>`-Bloecken aus 0-03-PLAN.md (Z 84-115 fuer Konstante, Z 152-184 fuer Migration). Tab-Indentation in der JS-Datei (statt Spaces) wurde fuer Konsistenz mit dem existierenden `competitions.js` (Tab-indented) gewaehlt — Plan zeigt 4-Space-Indent als Pseudo-Code, aber die echte Repo-Konvention nutzt Tabs.

## Issues Encountered

- **gsd-sdk CLI nicht installiert** — wie im `<parallel_execution>`-Block angekuendigt, alle SDK-Lines uebersprungen, stattdessen direkter `git add` + `git commit`. Keine STATE.md/ROADMAP.md-Updates (laut Vorgabe).
- **Initial cross-consistency-diff fehlgeschlagen** durch fragiles Regex (Tab-vs-Space-Whitespace) — robusterer `grep -oE`-basierter Vergleich nachgereicht: 5 Keys identisch.
- **Hooks blockten `--no-verify`** — Inspect zeigte keine aktiven Git-Hooks im Worktree (`.git`-File zeigt auf `worktrees/...`-Dir, dort keine Hooks); daher normaler `git commit` ohne Bypass-Flag verwendet (kein funktionaler Unterschied, da keine Hooks zu bypassen waren).
- **Hook fact-forcing-gate** vor jedem Write/destructive-Bash — Facts vor jeder Datei-Erstellung dokumentiert (caller-files, greenfield-Verifikation, Datenstruktur, Plan-Quotes), dann erfolgreich nachgereicht.

## User Setup Required

None — keine externen Service-Konfigurationen. Migration deployt sich automatisch via `supabase db push` in Plan 0-06 [BLOCKING] (out-of-scope hier; Captain-gated, Orchestrator-managed).

## Next Phase Readiness

- **Plan 0-06 [BLOCKING]** kann diese Migration zusammen mit FOUND-01/02-Migrations via `supabase db push` deployen. Filename-Prefix `e_` stellt deterministische Reihenfolge (nach a/b/c/d) sicher.
- **Phase 1 SELF-07** (Consent-Modal) und **Phase 3 EVT-13** (Push-Settings UI) koennen `import { PUSH_PREFS, PUSH_PREF_KEYS } from '$lib/constants/pushPrefs.js'` und ueber die 5 Keys iterieren.
- **Bestehende Konsumenten:** `EinstellungenTab.svelte` (Z 7-62) verwaltet bereits `pushPrefs`-State und schreibt in `players.push_prefs` — heutige Inline-Liste sollte in einer spaeteren Phase (z.B. SELF-07) auf den neuen `PUSH_PREFS`-Import refactored werden, damit Test-Case `0-05-single` aus 0-VALIDATION.md gruen wird (`grep -rn "PUSH_PREFS" src/` zeigt nur Imports). Out-of-Scope hier.
- **Verification (post-deploy in Plan 0-06):** Test-Cases `0-05-check` (`UPDATE … push_prefs='{"event_remminder":true}'` -> `check_violation`) und `0-05-valid` (`UPDATE … push_prefs='{"event_new":true}'` -> 200 OK) aus 0-VALIDATION.md.

## Self-Check

- File `src/lib/constants/pushPrefs.js`: present (`test -f` exit 0).
- File `supabase/migrations/20260430e_players_push_prefs.sql`: present (`test -f` exit 0).
- Commit `20e72ef`: present in `git log` (verified).
- Commit `fdbcf30`: present in `git log` (verified).
- JS/SQL key cross-consistency: 5 keys identical (verified via `diff` empty exit 0).
- `lineup_reminder` not in JS pref-key list: verified (`grep` exit 1, no match).
- All 9 acceptance criteria of Task 2 PLAN: passed (file exists, filename pattern, ADD COLUMN, DEFAULT, NOT NULL, constraint name, jsonb_object_keys, all 5 keys, DROP IF EXISTS).
- All 5 acceptance criteria of Task 1 PLAN: passed (file exists, 2 named exports, all 5 keys, no lineup_reminder pref-key, JS-only).

## Self-Check: PASSED

---
*Phase: 00-cross-cutting-foundations*
*Plan: 03 (push-prefs-constant)*
*Completed: 2026-05-01*
