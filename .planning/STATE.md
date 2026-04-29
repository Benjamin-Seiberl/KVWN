# KVWN Vereins-App — Project State

*Lebende Snapshot-Datei. Wird bei jedem Phase-Transition + Plan-Completion via `/gsd-progress` aktualisiert.*

---

## Project Reference

**What This Is:** Vollumfängliche Vereins-PWA für KV Wiener Neustadt (Kegelverein) — Spielbetrieb, Training, Statistik, Events, Push.

**Core Value:** "Alles unter einem Dach" — Konsolidierung aller Vereinsworkflows in einer App, die so schön und durchdacht ist, dass Spieler und Familie sie freiwillig nutzen.

**Current Focus:** v1 zur JHV (2026-05-22) — Demo-ready, nicht Production-ready.

---

## Current Position

**Milestone:** v1 (JHV-Demo)
**Phase:** Phase 0 of 6 — Cross-Cutting Foundations
**Status:** Planned (Step 8 abgeschlossen, Phase 0 Plan-Phase steht aus)
**Active Plan:** none
**Last Plan Completed:** none
**Deadline:** 2026-05-22 (~24 Tage ab heute)

### Progress

```
[░░░░░░░░░░] 0% — 0 / 6 Phasen completed
```

| Phase | Plans Complete | Status |
|-------|----------------|--------|
| 0. Cross-Cutting Foundations | 0/0 | Context gathered, Plan-Phase next |
| 1. Selfservice + Foto + Consent | 0/0 | Planned |
| 2. Trainingsbuchung-Vollausbau | 0/0 | Planned |
| 3. Events + Polls + Push systematisch | 0/0 | Planned |
| 4. Statistik-Dashboards | 0/0 | Planned |
| 5. Demo-Härtung + Reviewer-Pass | 0/0 | Planned |

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases completed | 0 / 6 |
| Plans completed | 0 |
| Requirements mapped | 75 / 75 (100% coverage) |
| Days elapsed | 0 / 24 (Deadline 2026-05-22) |
| Buffer | -1 d (mid-range Schätzung) bis +2 d (lower-bound) |

---

## Recent Decisions

Aus `.planning/PROJECT.md` § "Key Decisions" + Step-7-Differentiator-Picks (`.planning/REQUIREMENTS.md`):

1. **2026-04-28 — Vision-Spec-Frame statt Re-Spec ground-up.** Bestehender Code substanziell, kein Rewrite-Budget. Validated = live-Code, Roadmap = was fehlt.
2. **2026-04-28 — Core Value = Konsolidierung statt Killer-Feature.** "Alles unter einem Dach" treibt Verein-Adoption stärker als jedes Einzel-Feature.
3. **2026-04-28 — v1 = Demo-ready zur JHV (nicht Production-ready).** 24 Tage zu kurz für 4 Production-Features; Demo überzeugt JHV genauso. Mock-Daten für Statistik/Events explizit erlaubt.
4. **2026-04-28 — Stack-Lock SvelteKit + Supabase + Vercel.** Keine Migration; Velocity > Stack-Modernisierung.
5. **2026-04-29 (Step 7) — Familien/Gäste read-only-Tier auf v2 verschoben.** Schema + RLS-Tier-Logic ist eigenes Projekt, spart 3-4 Tage.
6. **2026-04-29 (Step 7) — `league_standings` als Captain-manuelle Tabelle + Mock-Seed mit `is_demo=true`.** ÖSKB-Feed-Import ist v1.1; Captain-Tool reicht für JHV.
7. **2026-04-29 (Step 7) — Differentiator-Picks final:** SELF-11/12 (Geburtstags-Banner, Konfetti), TRAIN-09/10 (Slot-Templates, Streak-Badge), EVT-16/17/18/19 (Time-Poll→Event, Cover-Foto, Recurring, Carpool generalisiert), STAT-14/15/16/17 (Form-Trend, Highlights, Animation, Bahn-Stats falls Schema).
8. **2026-04-29 (Step 8) — Phase 0 NON-NEGOTIABLE; Phase 2/3 Default seriell, Parallel optional.** 24-Tage-Budget zu knapp für Speculative Parallel; Phase 0 BLOCKER-Pitfalls C1+C3 müssen vor jeder Feature-Phase fixed sein.
9. **2026-04-29 (Phase 0 Discuss) — Phase 0 Implementation-Decisions locked.** Captain-Cleanup vor Email-Migration; RLS Policy-Branch `self OR captain`; PUSH_PREFS lineup_confirm always-on + 5 opt-in Keys + jsonb_object_keys()-CHECK; imageResize Square 512×512 cover-crop WebP via Canvas-Re-encode. Detail in `.planning/phases/00-cross-cutting-foundations/0-CONTEXT.md`. FOUND-03/04/06 sind Planner-Discretion.

---

## Pending Todos

Backlog-Items leben als REQ-IDs in `.planning/REQUIREMENTS.md`. Diese Liste sammelt nur **akute Tätigkeits-Todos**, die nicht bereits durch eine REQ-ID abgedeckt sind:

