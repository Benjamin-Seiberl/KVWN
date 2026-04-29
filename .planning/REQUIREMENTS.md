# KVWN v1 Requirements

**Project:** KVWN Vereins-App (PWA für KV Wiener Neustadt)
**Milestone:** v1 (JHV-Demo 2026-05-22)
**Defined:** 2026-04-29
**Source:** `.planning/PROJECT.md` (Vision) + `.planning/research/SUMMARY.md` (6-phase structure) + `.planning/research/FEATURES.md` (table-stakes/differentiators) + `.planning/research/PITFALLS.md` (foundation guards)

---

## Reading Guide

- **REQ-IDs** use 6 categories matching the 6-phase roadmap: `FOUND-` (Phase 0), `SELF-` (Phase 1), `TRAIN-` (Phase 2), `EVT-` (Phase 3), `STAT-` (Phase 4), `DEMO-` (Phase 5).
- **All v1 requirements are MUST-have for JHV-Demo 2026-05-22.** Differentiators picked during scoping (Step 7, 2026-04-29) are listed but explicitly tagged.
- **Out-of-Scope** at the bottom captures cut-from-v1 features with rationale + target version.
- **Traceability** section is empty — filled by `gsd-roadmapper` during Step 8.

---

## v1 Requirements

### FOUND — Cross-Cutting Foundations (Phase 0, NON-NEGOTIABLE)

Resolves the two BLOCKER pitfalls (C1 RLS-cross-write, C3 cron-TZ-drift) and lays cross-cutting helpers used by every Feature-Phase. If skipped, every Feature-Phase becomes either unsafe or duplicates the same plumbing 4×.

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| FOUND-01 | Migration `players.email NOT NULL UNIQUE` + lower()-Normalisierung + Pre-Deploy-Audit-Script | PITFALLS C1 | Audit `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL` muss 0 zurückgeben vor Deploy |
| FOUND-02 | RLS-Policy-Refactor `players` mit `WITH CHECK (id = …)`-Pin auf self-update | PITFALLS C1 | Verhindert Cross-Spieler-Writes wenn Selfservice-Schreibrechte aktiv werden |
| FOUND-03 | `$lib/server/timezone.js` mit `nowVienna()` / `dateInVienna(offsetDays)` Helper | PITFALLS C3 | `Intl.DateTimeFormat('de-AT', { timeZone: 'Europe/Vienna' })`-basiert |
| FOUND-04 | Refactor existing `lineup-reminders`-Cron auf TZ-Helper + `reminder_log(plan_id, kind, sent_at)`-Idempotenz-Tabelle | PITFALLS C3 | Bereits-gelivete Cron muss nachgezogen werden, sonst DST-Drift |
| FOUND-05 | `$lib/constants/pushPrefs.js` zentrale `PUSH_PREFS`-Konstante + DB-CHECK auf JSONB-Keys | PITFALLS C9 | Verhindert Push-Opt-Out-Bypass via Tippfehler |
| FOUND-06 | `is_demo BOOLEAN DEFAULT false` Pattern-Doku + Migration-Vorlage für alle neuen v1-Tabellen | PITFALLS C10 | Production-Views filtern `WHERE NOT is_demo`; vermeidet Mock-Daten-Cleanup-Trap |
| FOUND-07 | `$lib/utils/imageResize.js` Browser-Canvas-Resize-Helper (512×512 WebP, EXIF-strip) | PITFALLS C6 | iPhone-EXIF-GPS = DSGVO Art.5(1)(c)-Verstoß ohne Strip |

**Avoids:** C1, C3, C6, C9, C10 + partial C5/C11.
**Duration estimate:** 2 Tage.

---

### SELF — Spieler-Selfservice + Foto + Consent (Phase 1)

Spieler tragen Stammdaten selbst ein, laden Profilfoto über Storage-Bucket hoch, geben DSGVO-Einwilligungen explizit ab. Captain ist nur noch für initialen Invite zuständig.

