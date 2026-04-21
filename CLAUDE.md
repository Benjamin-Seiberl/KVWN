# CLAUDE.md

KVWN — German-language PWA for KV Wiener Neustadt (Kegeln club). Team coordination: lineups, training bookings, carpools, events, push notifications. All UI strings in Austrian German ("Jänner" not "Januar").

## Commands

```bash
npm run dev      # localhost:5173
npm run build
npm run preview  # localhost:4173
```

No tests, linter, or formatter.

## Environment (`.env.local`)

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_VAPID_PUBLIC_KEY=...
```

`VAPID_PRIVATE_KEY` is server-side only — no `VITE_` prefix.

## Stack

Svelte 5 runes + SvelteKit 2, Supabase (Postgres + Google Auth), Vercel (Node 22). All DB access via `sb` from `$lib/supabase.js` directly in the browser — no `+page.server.js` files.

## Routes & Subtabs

```
/login                      Google OAuth
/(app)/                     Auth-guarded shell
  +page.svelte              Dashboard       tabs: neuigkeiten · events
  kalender/                                 tabs: uebersicht · events · trainings
  spielbetrieb/                             tabs: uebersicht · aufstellungen · spiele · turnier · landesbewerb · statistiken
  profil/                                   tabs: uebersicht · meine-daten · einstellungen · admin(kapitaen)
/api/push/notify            Web Push send endpoint
```

`playerRole` is `'kapitaen'` or `'user'`. All admin features gated on `kapitaen`.

## Subtab Routing Pattern

Every `+page.svelte` is a thin router — separate `{#if}` blocks (not `{:else if}`):

```svelte
<script>
  import { currentSubtab } from '$lib/stores/subtab.js';
  import FooTab from '$lib/components/area/FooTab.svelte';
</script>

{#if $currentSubtab === 'foo'}<FooTab />{/if}
```

`uebersicht` tabs render outside any `.kal-page`/`.sp-page` wrapper so they control their own layout.

## Key DB Facts

- **`game_plans` ↔ `matches`** — joined via `cal_week` + `league_id`, NOT a `match_id` FK.
- **`players.email`** — the RLS auth bridge. Policies match `auth.jwt() ->> 'email'` against `players.email`. No `auth_user_id` column.
- **`matches.is_tournament` / `is_landesbewerb`** — boolean flags; no separate table per type.
- **Player photos** — `static/images/<photo-or-name>.jpg`, built by `imgPath()`.
- **`training_templates.lane_count` = Kapazität** pro Slot. Kein Rename (legacy). Bookings ohne `lane_number` (kapazitätsbasiert). `training_specials` = einmalige Sessions. `training_waitlist` = Warteliste. Buchen/Storno via RPCs `book_training_slot`, `cancel_training_booking`.

## RLS Write Patterns

```sql
-- Own row
player_id IN (SELECT id FROM players WHERE email = (auth.jwt() ->> 'email'))

-- Captain/admin
EXISTS (SELECT 1 FROM players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin'))
```

## CSS & Design System (`src/app.css`)

Never hardcode colours, spacing, or radii — always use tokens:

```
--color-primary #CC0000  --color-secondary #D4AF37
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

## Coding Conventions

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

## Where Things Live

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
| UI primitives | `$lib/components/ui/` |
| All global CSS + design tokens | `src/app.css` |
| DB migrations | `supabase/migrations/` |
