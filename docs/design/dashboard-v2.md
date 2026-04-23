# Dashboard v2 — "Cockpit" Design Spec

> Scope: `/(app)/+page.svelte` and components under `src/lib/components/dashboard/`.
> Out of scope: Bottom-Nav, Spielbetrieb, Kalender, Profil chrome.

## 1. Rationale

The current Dashboard is built around an **Action Hub** widget, **Quick Actions** tile row and two tabs (`neuigkeiten` / `events`). That model hides the two most load-bearing pieces of information — *"was muss ich tun?"* and *"wann spiele ich?"* — behind chrome (tabs, accordion headers, placeholder rows labeled "bald"). Captains open the app at 18:30 before training to check status; they should not be paying tab-switch cost to get it.

Cockpit v2 inverts the priority: **every section is visible in one scroll**, each card is smaller and denser, task cards are self-closing (no accordion), and the greeting becomes a *persistent status line* instead of a disappearing welcome banner. Information density is the feature. We trade decorative whitespace for glanceability.

---

## 2. Section-by-section spec

Global page frame:
- Page container `padding-bottom: calc(var(--nav-height, 72px) + var(--space-5))` (existing).
- Sections separated by `--space-5` (20 px) vertical rhythm, **not** `--space-6` — cockpit is denser than the old dashboard.
- Section heading row (`.sec-head`) reuses existing styling: filled 1.1 rem icon in `--color-primary`, title in `--font-display` 700 at `--text-title-md`, `padding: 0 var(--space-5)`, `margin-bottom: var(--space-3)`.
- Section wrapper keeps the `.dash-section` class and the `--i` stagger variable (see §6).

Section order (fixed):

### 2.1 Greeting (permanent)

**Intent:** Always-visible status line. Tells the user who the app thinks they are + what's on today, in one glance.

```
┌──────────────────────────────────────────────┐
│ DONNERSTAG, 23. APRIL                        │  ← muted eyebrow
│ Hallo Ben 👋                                 │  ← display title
│ 2 offen · Spiel in 3T                        │  ← adaptive status line
└──────────────────────────────────────────────┘
```

- Padding: `var(--space-4) var(--space-5) var(--space-3)`.
- Eyebrow (`.dash-date`): `--text-label-sm`, weight 700, `letter-spacing: 0.09em`, uppercase, color `var(--color-on-surface-variant)`.
- Name line (`.dash-greeting`): `font-family: var(--font-display)`, `font-size: clamp(1.35rem, 5vw, 1.6rem)` (unchanged), weight 700, color `var(--color-on-surface)`.
- Wave emoji: existing `.dash-wave` animation — plays once, then sits inert. **Do not auto-collapse the whole header anymore** (drop `greetingVisible` logic).
- Status line: `--text-body-md`, color `var(--color-on-surface-variant)`, segments joined by `·` padded with a non-breaking space on each side. See §4 for formula.
- Empty/fallback: if `firstName` hasn't loaded, show `Hallo 👋` (no dangling space). If status line has zero segments, omit the line entirely (keep the spacing collapsed so it doesn't leave a gap).

Rule notes:
1. Greeting never disappears — no `max-height: 0` transition.
2. Hour-of-day phrase (`Guten Morgen/Tag/Abend`) is dropped; first-name is warmer and shorter.
3. The status line replaces the old Action-Hub badge count.

### 2.2 Kapitän-Aufgaben (conditional)

**Intent:** Captain-only operational queue. Shown only if `playerRole === 'kapitaen'` AND at least one signal exists.

