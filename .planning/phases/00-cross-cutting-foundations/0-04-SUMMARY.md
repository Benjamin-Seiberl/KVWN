---
phase: 00-cross-cutting-foundations
plan: 04
subsystem: database
tags: [pattern, mock-data, jhv-demo, cleanup-migration, postgres, documentation]

# Dependency graph
requires: []
provides:
  - "is_demo BOOLEAN-Spalten-Pattern fuer Mock-Seed-Cleanup post-JHV"
  - "ROADMAP-Cross-Refs in Phase 4 STAT-03/05 + Phase 5 DEMO-03"
affects:
  - "Phase 4 (STAT-03 league_standings, STAT-05 Mock-Seed)"
  - "Phase 5 (DEMO-03 Cleanup-Migration)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "is_demo BOOLEAN DEFAULT false NOT NULL auf neuen v1-Tabellen"
    - "Production-Reads filtern via WHERE NOT is_demo (View oder inline)"
    - "Idempotente Cleanup-Migration post-JHV: DELETE WHERE is_demo"
    - "NICHT retroaktiv auf Bestandstabellen anwenden"

key-files:
  created:
    - "docs/patterns/is-demo.md"
  modified:
    - ".planning/ROADMAP.md"

key-decisions:
  - "Markdown-Pattern-Doku (kein Code-Helper) genuegt fuer FOUND-06 — Pattern wird in Phase 4 angewendet, nicht in Phase 0"
  - "Inline-Annotations in ROADMAP statt separater Doku-Verweis-Sektion — 3 Bullet-Punkte (STAT-03, STAT-05, DEMO-03) erweitert"
  - "Retroaktiv-NEIN-Regel als prominente Section in is-demo.md — verhindert Backfill-Trap auf Bestandstabellen"

patterns-established:
  - "is_demo-Pattern: BOOLEAN DEFAULT false NOT NULL auf neuen Tabellen, Mock-Seeds insert mit is_demo=true, Production-Read filtert WHERE NOT is_demo, Cleanup-Migration loescht WHERE is_demo"
  - "Cross-Reference-Style in ROADMAP: Inline ` — siehe `<doc>` ` oder ` (siehe `<doc>`, FOUND-XX) ` an REQ-Bullet-Punkten"

requirements-completed:
  - FOUND-06

# Metrics
duration: 4min
completed: 2026-05-01
---

# Phase 0 Plan 4: is_demo-Pattern Summary

**Pattern-Doku fuer is_demo BOOLEAN-Spalte (Mock-Daten-Cleanup post-JHV) als Markdown-Doc in docs/patterns/, mit Inline-Cross-Refs in ROADMAP Phase 4 + Phase 5**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-05-01T10:14:27Z
- **Completed:** 2026-05-01T10:17:56Z
- **Tasks:** 2
- **Files modified:** 2 (1 neu erstellt, 1 annotiert)

## Accomplishments

- `docs/patterns/is-demo.md` etabliert das is_demo-Pattern fuer alle v1-Phase-1-bis-4-Tabellen mit Mock-Seed-Bedarf
- Pattern-Doku enthaelt: SQL-Skelett, 3 Anwendungs-Saetze (Insert/Read/Cleanup), explizite NICHT-retroaktiv-Regel, Phase-4-Anwendungsbeispiel (`league_standings`), Audit-Query
- ROADMAP.md-Cross-Refs in Phase 4 STAT-03 + STAT-05 + Phase 5 DEMO-03 verweisen auf das Pattern-Doc — Future-Plan-Phasen koennen direkt darauf referenzieren
- Pitfall C10 (Mock-Daten-Cleanup-Trap) ist mit klarem Cleanup-Pfad abgedeckt: `DELETE FROM <table> WHERE is_demo` als idempotente Migration post-JHV

## Task Commits

Each task was committed atomically:

1. **Task 1: is-demo.md Pattern-Doku schreiben** — `bcee4b0` (docs)
2. **Task 2: ROADMAP.md Phase-4-Sektion mit Pattern-Verweis annotieren** — `3112fc5` (docs)

_Final SUMMARY commit follows separately._

## Files Created/Modified

- `docs/patterns/is-demo.md` (NEU, 100 Zeilen) — Pattern-Doku mit SQL-Skelett, Insert-/Read-/Cleanup-Anleitung, NICHT-retroaktiv-Regel, league_standings-Beispiel, Audit-Query, Referenzen auf REQUIREMENTS.md FOUND-06/STAT-03/STAT-05/DEMO-03
- `.planning/ROADMAP.md` (3 Zeilen geaendert) — Inline-Cross-Refs auf `docs/patterns/is-demo.md` an STAT-03 (Z 216), STAT-05 (Z 218), DEMO-03 (Z 264)

