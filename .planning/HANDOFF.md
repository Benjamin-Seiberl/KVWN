# GSD-New-Project Handoff — paused 2026-04-28

**User-pause-message verbatim:** *"after synthesizer finish tasks for today so that we can finish it the next time. going to bed soon"*

**Resume next time with:** `/gsd-resume-work` — *or* read this file and continue inline (Step 7 + Step 8 of the new-project workflow).

---

## Status

Workflow: `/gsd-new-project` (file at `~/.claude/get-shit-done/workflows/new-project.md`).

| Step | Done | Output |
|------|------|--------|
| 1. Setup | ✅ | gsd-sdk CLI not installed in expected form (`gsd-sdk` not on PATH); workflow ran without it. Brownfield detected via `.planning/codebase/` (mapped in prior session). |
| 2. Brownfield offer | ✅ skipped | User chose "Init kvwn as GSD project" — codebase already mapped. |
| 3. Deep questioning | ✅ | 6 AskUserQuestion rounds + freeform. Frame, core value, users, scope, deadline, JHV-status all captured. |
| 4. PROJECT.md | ✅ | `.planning/PROJECT.md` (commit `b02ca59` — `docs: initialize project`). |
| 5. Workflow preferences | ✅ | `.planning/config.json` extended (commit `b1933d5` — `chore: add project config`). YOLO + Standard + Parallel + commit_docs + research/plan_check/verifier all on + balanced models. Graphify section preserved. |
| 5.1 Sub-repo detection | ✅ skipped | kvwn = single repo. |
| 5.5 Resolve model profile | ✅ | balanced (Sonnet for most, Opus for roadmapper). |
| 6. Research | ✅ | 4 parallel researchers + 1 synthesizer. 5 files in `.planning/research/` (commit `662851c` — `docs(research): synthesize v1 research into SUMMARY`). |
| **7. Requirements** | ⬜ **TODO** | See "Resume Step 7" below. |
| **8. Roadmap** | ⬜ **TODO** | See "Resume Step 8" below. |
| 9. Done | ⬜ | Final summary + auto-advance to `/gsd-discuss-phase 1`. |

---

## What was decided (compressed)

- **Vision:** Vollumfängliche Vereins-App KVWN. "Alles unter einem Dach."
- **Frame:** Vision-Spec for existing brownfield app. Validated = live. Roadmap = was fehlt zur Vollumfänglichkeit.
- **v1 scope (4 features, JHV demo 2026-05-22):** Trainingsbuchung-Vollausbau, Spieler-Selfservice Stammdaten, Statistik-Dashboards, Events+Umfragen+Push systematisch.
- **JHV-status:** Demo-ready (klick-bar, überzeugend), nicht Production-ready.
- **Out of Scope:** Multi-Tenant, öffentliche Sponsor-Webseite, Stack-Replace.
- **Backlog (post-v1):** v2 = eigene Turniere, Vereinsmeisterschaften, Sponsoren intern, Kantinen-Besetzung, Vereinsfinanzen, Live-Score. v3 = Lagerstand Kantine.

## Recommended roadmap structure (from SUMMARY.md)

**6 phases / 24-day budget — feasible only with Phase 0 first.**

1. **Phase 0 — Cross-Cutting Foundations** (2d) — RLS email-pin, TZ-helper, `is_demo`-pattern, `PUSH_PREFS`-constant, image-resize util. **Non-negotiable** (resolves 2 BLOCKER pitfalls).
2. **Phase 1 — F2 Selfservice + Foto + Consent** (4-5d) — Profil-Sheets, Foto-Upload, DSGVO-Consent-Modal.
3. **Phase 2 — F1 Trainingsbuchung-Vollausbau** (4-5d) — Warteliste, Auto-Promote, Stats-Card, Lane-Strip, training-reminders cron.
4. **Phase 3 — F4 Events + Polls + Push systematisch** (5-6d) — push_outbox, scheduled-push cron, GCal-Dup-Guard refactor, EventCreate erweitert.
5. **Phase 4 — F3 Statistik-Dashboards** (5-6d) — DB-Views, league_standings, FormCurveChart, StatsView 3 sub-tabs.
6. **Phase 5 — Demo-Härtung + Reviewer-Pass** (2-3d) — Snapshot, Demo-Account, Cleanup-Migration, Pitfall-Verification, Reviewer-Pass über alle Diffs.

Phase 2 + 3 can run in parallel if executor capacity exists; default seriell.

---

## Open Questions (track during plan-phase)

- Liga-Tabelle-Datenquelle: Captain-Manuell vs. ÖSKB/NÖSKB-Feed? Default Captain-Manuell + Mock for JHV.
- `match_results.lane_id` exists? Verify before planning Bahn-Statistik.
- `league_standings` Punkte-Logik (2:0=2pkt etc.) — validate with Captain.
- PLAYER_FIELDS in `profil/UebersichtTab` reference unverified columns (per MEMORY.md). Researcher-sweep before Phase 1 frontend-dev.
- Familien/Gäste read-only-Tier — proposed cut from v1 Active to Out-of-Scope (per FEATURES.md guidance). User to confirm during Step 7.
- Reviewer-phase capacity per phase (0.5d each) — accommodate in plan-phase budgeting.

---

## Resume Step 7 — Requirements

Workflow file: `~/.claude/get-shit-done/workflows/new-project.md` lines 962-1114.

**Goal:** Produce `.planning/REQUIREMENTS.md` with REQ-IDs, v1 grouped by category, v2 deferred, Out-of-Scope explicit, traceability section (empty, filled later by roadmapper).

### Approach for next session

