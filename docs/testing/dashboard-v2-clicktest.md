# Browser Test Plan — Dashboard Cockpit v2

**Date written:** 2026-04-23
**Feature:** Dashboard redesign — Action Hub + QuickActions removed, inline task cards, GreetingHeader (permanent), NextTrainingCard, CaptainTaskBlock, UpcomingEvents bug fix, NewsFeed mixed-feed, Abwesenheit moved to Profil + Kalender, `dashboard_task_dismissals` DB table.

---

## Setup before you start

### Two browser sessions required

| Session | Account | Required DB state |
|---------|---------|-------------------|
| **Player (A)** | Normal user (no `kapitaen` role) | At least one `game_plan_players` row with `confirmed IS NULL` for a future match; at least one `matches` row with `is_landesbewerb = true`, future date, `registration_deadline` in the future, no existing `tournament_votes` row for this player |
| **Captain (B)** | `role = 'kapitaen'` | At least one published lineup (`lineup_published_at IS NOT NULL`) with one unconfirmed player (`confirmed IS NULL`) |

### DB prerequisite check (run these before starting)

```sql
-- Verify Player A has an unconfirmed lineup entry
SELECT gpp.id, gpp.confirmed, gp.lineup_published_at, m.date, m.opponent
FROM game_plan_players gpp
JOIN game_plans gp ON gp.id = gpp.game_plan_id
JOIN matches m ON m.cal_week = gp.cal_week AND m.league_id = gp.league_id
WHERE gpp.player_id = '<player_A_id>'
  AND gpp.confirmed IS NULL
  AND gp.lineup_published_at IS NOT NULL
  AND m.date >= CURRENT_DATE;

-- Verify an open Landesbewerb exists for Player A
SELECT m.id, m.date, m.registration_deadline
FROM matches m
WHERE m.is_landesbewerb = true
  AND m.date >= CURRENT_DATE
  AND m.registration_deadline > NOW()
  AND NOT EXISTS (
    SELECT 1 FROM tournament_votes tv
    WHERE tv.tournament_id = m.id AND tv.player_id = '<player_A_id>'
  );

-- Verify Player B has kapitaen role
SELECT id, name, role FROM players WHERE role = 'kapitaen';
```

---

## Happy Path (P0)

### Route: `/` — as Player A

**1.** Navigate to `http://localhost:5173/` and log in as Player A.

Expect: Page loads. At the very top (before any scroll), you see:
- An uppercase muted eyebrow line with today's weekday and date, e.g. `DONNERSTAG, 23. APRIL`
- A large heading `Hallo [Vorname] 👋`
- A status line below the name, e.g. `2 offen · Spiel in 3d` (exact numbers depend on DB state)
- The greeting does NOT collapse or fade away after a few seconds — it stays permanently visible

**2.** Wait 5 seconds without any interaction.

Expect: The greeting header is still fully visible. No collapse animation. The wave emoji has completed its one-off wiggle and is now still.

**3.** Scroll down slowly from the top and verify the section order.

Expect (top to bottom, no other sections in between):
1. Greeting header (already verified)
2. "Offene Aufgaben" section (bolt icon, red badge with count) — NO "Kapitän-Aufgaben" section for this normal player
3. "Mein nächstes Spiel" section heading + card (only if lineup entry exists for Player A)
4. "Nächstes Training" section heading + training card
5. "Spiele der Woche" section heading + horizontal match carousel
6. "Events" section heading + event list (or hidden if no events in 30 days)
7. "Neuigkeiten" section heading + vertical news/poll feed

**4.** Observe the bottom navigation bar.

Expect: Bottom nav still has all 4 tabs (Dashboard, Kalender, Spielbetrieb, Profil). There is NO sub-tab pill/switcher on the dashboard page — no "Neuigkeiten | Events" segmented control anywhere. The dashboard is a single scroll.

---

### "Mein nächstes Spiel" card (P0 — step 5)

**5.** Locate the "Mein nächstes Spiel" section (only appears if Player A is on a future lineup).

Expect: Section heading with trophy icon reads "Mein nächstes Spiel". The card below shows:
- Days-until badge (red pill), e.g. `in 5 T`
- Opponent name, e.g. `vs. SK Baden`
- Date + time, e.g. `Sa, 26.4. · 15:00 Uhr`
- League name + position, e.g. `Landesliga · Pos. 3`

If Player A is NOT on any future lineup: neither the section heading nor any card is visible. There is no empty state placeholder for this section — it is completely absent.

---

### Lineup-Confirm task (P0 — step 6–8)

**6.** In the "Offene Aufgaben" section, locate the lineup confirmation task card.

