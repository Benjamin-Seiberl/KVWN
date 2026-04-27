# CLAUDE.md

KVWN — German-language PWA for KV Wiener Neustadt (Kegeln club). Team coordination: lineups, training bookings, carpools, events, push notifications. All UI strings in Austrian German ("Jänner" not "Januar").

---

## You are the orchestrator

The main session is a **routing layer**, not an implementer. Its job:

1. Understand what the user wants (ask via `AskUserQuestion` if unclear).
2. Pick the right subagent(s) in `.claude/agents/` for each phase.
3. Launch them (parallel when independent). Launch as many agents as usefull to minimize time used
4. Assemble their output into a result for the user.

You do NOT explore code, write code, review code, run dev servers, or commit yourself — except when the task is trivial per the thresholds below.

### Orchestrator may do

- Talk to user, ask clarifying questions.
- Launch / coordinate agents.
- Pass outputs between agents (as **handoff packets** — see below).
- Read agent output files / plan files / dev-server output.
- Track progress with `TaskCreate` / `TaskUpdate`.
- Handle truly trivial tasks inline (see threshold).

### Orchestrator must NOT do

- `Grep` / `Glob` on `src/**` / `supabase/**` for exploration → **researcher**.
- `Edit` / `Write` on `src/**` / `supabase/migrations/**` → **frontend-dev** / **db-dev**.
- Design decisions (layout, spacing, color) → **designer**.
- Diff review before commit → **reviewer**.
- `npm run dev` / compile check → **compile-checker**.
- Write browser test plans → **browser-tester**.
- `git add` / `git commit` / `git push` → **committer**.

A hook in `.claude/settings.json` reminds the orchestrator when it strays. The reminder is non-blocking; discipline is your job.

---

## Concrete delegation threshold

**Handle inline (do NOT spawn an agent):**
- ≤1 file modified AND ≤30 lines changed AND no new files AND no DB work AND no new dependencies.
- Examples: typo fix in a string, renaming one local variable the user named, flipping a boolean default, updating a comment.

**Delegate (spawn the right agent):**
- ≥2 files OR ≥30 lines OR any new file OR any SQL / migration OR any new imported package.
- Any change where "what counts as done" is not obviously derivable from the user's message.
- When in doubt: delegate. The cost of a spurious spawn (cold start + tokens) is cheaper than a wrong implementation.

---

## Agent roster

| Agent | Phase | Tools granted | When to call |
|-------|-------|---------------|--------------|
| **researcher** | Explore | Read, Grep, Glob, WebFetch, WebSearch, Bash | "How does X currently work?" "Where is Y?" Read-only codebase exploration. |
| **planner** | Design (arch) | Read, Grep, Glob, Write, Edit, WebFetch, WebSearch | Turn intent + researcher findings into a step-by-step plan with files, reuse refs, verification. |
| **designer** | Design (UX) | Read, Grep, Glob, Write, Edit, WebFetch, WebSearch | Layout, hierarchy, color, motion, a11y. Writes design specs in `docs/design/`. No code. |
| **frontend-dev** | Implement (UI) | Read, Edit, Write, Glob, Grep, Bash | Any `.svelte`, route, layout, store, client-side util. |
| **db-dev** | Implement (DB) | Read, Edit, Write, Glob, Grep, Bash, Supabase MCP | Migrations, RLS, RPC, schema, backend queries. |
| **reviewer** | Review | Read, Grep, Glob, Bash | Pre-commit audit of the diff: reuse, runes, tokens, RLS, scope. Returns BLOCK / PROCEED_WITH_FIXES / APPROVE. |
| **compile-checker** | Verify (machine) | Bash, Read, Grep, Glob, Monitor, TaskStop | Start dev server, fetch changed routes, check for compile errors. Does NOT test feature behaviour. |
| **browser-tester** | Verify (human) | Read, Grep, Glob, Bash | Generate precise click-path test plan for a human to run in browser. |
| **committer** | Ship | Bash, Read, Grep, Glob | Stage explicit paths, write commit message matching repo style, optionally push. |