#### Tablestakes

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| SELF-01 | Migration `players`-Schema verifizieren — fehlende Spalten ergänzen (Telefon, Geburtstag, Adresse, Notfallkontakt-Name, Notfallkontakt-Telefon, Lizenz-Nummer) | FEATURES F2 + MEMORY → player_fields_unverified | Researcher-Sweep vor Frontend-Dev (PLAYER_FIELDS in `profil/UebersichtTab` referenzierte Spalten) |
| SELF-02 | `ProfilDatenSheet` mit valibot-Validation, alle Felder editierbar, RLS write-own-row | FEATURES F2 | Eigenes-row-Pin via FOUND-02 |
| SELF-03 | Migration: Storage-Bucket `player-photos` (public-read, write-own RLS) + `players.photo_url`-Spalte | FEATURES F2 + ARCH | Bucket geteilt mit EVT-17 (Event-Cover) |
| SELF-04 | `ProfilFotoSheet` NEU mit FOUND-07-Resize-Pipeline (EXIF-strip, 512×512 WebP, octet_length<200000-Constraint) | FEATURES F2 + PITFALLS C6 | Datei-Picker reicht für JHV — In-App-Capture ist Out-of-Scope |
| SELF-05 | `imgPath()` Storage-Branch + Fallback-Kette (`photo_url` → static/images → BLANK_IMG) | ARCH | Smoke-Test alle bestehenden Lineup-Listen (Risiko: alte Avatare) |
| SELF-06 | Profil-Vervollständigungs-Score — Progress-Ring im `ProfilHeroCard` aus `$derived` über Pflicht-Felder | FEATURES F2 | TeamSnap-Pattern, KVWN spielerischer |
| SELF-07 | DSGVO-Consent-Onboarding-Modal blockt Profil-Editing bis `consent_photo` / `consent_liga_data` / `consent_whatsapp` / `consent_accepted_at` gesetzt | PITFALLS C7 | Bestehende Spalten existieren, Workflow fehlt; Foto-Upload disabled wenn `consent_photo=false` |
| SELF-08 | Statische `/privacy`-Seite (Vorstand-textlich gegenliest, kein Code-Task außer Mounting) | PITFALLS C7 | Text-Workflow für Vorstand vor Phase 1 klären |
| SELF-09 | Datenschutz-Hinweis-Banner im Edit-Sheet ("Diese Daten sehen Kapitän + dein Konto") | FEATURES F2 | DSGVO-Transparenz |
| SELF-10 | Widerruf-Pfad in EinstellungenTab (Consent zurückziehen) | PITFALLS C7 | DSGVO Art.7 |

#### Differentiators (Step-7-Picks)

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| SELF-11 | Geburtstags-Banner Auto-Card im Dashboard `/neuigkeiten` (`Heute hat X Geburtstag`) | FEATURES F2 differentiator | S-Aufwand, soziale Wärme; nutzt SELF-01 Geburtstag-Spalte |
| SELF-12 | Konfetti-Animation bei 100% Profil-Score (CSS-keyframes) | FEATURES F2 differentiator | S-Aufwand, JHV-WOW-Faktor |

**Avoids:** C2, C6, C7, C11.
**Duration estimate:** 4-5 Tage.

---

### TRAIN — Trainingsbuchung-Vollausbau (Phase 2)

Warteliste mit Auto-Promote, 24h-Reminder, Trainings-Statistik, Slot-Templates, Storno-Frist, Bahn-Übersicht im Kalender.

#### Tablestakes

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| TRAIN-01 | `TrainingDetailSheet` Warteliste-UI ("Auf Warteliste"-Button + position-Anzeige bei vollem Slot) | FEATURES F1 | Daten-Modell `training_waitlist` existiert, UI fehlt |
| TRAIN-02 | Auto-Promote-RPC `promote_waitlist_on_cancel(p_date, p_start)` + Push-Trigger via `push_outbox` (EVT-01) | FEATURES F1 | Industry-Standard (Spond/ClubPal); ohne Auto-Promote = totes Datenfeld |
| TRAIN-03 | Storno-Workflow mit Frist (12h vorher) — `cancel_training_booking` RPC ergänzen + UI-Hinweis | FEATURES F1 | Server-side prüfen, nicht client-side |
| TRAIN-04 | 24h-Push-Reminder Cron `/api/cron/training-reminders` (täglich 09:00 Vienna via FOUND-03/04) | FEATURES F1 | Push-Pref-Toggle "training_24h" in EinstellungenTab via FOUND-05 |
| TRAIN-05 | Bahn-Übersicht im `TrainingDetailSheet` (alle Bahnen + Belegung sichtbar) | FEATURES F1 | Polish-Aufgabe, Komponente teilweise vorhanden |
| TRAIN-06 | `LaneStrip`-Primitive in WocheTab/MonatTab (read-only Belegungs-Visualisierung) | ARCH | Designer-Spec vor Frontend-Dev |
| TRAIN-07 | `TrainingsStatsCard` (Donut "X von Y Trainings besucht" + Saison-Trainings-Count) im Profil | FEATURES F1 | Aggregation aus `view_player_training_count` (STAT-02) |
| TRAIN-08 | `book_training_lane` RPC-Patch: `EXCEPTION WHEN unique_violation → status='lane_just_taken'` | PITFALLS C8 | Booking-Race-UX: zweiter Booker bekommt sauberen Toast statt 500 |