```
┌─ Kapitän-Aufgaben ─────────────────────────────┐
│ ┌────────────────────────────────────────────┐ │
│ │▌ 3 Spieler noch unbestätigt                │ │  ← task card (accent bar)
│ │  Landesliga · So 27.04.                    │ │
│ │                             [Anzeigen →]    │ │
│ └────────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────────┐ │
│ │▌ Aufstellung fehlt für KW 19                │ │
│ │                             [Erstellen →]   │ │
│ └────────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

- Uses the **shared task-card anatomy** (§3). Cards stack with `gap: var(--space-2)`.
- Three signal types rendered in this fixed order:
  1. *Unbestätigte Spieler* in current published lineup (>0 unconfirmed).
  2. *Aufstellung fehlt* for next `cal_week` that has a match but no `lineup_published_at`.
  3. *Neue kollidierende Abwesenheit* (player absent for a match they're on the lineup for).
- Primary action: single text button, right-aligned in the card, navigates into the relevant Spielbetrieb admin deep link.
- Section is *omitted entirely* (no heading, no empty state) when there are no signals.

Rule notes:
1. Captain-only — gate on `$playerRole === 'kapitaen'`.
2. No "success" state here — when the captain resolves the signal, the card simply disappears on next load.
3. Cards are **read + route**, never inline-actionable (captains resolve in Spielbetrieb, not here).

### 2.3 Offene Aufgaben (conditional)

**Intent:** Player's personal to-do queue. Shown only if `tasks.length >= 1`.

```
┌─ Offene Aufgaben ──────────────────────────────┐
│ ┌────────────────────────────────────────────┐ │
│ │▌ Aufstellung bestätigen                    │ │
│ │  Landesliga · So 27.04. · 15:00            │ │
│ │  vs. SK Baden · Pos. 3                     │ │
│ │                 [Absage]  [Zusage]          │ │
│ └────────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────────┐ │
│ │▌ Landesbewerb Einzel                   [×] │ │
│ │  Anmeldung bis Fr 25.04., 18:00            │ │
│ │                  [Nein]   [Ja]              │ │
│ └────────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

- Task card layout per §3.
- Card type order is fixed: **Lineup → Landesbewerb → (Captain cards above, not here) → Soft-Suggestions**.
- Lineup confirm card: two equal-weight inline buttons. `[Zusage]` = `.mw-btn.mw-btn--primary`, `[Absage]` = `.mw-btn.mw-btn--ghost`. On tap, the card swaps to success state (§3) then collapses.
- Landesbewerb card: `[Ja]` primary, `[Nein]` ghost, plus a small top-right `[×]` dismiss (icon-only, §3). Dismiss writes to DB and removes the card with the same collapse animation as success.
- Soft-suggestions (e.g. *Fahrgemeinschaft fehlt*, *Kein Mitspieler für Event X*): same card chrome but **no inline action** — tap card body to route.

Rule notes:
1. Section disappears completely when empty. No "Keine Aufgaben" placeholder — cockpit trusts absence.
2. Max visible = 5. If more, truncate with a muted trailing row: `+N weitere Aufgaben` (ghost button, full-width).
3. Never group task types visually — keep them as one flat list so priority order is obvious.

### 2.4 Mein nächstes Spiel (conditional)

**Intent:** Personal "you are playing" hero card. Only shown if the player is on a future lineup.

```
┌─ Mein nächstes Spiel ──────────────────────────┐
│ ┌────────────────────────────────────────────┐ │
│ │▌ ┌───┐ DEIN NÄCHSTER EINSATZ               │ │
│ │  │ 3 │ vs. SK Baden                         │ │
│ │  │Tage│ So, 27.4. · 15:00 Uhr · Pos. 3     │ │
│ │  └───┘ Landesliga                      ›    │ │
│ └────────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

- Reuse `MyNextMatchCard.svelte` visual verbatim — it's already on-spec (`.nmc` with `border-left: 4px solid var(--color-primary)`, gradient icon-wrap, ellipsising opponent, chevron hint).
- Section heading + card both hidden when no future lineup exists. No skeleton shown after initial load.
- Skeleton during initial load: existing `.nmc--skeleton` shimmer.

Rule notes:
1. This is a *distinct* card from the Task block — it's a "status", not a "todo".
2. Heading wording is `Mein nächstes Spiel` (not `Dein nächstes Spiel`) — consistent with how other section titles read in first-person.
3. Only the *earliest* future match where the player is on the lineup. Never show a list.

### 2.5 Nächstes Training (always)

**Intent:** Next training session or next booking the player is signed up for. Always rendered — Kegeln läuft ganzjährig.

```
┌─ Nächstes Training ────────────────────────────┐
│ ┌────────────────────────────────────────────┐ │
│ │▌ Di, 29.4. · 18:00                         │ │
│ │  Du bist gebucht · 4/6 Plätze belegt       │ │
│ │                              [Übersicht →]  │ │
│ └────────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