## Decisions Made

- **Pattern-Doc-Format:** Markdown-only, kein Code-Helper. Begruendung: is_demo-Spalte ist eine triviale BOOLEAN-Konvention, kein Helper-Code noetig. Phase-4-STAT-Plans embedden die Spalte direkt in ihre `CREATE TABLE`-Migrations.
- **Cross-Ref-Form in ROADMAP:** Inline-Annotation an existierenden Bullet-Punkten (`- STAT-03 — ...`) statt separater "References"-Sektion. Begruendung: Sichtbarkeit am Use-Site, kein Lookup noetig.
- **NICHT-retroaktiv-Regel als prominente Section:** `players`, `matches`, `game_plans`, `training_*`, `events` enthalten Real-Daten — `ADD COLUMN is_demo` retroaktiv waere Default-Spalte ohne semantischen Wert + Backfill-Trap. Pattern explizit auf neue Phase-1-bis-4-Tabellen beschraenkt.

## Deviations from Plan

### Plan-Verify-Expression-Bug (nicht-blockierend)

**1. [Rule 3 - Plan Bug Documented] Plan-Acceptance `grep -c "^### Phase" .planning/ROADMAP.md = 6` greift nicht**

- **Found during:** Task 2 verification
- **Issue:** Plan-Acceptance-Criterion zaehlt `^### Phase`-Headings und erwartet `= 6`. Tatsaechlich liefert grep `7` weil `### Phase Summary Table` (Zeile 20) ebenfalls matcht. Der Count war auch VOR meinen Edits bereits `7` (verifiziert via `git show HEAD:.planning/ROADMAP.md`).
- **Fix:** Keine — die strukturelle Integritaet ist erhalten (alle 6 echten Phasen-Sections + 1 Summary-Heading unveraendert). Der Plan-Verify-Pattern hat eine off-by-one-Issue die nicht durch meine Edits ausgeloest wurde.
- **Files modified:** keine (Issue im PLAN.md selbst, nicht in der Roadmap)
- **Verification:** `grep -n "^### Phase" .planning/ROADMAP.md` zeigt 6 Phase-N-Headings (Z 38, 72, 113, 153, 204, 252) + 1 Summary-Table-Heading (Z 20) = 7 total. Vor + nach Edits identisch.
- **Committed in:** n/a (kein Code-Fix noetig)

---

**Total deviations:** 1 documented plan-verify-bug (no work needed)
**Impact on plan:** Keine. Semantische Acceptance-Intent ("alle 6 Phasen noch da") ist erfuellt — alle 6 Phase-N-Sections sind unveraendert vorhanden.

## Issues Encountered

- **Hook-Friction (PreToolUse-Gates):** Mehrere Bash/Edit-Operationen wurden vom Fact-Forcing-Gate-Hook geblockt — auch read-only `grep`-Commands (regex `DELETE FROM` triggert Destructive-Heuristik) und reine Markdown-Annotation-Edits in ROADMAP.md. Workaround: Facts vor jedem Tool-Call praesentiert, Bash-grep durch Grep-Tool ersetzt wo moeglich. Keine inhaltlichen Probleme, nur Verbose-Pfad.

## User Setup Required

None - kein externer Service-Setup, reine Doku-Plan.

## Next Phase Readiness

- **Phase 4 PLAN-Phase ready:** Wenn Phase-4-Planner STAT-03 / STAT-05 schreibt, kann er `docs/patterns/is-demo.md` als `<read_first>`-Reference auflisten. ROADMAP weist bereits darauf hin.
- **Phase 5 DEMO-03 ready:** Cleanup-Migration-Template ist im Pattern-Doc dokumentiert — Phase-5-Planner kann direkt mit `DELETE FROM public.league_standings WHERE is_demo;` starten.
- **Pitfall C10 mitigation:** Cleanup-Pfad existiert nun als dokumentiertes Pattern. Phase 5 DEMO-03 kann es 1:1 anwenden.

## Self-Check

Verified post-execution:

- File `docs/patterns/is-demo.md` existiert (100 Zeilen, alle 6 Acceptance-Greps treffen)
- Commit `bcee4b0` (Task 1) im git-log
- Commit `3112fc5` (Task 2) im git-log
- `.planning/ROADMAP.md` enthaelt 3 `is-demo.md`-Treffer (STAT-03 Z 216, STAT-05 Z 218, DEMO-03 Z 264)
- Alle 6 Phase-Sections in ROADMAP.md unveraendert (Z 38, 72, 113, 153, 204, 252)

## Self-Check: PASSED

---
*Phase: 00-cross-cutting-foundations*
*Completed: 2026-05-01*