#### Differentiators (Step-7-Picks)

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| TRAIN-09 | Slot-Templates UI-Builder im AdminTab (Captain definiert wiederkehrende Slots Mo 18-20 etc.) | FEATURES F1 differentiator | M-Aufwand; `training_templates`-Schema existiert bereits, UI fehlt |
| TRAIN-10 | Gold-Streak-Badge "5 Wochen in Folge" im Profil — Berechnung aus `training_bookings`, Gold-Token-CSS (`--color-secondary`) | FEATURES F1 differentiator | S-Aufwand, Gamification light |

**Avoids:** C8.
**Duration estimate:** 4-5 Tage.

---

### EVT — Events + Polls + Push systematisch (Phase 3)

Push-Outbox-Pattern als zentrale Reminder-Infra. Polls (Text + Time) mit Voting. Event-RSVPs systematisch. Push bei jedem neuen Event statt ad-hoc.

#### Tablestakes

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| EVT-01 | Migration `push_outbox(send_at, target_kind, target_id, target_player_ids, payload, pref_key, sent_at, sent_count)` + Index `WHERE sent_at IS NULL` | ARCH | Scheduled-push-Queue, browser-`setTimeout` ersetzt |
| EVT-02 | `/api/cron/scheduled-push` (alle 15min, idempotent via `sent_at IS NULL`, ruft `/api/push/notify`) | ARCH | Vercel-Cron Pro-Tier (laut MEMORY confirmed) |
| EVT-03 | Migration `polls.target_event_id` FK + `poll_options.target_kind` (formalisiert bestehendes Schema) | ARCH | `EventDetailSheet` zeigt nur Polls mit `target_event_id = ev.id` |
| EVT-04 | Vote-Once-PK + RLS `WITH CHECK (now() < closes_at)` auf `poll_responses` | PITFALLS C5 | Verhindert Poll-Vote-Manipulation |
| EVT-05 | `events.type`-Enum erweitern + Color-Code je Typ (Vereinsabend, Ausflug, Saisonschluss, Sitzung) | FEATURES F4 | UI-Color-Variable je Typ |
| EVT-06 | `event_rsvps`-Tabelle/Erweiterung — Status (Zusage/Absage/Vielleicht) + Kommentar-Feld + RLS write-own | FEATURES F4 | Migration `20260427_event_rsvps.sql` existiert teilweise |
| EVT-07 | RSVP-Liste im `EventDetailSheet` (Avatar-Reihe + Kommentar-Liste) | FEATURES F4 | Reuse `imgPath()` aus SELF-05 |
| EVT-08 | `EventCreateSheet` erweitert (Reminder-Toggle + optional gekoppelter Poll-Verweis) | FEATURES F4 + ARCH | Additive Felder only — bestehender GCal-Push-Flow darf nicht brechen |
| EVT-09 | `PollCreateSheet` NEU (Captain-Action am Dashboard) | FEATURES F4 | Text-Poll + Time-Poll-Modi |
| EVT-10 | `PollCard` Voting-UI mit Result-Bars + animierter Vote-Counter (CSS `transition: width`) | FEATURES F4 | Bestehende Component erweitern |
| EVT-11 | Push systematisch bei neuem Event — Trigger nach Event-Insert via `push_outbox`-Fan-Out an alle Mitglieder | FEATURES F4 | Pref-Key `event_new` (FOUND-05) |
| EVT-12 | Event-Reminder-Cron (24h vor Event für Nicht-Antworter) — nutzt `push_outbox` | FEATURES F4 | Filter `RSVP=null` |
| EVT-13 | Push-Settings pro Event-Typ in EinstellungenTab (training_24h, event_new, event_reminder, poll_close — via FOUND-05) | FEATURES F4 | Vermeidet Push-Müdigkeit |
| EVT-14 | GCal-Dup-Guard-Refactor auf `external_id` statt match-Datum-Skip | PITFALLS C14 | Sonst verschwinden Vereins-Events am Match-Tag |
| EVT-15 | Quiet Hours: `push_outbox`-Cron skipped 22:00-08:00 Vienna (FOUND-03) | FEATURES F4 cross-cutting | Push-Nachtruhe |