Expect: Card has a red left accent bar, title "Aufstellung bestätigen", sub-line showing the league and opponent (e.g. `Landesliga · vs. SK Baden`), a meta line with date + time + position, and two buttons at the bottom: `[Absage]` (ghost/outline) and `[Zusage]` (filled red).

**7.** Tap `[Zusage]`.

Expect:
- Both buttons disappear immediately
- A green pill appears inside the card reading `check_circle Bestätigt`
- The card's left accent bar turns green (`--color-success`)
- After approximately 1.4 seconds the card begins fading out and collapsing upward
- After the collapse completes (~280 ms later), the card is gone from the DOM
- The "Offene Aufgaben" badge count decrements by 1
- If the count reaches 0, the entire "Offene Aufgaben" section (heading + list) disappears

**8.** Open Supabase or run the DB check below to verify the action was written.

```sql
SELECT id, confirmed FROM game_plan_players WHERE id = '<gamePlanPlayerId>';
-- Expect: confirmed = true
```

---

### Landesbewerb task — dismiss (P0 — step 9–12)

**9.** In the "Offene Aufgaben" section, locate the Landesbewerb task card.

Expect: Card has a gold left accent bar (or red if deadline <24 h away), a trophy/premium icon in a gold gradient square, title "Landesbewerb-Anmeldung", subtitle with the tournament name, a date line, a deadline line with clock icon (e.g. `bis 25.04.2026, 18:00`), and two buttons `[Nein]` (ghost) + `[Ja]` (filled red). There is also a small `close` icon button in the top-right corner of the card (aria-label "Aufgabe ausblenden").

**10.** Tap the `close` dismiss button (top-right corner of the Landesbewerb card, NOT the `[Nein]` button).

Expect: The card immediately begins fading out and collapsing. No success banner is shown. The card disappears within about 500 ms.

**11.** Hard-reload the page (`Ctrl+Shift+R` / `Cmd+Shift+R`).

Expect: The Landesbewerb card does NOT reappear. The dismiss is persistent. The "Offene Aufgaben" section count does not include it.

**12.** Run the DB check to confirm the dismissal row was written.

```sql
SELECT * FROM dashboard_task_dismissals
WHERE player_id = '<player_A_id>'
  AND task_kind = 'landesbewerb';
-- Expect: one row with task_ref_id = <match_id of the Landesbewerb match>
```

---

### Nächstes Training card (P0 — step 13–15)

**13.** Locate the "Nächstes Training" section.

Expect: Always visible (never hidden). The card shows:
- A red date square (top-left) with abbreviated weekday, day number, and month abbreviation
- A relative label, e.g. `HEUTE`, `MORGEN`, or `IN X TAGEN` (in uppercase small caps style)
- Time range, e.g. `18:00 – 19:00 Uhr`
- Slot status, e.g. `3 von 6 Plätzen frei` (if not booked), or `Gebucht · Bahn 2` (if already booked), or `Voll belegt · 1 auf Warteliste` (if full)

**14.** If the slot shows free spots — tap `[Buchen]`.

Expect:
- Button is replaced by a green result row reading `check_circle Gebucht`
- A toast notification appears, e.g. `Gebucht (Bahn 2)`
- After ~1.4 seconds the card reloads. The status line now reads `Gebucht · Bahn N` and the CTA changes to `[Stornieren]`

**15.** Tap `[Stornieren]` (only available if training is NOT today).

Expect:
- Button changes to a red result row reading `cancel Storniert`
- A toast `Storniert` appears
- After ~1.4 seconds the card reloads with free-spots status and `[Buchen]` button again

---

### Events section (P0 — step 16)

**16.** Locate the "Events" section (below "Spiele der Woche").

Expect: Up to 3 event rows, each showing:
- Left column: abbreviated weekday (e.g. `Sa`), day number, abbreviated month (e.g. `Mai`) — all in correct German (no `undefined` or raw `NaN` values)
- Right column: event title and optional time + location meta line
- A `Alle` link/button on the section header right side that navigates to `/kalender`

Verify: No `undefined`, `NaN`, or `[object Object]` anywhere in the date columns. This was the bug that was fixed (missing `DAY_SHORT`/`MONTHS` imports).

---

## Edge Cases

### E1: No open tasks for Player A

**Setup:** Ensure Player A has no pending lineup confirmations AND no open Landesbewerb votes (either voted already, or dismissed, or none exist).

**17.** Navigate to `/` as Player A.

Expect: The "Offene Aufgaben" section (bolt icon heading + task cards) is completely absent from the page. No heading, no empty-state placeholder, no badge. The section order jumps directly from the Greeting to "Mein nächstes Spiel" (or to "Nächstes Training" if also not on a lineup).

---

### E2: Player A not on any lineup

**Setup:** Use a player account that has no `game_plan_players` rows for future matches.

**18.** Navigate to `/` as this player.

