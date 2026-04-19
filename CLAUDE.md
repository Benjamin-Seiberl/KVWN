# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KVWN is a German-language PWA for KV Wiener Neustadt, a Kegeln (ninepins) club. It handles team coordination: match lineups, training bookings, carpools, post-match feedback, and club events. All UI strings are hardcoded German (Austrian dialect — use "Jänner" not "Januar").

## Commands

```bash
npm install       # Install dependencies
npm run dev       # Dev server at http://localhost:5173
npm run build     # Production build
npm run preview   # Preview production build at http://localhost:4173
```

There is no test framework, linter, or formatter configured.

## Environment

Create `.env.local` with:
```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=...
VITE_VAPID_PUBLIC_KEY=...   # Optional: push notifications
```

## Architecture

**Stack**: Svelte 5 (runes mode) + SvelteKit 2, Vite 8, Supabase (PostgreSQL + Auth), deployed on Vercel.

### Route Structure

- `/login` — Google OAuth entry point
- `/(app)/` — Protected shell; redirects to `/login` if `isMember` is false
  - `+page.svelte` — Dashboard (Neuigkeiten / Events subtabs)
  - `kalender/` — Calendar & training lane booking
  - `spielbetrieb/` — Match management (Spiele / Turnier / Landesbewerb / Statistiken subtabs)
  - `statistiken/` — Player stats
  - `profil/` — Profile, settings, and admin panel (kapitaen-only)

### State Management (Svelte Stores)

| Store | Purpose |
|-------|---------|
| `src/lib/stores/auth.js` | `user`, `isMember`, `playerId`, `playerRole` — drives auth guard |
| `src/lib/stores/subtab.js` | Tracks active subtab per route; `PAGE_CONFIG` defines all tabs |
| `src/lib/stores/scroll.js` | `scrollY` / `scrollDirection` — hides/shows BottomNav |
| `src/lib/stores/spotlight.js` | Global search overlay open/close |
| `src/lib/stores/toast.js` | Toast notification trigger |

### Data Flow

All database access goes through the Supabase client at `src/lib/supabase.js`. Pages call `sb.from('table').select/insert/update` directly and bind results to `$state` variables. There is no server-side data loading layer (no `+page.server.js` files); everything runs in the browser.

### App Shell (`src/routes/(app)/+layout.svelte`)

This file owns:
- Auth guard (redirect to `/login`)
- Pull-to-refresh physics (rubber-band resistance: `distance ^ 0.75`, spotlight opens at 58px)
- Global drag/touch listeners
- `SpotlightSearch` and `BottomNav` mounting

### Svelte 5 Runes

Use `$state`, `$derived`, and `$effect` — not `writable`/`derived` from `svelte/store` inside components. The stores in `src/lib/stores/` use the legacy store API for cross-component sharing; inside `.svelte` files prefer runes.

### Key Business Logic

- **`src/lib/utils/eligibility.js`** — Tier-based roster rules: positions 1–4 are locked to assigned league tier; positions 5+ can play one tier lower; a player can only appear in one team per round.
- **`src/lib/utils/roundCode.js`** — Generates H01–HNN (Sep–Dec) / F01–FNN (Jan–May) codes from ISO week numbers used for eligibility checks.
- **`src/lib/utils/feedbackRotation.js`** — FNV-1a hash picks one of 20 post-match questions deterministically per (player, match) pair.
- **`src/lib/utils/league.js`** — Encodes arrival/duration windows: Bundesliga/Landesliga = 60 min arrival + 180 min; A/B-Liga = 40 min + 120 min.

### Database

All tables use Supabase Row-Level Security. The migration at `supabase/migrations/20260414_match_workflow.sql` defines the match-workflow tables: `match_meetups`, `match_carpools`, `match_carpool_seats`, `match_supporters`, `match_venues`, `match_venue_votes`, `feedback_questions`, and `match_feedback`.

Core tables (players, matches, game_plans, leagues, events, training_templates, training_bookings, team_rosters) are managed outside this migration.

### Roles

`playerRole` is either `'kapitaen'` or `'user'`. Captain-only features (AdminRollen, AdminAufstellung, AdminErgebnis, AdminTraining) are gated on this value inside `AdminTab.svelte` and related admin components under `src/lib/components/admin/`.

---

## Coding Conventions

These patterns must be followed consistently so agents can navigate the codebase without ambiguity.

### Error Handling (Supabase)

Always destructure errors and call `triggerToast` — never set a `msg` state string:

```js
const { data, error } = await sb.from('...').select(...);
if (error) { triggerToast('Fehler: ' + error.message); return; }
```

### Loading State

One `let loading = $state(true)` per data domain, always reset to `false` in a `finally` block or after the load.

### Date / Time Display

**Never** define local month or day arrays. Always import from `$lib/utils/dates.js`:

```js
import { DAY_SHORT, MONTH_SHORT, MONTH_FULL, fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
```