#### Differentiators (Step-7-Picks)

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| EVT-16 | Time-Poll → Event-Auto-Erstellung — Captain-Trigger nach Poll-Schluss erzeugt Event aus winning option | FEATURES F4 differentiator | Spond-Killer-Pattern; M-Aufwand |
| EVT-17 | Event-Cover-Foto / Hero-Bild — `events.cover_url` (Storage-Bucket geteilt mit SELF-03) | FEATURES F4 differentiator | S-Aufwand, macht Events greifbar |
| EVT-18 | Recurring Events via `events.recurrence` RRULE-Feld + GCal-Sync nimmt RRULE nativ | FEATURES F4 differentiator | M-Aufwand, Vereinsabend monatlich = Use-Case |
| EVT-19 | Carpool generalisiert auf Events — `CarpoolCard` von `match_id` auf `event_id` refactoren | FEATURES F4 differentiator | M-Aufwand; Risiko: Refactor bricht Spielbetrieb-Carpool — Smoke-Test vorher |

**Avoids:** C5, C9, C12, C14.
**Duration estimate:** 5-6 Tage.

---

### STAT — Statistik-Dashboards (Phase 4)

Saison-Schnitt + Form-Sparkline + Liga-Tabelle (Captain-manuell + Mock für JHV) + Bahn-Statistik + 4 Differentiators für JHV-WOW-Wirkung.

#### Tablestakes

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| STAT-01 | Migration View `view_player_season_stats` (AVG/COUNT/MIN/MAX über `match_results`) | ARCH | Niemals Client-Reduce |
| STAT-02 | Migration View `view_player_training_count` | ARCH | Konsumiert von TRAIN-07 |
| STAT-03 | Migration `league_standings`-Tabelle (`league_id, team_name, is_kvwn, points, season, …`) + RLS (Captain-write, all-read) | FEATURES F3 + STEP-7-DECISION | Captain-Manuell + Mock-Seed-Quelle (Step-7 confirmed) |
| STAT-04 | Schema-Härtung: `season`-Spalte oder `match_id`-FK auf `game_plans` gegen Cross-Saison-Mix | PITFALLS C4 | Rückwärts-Befüllung bei Bestandsdaten riskant — Migration vorsichtig |
| STAT-05 | Mock-Liga-Tabelle-Seed mit `is_demo=true` (FOUND-06-Pattern) für JHV-Demo | STEP-7-DECISION | PROJECT.md erlaubt Mock-Daten explizit |
| STAT-06 | AdminUI in `AdminTab` zum manuellen Befüllen `league_standings` (Captain-Tool) | STEP-7-DECISION | Punkte-Logik 2:0=2pkt etc. — Captain/Vorstand-Validierung in Plan-Phase |
| STAT-07 | RPC `compare_seasons(int, int)` (Aggregation für historische Vergleiche) | ARCH | Server-side, niemals Client-Reduce |
| STAT-08 | `StatsView` mit 3 Sub-Tabs (mannschaft \| spieler \| liga) via lokalem `$state`-PillSwitcher (kein neuer Subtab im PAGE_CONFIG) | ARCH | Pattern wie Kalender-View-Modes |
| STAT-09 | `PlayerStatsView` — Saison-Schnitt + Form-Sparkline (layerchart oder inline-SVG) | FEATURES F3 | Sparkline 0-100% historisches Max |
| STAT-10 | Persönliche Bestleistung-Card (MAX-score per Spieler aus STAT-01) | FEATURES F3 | Soziales Storytelling |
| STAT-11 | Mannschafts-Schnitt-Vergleichslinie im `PlayerStatsView` (Referenz-Linie aus STAT-01) | FEATURES F3 | "Bin ich besser/schlechter als Schnitt?" — Kern-Frage |
| STAT-12 | `LeagueTableCard` (Rang/Mannschaft/Spiele/Punkte/Differenz aus STAT-03) | FEATURES F3 | Standard Liga-Tabellen-Layout |
| STAT-13 | Mini-Stats-Card auf `/profil` (Reuse `PlayerStatsView`) | ARCH | Kein doppelter View-Code |