Mode is **YOLO** per config.json — but Step 7 still needs interactive scoping per category. Workflow auto-mode skips scoping AskUserQuestion loops; YOLO is not auto-mode. **Decision:** ask Benjamin per-category scoping (table-stakes vs differentiators vs cut), one AskUserQuestion per v1-feature-area (4 total). Source the options from `.planning/research/FEATURES.md` (already has table-stakes/differentiators/anti-features split).

### REQ-ID schema

`<CATEGORY>-NN`. Suggested categories from PROJECT.md + research:

- `FOUND-` (Phase-0 Foundations: RLS-pin, TZ-helper, is_demo, push_prefs, image-resize)
- `SELF-` (F2 Selfservice + Foto + Consent)
- `TRAIN-` (F1 Training-Vollausbau)
- `EVT-` (F4 Events + Polls + Push)
- `STAT-` (F3 Statistik-Dashboards)
- `DEMO-` (Phase 5 Demo-Härtung)

### Files to read at resume

1. `.planning/PROJECT.md` — vision, active scope, out-of-scope
2. `.planning/research/SUMMARY.md` — 6-phase structure with rationale
3. `.planning/research/FEATURES.md` — table-stakes/differentiators/anti-features pro v1-area
4. `.planning/research/PITFALLS.md` — 15 pitfalls with phase mapping (informs FOUND-/DEMO- requirements)

### Commit at end

`git add .planning/REQUIREMENTS.md && git commit -m "docs: define v1 requirements"`

---

## Resume Step 8 — Roadmap

Workflow file: `~/.claude/get-shit-done/workflows/new-project.md` lines 1116-1262.

**Goal:** Spawn `gsd-roadmapper` agent with REQUIREMENTS.md + PROJECT.md + SUMMARY.md as inputs. Agent writes `.planning/ROADMAP.md` + `.planning/STATE.md` + updates REQUIREMENTS.md traceability.

### Roadmapper prompt template (workflow line 1131-1156)

```
Task(prompt="
<planning_context>

<files_to_read>
- .planning/PROJECT.md
- .planning/REQUIREMENTS.md
- .planning/research/SUMMARY.md
- .planning/config.json
</files_to_read>

</planning_context>

<instructions>
Create roadmap:
1. Derive phases from requirements (6 phases recommended per SUMMARY.md — Phase 0 + 4 features + Phase 5)
2. Map every v1 requirement to exactly one phase
3. Derive 2-5 success criteria per phase (observable user behaviors)
4. Validate 100% coverage
5. Write files immediately (ROADMAP.md, STATE.md, update REQUIREMENTS.md traceability)
6. Return ROADMAP CREATED with summary
</instructions>
", subagent_type="gsd-roadmapper", model="opus", description="Create roadmap")
```

### Approval gate (YOLO mode = auto-approve per workflow line 1207)

Per config.json `mode: yolo` → workflow line 1207 says "Skip approval gate — auto-approve and commit directly." But for a 6-phase roadmap touching production app, present the ROADMAP table inline before commit and offer adjustment opportunity. User can still say "ship it" without re-approval.

### Generate CLAUDE.md regeneration

Per workflow line 1252:
```bash
gsd-sdk query generate-claude-md --output CLAUDE.md
```
**BUT:** `gsd-sdk` is not on PATH. Skip this step or invoke via `node C:/Users/benni/.claude/get-shit-done/bin/gsd-tools.cjs ...` if a matching command exists. **Existing CLAUDE.md is project-specific and high-quality — do NOT auto-regenerate without diffing first.** Recommend: skip this regen step, keep current CLAUDE.md untouched, document the skip in handoff.

### Commit at end

```bash
git add .planning/ROADMAP.md .planning/STATE.md .planning/REQUIREMENTS.md
git commit -m "docs: create roadmap (6 phases)"
```
(omit CLAUDE.md from commit if regen skipped)

---

## Resume Step 9 — Done

Per workflow line 1266-1346. Print completion summary, route user to `/gsd-discuss-phase 0` (Phase 0 = Foundations) — NOT Phase 1, because SUMMARY.md recommends Phase 0 first.

If config has `workflow.auto_advance: true` (it does), workflow line 1287-1295 says auto-advance to discuss-phase. **Override recommendation:** for kvwn brownfield with 24-day deadline, the user should manually decide before kicking off Phase 0 (it touches production RLS + cron — not a fire-and-forget step). Present the Next-Up block, do NOT auto-invoke.

---

## Tooling note

`gsd-sdk` CLI is NOT installed (was expected by workflow). Workflow ran without it; init detection, config-write, commit-helper all done manually.

To install if desired:
```bash
npx --yes get-shit-done-cc@latest --global
```
(was done at start of this session, but it installed `gsd-tools.cjs` only, not `gsd-sdk`. Different binary. The workflow expects `gsd-sdk query …` syntax which `gsd-tools.cjs` does not provide.)

Skipping the SDK has been workable so far. Step 7+8 do not strictly require it either — manual JSON construction + manual git commits work fine.

---

## Files already on disk + committed

- `.planning/PROJECT.md` (b02ca59)
- `.planning/config.json` (b1933d5)
- `.planning/research/STACK.md` (662851c)
- `.planning/research/FEATURES.md` (662851c)
- `.planning/research/ARCHITECTURE.md` (662851c)
- `.planning/research/PITFALLS.md` (662851c)
- `.planning/research/SUMMARY.md` (662851c)
- `.planning/codebase/` (from prior session, not committed yet — orchestrator can decide whether to commit before resume)
- `.planning/HANDOFF.md` (this file — to be committed in this session's final commit)

## Files NOT yet on disk (Step 7 + 8 outputs)

- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `.planning/STATE.md`

---

*Handoff written: 2026-04-28. Resume target: complete Steps 7+8+9 of `/gsd-new-project`.*
