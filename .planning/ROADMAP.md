# KVWN Vereins-App — v1 Roadmap

**Project:** KVWN Vereins-App (PWA für KV Wiener Neustadt)
**Milestone:** v1 — Demo-ready zur JHV
**Deadline:** 2026-05-22 (JHV — ~24 Tage ab heute 2026-04-29)
**Confidence:** HIGH (gestützt auf 4 parallele Researcher + Brownfield-Audit)
**Source:** `.planning/PROJECT.md` · `.planning/REQUIREMENTS.md` (75 v1-Reqs) · `.planning/research/SUMMARY.md`

---

## Phases

- [ ] **Phase 0: Cross-Cutting Foundations** — RLS-Pin, TZ-Helper, `is_demo`-Pattern, Resize-Util, `PUSH_PREFS`-Konstante (NON-NEGOTIABLE Bevor jede Feature-Phase)
- [ ] **Phase 1: Spieler-Selfservice + Foto + Consent** — Spieler pflegen Stammdaten + Foto selbst, DSGVO-Workflow live
- [ ] **Phase 2: Trainingsbuchung-Vollausbau** — Warteliste mit Auto-Promote, 24h-Reminder, Streak-Stat, Slot-Templates
- [ ] **Phase 3: Events + Polls + Push systematisch** — `push_outbox` als Reminder-Infra, RSVPs, Polls mit Voting, Event-Push
- [ ] **Phase 4: Statistik-Dashboards** — Saison-Schnitt, Form-Sparkline, Liga-Tabelle (Captain-manuell + Mock), Bahn-Stats
- [ ] **Phase 5: Demo-Härtung + Reviewer-Pass** — Snapshot, Reviewer-Sweep, Pitfall-Verifikation, Cleanup-Migration vorbereitet

### Phase Summary Table

| # | Phase | Dauer | REQs | Parallel? | Status |
|---|-------|-------|------|-----------|--------|
| 0 | Cross-Cutting Foundations | 2 d | 7 | nein (BLOCKER für alle Folgephasen) | Planned |
| 1 | Spieler-Selfservice + Foto + Consent | 4-5 d | 12 | nein (Phase 3+4 abhängig) | Planned |
| 2 | Trainingsbuchung-Vollausbau | 4-5 d | 10 | optional parallel zu Phase 3 (Default seriell) | Planned |
| 3 | Events + Polls + Push systematisch | 5-6 d | 19 | optional parallel zu Phase 2 (Default seriell) | Planned |
| 4 | Statistik-Dashboards | 5-6 d | 17 | nein (verbraucht Phase 1+2 Outputs) | Planned |
| 5 | Demo-Härtung + Reviewer-Pass | 2-3 d | 10 | nein (operational, Reviewer-Findings können Re-Work triggern) | Planned |
| | **Total** | **22-27 d** | **75** | | |

**Budget-Realität:** 24 Tage Deadline · 22-27 Tage Schätzung. Mid-Range = 25 d → 1 Tag Überzug. Lower-Bound 22 d → 2 Tage Buffer. **Tight; Re-Work-Risiko in Phase 5 muss durch Phase-1-4-Disziplin gedrückt werden.** Phase 2/3 parallel = potenzielle 4-5 Tage Einsparung wenn Executor-Kapazität verfügbar.

---

## Phase Details

### Phase 0: Cross-Cutting Foundations

**Status:** Planned
**Goal:** Die zwei BLOCKER-Pitfalls (C1 RLS-Cross-Write, C3 Cron-TZ-Drift) sind fixed und alle Cross-Cutting-Helper (TZ, Resize, `is_demo`, `PUSH_PREFS`) liegen einmal sauber, sodass die nachfolgenden Feature-Phasen nicht 4× dieselbe Plumbing wiederholen oder Sicherheits-Lücken einschleppen.

**Depends on:** Nichts (erste Phase)
**Parallel-eligible:** Nein — BLOCKER für alle Folgephasen
**Duration:** 2 Tage

**Requirements:**
- FOUND-01 — Migration `players.email NOT NULL UNIQUE` + lower()-Normalisierung + Pre-Deploy-Audit
- FOUND-02 — RLS-Policy-Refactor `players` mit `WITH CHECK (id = …)`-Pin
- FOUND-03 — `$lib/server/timezone.js` mit `nowVienna()` / `dateInVienna(offsetDays)` Helper
- FOUND-04 — Refactor existing `lineup-reminders`-Cron auf TZ-Helper + `reminder_log`-Idempotenz-Tabelle
- FOUND-05 — `$lib/constants/pushPrefs.js` zentrale `PUSH_PREFS`-Konstante + DB-CHECK auf JSONB-Keys
- FOUND-06 — `is_demo BOOLEAN DEFAULT false` Pattern-Doku + Migration-Vorlage
- FOUND-07 — `$lib/utils/imageResize.js` Browser-Canvas-Resize (512×512 WebP, EXIF-strip)