- Single-card layout, **same chrome as task card** (left accent bar, compact padding). Reuses the shared base (§3), *not* a match-hero (`.nmc`) style.
- Two display modes:
  - **Gebucht**: accent bar `var(--color-primary)`, sub-line `Du bist gebucht · N/M Plätze`.
  - **Nicht gebucht**: accent bar at 40% primary (`color-mix(in srgb, var(--color-primary) 40%, transparent)`), sub-line `Plätze frei · N/M` or `Warteliste · N`.
- Empty state (no template/special in next 14 days): show card with muted accent bar and text `Nächste Woche keine Einheit geplant`, button `[Kalender öffnen →]`.
- Skeleton: 2 shimmer bars, same dimensions as title + sub.

Rule notes:
1. Prefer *Trainings-Special* over next regular template if both fall on the same day.
2. Button text is the CTA (e.g. `Buchen`, `Absagen`, `Übersicht`) — not generic `Öffnen`.
3. Full-bleed section like the others; does not become 2-col on tablet (single card reads better wide).

### 2.6 Spiele der Woche (always)

**Intent:** Horizontal carousel of this week's matches across all teams.

- Keep existing `MatchCarousel` verbatim. No visual changes.
- Section heading: icon `sports_score`, title `Spiele der Woche`.
- No skeleton override — the component owns its loading state.

Rule notes:
1. Cockpit density push means **no margin above** section heading beyond the global `--space-5` rhythm.
2. Heading stays outside the carousel's horizontal scroll (the title must not scroll with cards).

### 2.7 Events (vertical list, 3 max)

**Intent:** Next upcoming club events (Ausflüge, Feiern). Vertical list replaces the old `events` tab entirely.

```
┌─ Events ───────────────────────────────────────┐
│ ┌────────────────────────────────────────────┐ │
│ │  Clubmeisterschaft                          │ │
│ │  Sa, 10. Mai · Kegelhalle WN                │ │
│ │                          [Anmelden →]        │ │
│ └────────────────────────────────────────────┘ │
│ ┌── dito ────────────────────────────────────┐ │
│ └────────────────────────────────────────────┘ │
│ ┌── dito ────────────────────────────────────┐ │
│ └────────────────────────────────────────────┘ │
│                            [Alle Events →]      │  ← muted ghost
└────────────────────────────────────────────────┘
```

- Compact list card (same base chrome as task card **without** left accent bar — events are informational, not actionable-until-tapped).
- Title `--text-title-sm` weight 700, meta line `--text-body-sm` color `--color-on-surface-variant`.
- Right-side CTA: `[Anmelden]` if registrable and user hasn't registered, `[Angemeldet ✓]` pill (neutral soft style) if they have, nothing if the event is info-only.
- `[Alle Events →]` full-width ghost button routes to a future `/events` index (or `/kalender?filter=event` until that exists — frontend-dev decides).
- Empty state: entire section (heading + list) hidden when 0 events in next 30 days.

Rule notes:
1. Max 3 items; 4th and beyond reachable via the ghost trailing button.
2. Never show past events here (UpcomingEvents already filters).
3. No accent bar — this section should read as *browsing*, not *doing*.

### 2.8 Neuigkeiten (mixed feed)

**Intent:** News posts and polls interleaved, chronologically, with pinned items first.