- `/gsd-plan-phase 0` starten — Phase 0 CONTEXT.md ist locked, Researcher + Planner können ran.
- Captain-Touchpoint planen: Email-Cleanup-Runbook (`docs/runbooks/email-cleanup.md`) muss vor FOUND-01-Migration-Deploy von Captain manuell durchgegangen werden (~30 min).

---

## Blockers / Concerns

Übernommen aus `.planning/REQUIREMENTS.md` § "Open Questions" — alle 6 sind Plan-Phase-resolvable, KEIN harter Stopper für Step 8/9.

1. **Open Q1 — `match_results.lane_id` Spalte verifizieren.** STAT-17 hängt davon ab. Plan-Phase 4 muss Researcher-Sweep machen; falls fehlt → STAT-17 → v1.1.
2. **Open Q2 — `league_standings` Punkte-Logik (2:0=2pkt etc.).** Captain-Rückfrage vor Plan-Phase 4 / STAT-06.
3. **Open Q3 — PLAYER_FIELDS unverified** (MEMORY: `project_player_fields_unverified.md`). Researcher-Sweep vor Plan-Phase 1 / SELF-01.
4. **Open Q4 — DSGVO-`/privacy`-Seitentext text-driven.** Vorstand-Workflow für Gegenlesen vor Plan-Phase 1 / SELF-08.
5. **Open Q5 — GCal-Dup-Guard-Refactor (EVT-14) Edge-Cases.** Was passiert mit existierenden Match-Tag-skipped Events? Kurze Research vor Plan-Phase 3.
6. **Open Q6 — Reviewer-Phase-Kapazität pro Phase (0.5d eingerechnet).** Accommodate during Plan-Phase Budgeting; falls Reviewer-Findings explodieren, wird Phase 5 zur Engstelle.

**Globale Risiken (aus PITFALLS-Recovery-Strategien, schon in Phase-Reqs gemappt):**

- 24-Tage-Budget vs 22-27d Schätzung: Mid-Range = 1d Überzug. Phase 2/3 Parallel-Option ist der Hauptlever (4-5d Einsparung).
- Re-Work aus Phase 5 Reviewer-Pass kann Phase 1-4 zurückwerfen — Disziplin in Plan-Phase ist Hauptmitigation.

---

## Accumulated Context

### Key References

- **Vision:** `.planning/PROJECT.md`
- **Requirements (75 v1-Reqs):** `.planning/REQUIREMENTS.md`
- **Roadmap (6 Phasen):** `.planning/ROADMAP.md` (Step 8, 2026-04-29)
- **Research-Synthese:** `.planning/research/SUMMARY.md`
- **Pitfalls-Detail:** `.planning/research/PITFALLS.md`
- **Brownfield-Codebase-Doku:** `.planning/codebase/` (7 Files, ARCHITECTURE/STACK/STRUCTURE/CONCERNS/REFERENCE/etc.)
- **Project-Konventionen:** `C:\kvwn\CLAUDE.md`
- **Memory-Index:** `C:\Users\benni\.claude\projects\C--kvwn\memory\MEMORY.md`

### Step-Status

- ✓ Step 1-6 (`/gsd-new-project`): Vision + Research complete (Commits 5620fcd → 662851c → b02ca59 → b1933d5)
- ✓ Step 7 (Requirements-Definition): 75 v1-Reqs in 6 Kategorien (Commit `6ab4ca1`)
- ✓ Step 8 (Roadmapper): ROADMAP.md + STATE.md + REQUIREMENTS.md-Traceability (Commit `e95028a`)
- ✓ Phase 0 Discuss (`/gsd-discuss-phase 0`): 0-CONTEXT.md + 0-DISCUSSION-LOG.md committed (`f27f94c`)
- ⧗ Phase 0 Plan (`/gsd-plan-phase 0`): next

---

## Session Continuity

**Last session:** 2026-04-29 — Phase 0 Discuss-Phase abgeschlossen.

**Stopped at:** Phase 0 CONTEXT committed (`f27f94c`). Files on disk: `.planning/phases/00-cross-cutting-foundations/0-CONTEXT.md` (8 Decisions locked), `.planning/phases/00-cross-cutting-foundations/0-DISCUSSION-LOG.md` (Audit-Trail). STATE.md aktualisiert.

**Next action:** `/clear` dann `/gsd-plan-phase 0` — Researcher + Planner spawnen, PLAN.md erzeugen mit Task-Breakdown FOUND-01..07.

**Resume hint:** Bei Session-Wiederaufnahme zuerst `.planning/phases/00-cross-cutting-foundations/0-CONTEXT.md` lesen für locked-Decisions, dann `.planning/STATE.md` für aktuellen Stand.

---

*State initialized: 2026-04-29 (Step 8 of `/gsd-new-project`)*
*Updates triggered by: `/gsd-progress`, `/gsd-transition`, plan completions.*