**Success Criteria** (was muss WAHR sein):
1. Pre-Deploy-Audit-Query `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL` gibt 0 zurück; Migration ist auf Production deployed.
2. Manueller RLS-Test: Spieler A versucht via DevTools Spieler B's Row zu updaten → Supabase liefert 403 (Cross-Write blockiert via `WITH CHECK`-Pin).
3. `nowVienna()` und `dateInVienna(0)` retournieren in Vercel-Cron-Logs konsistent Vienna-Local-Date über DST-Wechsel-Test (manuell mit `TZ=UTC` simuliert).
4. Bestehender `lineup-reminders`-Cron läuft auf neuer TZ-Helper-Basis und schreibt `reminder_log`-Idempotenz-Einträge; doppelter Cron-Trigger schickt KEINE doppelten Pushes.
5. `PUSH_PREFS`-Konstante ist die einzige Quelle für Pref-Keys; DB-CHECK-Constraint rejected JSONB mit unbekanntem Key (manueller `INSERT` mit Tippfehler-Key schlägt fehl).
6. `imageResize.js` produziert für ein iPhone-Sample-Foto (mit GPS-EXIF) einen Output, in dem `exiftool` keine GPS-Tags mehr findet und `octet_length < 200000` gilt.

**Key risks:**
- RLS-Activation könnte unentdeckte 401/403-Pfade in bestehenden Captain-Workflows zutage fördern (Pitfall C11) — Browser-Network-Tab nach Migration-Deploy beobachten.
- Bestandsdaten-Audit könnte Email-Duplikate zeigen (Familien-Gmail) → manueller Cleanup vor Migration.

**Plans:** TBD

---

### Phase 1: Spieler-Selfservice + Foto + Consent

**Status:** Planned
**Goal:** Spieler pflegen ihre Stammdaten (Telefon, Adresse, Geburtstag, Notfallkontakt, Lizenz) selbst, laden ein Profilfoto über Storage-Bucket hoch und haben dokumentierte DSGVO-Einwilligungen erteilt; Captain ist nur noch für initialen Invite zuständig.

**Depends on:** Phase 0 (RLS-Pin, Resize-Util, `is_demo`-Pattern)
**Parallel-eligible:** Nein — Phase 3 (RSVP-Avatar-Reihen) und Phase 4 (PlayerStatsView mit Foto) hängen davon ab
**Duration:** 4-5 Tage

**Requirements:**
- SELF-01 — Migration `players`-Schema verifizieren (Researcher-Sweep) + fehlende Spalten ergänzen
- SELF-02 — `ProfilDatenSheet` mit valibot-Validation, RLS write-own-row
- SELF-03 — Migration: Storage-Bucket `player-photos` + `players.photo_url`-Spalte
- SELF-04 — `ProfilFotoSheet` NEU mit FOUND-07-Resize-Pipeline
- SELF-05 — `imgPath()` Storage-Branch + Fallback-Kette
- SELF-06 — Profil-Vervollständigungs-Score (Progress-Ring im `ProfilHeroCard`)
- SELF-07 — DSGVO-Consent-Onboarding-Modal (blockiert Profil-Editing bis Consent)
- SELF-08 — Statische `/privacy`-Seite (Vorstand-textlich)
- SELF-09 — Datenschutz-Hinweis-Banner im Edit-Sheet
- SELF-10 — Widerruf-Pfad in EinstellungenTab
- SELF-11 (Differentiator) — Geburtstags-Banner Auto-Card im Dashboard `/neuigkeiten`
- SELF-12 (Differentiator) — Konfetti-Animation bei 100% Profil-Score