- `fmtDate('2026-04-19')` → `'So, 19. Apr'`
- `fmtTime('09:30:00')` → `'09:30 Uhr'`
- `toDateStr(new Date())` → `'2026-04-19'`
- `daysUntil('2026-04-19')` → number (negative = past)
- `DAY_SHORT` is Sunday-first `['So','Mo',…]`; calendar grids that need Monday-first keep their own local array

### Player Utilities

**Never** reimplement `imgPath` or `shortName` inline. Import from `$lib/utils/players.js`:

```js
import { imgPath, shortName } from '$lib/utils/players.js';
```

### Competition Types

**Never** define `BEWERB_TYPEN` or `BEWERB_LABEL` locally. Import from `$lib/constants/competitions.js`:

```js
import { BEWERB_TYPEN, BEWERB_LABEL } from '$lib/constants/competitions.js';
```

### Callback Props

- `onReload` — callback to reload the parent's list after a child write
- `onClose` — callback to close a sheet/modal

### Toast Notifications

```js
import { triggerToast } from '$lib/stores/toast.js';
triggerToast('Gespeichert');          // success
triggerToast('Fehler: ' + err.message); // error
```

---

## Where Things Live

Quick lookup — "where do I find / put X?":

| What | Where |
|------|-------|
| German date/time formatting | `$lib/utils/dates.js` |
| Player avatar URL + short name | `$lib/utils/players.js` |
| Competition type labels | `$lib/constants/competitions.js` |
| Toast notifications | `triggerToast()` in `$lib/stores/toast.js` |
| Auth + role checks | `$lib/stores/auth.js` |
| Tab routing config | `PAGE_CONFIG` in `$lib/stores/subtab.js` |
| Eligibility / roster rules | `$lib/utils/eligibility.js` |
| Arrival/duration windows | `$lib/utils/league.js` |
| Round code (H01–FNN) | `$lib/utils/roundCode.js` |
| Post-match question rotation | `$lib/utils/feedbackRotation.js` |

---

## Component Index

### Routes (page routers — thin, delegate to tab components)

| File | Purpose |
|------|---------|
| `routes/(app)/+page.svelte` | Dashboard router: Neuigkeiten / Events tabs |
| `routes/(app)/kalender/+page.svelte` | Calendar & training lane booking (single page) |
| `routes/(app)/spielbetrieb/+page.svelte` | Spielbetrieb router: Spiele / Turnier / Landesbewerb / Statistiken |
| `routes/(app)/profil/+page.svelte` | Profil router: Meine Daten / Einstellungen / Admin + `:global` CSS |

### Spielbetrieb Tab Components

| File | Purpose |
|------|---------|
| `components/spielbetrieb/SpielbetriebeTab.svelte` | Match list + detail view with lineup and scores |
| `components/spielbetrieb/TurniereTab.svelte` | Tournament list, voting status, create form |
| `components/spielbetrieb/LandesbewerbeTab.svelte` | Landesbewerb list, registration status, create form |
| `components/spielbetrieb/TournamentMatchCard.svelte` | Full tournament detail card (voting, schedule, players) |
| `components/spielbetrieb/LandesbewerbCard.svelte` | Full Landesbewerb detail card (registration, player list) |

### Profil Tab Components

| File | Purpose |
|------|---------|
| `components/profil/MeineDatenTab.svelte` | Player stats, next match, profile edit, events RSVP, milestones |
| `components/profil/EinstellungenTab.svelte` | Push notification toggle + prefs, sign-out |
| `components/profil/AdminTab.svelte` | Kapitäns-Panel: admin action grid + bottom sheets |

### Dashboard Components

| File | Purpose |
|------|---------|
| `components/dashboard/NewsFeed.svelte` | Club news + polls feed |
| `components/dashboard/MyNextMatchCard.svelte` | Next match card for logged-in player |
| `components/dashboard/QuickActions.svelte` | Quick navigation shortcuts |
| `components/dashboard/UpcomingEvents.svelte` | Upcoming events list |
| `components/dashboard/OpenRegistrationsCard.svelte` | Tournaments/Landesbewerbe with open registration |

### Shared Components

| File | Purpose |
|------|---------|
| `components/MatchCarousel.svelte` | Horizontal scrollable match cards for current week |
| `components/ActionHub.svelte` | Action items: lineup confirm, polls, events, tournaments |
| `components/BottomNav.svelte` | Tab bar + subtab strip; reads `PAGE_CONFIG` from subtab store |
| `components/BottomSheet.svelte` | Slide-up modal sheet with handle and backdrop |
| `components/SpotlightSearch.svelte` | Pull-to-open global search overlay |
| `components/PagePill.svelte` | Toast pill — slides from top for 3 s |

### Admin Components (`components/admin/`)

| File | Purpose |
|------|---------|
| `AdminRollen.svelte` | Assign player roles |
| `AdminAufstellung.svelte` | Create/edit match lineups |
| `AdminErgebnis.svelte` | Enter match results |
| `AdminTraining.svelte` | Manage training sessions |

### Statistiken Components

| File | Purpose |
|------|---------|
| `components/statistiken/StatsView.svelte` | Full stats view: leaderboard, trend charts, filters |