```
┌─ Neuigkeiten ──────────────────────────────────┐
│ ┌── 📌 Pinned NewsCard ──────────────────────┐ │
│ ├── PollCard ───────────────────────────────┤ │
│ ├── NewsCard ───────────────────────────────┤ │
│ ├── PollCard ───────────────────────────────┤ │
│ └── NewsCard ───────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

- Reuse existing `NewsFeed.svelte` container and `NewsCard.svelte` / `PollCard.svelte` children.
- Feed ordering: `pinned DESC, created_at DESC` (pinned bubble to top, then chrono).
- Gap between cards: `var(--space-3)`.
- Empty state: heading + single muted line `Noch keine Beiträge`.

Rule notes:
1. Feed is infinite-scroll-eligible but **lazy** — render first 10, "Mehr laden" button at bottom if more exist.
2. Pinned badge visual already lives on NewsCard — do not re-implement.
3. Polls and news share the same card chrome, only the action row differs.

---

## 3. Task-card anatomy (reusable base)

One card visual is shared by: **Kapitän-Aufgaben**, **Offene Aufgaben (Lineup, Landesbewerb, Soft)**, **Nächstes Training**. The shared look is what makes the cockpit feel cohesive.

### Structure

```
┌─────────────────────────────────────────────┐
│▌  [icon?] Titel                        [×]? │  ← title row (accent bar on left)
│▌  Meta / subtitle                           │
│▌  Optional tertiary line                    │
│▌                        [Sec]  [Primary]    │  ← action row (right-aligned)
└─────────────────────────────────────────────┘
```

### Tokens

- **Background:** `var(--color-surface-container-lowest)`.
- **Border radius:** `var(--radius-lg)` (12 px).
- **Padding:** `var(--space-3) var(--space-4)`. Tighter than the old hero cards — density-first.
- **Left accent bar:** `border-left: 4px solid var(--color-primary)`. Variants:
  - Urgent (<24 h deadline): keep `--color-primary`, add `box-shadow: 0 0 0 1.5px color-mix(in srgb, var(--color-primary) 35%, transparent)` as a hairline ring.
  - Soft suggestion: `border-left-color: color-mix(in srgb, var(--color-primary) 40%, transparent)`.
  - Captain card: `--color-primary` (standard — captain tasks are already high-priority by virtue of living in the captain block).
- **Shadow:** `var(--shadow-card)`.
- **Title:** `--text-title-sm` (0.875 rem), weight 700, `--font-display`, color `--color-on-surface`.
- **Meta:** `--text-body-sm` (0.8125 rem if added to tokens, else `--text-body-md` scaled 0.9), color `--color-on-surface-variant`.
- **Gap between stacked cards:** `var(--space-2)`.

### Inline buttons (action row)

Reuse the existing `.mw-btn` system:
- Primary: `.mw-btn.mw-btn--primary` → filled `--color-primary`, white text.
- Secondary (Absage, Nein): `.mw-btn.mw-btn--ghost` → transparent, 1.5 px outline `--color-outline`, text `--color-on-surface`.
- Min target: 44×44 px per button (the existing `.mw-btn` already satisfies this).
- Button row `gap: var(--space-2)`, right-aligned (`justify-content: flex-end`), `margin-top: var(--space-2)`.

### Dismiss button (top-right, optional)

- Position: `top: var(--space-2); right: var(--space-2)`, absolute-positioned.
- Visual: icon-only (`close`), 28×28 px tap area (hit-box extended via padding), icon color `var(--color-on-surface-variant)`, no background.
- Hover/focus: background `color-mix(in srgb, var(--color-on-surface) 6%, transparent)`.
- aria-label: `Aufgabe verbergen`.

### Success state (Lineup + Landesbewerb confirm)

Trigger: user taps `[Zusage]` / `[Ja]`. The card morphs in-place:

```
┌─────────────────────────────────────────────┐
│▌  ✓  Bestätigt                              │
│▌  Deine Zusage ist gespeichert              │
└─────────────────────────────────────────────┘
```

Timing & tokens:
1. **T=0 ms**: background transitions to `color-mix(in srgb, var(--color-primary) 12%, var(--color-surface-container-lowest))`, action row fades out (`opacity 0` over 150 ms), check icon + "Bestätigt" label fade in (`opacity 0 → 1` over 150 ms).
2. **T=0 → 2000 ms**: card sits in success state.
3. **T=2000 ms**: card begins collapse: `opacity 1 → 0` over 300 ms ease, `max-height: 200px → 0` over 300 ms ease, `margin-block` collapses to 0 in the same 300 ms, `padding-block` to 0.
4. **T=2300 ms**: DOM removal.

Easing: `cubic-bezier(0.4, 0, 0.2, 1)` (Material standard ease-in-out) for background; `cubic-bezier(0.22, 1, 0.36, 1)` for the collapse (matches existing `.dash-section` feel).

### Decline state (Absage)

- Same 2 s + collapse choreography, but the body text reads `Absage verschickt` and the background uses a neutral soft wash: `color-mix(in srgb, var(--color-on-surface) 5%, var(--color-surface-container-lowest))`. **No red** — absence is not an error.
- Icon: `check` (the action succeeded), not `close`.

---

## 4. Status-line formula (greeting §2.1)

Segments are computed independently, then joined with ` · `.

```
openTasks  = count(lineupPending) + count(landesbewerbOpen) + count(softSuggestions)
nextMatch  = earliest future match the player is on the lineup for
```

Rules (in order):

| openTasks | nextMatch | Output |
|-----------|-----------|--------|
| 0         | none      | _(line omitted)_ |
| 0         | today     | `Spiel heute` |
| 0         | >0 days   | `Spiel in Xd` (where X = `daysUntil(match.date)`) |
| ≥1        | none      | `N offen` |
| ≥1        | today     | `N offen · Spiel heute` |
| ≥1        | >0 days   | `N offen · Spiel in Xd` |

Extras (append only if applicable, max one extra to keep line short):
- Captain with `captainSignals > 0`: prepend `⚑ N` at the very start, e.g. `⚑ 2 · 1 offen · Spiel in 3T`. The flag glyph uses `color: var(--color-primary)` via a span.
- Training tonight (`daysUntil(trainingDate) === 0` AND `time > now`): append `Training heute`.

German:
- `in Xd` — short form, no space (`3d`, not `3 Tagen`). If the user prefers the spelled form: use `in X Tagen` when `X >= 2`, `morgen` when `X === 1`, `heute` when `X === 0`. **Frontend-dev decides between `Xd` and `X Tagen` based on final width — open question §8.**

---

## 5. Responsive breakpoints

Single-column mobile-first is the default. Two breakpoints:

### Mobile (≤420 px, and default)

- All sections single-column, full-bleed within the page's `--space-5` horizontal padding.
- Task cards: stack vertically.
- MatchCarousel: horizontal scroll, one card visible at a time.

### Tablet (≥768 px)

- Page max-width `600px`, centered (horizontal auto-margins).
- **Task block (§2.2, §2.3)**: 2-column grid, `grid-template-columns: 1fr 1fr; gap: var(--space-3)`. Cards fill their cell; dismiss button stays top-right within the card.
- **Mein nächstes Spiel**, **Nächstes Training**: stay single-card full-width — they're statements, not lists.
- **Events**: stays 1-column; a 2-column events grid reads as a generic content feed, not as "3 upcoming items".
- **Neuigkeiten**: stays 1-column (readable line length).

Sketch (tablet task block):
```
┌─────────────────┬─────────────────┐
│  Lineup         │  Landesbewerb   │
│  confirm card   │  card           │
├─────────────────┼─────────────────┤
│  Captain        │  Soft           │
│  unconfirmed    │  suggestion     │
└─────────────────┴─────────────────┘
```

### Desktop (≥1200 px)

- Page max-width remains `600px` (**not** expanded). Centered. Deliberate phone-feel on big screens — cockpit is a glance, not a wall.
- No extra columns.
- Add a subtle drop-shadow around the centered content *only* if the surrounding page background is not identical to the card background — otherwise leave it flat. If needed: `box-shadow: var(--shadow-float); border-radius: var(--radius-xl)` around the page wrapper.

Odd-count fallback on tablet:
- If §2.3 has an odd number of cards, the last card spans both columns (`grid-column: span 2`) to avoid a dangling half-row.

---

## 6. Motion

### Section stagger (keep)

Keep the existing `.dash-section { animation-delay: calc(var(--i) * 70ms + 40ms); }` — it still works and its cadence matches the cockpit's "glance reveal" feel. Each section gets an `--i` starting at 0 for greeting.

Indexing:

| Section | `--i` |
|---|---|
| Greeting | 0 |
| Kapitän-Aufgaben | 1 (only if present) |
| Offene Aufgaben | next available |
| Mein nächstes Spiel | next |
| Nächstes Training | next |
| Spiele der Woche | next |
| Events | next |
| Neuigkeiten | next |

Conditional sections don't reserve their slot — the next section slides up into the empty index. That keeps the staircase tight when blocks are missing.

### Greeting entrance

- First paint only: `translateY(-8px) → 0`, `opacity 0 → 1` over 350 ms, easing `cubic-bezier(0.22, 1, 0.36, 1)`. **Drop the old spring hop and the `--gone` collapse logic entirely.** The wave emoji keeps its existing one-off animation.
- Status-line updates (when `openTasks` changes): text swap is instant. No fade — the number changing *is* the feedback.

### Task-card success/decline

Covered in §3. Summary:
- Background morph: 150 ms ease.
- Action-row fade-out + confirmation fade-in: 150 ms.
- 2 s hold.
- Collapse (opacity + max-height + margin + padding): 300 ms `cubic-bezier(0.22, 1, 0.36, 1)`.
- DOM removal on transition-end, not on a timer — more robust if the animation is interrupted.

### Tap affordance

All cards with a primary tap-target: `transform: scale(0.97)` on `:active`, 100 ms, `transform-origin: center`. Already in use on `.nmc` — extend to the new shared task card.

### Reduced motion

`@media (prefers-reduced-motion: reduce)`: disable stagger (`animation-delay: 0`), disable collapse (`transition: none`), keep opacity changes only. Success-state hold becomes instant display + instant removal after 2 s.

---

## 7. Delete decisions

Components to delete (no visual patterns worth preserving):

| Component | Why safe to delete |
|---|---|
| `QuickActions.svelte` | Covered by per-section CTAs. The old tile-row duplicated routes already reachable from BottomNav. |
| `RankCard.svelte` | Rank display belongs in Profil, not the dashboard. Not in Cockpit v2 scope. |
| `TeamStatsCard.svelte` | Same — stats live in Spielbetrieb/Statistiken. No user value on Dashboard. |
| `ActionHub.svelte` | Replaced by §2.2 + §2.3 inline task cards. The accordion-with-placeholders pattern ("Abstimmungen — bald") is explicitly what Cockpit v2 rejects. |

Visual patterns from ActionHub **worth carrying forward** (make sure frontend-dev keeps these when writing the new task card):
- The lineup-confirm avatar row (teammates with *Du* marker in gold) — **preserve** as the expanded detail view inside the Lineup task card (or as the body of the card before the button row).
- The `.lcc-btn--confirm` / `.lcc-btn--decline` button pair — already subsumed by `.mw-btn--primary` / `.mw-btn--ghost`.
- The `ah-lineup-in` 0.25 s expand animation — obsolete; new cards don't expand, they act-then-collapse.
- Captain push-notify on Absage (`/api/push/notify`) — **preserve behavior** (not visual). Keep the fetch call on the new Lineup card's decline action.

No patterns from QuickActions / RankCard / TeamStatsCard are load-bearing.

The `neuigkeiten` ↔ `events` **tab-switcher in PAGE_CONFIG** for `/` is removed — cockpit is a single scroll. Frontend-dev needs to update `PAGE_CONFIG` so Dashboard has `tabs: []`. This is a note, not a design concern, but it's a corollary of deleting the two-tab model.

---

## 8. Open design questions for frontend-dev

1. **Status-line format**: short (`3d`) vs. spelled (`in 3 Tagen`)? Short is denser but reads CLI-ish; spelled is warmer and matches KVWN tone. My recommendation: **spelled for `0/1` (`heute`/`morgen`), short for `≥2` (`2d`, `3d`)** — keeps the line tight without losing warmth at the close-in values. Pick one at implementation.

2. **Training "not booked" visual**: should the accent bar be the 40%-primary soft variant, or should there be no bar at all (reserved for "you have a job here")? I spec'd soft-bar; the stronger alternative is zero bar and the booking-CTA carries the weight.

3. **Events section trailing CTA**: `[Alle Events →]` — where does it route? No `/events` index exists yet. Interim: `/kalender` with a query filter. Worth confirming with the orchestrator/planner whether Cockpit v2 ships an `/events` route or not.

4. **Desktop framing**: do we want the centered content to have a visible card frame (shadow + radius around the whole 600 px column), or stay flat on the page background? I spec'd flat; the frame is an easy add later if it feels too "floating".

5. **Kapitän-Aufgaben max count**: I didn't cap it. If a captain has e.g. 8 unconfirmed players across two teams, do we render 8 cards or collapse to `3 Spieler noch unbestätigt` as a single summary card (as drawn)? The sketch assumes *summary-per-signal-type*, not *one-card-per-player*. Confirm this is the intended model before implementation.

6. **Soft-suggestions source**: the spec mentions them as a task-card type but doesn't say where they come from. Frontend-dev/planner need to agree on which DB signals generate suggestions (e.g. `matches.home_away = AUSWÄRTS` AND no carpool row = `Fahrgemeinschaft fehlt`). Out of scope for design — flagged so it isn't forgotten.

7. **Reduced-motion on status-line updates**: should the status-line animate when `openTasks` drops (e.g. after a Zusage)? I said instant swap. If the zero-to-one transition feels abrupt, a 150 ms cross-fade on the number alone is acceptable.