**Success Criteria** (was muss WAHR sein):
1. Spieler ohne Captain-Rechte kann auf `/profil/uebersicht` Telefon, Geburtstag, Adresse, Notfallkontakt + Lizenz-Nummer eintragen, speichern, Reload — Daten persistent in seiner eigenen Row.
2. Spieler kann auf `/profil/uebersicht` ein iPhone-Foto hochladen; nach Upload zeigt jede Lineup-Liste (Spielbetrieb, Aufstellung, Profil) das neue Foto via `imgPath()`-Storage-Branch.
3. Erstmaliger Login auf einem unkonsentierten Account zeigt Consent-Modal, das Profil-Editing blockiert; nach Annahme der vier Consents (`photo`, `liga_data`, `whatsapp`, `accepted_at`) ist Editing freigeschaltet; Foto-Upload-Button bleibt disabled solange `consent_photo=false`.
4. Profil-Vervollständigungs-Ring zeigt anteiligen Fortschritt (0-100%); bei 100% spielt Konfetti-Animation einmalig ab.
5. Am Geburtstag eines Spielers erscheint Auto-Card "Heute hat X Geburtstag" auf Dashboard `/neuigkeiten` (sichtbar für alle Mitglieder).
6. Spieler kann in EinstellungenTab erteilte Consents widerrufen; Foto wird beim Widerruf von `consent_photo` aus DB-Public-View entfernt (Hard-Delete-Pfad oder Soft-Hide).

**Key risks:**
- `imgPath()`-Erweiterung bricht alte Avatare (Lineup-Listen) — Smoke-Test alle bestehenden Listen vor Deploy.
- Consent-Modal-UX bei Bestands-Spielern: Force-Through-Flow muss elegant sein, nicht blockierend für JHV-Demo.
- DSGVO-`/privacy`-Text ist Vorstand-Workflow (Open Question 4) — Text muss vor Phase-1-Ende vorliegen.

**UI hint**: yes
**Plans:** TBD

---

### Phase 2: Trainingsbuchung-Vollausbau

**Status:** Planned
**Goal:** Spieler können sich auf vollen Slots auf Warteliste setzen und werden bei Storno automatisch promoted; jeder bekommt 24h vor Training einen Push-Reminder; Captain pflegt wiederkehrende Slot-Templates; Profil zeigt Trainings-Statistik (Donut + Streak); Bahn-Belegung ist im Kalender sichtbar.

**Depends on:** Phase 0 (TZ-Helper für 24h-Reminder-Cron, `PUSH_PREFS`-Konstante, `is_demo`-Pattern)
**Parallel-eligible:** Optional parallel zu Phase 3 wenn Executor-Kapazität (disjunkte UI-Files: Training-Sheets vs. Event-Sheets/Polls). **Default: seriell nach Phase 1, vor Phase 3** — 24-Tage-Budget zu knapp für Speculative Parallel.
**Duration:** 4-5 Tage

**Requirements:**
- TRAIN-01 — `TrainingDetailSheet` Warteliste-UI (Position-Anzeige bei vollem Slot)
- TRAIN-02 — Auto-Promote-RPC `promote_waitlist_on_cancel(p_date, p_start)` + Push-Trigger via `push_outbox`
- TRAIN-03 — Storno-Workflow mit Frist (12h) — RPC + UI-Hinweis
- TRAIN-04 — 24h-Push-Reminder Cron `/api/cron/training-reminders`
- TRAIN-05 — Bahn-Übersicht im `TrainingDetailSheet`
- TRAIN-06 — `LaneStrip`-Primitive in WocheTab/MonatTab (read-only)
- TRAIN-07 — `TrainingsStatsCard` (Donut + Saison-Trainings-Count) im Profil
- TRAIN-08 — `book_training_lane` RPC-Patch: `EXCEPTION WHEN unique_violation → status='lane_just_taken'`
- TRAIN-09 (Differentiator) — Slot-Templates UI-Builder im AdminTab
- TRAIN-10 (Differentiator) — Gold-Streak-Badge "5 Wochen in Folge" im Profil

**Success Criteria** (was muss WAHR sein):
1. Spieler kann sich auf vollem Trainings-Slot auf Warteliste setzen und sieht eigene Position (z.B. "Position 2"). Bei Storno einer gebuchten Person wird Spieler-1 der Warteliste automatisch befördert und erhält Push-Notification (sichtbar in Outbox-Log oder bei aktivem Toggle).
2. Storno innerhalb 12h-Frist wird vom RPC server-side abgelehnt mit Toast "Storno-Frist überschritten"; ausserhalb der Frist funktioniert Storno + freigewordener Slot wird sofort in UI sichtbar.
3. Spieler mit Pref-Toggle `training_24h=true` erhalten 24h vor Training Push-Reminder; Cron-Log zeigt korrekte Vienna-Lokalzeit-Auslösung (kein DST-Drift).
4. Wenn zwei Spieler gleichzeitig dieselbe freie Bahn klicken, sieht der Verlierer-Browser einen Toast "Bahn gerade vergeben" statt einem 500er-Fehler (TRAIN-08 Race-UX-Verifikation).
5. Profil-Tab zeigt Trainings-Donut "X von Y Trainings besucht" + bei 5+ Wochen Konstanz Gold-Streak-Badge mit `--color-secondary`-Token.
6. WocheTab/MonatTab zeigen Bahn-Belegung pro Slot als `LaneStrip` (read-only farbcodiert nach Belegungs-Status).
7. Captain kann im AdminTab wiederkehrende Slot-Templates definieren ("Mo 18-20 Uhr, alle 2 Bahnen"); neue Slots werden ab Definitionsdatum automatisch im Kalender angezeigt.