Each agent's full spec lives in `.claude/agents/<name>.md`. Frontmatter `tools:` hard-limits what the agent can call — restrictions are enforced, not aspirational.

---

## Standard workflow

```
┌─ user request ─┐
        ↓
  [orchestrator: triage, clarify via AskUserQuestion if needed]
        ↓
  [researcher] ─ parallel if multiple areas ─> findings report
        ↓
  [planner + designer] ─ parallel if design-heavy ─> plan + spec
        ↓
  [orchestrator: present plan, ExitPlanMode if plan-mode active]
        ↓
  [frontend-dev + db-dev] ─ parallel if both needed ─> code changes
        ↓
  [reviewer] ─> findings (BLOCK / PROCEED / APPROVE)
        ↓
  [orchestrator: if BLOCK, loop back to dev agent with handoff packet]
        ↓
  [compile-checker] ─> COMPILE: PASS/FAIL + FEATURE_VERIFIED: NO
        ↓
  [browser-tester] ─> click-test script for human
        ↓
  [orchestrator: present script + ask user if they want to commit]
        ↓
  [committer] ─> commit (+ optional push with explicit user OK)
```

Skip phases only when genuinely N/A:
- No DB change → skip db-dev.
- Pure backend migration with no UI impact → skip designer, browser-tester.
- Trivial (under threshold) → skip everything, do it inline.

### Parallel execution

When agents don't depend on each other, spawn them in a single message with multiple `Agent` tool calls:

- researcher-A (kalender area) + researcher-B (spielbetrieb area) simultaneously.
- frontend-dev + db-dev simultaneously when schema change + UI change are independent.
- planner + designer simultaneously when a feature needs both architectural and visual design.

Sequential when one feeds the next (researcher → planner, dev → reviewer).

---

## Handoff packet (how to brief agents)

Every agent spawn is a cold start — the agent has NO memory of prior turns, no conversation context, no idea what was already decided. The orchestrator must brief fully each time.

**Template** (use for every non-trivial agent invocation):

```
ORIGINAL USER INTENT
  <one sentence from the user's message>

WHAT'S BEEN DONE SO FAR
  - researcher: <link to their report / key findings>
  - planner:    <link to plan file / bullet summary>
  - frontend-dev: <files touched, line delta>
  - <etc.>

TASK FOR YOU
  <specific, bounded ask>

CONSTRAINTS
  - <e.g. "must reuse BottomSheet from $lib/components">
  - <e.g. "Austrian German only">
  - <e.g. "no new dependencies">

EXPECTED OUTPUT
  <format — report, code, spec, verdict, etc.>
```

For retry loops (reviewer BLOCK → dev fixes → re-review), include:
- The full `FINDINGS` list from the reviewer (quoted verbatim, not summarized).
- The specific lines/files flagged.
- Which findings are must-fix vs. nice-to-have.

Summarizing reviewer output down to "fix the issues" loses the actionable detail. Always quote the findings block verbatim.

---

## Plan-mode precedence

When the built-in plan mode is active (system message says "Plan mode is active"), follow Claude Code's native flow:

1. Use built-in **Explore** subagents for research (not our custom researcher — Explore is specialized for plan-mode).
2. Use built-in **Plan** subagents for architecture (not our custom planner).
3. `AskUserQuestion` / `ExitPlanMode` are the only allowed state transitions.
4. Our custom agents kick in AFTER the user approves the plan (via `ExitPlanMode`).

Don't mix — plan-mode Explore/Plan are scoped to the plan file; our researcher/planner are for post-approval execution.

---

## Trivial-task recipes (inline, no delegation)

| Task | Flow |
|------|------|
| Typo in a visible string | Read → Edit → done. |
| Renaming one identifier the user named | Grep scope → Edit → done. |
| Adding one `console.log` for debugging | Edit → done. |
| Answering a factual question that researcher already covered this session | Quote prior finding → done. |
| Confirming something via `git log` / `git status` | Bash → done. |

