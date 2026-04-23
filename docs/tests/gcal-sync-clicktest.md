# Browser Test Plan — Google Calendar Two-Way Sync

Start: https://kvwn.vercel.app (production)
Prerequisite: service-account calendar share, Vercel env vars, and `vercel --prod` deploy are ALL complete before running any step below.

---

## Pre-flight (no browser needed)

**P1 — Migration applied (already confirmed by compile-checker)**
No action required. The columns `external_id`, `source`, `synced_at`, `etag` exist on `events`; `gcal_sync_state` table exists. Confirmed via Supabase dashboard or compile pass.

**P2 — Initial cron trigger (terminal, run once before opening browser)**
```
curl -H "Authorization: Bearer $CRON_SECRET" https://kvwn.vercel.app/api/cron/gcal-sync
```
Expected response shape (HTTP 200):
```json
{ "upserted": N, "deleted": 0, "skipped_match_dates": M, "next_sync_token": "Cg..." }
```
- `upserted` must be > 0 if Google Calendar has any events in the window (-30 d .. +180 d).
- `next_sync_token` must be a non-null string (proves Supabase `gcal_sync_state` row was written).
- If you get `401 unauthorized`: CRON_SECRET env var is missing or the deploy did not pick it up — redeploy.
- If you get `500` with a Google error: service-account key or calendar share is wrong.
- Rollback: none needed — this only reads from Google and writes to Supabase `events`.

---

## Happy path

### HP1 — Synced events appear in Agenda view

1. Navigate to `https://kvwn.vercel.app` and log in with the kapitaen account (Google OAuth).
2. Tap the bottom nav item **Kalender**.
   - Expect: `/kalender` opens, pill-bar shows **Agenda | Woche | Monat**, Agenda is active.
3. Scroll the Agenda list.
   - Expect: events imported from Google Calendar appear inline with manually created events. They use the same card style (no special colour/badge). Events that have a time show it as "HH:MM Uhr"; all-day events show no time line.
4. Tap any synced event card to open its detail sheet.
   - Expect: bottom sheet slides up, titled **Termin**. Below the date/location block there is a subtle line with a sync icon and the text **Synchronisiert mit Google Calendar**. Two buttons appear at the bottom: **Bearbeiten** (soft) and **Löschen** (danger/red tint).
   - Rollback: tap outside the sheet or swipe it down to close without changes.

### HP2 — Captain creates a new event (Push Create)

5. Still on `/kalender` (Agenda or any view), scroll to the **Termin anlegen** button (visible only to kapitaen, positioned above the events list).
6. Tap **Termin anlegen**.
   - Expect: bottom sheet opens with title **Termin anlegen** and five fields: **Titel**, **Datum**, **Uhrzeit (optional)**, **Ort**, **Beschreibung**.
7. Fill in:
   - Titel: `Testtermin KVWN`
   - Datum: pick a date at least 2 days in the future (e.g. 2026-05-10)
   - Uhrzeit: `19:00`
   - Ort: `Vereinsheim`
   - Beschreibung: leave empty
8. Tap **Speichern**.
   - Expect: sheet closes, toast shows **Termin angelegt**, the new event card appears in the Agenda list immediately (component calls `loadData` via `onCreated`).
9. Open `https://calendar.google.com` in a second tab, signed in as `kvwienerneustadt@gmail.com`.
   - Expect: within a few seconds the event **Testtermin KVWN** appears on 2026-05-10 at 19:00 (Europe/Vienna).
   - Rollback: proceed to HP3 (Push Edit) or HP4 (Push Delete) to clean up; or delete directly in Google Calendar.

### HP3 — Captain edits an existing synced event (Push Edit)

10. Back in KVWN `/kalender`, tap the **Testtermin KVWN** card created in HP2.
    - Expect: detail sheet opens, shows **Synchronisiert mit Google Calendar** and **Bearbeiten** button.
11. Tap **Bearbeiten**.
    - Expect: sheet switches to edit mode showing the same five fields pre-filled with current values.
12. Change **Titel** to `Testtermin KVWN – geändert`. Tap **Speichern**.
    - Expect: toast shows **Gespeichert**, sheet closes, Agenda shows the updated title.
13. Switch to the Google Calendar tab and reload.
    - Expect: the event title is now **Testtermin KVWN – geändert**.
    - Rollback: repeat edit to restore original title, or proceed to HP4.

### HP4 — Captain deletes a synced event (Push Delete)

14. Tap the **Testtermin KVWN – geändert** card in KVWN `/kalender`.
15. Tap **Löschen**.
    - Expect: browser shows a native confirm dialog: `Termin "Testtermin KVWN – geändert" wirklich löschen?`
16. Confirm the dialog.
    - Expect: toast shows **Termin gelöscht**, sheet closes, event disappears from Agenda immediately.
17. Switch to Google Calendar tab and reload.
    - Expect: the event is gone from the calendar.
    - Rollback: none needed — event is already removed. If you want it back, create it again via HP2.

---

## Edge cases

### E1 — Pull Edit (Google change propagates to KVWN)

Precondition: at least one synced event exists in KVWN (visible in Agenda with **Synchronisiert mit Google Calendar** label).