**Key risks:**
- LaneStrip in MonatTab könnte visuell brechen — Designer-Spec vor Frontend-Implementation ist hartes Gate.
- Push via `push_outbox` (Phase 3) noch nicht live → Phase-2-Auto-Promote muss Direct-Fire-Fallback haben oder seriell hinter Phase 3 schieben.
- 12h-Storno-Frist ist Captain-Policy-Entscheidung (Frist-Wert in Plan-Phase final mit Captain abstimmen).

**UI hint**: yes
**Plans:** TBD

---

### Phase 3: Events + Polls + Push systematisch

**Status:** Planned
**Goal:** `push_outbox` ist die zentrale Reminder-Infra (browser-`setTimeout` ersetzt); Spieler RSVPen Vereinsabende/Ausflüge mit Status + Kommentar; Captain erstellt Polls (Text + Time) mit Vote-Once-Schutz; jedes neue Event löst systematisch Fan-Out-Push aus (statt ad-hoc); Push-Settings sind pro Event-Typ steuerbar; GCal-Sync skipped Match-Tag-Events nicht mehr fälschlicherweise.

**Depends on:** Phase 0 (`PUSH_PREFS`, TZ-Helper, `is_demo`), Phase 1 (`imgPath()` für RSVP-Avatare, Storage-Bucket geteilt für Event-Cover)
**Parallel-eligible:** Optional parallel zu Phase 2 wenn Executor-Kapazität (disjunkte UI: Event-Sheets/Polls vs. Training-Sheets). **Default: seriell nach Phase 2** — Phase 2 Auto-Promote nutzt `push_outbox` aus dieser Phase, also entweder seriell ODER Phase 2 baut Direct-Fire-Push als Übergangs-Fallback.
**Duration:** 5-6 Tage

**Requirements:**
- EVT-01 — Migration `push_outbox` + Index `WHERE sent_at IS NULL`
- EVT-02 — `/api/cron/scheduled-push` (alle 15min, idempotent)
- EVT-03 — Migration `polls.target_event_id` FK + `poll_options.target_kind`
- EVT-04 — Vote-Once-PK + RLS `WITH CHECK (now() < closes_at)` auf `poll_responses`
- EVT-05 — `events.type`-Enum erweitern + Color-Code je Typ
- EVT-06 — `event_rsvps`-Tabelle/Erweiterung (Status + Kommentar) + RLS write-own
- EVT-07 — RSVP-Liste im `EventDetailSheet` (Avatar-Reihe + Kommentare)
- EVT-08 — `EventCreateSheet` erweitert (Reminder-Toggle + Poll-Verweis)
- EVT-09 — `PollCreateSheet` NEU
- EVT-10 — `PollCard` Voting-UI mit Result-Bars + animiertem Vote-Counter
- EVT-11 — Push systematisch bei neuem Event (Fan-Out via `push_outbox`)
- EVT-12 — Event-Reminder-Cron (24h vor Event für Nicht-Antworter)
- EVT-13 — Push-Settings pro Event-Typ in EinstellungenTab
- EVT-14 — GCal-Dup-Guard-Refactor auf `external_id`
- EVT-15 — Quiet Hours: `push_outbox`-Cron skipped 22:00-08:00 Vienna
- EVT-16 (Differentiator) — Time-Poll → Event-Auto-Erstellung (Captain-Trigger)
- EVT-17 (Differentiator) — Event-Cover-Foto / Hero-Bild
- EVT-18 (Differentiator) — Recurring Events via `events.recurrence` RRULE-Feld
- EVT-19 (Differentiator) — Carpool generalisiert auf Events (`event_id` statt `match_id`)