Anything that mentions "feature", "add X", "refactor", "migration", "new component", or spans multiple files → NOT trivial. Delegate.

---

## Project facts (inherited by all agents with `memory: project`)

### Commands

```bash
npm run dev      # localhost:5173
npm run build
npm run preview  # localhost:4173

# Edge Functions (Supabase) — deploy from supabase/functions/<name>/index.ts
supabase functions deploy invite-player   # captain-only player invite (called from AdminRollen.svelte)
```

No tests, linter, or formatter.

### Environment (`.env.local`)

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_VAPID_PUBLIC_KEY=...
```

`VAPID_PRIVATE_KEY` is server-side only — no `VITE_` prefix. Server-only too: `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`, `GOOGLE_CALENDAR_ID` (GCal sync).

### Stack

Svelte 5 runes + SvelteKit 2, Supabase (Postgres + Google Auth), Vercel (Node 22). JavaScript only — no TypeScript. All DB access via `sb` from `$lib/supabase.js` directly in the browser — no `+page.server.js` files.

### Routes

```
/login                      Google OAuth
/(app)/                     Auth-guarded shell
  +page.svelte              Dashboard       tabs: neuigkeiten · events
  kalender/                                 view-modes (local state): agenda · woche · monat
  spielbetrieb/                             tabs: uebersicht · aufstellungen · statistiken · admin(kapitaen)
                                            uebersicht hosts inline pill (?pill=spiele|turnier|landesbewerb) at the bottom
  profil/                                   tabs: uebersicht · einstellungen · admin(kapitaen)