18. In Google Calendar, find any synced event and edit its title to something clearly different (e.g. append ` – PULL TEST`). Save.
19. Either wait up to 15 minutes for the Vercel cron to fire, OR trigger manually:
    ```
    curl -H "Authorization: Bearer $CRON_SECRET" https://kvwn.vercel.app/api/cron/gcal-sync
    ```
    Expected response: `{ "upserted": 1, ... }` (at minimum 1 for the changed event).
20. Back in KVWN, navigate to `/kalender` and hard-reload (pull-to-refresh or browser reload).
    - Expect: the event card shows the updated title ` – PULL TEST`.
    - Rollback: edit the event title back in Google Calendar and trigger cron again.

### E2 — Pull Delete (Google deletion propagates to KVWN)

Precondition: choose a synced event that you are willing to permanently remove from KVWN.

21. In Google Calendar, delete that event.
22. Trigger cron manually:
    ```
    curl -H "Authorization: Bearer $CRON_SECRET" https://kvwn.vercel.app/api/cron/gcal-sync
    ```
    Expected response: `{ "deleted": 1, ... }`.
23. Reload `/kalender` in KVWN.
    - Expect: the event is no longer in the Agenda list.
    - Rollback: none (event deleted from both systems). Re-create via HP2 if needed.

### E3 — Incremental sync shows no ghost upserts

Precondition: cron has run at least once (P2 complete), and nothing has changed in Google Calendar since then.

24. Trigger cron a second time without making any changes in Google:
    ```
    curl -H "Authorization: Bearer $CRON_SECRET" https://kvwn.vercel.app/api/cron/gcal-sync
    ```
    - Expect: HTTP 200, response contains `"upserted": 0, "deleted": 0`. `next_sync_token` is present and different from the previous run's token (Google issues a fresh token each incremental call).
    - Rollback: not applicable.

### E4 — Match-date duplicate guard

Precondition: identify a date that has a match in KVWN (check `/spielbetrieb` Uebersicht for an upcoming or recent match, note its date — e.g. 2026-04-26). Verify that Google Calendar has or had an event on that same date (legacy entry from old Google-based match tracking).

25. Trigger cron manually (same curl as above).
    - Expect: response contains `"skipped_match_dates": K` where K >= 1. No new event card for that match date appears in `/kalender` beyond the already-existing match card from the `matches` table.
26. Open `/kalender`, navigate to that match date in any view.
    - Expect: only one entry appears for that day (the KVWN match card), not a second duplicate event card.
    - Rollback: not applicable — cron correctly skipped the duplicate.

---

## Regression checks

### R1 — Non-captain user sees no write controls

Precondition: log out, then log in with a non-kapitaen account (role = `user`).

27. Navigate to `https://kvwn.vercel.app/kalender`.
    - Expect: the **Termin anlegen** button is NOT visible anywhere on the page.
28. Tap any synced event card (one that shows **Synchronisiert mit Google Calendar** for the kapitaen).
    - Expect: detail sheet opens and shows event details and the **Synchronisiert mit Google Calendar** line. The **Bearbeiten** and **Löschen** buttons are NOT present.
29. Tap a manually created event (one without a sync hint — `source='manual'`, no `external_id`).
    - Expect: detail sheet opens, no **Synchronisiert mit Google Calendar** line, no **Bearbeiten** or **Löschen** buttons (regardless of role, because `canEdit` requires both kapitaen AND `external_id`).
    - Rollback: log back in as kapitaen for further tests.

### R2 — Manual events (source='manual') untouched by kapitaen

Precondition: log in as kapitaen. Identify an event that was created before this feature (has no `external_id` — it will NOT show the sync hint line).

30. Tap a manual event card in the Agenda.
    - Expect: detail sheet opens, the **Synchronisiert mit Google Calendar** line is absent, and the **Bearbeiten** and **Löschen** buttons are NOT shown (even though the user is kapitaen). This confirms the `canEdit = $playerRole === 'kapitaen' && isGcal` guard works correctly.
    - Rollback: not applicable — no action taken.

### R3 — Woche and Monat views render synced events

31. Navigate to `/kalender`, tap the **Woche** pill.
    - Expect: synced events appear as cards in the week grid on their correct day column, using the same card style as manual events and matches.
32. Tap the **Monat** pill.
    - Expect: synced events appear as dot indicators or compact entries on their correct day cells, consistent with how manual events render.
    - Rollback: not applicable.

---

## What I did NOT check

- Visual polish: spacing, font rendering, icon alignment in dark mode.
- Offline/PWA behaviour: what the app shows when the device is offline during a save or cron trigger.
- Push notification interaction: whether a new synced event triggers a push to registered devices.
- 412 etag conflict: simultaneous edits from two kapitaen accounts (plan marks this as out of scope for Phase 1 — last write wins).
- Non-match events that fall on a match day: per plan these are currently skipped by the cron guard and must be recreated via "Termin anlegen" in KVWN.
- Recurring Google Calendar events: the cron uses `singleEvents: true` so instances render, but creating/editing a recurring master event through KVWN UI was not designed and is not testable here.
- Vercel cron log inspection: verify run history in Vercel dashboard under Project > Logs > Cron if you want server-side confirmation beyond the curl response.
- `matches.external_id` column: present in migration as Phase 2 preparation but the Match → Google push flow is out of scope for Phase 1 and has no UI to test.