**Success Criteria** (was muss WAHR sein):
1. Captain erstellt einen neuen Vereinsabend mit Reminder-Toggle = on; alle Spieler mit `event_new=true`-Pref erhalten innerhalb 15min-Cron-Cycle einen Push (sichtbar in `push_outbox.sent_at`).
2. Spieler RSVPen mit Status (Zusage/Absage/Vielleicht) + Kommentar; `EventDetailSheet` zeigt Avatar-Reihe mit Status-Färbung und Kommentar-Liste; eigene RSVP ist editierbar, fremde nicht.
3. Captain erstellt Poll "Wann Saisonschluss-Grillen?" mit 4 Time-Optionen; Spieler stimmen ab und sehen animierte Result-Bars; Versuch eines zweiten Votes wird via Vote-Once-PK abgelehnt (Toast "Bereits abgestimmt"); Vote nach `closes_at` wird via RLS abgelehnt.
4. Push-Job um 22:30 Vienna (Quiet Hours) wird vom Cron geskipped; derselbe Job um 08:30 Vienna feuert (Quiet-Hours-Logik durch FOUND-03 TZ-Helper getrieben).
5. GCal-Vereinsabend, der zufällig auf einen Match-Tag fällt, wird NICHT mehr fälschlicherweise vom Pull-Cron geskipped (Verifikation via Test-Event in Staging-GCal); Dup-Guard greift jetzt über `external_id`.
6. Time-Poll mit "Vereinsabend nächste Woche" und Ergebnis "Mittwoch 19:00" lässt Captain via Sheet-Aktion direkt Event aus winning option erzeugen (EVT-16); Event landet im Kalender + GCal.
7. Event-Cover-Foto wird im EventCard + EventDetailSheet als Hero-Bild gerendert (Storage-Bucket geteilt mit SELF-03).
8. Spieler kann in EinstellungenTab Push-Toggles pro Event-Typ einzeln aktivieren/deaktivieren (`event_new`, `event_reminder`, `poll_close`, `training_24h`); Toggle-OFF stoppt Pushes innerhalb 1 Cron-Cycle.

**Key risks:**
- `push_outbox`-Cron muss idempotent gegen Vercel-Retry-Storms bleiben — `sent_at IS NULL`-Filter + DB-Lock-Pattern in Plan-Phase präzisieren.
- `EventCreateSheet`-Erweiterung darf bestehenden GCal-Push-Flow nicht brechen (additive Felder only — Smoke-Test gegen Live-GCal).
- EVT-19 (Carpool-Refactor `match_id` → `event_id`) berührt Spielbetrieb-Carpool — Smoke-Test vor Deploy obligatorisch (existierende Match-Carpools müssen migrierbar sein).
- GCal-Edge-Case (Open Question 5): existierende skipped Events brauchen Backfill-Strategie — Research vor Phase-3-Plan.

**UI hint**: yes
**Plans:** TBD

---

### Phase 4: Statistik-Dashboards

**Status:** Planned
**Goal:** Spieler sehen ihren Saison-Schnitt mit Form-Kurve und Trend-Indikator auf eigenem Profil; Mannschafts-Schnitt-Vergleichslinie zeigt "Bin ich besser/schlechter?"; Liga-Tabelle (Captain-manuell + Mock für JHV) animiert die KVWN-Reihe; persönliche Bestleistung + Bahn-Statistik (falls Schema vorhanden) liefern JHV-WOW-Wirkung. Alle Aggregate in DB-Views — niemals Client-Reduce.

**Depends on:** Phase 0 (`is_demo`-Flag für Mock-Liga), Phase 1 (Foto in PlayerStatsView), Phase 2 (`view_player_training_count` aus TrainingsStatsCard)
**Parallel-eligible:** Nein — verbraucht Outputs aus Phase 1 + 2
**Duration:** 5-6 Tage

**Requirements:**
- STAT-01 — Migration View `view_player_season_stats` (AVG/COUNT/MIN/MAX)
- STAT-02 — Migration View `view_player_training_count`
- STAT-03 — Migration `league_standings`-Tabelle + RLS (Captain-write, all-read)
- STAT-04 — Schema-Härtung: `season`-Spalte gegen Cross-Saison-Mix
- STAT-05 — Mock-Liga-Tabelle-Seed mit `is_demo=true` für JHV
- STAT-06 — AdminUI in `AdminTab` zum manuellen Befüllen `league_standings`
- STAT-07 — RPC `compare_seasons(int, int)`
- STAT-08 — `StatsView` mit 3 Sub-Tabs (mannschaft \| spieler \| liga) via lokalem `$state`-PillSwitcher
- STAT-09 — `PlayerStatsView` — Saison-Schnitt + Form-Sparkline
- STAT-10 — Persönliche Bestleistung-Card
- STAT-11 — Mannschafts-Schnitt-Vergleichslinie im `PlayerStatsView`
- STAT-12 — `LeagueTableCard`
- STAT-13 — Mini-Stats-Card auf `/profil` (Reuse `PlayerStatsView`)
- STAT-14 (Differentiator) — Form-Trend-Indikator "↑ +12% letzte 5 Spiele" (SMA-5 vs SMA-10)
- STAT-15 (Differentiator) — Saison-Highlights-Card "Bestes Spiel"
- STAT-16 (Differentiator) — Liga-Tabellen-Animation (eigene Reihe pulsiert via `@keyframes`)
- STAT-17 (Differentiator) — Bahn-Statistik "Auf Bahn 3 +8%" — **PREREQUISITE: `match_results.lane_id` verifizieren; falls fehlt → Cut auf v1.1**