#### Differentiators (Step-7-Picks)

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| STAT-14 | Form-Trend-Indikator "↑ +12% letzte 5 Spiele" — SMA(5) vs SMA(10) Pfeil-Icon mit Farb-Code (`--color-success` / `--color-danger`) | FEATURES F3 differentiator | M-Aufwand, einer der stärksten JHV-WOW-Hooks |
| STAT-15 | Saison-Highlights-Card "Bestes Spiel" — Top-Match je Saison als Card mit Datum + Gegner | FEATURES F3 differentiator | S-Aufwand, sentiment-driven |
| STAT-16 | Liga-Tabellen-Animation — eigene Reihe pulsiert sanft via `@keyframes pulse-row` gated auf own team_id | FEATURES F3 differentiator | S-Aufwand, CSS-only |
| STAT-17 | Bahn-Statistik "Auf Bahn 3 +8%" — Aggregation pro `lane_id` über `match_results` | FEATURES F3 differentiator | **PREREQUISITE: `match_results.lane_id`-Spalte verifizieren in Plan-Phase. Falls fehlt → STAT-17 cut auf v1.1.** |

**Avoids:** C4, C13.
**Duration estimate:** 5-6 Tage.

---

### DEMO — Demo-Härtung + Reviewer-Pass (Phase 5)

Operational, kein Feature. Snapshot-Strategie, Reviewer-Pass über alle Phase-1-4-Diffs, Pitfall-Verifikation, Cleanup-Migration vorbereitet.

| REQ-ID | Title | Source | Notes |
|--------|-------|--------|-------|
| DEMO-01 | DB-Snapshot 3 Tage vor JHV (Supabase Pro Backup + lokale Kopie) | PITFALLS C15 | Restore-Test-Lauf in Staging vorher |
| DEMO-02 | Demo-Login = read-only-Account ohne Captain-Rolle | PITFALLS C10 | Verhindert versehentliche Demo-Edits in Produktion |
| DEMO-03 | Cleanup-Migration `DELETE … WHERE is_demo` vorbereitet (nicht ausgeführt) | PITFALLS C10 + FOUND-06 | Sommer-Rollout kann Mock-Daten clean entfernen |
| DEMO-04 | Reviewer-Pass über alle Phase-1-4-Diffs (committer-agent kann das nicht — manuelle Review nötig) | CROSS-PHASE | Nicht skippable laut PITFALLS Cross-Phase-Concern |
| DEMO-05 | Smoke-Test `push_outbox` 1-Minuten-Reminder vor JHV | PITFALLS C3-Verify | TZ-Helper End-to-End validieren |
| DEMO-06 | exiftool-Test auf 5 Sample-Avatars (EXIF strip verifizieren) | PITFALLS C6-Verify | DSGVO-Compliance |
| DEMO-07 | Concurrent-Booking-Test mit zwei Sessions (Race-UX validieren) | PITFALLS C8-Verify | TRAIN-08 funktioniert wie spezifiziert |
| DEMO-08 | Push-Subscription-Cleanup-Cron initial deployen | PITFALLS C12 | Verhindert Push an abgemeldete Subscriptions |
| DEMO-09 | Vollständige "Looks Done But Isn't"-Checklist abarbeiten | PITFALLS Zeile 617-630 | 10-Item-Checklist |
| DEMO-10 | Demo-Account-Login-Pfad dokumentieren (für JHV-Vorführung Zugang vorbereiten) | OPS | "Wie zeigen wir das?" — kein Code |