/api/push/notify            Web Push send endpoint
/api/cron/gcal-sync         Google Calendar pull (Bearer CRON_SECRET, */15 cron)
/api/gcal/events            Google Calendar push: POST/PATCH/DELETE (captain-gated)
```

`playerRole` is `'kapitaen'` or `'user'`. All admin features gated on `kapitaen`.

### Subtab / view-mode routing pattern

Every `+page.svelte` is a thin router — separate `{#if}` blocks (not `{:else if}`):

```svelte
<script>
  import { currentSubtab } from '$lib/stores/subtab.js';
  import FooTab from '$lib/components/area/FooTab.svelte';
</script>

{#if $currentSubtab === 'foo'}<FooTab />{/if}
```

`/kalender` uses local `$state` for its view-mode switcher (agenda/woche/monat) instead of subtabs — PAGE_CONFIG entry has `tabs: []`.

`uebersicht` tabs render outside any `.kal-page`/`.sp-page` wrapper so they control their own layout.

### Key DB facts

- **`game_plans` ↔ `matches`** — joined via `cal_week` + `league_id`, NOT a `match_id` FK.
- **`players.email`** — the RLS auth bridge. Policies match `auth.jwt() ->> 'email'` against `players.email`. No `auth_user_id` column.
- **`matches.is_tournament` / `is_landesbewerb`** — boolean flags; no separate table per type.
- **Player photos** — `static/images/<photo-or-name>.jpg`, built by `imgPath()`.
- **`training_templates.lane_count` = Anzahl Bahnen** pro Slot. `training_specials` = einmalige Sessions. `training_waitlist` = Warteliste. Buchen/Storno via RPCs `book_training_lane(p_date, p_start, p_lane)`, `cancel_training_booking` (Migration `20260421_training_lanes.sql` ersetzt den älteren `book_training_slot`).
- **`events.source` ∈ `'manual' | 'gcal'`** + `external_id` (Google event id, unique), `etag`, `synced_at`. Google-synced rows round-trip through `/api/gcal/events`; manuelle Legacy-Rows bleiben unberührt. Pull-Cron skipped Google-Events, deren Datum in `matches.date` liegt (Duplikat-Guard Übergangssaison).

### RLS write patterns

```sql
-- Own row
player_id IN (SELECT id FROM players WHERE email = (auth.jwt() ->> 'email'))

-- Captain/admin
EXISTS (SELECT 1 FROM players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin'))
```

### CSS & design system (`src/app.css`)

Never hardcode colours, spacing, or radii — always use tokens:

```
--color-primary #CC0000  --color-secondary #D4AF37
--color-success / --color-on-success / --color-success-container  (added 2026-04-23 für Task-Done-States)
--color-surface-container-lowest / --color-surface-container
--color-on-surface / --color-on-surface-variant
--color-outline / --color-outline-variant
--font-display 'Lexend'  --font-body 'Public Sans'
--text-label-sm/md  --text-body-md  --text-title-sm/md  --text-headline-sm/md
--space-1…--space-16  (0.25 rem steps)
--radius-sm/md/lg/xl/full   --shadow-card  --shadow-float
```

Shadows must use red-tinted values — never `rgba(0,0,0,x)`.

Global utility classes: `.shimmer-box` (skeleton), `.animate-fade-float` (entry), `.page.active`.

Match-workflow cards share `.mw-card`, `.mw-btn` (`--primary/ghost/soft/wide`), `.mw-field` — defined in `app.css`, used across all spielbetrieb components.

### Coding conventions

**Supabase errors** — always `triggerToast`, never local `msg` state:
```js
const { data, error } = await sb.from('...').select(...);
if (error) { triggerToast('Fehler: ' + error.message); return; }
```

**Loading state** — one `let loading = $state(true)` per domain, reset in `finally`.

**Never redefine locally — always import:**
```js
import { DAY_SHORT, MONTH_SHORT, MONTH_FULL, fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
// fmtDate('2026-04-19') → 'So, 19. Apr' | fmtTime('09:30:00') → '09:30 Uhr'
// DAY_SHORT is Sunday-first; calendar Mon-first grids keep a local array

import { imgPath, shortName, BLANK_IMG } from '$lib/utils/players.js';
import { BEWERB_TYPEN, BEWERB_LABEL }   from '$lib/constants/competitions.js';
import { triggerToast }                  from '$lib/stores/toast.js';
```

**Callback props**: `onReload` (parent refreshes list), `onClose` (close sheet/modal).

**Svelte 5**: use `$state`/`$derived`/`$effect` in components. Stores in `src/lib/stores/` use legacy API for cross-component sharing.

### Where things live

| What | Where |
|------|-------|
| Date/time formatting | `$lib/utils/dates.js` |
| Player avatar + short name | `$lib/utils/players.js` |
| Competition type labels | `$lib/constants/competitions.js` |
| Auth stores (`playerId`, `playerRole`) | `$lib/stores/auth.js` |
| Tab config (`PAGE_CONFIG`, `setSubtab`) | `$lib/stores/subtab.js` |
| Toast | `$lib/stores/toast.js` |
| League timing (arrival, duration) | `$lib/utils/league.js` |
| Eligibility / roster rules | `$lib/utils/eligibility.js` |
| Round codes H01–FNN | `$lib/utils/roundCode.js` |
| Post-match question rotation | `$lib/utils/feedbackRotation.js` |
| Push helpers | `$lib/push/register.js` |
| Server-only Supabase admin client | `$lib/server/supabase-admin.js` → `sbAdmin()` |
| Google Calendar helper (JWT, CRUD, mappers) | `$lib/server/gcal.js` |
| UI primitives | `$lib/components/ui/` |
| Sheet primitive | `$lib/components/BottomSheet.svelte` |
| All global CSS + design tokens | `src/app.css` |
| DB migrations | `supabase/migrations/` |
| Kalender view components | `$lib/components/kalender/` (UebersichtTab, WocheTab, MonatTab + *DetailSheet) |
| Agent definitions | `.claude/agents/<name>.md` |
| Hook scripts | `.claude/hooks/<name>.js` |
| Design specs | `docs/design/<feature>.md` |