**Success Criteria** (was muss WAHR sein):
1. Spieler öffnet `/spielbetrieb?subtab=statistiken` → PillSwitcher zeigt 3 Sub-Tabs (mannschaft/spieler/liga); Wechsel ist instant via lokalem `$state` (kein PAGE_CONFIG-Eintrag).
2. `PlayerStatsView` zeigt Spieler-Foto (aus Phase 1 SELF-05), Saison-Schnitt-Zahl, Form-Sparkline der letzten 10 Spiele und Mannschafts-Schnitt-Vergleichslinie als horizontaler Reference-Line auf der Sparkline.
3. Form-Trend-Indikator zeigt SMA-5 vs SMA-10 als Pfeil-Icon mit Color-Token (`--color-success` für ↑, `--color-danger` für ↓) und Prozent-Wert.
4. `LeagueTableCard` zeigt Liga-Tabelle mit Rang/Mannschaft/Spiele/Punkte/Differenz; KVWN-Reihe pulsiert sanft via `@keyframes pulse-row`; Daten kommen aus `league_standings` (für JHV: Mock-Seed mit `is_demo=true`).
5. Captain öffnet AdminTab → `LeagueStandingsAdmin`-UI ermöglicht manuelles Eintragen/Editieren der Liga-Tabelle; Save persistiert in `league_standings` mit Captain's Vote-Once-RLS.
6. `Profil` zeigt Mini-Stats-Card mit Saison-Schnitt + Form-Sparkline (komponenten-Reuse aus `PlayerStatsView`, kein doppelter View-Code).
7. Persönliche Bestleistung-Card zeigt MAX-Score + Datum + Gegner aus `view_player_season_stats`; "Saison-Highlights" zeigt Best-Match je Saison als Card.
8. Wenn `match_results.lane_id` existiert (Open Question 1 aufgelöst): Bahn-Statistik zeigt "Auf Bahn 3 +8% gegenüber Schnitt"; falls Spalte fehlt: STAT-17 ist v1.1-cut, alle anderen STAT-Items unbeeinflusst.

**Key risks:**
- STAT-17 abhängig von Schema-Verify (Open Question 1) — Plan-Phase muss zuerst Researcher-Sweep machen.
- Schema-Migration `season`-Spalte (STAT-04) auf Bestandsdaten ist riskant — Backfill-Strategie in Plan-Phase präzisieren.
- Liga-Tabelle Punkte-Logik (Open Question 2) braucht Captain-Validierung vor STAT-06-Bau.

**UI hint**: yes
**Plans:** TBD

---

### Phase 5: Demo-Härtung + Reviewer-Pass

**Status:** Planned
**Goal:** JHV-Demo läuft auf einer reproduzierbaren, snapshotted Datenbasis mit verifizierten Pitfall-Fixes; Reviewer-Pass über alle Phase-1-4-Diffs ist abgeschlossen; Demo-Account ist read-only; Cleanup-Migration für post-JHV-Bereinigung der `is_demo`-Mocks liegt deploybar vor; alle "Looks Done But Isn't"-Items sind abgehakt.

**Depends on:** Alle Phase 1-4 abgeschlossen (Reviewer braucht stable Diffs)
**Parallel-eligible:** Nein — Reviewer-Findings können Re-Work in Phase 1-4 triggern
**Duration:** 2-3 Tage (inkl. Buffer für Re-Work-Loops)

**Requirements:**
- DEMO-01 — DB-Snapshot 3 Tage vor JHV (Supabase Pro Backup + lokale Kopie)
- DEMO-02 — Demo-Login = read-only-Account (keine Captain-Rolle)
- DEMO-03 — Cleanup-Migration `DELETE … WHERE is_demo` vorbereitet
- DEMO-04 — Reviewer-Pass über alle Phase-1-4-Diffs
- DEMO-05 — Smoke-Test `push_outbox` 1-Minuten-Reminder vor JHV (TZ-Verify)
- DEMO-06 — exiftool-Test auf 5 Sample-Avatars (EXIF-strip-Verify)
- DEMO-07 — Concurrent-Booking-Test mit zwei Sessions (TRAIN-08-Verify)
- DEMO-08 — Push-Subscription-Cleanup-Cron initial deployen
- DEMO-09 — Vollständige "Looks Done But Isn't"-Checklist (10 Items)
- DEMO-10 — Demo-Account-Login-Pfad dokumentieren