**Duration estimate:** 2-3 Tage. Reviewer-Findings können Re-Work in Phase 1-4 triggern — Buffer im 24-Tage-Budget bewusst dafür.

---

## Out of Scope (v1)

Bewusste Grenzen. Werden in Roadmap-Out-of-Scope mit Verweis auf Ziel-Version dokumentiert.

### Cut from PROJECT.md (out of scope, hard)

| Item | Reason | Target |
|------|--------|--------|
| Multi-Tenant für andere Kegelvereine | Vision ist KVWN-spezifisch, kein Plattform-Anspruch | nie |
| Öffentliche Sponsor-Webseite / SEO-Marketing | Sponsoren-Modul intern, keine öffentliche Sichtbarkeit | nie |
| Marketing-Website / KVWN-Public-Page | App ist Vereins-internes Tool | nie |
| Replace bestehender Stack | SvelteKit + Supabase + Vercel locked | nie |
| Tests/Lint/Format-Toolchain | Velocity > Ceremony | nie |

### Cut from v1 (deferred)

| Item | Reason | Target |
|------|--------|--------|
| **Familien/Gäste read-only-Tier** (eigenes `players.tier`-Schema) | Step-7-Decision: Funktional erst nach v1 nötig (FEATURES.md). Schema + RLS-Tier-Logic ist eigenes Projekt. Spart 3-4 Tage. | v2 |
| Eigene Turniere organisieren | PROJECT.md v2-Roadmap | v2 |
| Interne Vereinsmeisterschaften | PROJECT.md v2-Roadmap | v2 |
| Sponsoren-Pflege intern | PROJECT.md v2-Roadmap | v2 |
| Kantinen-Besetzung | PROJECT.md v2-Roadmap | v2 |
| Vereinsfinanzen (Beiträge/Strafen/Trainingsgebühren) | PROJECT.md v2-Roadmap. DSGVO + SEPA = eigenes Projekt | v2 |
| Live-Score Kegel-für-Kegel | PROJECT.md v2-Roadmap. Hardware-fragil | v2 |
| Lagerstand Kantine | PROJECT.md v3-Roadmap | v3 |

### Differentiator-Cuts (Step-7-Decisions)

| Item | Reason | Target |
|------|--------|--------|
| F2 — VCard-Export Notfallkontakt | Step-7-Decision: niemand exportiert in Praxis | v1.1 |
| F2 — In-App-Foto-Capture (`getUserMedia`) | Step-7-Decision: Datei-Picker reicht für Demo, iOS-Safari-Edge-Cases nicht-trivial | v1.1 |
| F1 — "Wer ist heute Abend dabei"-Avatar-Reihe | Step-7-Decision: nicht gepickt | v1.1 |
| F1 — "Heute frei?"-Spotlight am Dashboard | Step-7-Decision: Demo-Daten zeigen oft leere Slots → CTA wirkt unsouverän | v1.1 |
| F3 — Saison-Wrapped Story-Card | FEATURES.md cut (post-Saison-Endpunkt, eigene Story-UI) | v1.5 |
| F3 — Cross-Saison-Vergleich | FEATURES.md cut | v1.1 |
| F3 — Heatmap Wochentage | FEATURES.md cut (Datenvolumen dünn Sa/So-fokussiert) | v1.1 |
| F4 — Photo-Pinwand pro Event | FEATURES.md cut (Storage-Kosten + Moderation) | v2 |
| F4 — Draft-Mode Events | FEATURES.md cut | v1.1 |
| F4 — Geheime Abstimmungen (anonym) | FEATURES.md cut (DSGVO + Crypto-Voting eigene Welt) | nie |
| F4 — Bezahlte Events | FEATURES.md cut (Vereinsfinanzen v2) | v2 |
| F4 — Event-Chat / Kommentar-Thread | FEATURES.md cut (WhatsApp-Konkurrenz, Moderation) | nie |
| F4 — Externe Gäste-Einladung via Token | FEATURES.md cut (eigene Auth-Architektur nötig) | nie |
| ELO-Rating zwischen Spielern | FEATURES.md cut (Kegeln nicht 1v1, falsch konzipiert) | nie |
| Predictive Analytics | FEATURES.md cut (Datenvolumen reicht nicht, falsche Prognosen schaden) | nie |
| Cross-Verein-Vergleich | Multi-Tenant out-of-scope | nie |