Expect: Neither the "Mein nächstes Spiel" section heading nor any match card is visible. The section is entirely absent. The status line in the greeting shows `0 offen` segments only (or is omitted entirely if no tasks either).

---

### E3: Training slot fully booked (Warteliste)

**Setup:** Ensure the next training slot has `bookings.length >= lane_count` (fully booked).

**19.** Locate the "Nächstes Training" card.

Expect: Status line reads `Voll belegt · N auf Warteliste`. CTA button shows `[Warteliste]` (soft/neutral style, not filled red).

**20.** Tap `[Warteliste]`.

Expect: Button replaced by `hourglass_top Auf Warteliste` result row. Toast shows `Auf Warteliste (Position N)`. After reload the card shows `Warteliste · Position N` and a `[Warteliste verlassen]` ghost button.

---

### E4: Landesbewerb deadline <24 h

**Setup:** Set a `matches` row with `is_landesbewerb = true` and `registration_deadline` within the next 24 hours.

**21.** View the Landesbewerb task card in "Offene Aufgaben".

Expect: Card has a red left accent bar (not gold), a faint red gradient background wash, and the deadline line is red with an additional `· nur mehr Xh` suffix, e.g. `bis 23.04.2026, 23:59 · nur mehr 4 h`.

---

## Captain-Only Checks (Session B — log in as captain)

**22.** Log out Player A. Log in as Player B (kapitaen role). Navigate to `/`.

Expect: Below the Greeting header and ABOVE the "Offene Aufgaben" section, a section "Kapitän-Aufgaben" (bolt icon) is visible with one or more task cards. Normal players who log in after this step should NOT see this section.

**23.** Verify the first captain signal card.

Expect: If a published lineup has unconfirmed players, the card reads `N Spieler noch unbestätigt` with sub-line `Aktuelle Aufstellung` and a right-aligned text link `Anzeigen →`. The left accent bar is solid red.

**24.** Tap the "Anzeigen →" link (or anywhere on the card body).

Expect: Navigates to `/spielbetrieb` with the "Aufstellungen" sub-tab active. The captain task block is a read+navigate card — it does NOT have inline action buttons.

**25.** Navigate back to `/` (tap Dashboard in bottom nav). Verify the "Offene Aufgaben" section for the captain.

Expect: If the captain is also personally on a lineup with `confirmed IS NULL`, they see their own lineup task in "Offene Aufgaben" (separate from "Kapitän-Aufgaben"). If not, "Offene Aufgaben" may be absent for the captain.

**26.** Log back in as Player A. Navigate to `/`.

Expect: "Kapitän-Aufgaben" section is completely absent. No heading, no cards, no empty state.

---

## Profil Route (P1 — both players)

**27.** As Player A, tap "Profil" in the bottom nav. The default sub-tab "Übersicht" loads.

Expect: Scroll down past the hero card, action cards, and Mitgliedschaft card. Locate a section titled "Meine Abwesenheiten" with a `event_busy` icon and a `+ Melden` button in the top-right of the section header.

**28.** Tap `[+ Melden]`.

Expect: A bottom sheet slides up titled with absence-related content (e.g. "Abwesenheit melden"). It contains date-range fields (Von / Bis) and a reason field or similar. The sheet is the `AbsenceSheet` component.

**29.** Fill in a date range (from today to 3 days from now) and submit.

Expect: Sheet closes. The "Meine Abwesenheiten" section in the Profil tab now shows the newly created absence row with a formatted date range and a delete option.

**30.** Tap the delete button on the newly created absence row.

Expect: A toast confirms `Abwesenheit entfernt`. The row disappears from the list.

---

## Kalender Route (P1 — agenda view)

**31.** Tap "Kalender" in the bottom nav. Agenda view is the default.

Expect: Bottom of the visible screen (or above the bottom nav) shows a blue/red filled button with a `+` icon and label `Eintrag`.

**32.** Tap `[+ Eintrag]`.

Expect: A small popover menu appears with two options:
- `event` icon + "Vereinstermin" heading + sub-text (captain-only; this option may be absent or grayed if Player A is not a captain)
- `event_busy` icon + "Abwesenheit" heading + sub-text "Zeitraum melden" (always visible)

**33.** Tap "Abwesenheit" in the popover.

Expect: The popover closes and the AbsenceSheet bottom sheet slides up. Same sheet as in step 28.

**34.** Tap outside the popover (or press Escape) without selecting an option.

Expect: The popover closes. No sheet is opened.

**35.** As Captain (Session B), tap `[+ Eintrag]` on the Kalender agenda view.

Expect: The popover shows BOTH options — "Vereinstermin" (Event) AND "Abwesenheit". Tapping "Vereinstermin" opens the EventCreateSheet.

---