**Success Criteria** (was muss WAHR sein):
1. DB-Snapshot ist 2026-05-19 (3 Tage vor JHV) gezogen; Restore-Test in Staging-Project läuft erfolgreich durch (Daten + RLS + Migrations identisch).
2. Demo-Account `demo@kvwn.local` ist konfiguriert mit `role='user'` (nicht `kapitaen`); manueller Test: Login als Demo-Account zeigt keine Captain-Tabs/Aktionen.
3. Cleanup-Migration `DELETE FROM <tabellen> WHERE is_demo` ist als unmerged Migration im Repo, getestet gegen Staging-Snapshot — Production-Run wird post-JHV manuell freigegeben.
4. Reviewer-Pass-Report ist verfasst: alle Phase-1-4-Diffs durchgegangen, 0 BLOCK-Findings offen, alle PROCEED-WITH-FIXES-Findings sind committed; Reviewer-Verdict = APPROVE.
5. `exiftool` über 5 zufällig ausgewählte hochgeladene Avatare zeigt 0 GPS-Tags (DSGVO-Compliance verifiziert).
6. Concurrent-Booking-Test: zwei Browser-Sessions buchen gleichzeitig dieselbe Bahn; Verlierer sieht "Bahn gerade vergeben"-Toast (kein 500er); `book_training_lane`-RPC-Patch funktioniert wie spezifiziert.
7. 1-Minuten-Reminder-Outbox-Test: `push_outbox`-Eintrag mit `send_at = now() + 1 min` Vienna-local wird vom Cron innerhalb des nächsten Cycles abgesendet; manuelles DST-Boundary-Simulation zeigt keine Drift.
8. Push-Subscription-Cleanup-Cron läuft 1× pro Tag und entfernt 410-Gone-Subscriptions aus DB (Pitfall C12); Cron-Log zeigt erfolgreiche Erstläufe.
9. "Looks Done But Isn't"-Checklist (10 Items aus PITFALLS.md) ist 10/10 abgehakt; jeder Item hat verifizierten Beleg (Screenshot/Log/Test).
10. Demo-Login-Pfad ist dokumentiert in `.planning/JHV-DEMO.md` (oder ähnlich): URL, Account, Demo-Reihenfolge der Features, Backup-Plan bei Live-Issues.

**Key risks:**
- Reviewer-Findings könnten Re-Work in Phase 1-4 triggern → Buffer ist 2-3 Tage; bei mehr Findings wird Phase 5 zur Engstelle.
- Snapshot-Restore-Test in Staging muss vor 2026-05-19 mindestens 1× geprobt sein (Pitfall C15).
- Demo-Account-Setup ist Operational, leicht vergessen — DEMO-10 als finaler Checkpoint.

**Plans:** TBD

---

## Dependency Graph

```
                    ┌─────────────────────────────────┐
                    │ Phase 0: Cross-Cutting Founda-  │
                    │ tions (BLOCKER für alle)        │
                    │ FOUND-01..07 · 2 d              │
                    └────────────────┬────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────┐
                    │ Phase 1: Selfservice + Foto +   │
                    │ Consent · SELF-01..12 · 4-5 d   │
                    │ (blocks Phase 3 Avatare,        │
                    │  Phase 4 PlayerStatsView)       │
                    └────────────────┬────────────────┘
                                     │
                          ┌──────────┴──────────┐
                          │                     │
                ┌─ default seriell ─┐  ┌─ optional parallel ─┐
                │                   │  │                     │
                ▼                   │  │                     ▼
    ┌──────────────────────┐        │  │        ┌──────────────────────┐
    │ Phase 2: Training    │        │  │        │ Phase 3: Events +    │
    │ Vollausbau           │        │  │        │ Polls + Push         │
    │ TRAIN-01..10 · 4-5 d │        │  │        │ EVT-01..19 · 5-6 d   │
    └──────────┬───────────┘        │  │        └──────────┬───────────┘
               │                    │  │                   │
               └────────────────────┴──┴───────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────┐
                    │ Phase 4: Statistik-Dashboards   │
                    │ STAT-01..17 · 5-6 d             │
                    │ (verbraucht Phase 1+2 Outputs)  │
                    └────────────────┬────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────┐
                    │ Phase 5: Demo-Härtung +         │
                    │ Reviewer-Pass                   │
                    │ DEMO-01..10 · 2-3 d             │
                    └─────────────────────────────────┘
                                     │
                                     ▼
                            JHV 2026-05-22
```