---

## Open Questions (Track during Plan-Phase)

Aus HANDOFF.md übernommen — nicht alle in Step 7 auflösbar, brauchen Phase-Plan-Phase oder Captain-Rückfrage.

1. **`match_results.lane_id`-Spalte exists?** STAT-17 (Bahn-Statistik) hängt davon ab. **Action:** Researcher-Sweep in Phase 4 Plan-Phase. Falls fehlt → STAT-17 cut auf v1.1.
2. **`league_standings`-Punkte-Logik** (2:0=2pkt etc.) noch nicht mit Captain validiert. **Action:** Captain-Rückfrage in Phase 4 Plan-Phase.
3. **PLAYER_FIELDS unverified** (MEMORY → `project_player_fields_unverified.md`). **Action:** Researcher-Sweep vor Phase 1 Frontend-Dev (siehe SELF-01).
4. **DSGVO-`/privacy`-Seitentext** ist text-driven, kein Code-Task. **Action:** Vorstand-Workflow für Gegenlesen vor Phase 1 klären (siehe SELF-08).
5. **GCal-Dup-Guard-Refactor (EVT-14)** berührt Production-Sync — Edge-Cases (was passiert mit existierenden skipped Events?) brauchen kurze Research vor Phase 3.
6. **Reviewer-Phase-Kapazität** pro Phase (0.5d eingerechnet) — accommodate during Plan-Phase budgeting.

---

## v2 / v3 / Future (Backlog)

### v2 (post-JHV, Q3-Q4 2026)
- Familien/Gäste read-only-Tier (Schema + RLS)
- Eigene Turniere + Vereinsmeisterschaften
- Sponsoren-Pflege intern (Akquise-Tasks, Kontaktdaten)
- Kantinen-Besetzung
- Vereinsfinanzen (Beiträge/Strafen/Trainingsgebühren)
- Live-Score Kegel-für-Kegel während Match
- Photo-Pinwand pro Event

### v1.1 (Q3 2026 — Quick Wins post-JHV)
- VCard-Export, In-App-Foto-Capture, "Heute frei?"-Spotlight, "Wer ist dabei"-Avatar-Reihe
- Cross-Saison-Vergleich, Heatmap Wochentage, Bahn-Statistik (falls Schema vorhanden)
- Draft-Mode Events, Liga-Tabelle live (ÖSKB-Feed-Import)

### v1.5 (post-Saison-Endpunkt)
- Saison-Wrapped Story-Card

### v3 (2027+)
- Lagerstand Kantine

---

## Coverage Summary

| Category | Count | Notes |
|----------|-------|-------|
| FOUND | 7 | Phase 0 cross-cutting, non-negotiable |
| SELF | 12 | Phase 1 — 10 tablestakes + 2 differentiators |
| TRAIN | 10 | Phase 2 — 8 tablestakes + 2 differentiators |
| EVT | 19 | Phase 3 — 15 tablestakes + 4 differentiators |
| STAT | 17 | Phase 4 — 13 tablestakes + 4 differentiators |
| DEMO | 10 | Phase 5 operational |
| **Total v1** | **75** | Mapped to 6 phases by `gsd-roadmapper` in Step 8 |

---

## Traceability

Filled by `gsd-roadmapper` (Step 8, 2026-04-29). Each REQ-ID is mapped to exactly one phase. Plan-Slot column will be populated by `/gsd-plan-phase <N>` as plans are created.

**Coverage check:** 75 / 75 REQs mapped · 0 orphaned · 0 duplicated.

### Phase 0 — Cross-Cutting Foundations (FOUND, 7 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| FOUND-01 | Phase 0 | — |
| FOUND-02 | Phase 0 | — |
| FOUND-03 | Phase 0 | — |
| FOUND-04 | Phase 0 | — |
| FOUND-05 | Phase 0 | — |
| FOUND-06 | Phase 0 | — |
| FOUND-07 | Phase 0 | — |

