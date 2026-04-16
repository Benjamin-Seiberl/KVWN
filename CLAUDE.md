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

`playerRole` is either `'kapitaen'` or `'user'`. Captain-only features (AdminRollen, AdminAufstellung, AdminErgebnis, AdminTraining) are gated on this value inside `profil/+page.svelte` and related admin components under `src/lib/components/admin/`.