**Parallel-Hinweis:** Phase 2 und Phase 3 sind disjunkt in UI-Files (Training-Sheets vs. Event-Sheets/Polls). Wenn Executor-Kapazität verfügbar ist, können sie parallel laufen — Einsparung 4-5 Tage. **Default-Empfehlung: seriell** (Phase 2 → Phase 3), weil Phase 2's Auto-Promote (TRAIN-02) auf `push_outbox` aus Phase 3 angewiesen ist; entweder seriell ODER Phase 2 baut Direct-Fire-Push als Übergangs-Fallback.

---

## Out of Scope (v1)

Vollständige Liste mit Begründung + Ziel-Version: siehe `.planning/REQUIREMENTS.md` § "Out of Scope (v1)" und § "Differentiator-Cuts".

**Hard out of scope (PROJECT.md):** Multi-Tenant, öffentliche Sponsor-Webseite, Marketing-Page, Stack-Replace, Tests/Lint/Format.

**Cut from v1 (deferred):** Familien/Gäste read-only-Tier (v2), eigene Turniere (v2), interne Vereinsmeisterschaften (v2), Sponsoren-Pflege intern (v2), Kantinen-Besetzung (v2), Vereinsfinanzen (v2), Live-Score Kegel-für-Kegel (v2), Lagerstand Kantine (v3).

**Differentiator-Cuts (Step-7-Decisions):** VCard-Export (v1.1), In-App-Foto-Capture (v1.1), "Heute frei?"-Spotlight (v1.1), "Wer ist dabei"-Avatar-Reihe (v1.1), Saison-Wrapped Story-Card (v1.5), Cross-Saison-Vergleich (v1.1), Heatmap Wochentage (v1.1), Photo-Pinwand (v2), Draft-Mode Events (v1.1), geheime Abstimmungen (nie), bezahlte Events (v2), Event-Chat (nie), externe Gäste-Tokens (nie), ELO-Rating (nie), Predictive Analytics (nie), Cross-Verein-Vergleich (nie).

---

## Open Questions (Track during Plan-Phase)

Übernommen aus REQUIREMENTS.md § "Open Questions" — propagiert für Plan-Phase-Auflösung.

1. **`match_results.lane_id`-Spalte exists?** STAT-17 (Bahn-Statistik) hängt davon ab. **Action:** Researcher-Sweep in Phase 4 Plan-Phase. Falls fehlt → STAT-17 cut auf v1.1.
2. **`league_standings`-Punkte-Logik** (2:0=2pkt etc.) noch nicht mit Captain validiert. **Action:** Captain-Rückfrage in Phase 4 Plan-Phase.
3. **PLAYER_FIELDS unverified** (MEMORY → `project_player_fields_unverified.md`). **Action:** Researcher-Sweep vor Phase 1 Frontend-Dev (siehe SELF-01).
4. **DSGVO-`/privacy`-Seitentext** ist text-driven, kein Code-Task. **Action:** Vorstand-Workflow für Gegenlesen vor Phase 1 klären (siehe SELF-08).
5. **GCal-Dup-Guard-Refactor (EVT-14)** berührt Production-Sync — Edge-Cases (was passiert mit existierenden skipped Events?) brauchen kurze Research vor Phase 3.
6. **Reviewer-Phase-Kapazität** pro Phase (0.5d eingerechnet) — accommodate during Plan-Phase budgeting.

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Cross-Cutting Foundations | 0/0 | Not started | — |
| 1. Selfservice + Foto + Consent | 0/0 | Not started | — |
| 2. Trainingsbuchung-Vollausbau | 0/0 | Not started | — |
| 3. Events + Polls + Push systematisch | 0/0 | Not started | — |
| 4. Statistik-Dashboards | 0/0 | Not started | — |
| 5. Demo-Härtung + Reviewer-Pass | 0/0 | Not started | — |

---

*Roadmap generated: 2026-04-29 (Step 8 of `/gsd-new-project`)*
*Source REQs: `.planning/REQUIREMENTS.md` (75 v1-Reqs, 6 categories)*
*Source rationale: `.planning/research/SUMMARY.md` (lines 100-220)*
*Coverage: 75/75 mapped, 0 orphaned, 0 duplicated*