### Phase 1 — Spieler-Selfservice + Foto + Consent (SELF, 12 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| SELF-01 | Phase 1 | — |
| SELF-02 | Phase 1 | — |
| SELF-03 | Phase 1 | — |
| SELF-04 | Phase 1 | — |
| SELF-05 | Phase 1 | — |
| SELF-06 | Phase 1 | — |
| SELF-07 | Phase 1 | — |
| SELF-08 | Phase 1 | — |
| SELF-09 | Phase 1 | — |
| SELF-10 | Phase 1 | — |
| SELF-11 | Phase 1 | — |
| SELF-12 | Phase 1 | — |

### Phase 2 — Trainingsbuchung-Vollausbau (TRAIN, 10 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| TRAIN-01 | Phase 2 | — |
| TRAIN-02 | Phase 2 | — |
| TRAIN-03 | Phase 2 | — |
| TRAIN-04 | Phase 2 | — |
| TRAIN-05 | Phase 2 | — |
| TRAIN-06 | Phase 2 | — |
| TRAIN-07 | Phase 2 | — |
| TRAIN-08 | Phase 2 | — |
| TRAIN-09 | Phase 2 | — |
| TRAIN-10 | Phase 2 | — |

### Phase 3 — Events + Polls + Push systematisch (EVT, 19 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| EVT-01 | Phase 3 | — |
| EVT-02 | Phase 3 | — |
| EVT-03 | Phase 3 | — |
| EVT-04 | Phase 3 | — |
| EVT-05 | Phase 3 | — |
| EVT-06 | Phase 3 | — |
| EVT-07 | Phase 3 | — |
| EVT-08 | Phase 3 | — |
| EVT-09 | Phase 3 | — |
| EVT-10 | Phase 3 | — |
| EVT-11 | Phase 3 | — |
| EVT-12 | Phase 3 | — |
| EVT-13 | Phase 3 | — |
| EVT-14 | Phase 3 | — |
| EVT-15 | Phase 3 | — |
| EVT-16 | Phase 3 | — |
| EVT-17 | Phase 3 | — |
| EVT-18 | Phase 3 | — |
| EVT-19 | Phase 3 | — |

### Phase 4 — Statistik-Dashboards (STAT, 17 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| STAT-01 | Phase 4 | — |
| STAT-02 | Phase 4 | — |
| STAT-03 | Phase 4 | — |
| STAT-04 | Phase 4 | — |
| STAT-05 | Phase 4 | — |
| STAT-06 | Phase 4 | — |
| STAT-07 | Phase 4 | — |
| STAT-08 | Phase 4 | — |
| STAT-09 | Phase 4 | — |
| STAT-10 | Phase 4 | — |
| STAT-11 | Phase 4 | — |
| STAT-12 | Phase 4 | — |
| STAT-13 | Phase 4 | — |
| STAT-14 | Phase 4 | — |
| STAT-15 | Phase 4 | — |
| STAT-16 | Phase 4 | — |
| STAT-17 | Phase 4 | — |

### Phase 5 — Demo-Härtung + Reviewer-Pass (DEMO, 10 REQs)

| REQ-ID | Phase | Plan-Slot |
|--------|-------|-----------|
| DEMO-01 | Phase 5 | — |
| DEMO-02 | Phase 5 | — |
| DEMO-03 | Phase 5 | — |
| DEMO-04 | Phase 5 | — |
| DEMO-05 | Phase 5 | — |
| DEMO-06 | Phase 5 | — |
| DEMO-07 | Phase 5 | — |
| DEMO-08 | Phase 5 | — |
| DEMO-09 | Phase 5 | — |
| DEMO-10 | Phase 5 | — |

### Coverage Validation

| Category | Mapped | Expected | Match |
|----------|--------|----------|-------|
| FOUND | 7 | 7 | yes |
| SELF | 12 | 12 | yes |
| TRAIN | 10 | 10 | yes |
| EVT | 19 | 19 | yes |
| STAT | 17 | 17 | yes |
| DEMO | 10 | 10 | yes |
| **Total** | **75** | **75** | **yes** |

No orphans. No duplicates. Each REQ-ID appears in exactly one phase table above.

---

*Requirements defined: 2026-04-29*
*Step 7 of `/gsd-new-project` complete*
*Step 8 (gsd-roadmapper) complete: 2026-04-29 — ROADMAP.md + STATE.md + Traceability above*
*Next: `/gsd-plan-phase 0` (after user approval of roadmap)*