## Regression Checks (P2)

**36.** From the bottom nav, tap "Spielbetrieb". The default sub-tab loads.

Expect: Page loads without any JavaScript errors in the browser console. The pill switcher ("Spiele | Turnier | Landesbewerb") is visible inside the Übersicht tab. No dangling import errors from deleted components (ActionHub, QuickActions, OpenRegistrationsCard).

**37.** In Spielbetrieb, tap the "Aufstellungen" pill/tab.

Expect: Lineup management view loads normally. No console errors.

**38.** Navigate to `/profil` → tap the "Einstellungen" sub-tab.

Expect: Settings tab loads. Push notification preferences and other settings are visible and functional.

**39.** Resize the browser to 768 px width (tablet breakpoint). Navigate to `/`.

Expect: Task cards in the "Offene Aufgaben" section render in a 2-column grid (two cards side-by-side). Section headings remain full-width. "Mein nächstes Spiel" and "Nächstes Training" remain single-column full-width cards — they do NOT become 2-column.

**40.** Resize to 1200 px+ (desktop). Navigate to `/`.

Expect: Page content is centered with a visible max-width (approximately 600 px). Content does not stretch to fill the full screen width. Bottom nav remains full-width.

---

## Visual/Animation Checks (P3)

**41.** On the Lineup task card, tap `[Absage]` instead of `[Zusage]`.

Expect:
- Action row fades out
- A result pill appears reading `cancel Abgesagt` (the icon is `cancel`, not a check)
- The background wash is neutral gray (NOT red — absence is not an error)
- After ~1.4 seconds the card collapses and disappears
- No "Kapitän-Aufgaben" notification appears on the dashboard (push notification goes to captain device, but no visual change on this player's dashboard)

**42.** On the Landesbewerb task, tap `[Ja]` (not the dismiss X button).

Expect:
- Action row fades out
- Green pill appears reading `check_circle Angemeldet`
- After ~1.4 seconds the card collapses
- Reloading the page: the card does NOT reappear (vote was recorded) and there is NO entry in `dashboard_task_dismissals` (votes and dismissals are stored separately)

```sql
-- Should return a row (vote recorded):
SELECT * FROM tournament_votes WHERE player_id = '<player_A_id>';

-- Should NOT return a row (not a dismissal):
SELECT * FROM dashboard_task_dismissals WHERE player_id = '<player_A_id>' AND task_kind = 'landesbewerb';
```

**43.** Check the Landesbewerb card's trophy icon visual.

Expect: The trophy icon is displayed inside a square tile with a gold gradient background — derived from `--color-secondary` tokens. There is no hardcoded `#D4AF37` color visible via browser DevTools inspector on the `.lbt-trophy` element (the CSS should use `color-mix(in srgb, var(--color-secondary) 75%, white)` as the gradient start).

---

## DB Appendix — one-liner checks

```sql
-- 1. Did the lineup confirm write through?
SELECT id, confirmed FROM game_plan_players WHERE id = '<gamePlanPlayerId>';

-- 2. Did the Landesbewerb dismiss persist?
SELECT * FROM dashboard_task_dismissals WHERE player_id = '<player_A_id>';

-- 3. Did the Landesbewerb Ja-vote write through?
SELECT * FROM tournament_votes WHERE player_id = '<player_A_id>' AND tournament_id = '<match_id>';

-- 4. RLS isolation — Player B cannot see Player A's dismissals:
-- (Run while authenticated as Player B in Supabase dashboard or via anon key)
SELECT * FROM dashboard_task_dismissals WHERE player_id = '<player_A_id>';
-- Expect: 0 rows returned (RLS blocks it)

-- 5. Training booking written:
SELECT * FROM training_bookings WHERE player_id = '<player_A_id>' ORDER BY created_at DESC LIMIT 1;

-- 6. Absence written:
SELECT * FROM absences WHERE player_id = '<player_A_id>' ORDER BY created_at DESC LIMIT 1;
```

---

## What this plan does NOT cover

- Visual pixel-perfect spacing (card padding, gap values) — DevTools inspector if needed.
- Offline / service-worker behaviour.
- Push notification delivery to captain devices on Absage (the fetch to `/api/push/notify` fires client-side — verifiable via browser Network tab on the decline action).
- NewsFeed poll voting behaviour — unchanged component, not part of this diff.
- `MatchCarousel` internals — unchanged, not part of this diff.
- Same-day Storno lock on training (code path exists; testing requires booking on the exact current date).
- Reduced-motion behaviour (`prefers-reduced-motion: reduce` media query disables stagger + collapse animations).
- The `[Alle Events →]` button routing destination (currently routes to `/kalender` — an open design question in the spec, not a bug).
- Multi-player RLS isolation beyond the one SQL check in the appendix.
