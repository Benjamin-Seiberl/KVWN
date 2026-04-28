# Feature Research

**Domain:** Vereins-App / Amateur-Sports-Club Management (KVWN — Kegelverein, Brownfield)
**Researched:** 2026-04-28
**Confidence:** HIGH (live brownfield, comparable apps well-documented, demo deadline 2026-05-22 hard-bounded)

---

## Reading Guide

This document is split per **v1-feature-area** (4 sections, one per Active requirement in PROJECT.md). Each section has:

1. **Table Stakes** — must work credibly at JHV-Demo or the feature feels broken
2. **Differentiators** — UX wins that align with KVWN core value ("alles unter einem Dach + schön + Spaß")
3. **Anti-Features** — explicitly cut to ship by 2026-05-22
4. **Demo-vs-Production gap** — what's needed for a 22-Mai-Demo vs full rollout

**Vendor benchmarks used throughout:** Spond, TeamSnap, SpielerPlus / TeamPlus, Heja, easyVerein, Web4Kegeln / Sportwinner Kegeln, BSKV-App, BowlSheet, LaneTalk. These are the apps a Kegelverein-Vorstand would compare KVWN against (mentally or explicitly) when deciding adoption at JHV.

---

## Feature Area 1 — Trainingsbuchung-Vollausbau

**Brownfield-Status:** `book_training_lane` / `cancel_training_booking` RPCs live, `training_specials` + `training_waitlist` Tabellen existieren als Daten-Modell, aber Warteliste hat keine UI, keine Erinnerungen, keine Statistik.

**Vendor benchmarks:** Spond (RSVP-Reminder + recurring sessions), SpielerPlus (Trainings-Statistik + Anwesenheits-Listen), ClubPal (waitlist + auto-promote), MevoLife (waitlist alert when slot frees).

### Table Stakes (Demo-credibility floor)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Warteliste-UI: "Auf Warteliste setzen"-Button wenn Slot voll** | Daten-Modell existiert, aber ohne UI ist es ein totes Feature. Spond/SpielerPlus zeigen Warteliste prominent | S | Reuse `BottomSheet`. Triggert `INSERT` in `training_waitlist`, schreibt `position` |
| **Auto-Promote: Storno → erste Wartelisten-Person rückt nach + Push** | Industry-Standard (Spond, ClubPal). Ohne Auto-Promote ist Warteliste reine Anzeige | M | Trigger oder RPC `promote_waitlist_on_cancel(p_date, p_start)`. Push via `/api/push/notify` |
| **"Meine nächste Trainingseinheit"-Card auf Dashboard** | Existiert teilweise (`NextTrainingCard.svelte`), muss gebuchten Slot + Bahn anzeigen | S | Component vorhanden, ggf. Bahn-Nummer ergänzen |
| **Storno-Workflow mit Frist: "Bis 12h vorher kostenfrei stornieren"** | TeamSnap/Spond zeigen Cancellation-Deadline. Verein erwartet Disziplin-Hebel | S-M | Server-side prüfen (RPC `cancel_training_booking` ergänzen), UI-Hinweis |
| **Push-Erinnerung 24h vor gebuchtem Training** | Spond bietet 48h-Variante; 24h ist die ehrlichere Erinnerung. Cron-Job analog `lineup-reminders` | M | Neuer Cron `/api/cron/training-reminders` (täglich 18:00). Push-Pref-Toggle in EinstellungenTab |
| **Bahn-Übersicht im Kalender-Detail-Sheet (TrainingDetailSheet)** | Existiert als Komponente; muss alle Bahnen mit Belegung zeigen | S | Schon teilweise da; Polish-Aufgabe |

### Differentiators ("Spaß + Schönheit"-Layer)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Trainings-Statistik pro Spieler: "Du hast diese Saison X von Y Trainings besucht"** | Macht Daten sichtbar, schafft sanften Anreiz. SpielerPlus hat das, aber lieblos. Wir machen Donut-Chart + Vergleich zum Team-Durchschnitt | M | Aggregation: `SELECT count(*) FROM training_bookings WHERE player_id=X AND date >= season_start`. Donut: SVG ohne Library |
| **Trainings-Streak: "5 Wochen in Folge"-Badge im Profil** | Gamification light, treibt Konstanz. Bowling-Apps (BowlSheet) machen Streak-Tracking, aber nicht für Trainingsbesuch | S | Berechnen aus `training_bookings`. Badge-CSS reuse `--color-secondary` (Gold) |
| **Slot-Templates für wiederkehrende Trainings (Mo 18-20, Mi 19-21)** | Captain spart Zeit. Spond hat "season planner" für recurring events | M | Migration `training_templates` schon da (s. CLAUDE.md `lane_count`). UI-Builder für Template fehlt |
| **"Wer ist heute Abend dabei"-Vorschau im Slot** | Soziale Komponente — "ich geh hin weil X auch da ist". Heja-Style Anwesenheits-Liste, aber für ein- und ausklappbar im DetailSheet | S | Bookings haben `player_id`; Avatar-Reihe via `imgPath()` |
| **"Heute frei? Buche spontan!" — Bahn-Spotlight am Dashboard** | Wenn weniger als 50% Auslastung 4h vor Slot, prominenter CTA aufs Dashboard | M | `$derived` über kommende Slots, neue Card-Variante |

### Anti-Features (Cut for JHV)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Kostenpflichtige Buchung mit Stripe/PayPal-Integration** | "Trainingsgebühren digital" klingt fortschrittlich | Sensibel + komplex (PSD2, Mehrwertsteuer, Stornoregeln); blockiert v1 Wochen | Vereinsfinanzen ist v2 in PROJECT.md. v1: "Bezahlung läuft separat" |
| **Trainer-Bewertungen / Trainings-Feedback nach jedem Slot** | "Mehr Daten ist besser" | Kegelverein hat keine bezahlten Trainer; macht das Feature awkward | Post-Match-Feedback existiert für Spiele — das reicht |
| **Live-Verfügbarkeits-Anzeige in Echtzeit (WebSocket)** | "Real-time everywhere" Demo-Trick | Supabase Realtime auf 1 Tabelle für 30 Spieler ist Overengineering; pull-to-refresh reicht | Polling on `onMount` + manuelles Refresh-Pattern bleibt |
| **Komplexe Trainings-Pläne mit Übungs-Bibliothek** | SpielerPlus hat "training plans" für Fußball | Nicht Kegel-Realität; Kegeltraining ist "auf Bahn werfen" | Skip — kein Bedarf |
| **Trainings-Anwesenheitspflicht mit automatischer Mannschafts-Strafe** | "Disziplin-Hebel" — Captain-Wunsch | Jurisdiktional heikel + erzeugt Unmut | Statistik macht Anwesenheit transparent — das reicht als sozialer Hebel |
| **Bahn-Buchung für externe Gäste / Buchung außerhalb Vereinszeiten** | "App könnte mehr Auslastung bringen" | KVWN ist Verein, nicht Bowling-Center; sprengt Scope | Multi-Tenant ist out-of-scope laut PROJECT.md |

### Demo-vs-Production Gap

**Für 22.05.2026 nötig:**
- Warteliste-UI + Auto-Promote (sonst totes Datenfeld)
- Trainings-Statistik (Donut + Streak) — Demo-WOW-Faktor
- 24h-Reminder-Cron (zumindest scheduled, nicht zwingend live)

**Production-Polish nach Demo:**
- Slot-Templates UI-Builder
- "Heute frei?"-Spotlight
- Edge-Cases im Storno-Workflow (Krankheits-Override)

### Inter-Feature-Dependencies

- Warteliste **abhängig von** Storno-Workflow (Auto-Promote braucht funktionierendes Cancel)
- Trainings-Statistik **abhängig von** stabilem `training_bookings`-Datenmodell (✓ live)
- Push-Reminder **abhängig von** existierender Push-Infra (✓ live: `/api/push/notify`, VAPID)
- Bahn-Übersicht **abhängig von** `lane_count`-Feld in `training_templates` (✓ live laut Migration `20260421_training_lanes.sql`)

---

## Feature Area 2 — Spieler-Selfservice Stammdaten

**Brownfield-Status:** `ProfilDatenSheet` / `ProfilDatenAccordion` existieren, aber laut `MEMORY.md → project_player_fields_unverified.md` referenzieren sie Spalten, die in keiner Migration definiert sind. Verifizieren vor Bau.

**Vendor benchmarks:** TeamSnap (Roster-Profile mit Selbst-Editing — "members or parents can easily edit contact information"), easyVerein (Mitglieder-Selbstverwaltung als zentrales Feature), Heja ("everything doesn't have to go through the coach"), SpielerPlus (Premium: Spieler editieren Stammdaten).

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Editierbare Felder: Telefon, E-Mail (read-only OAuth), Geburtstag, Adresse** | TeamSnap/easyVerein machen das seit Jahren; Captain-Pain heute = manuelle Pflege | S | Migration: ergänze `players` um fehlende Spalten. RLS: nur own row schreibbar (`player_id = current_player_id`) |
| **Foto-Upload mit Crop / Standard-Aspect-Ratio** | Heute liegt das in `static/images/` per filename — geht nicht für Selfservice | M | Supabase Storage Bucket `player-photos` mit RLS; ersetzt File-Path-Lookup in `imgPath()` |
| **"Profil unvollständig"-Indikator (Onboarding-Checkliste)** | TeamSnap/Spond zeigen Progress; Daten-Vollständigkeit treibt Adoption | S | `$derived` über Felder; Progress-Ring im `ProfilHeroCard` |
| **Lizenz-Nummer (ÖSKB/NÖSKB-Spielerausweis-ID)** | Kegelverband-spezifisch, Captain braucht das für Aufstellungs-Meldung | S | Plain text-Feld, Validation optional (Format-Hinweis) |
| **Notfallkontakt: Name + Telefon** | Standard bei Sport-Apps (TeamSnap, Spond) für Vereinsfahrten | S | Zwei Felder in `players`-Tabelle, RLS sichtbar nur Captain + Spieler selbst |
| **Datenschutz-Hinweis "Diese Daten sehen Kapitän + dein Konto"** | DSGVO-relevant, vermeidet "wer sieht das?"-Rückfragen | S | Plain Text-Banner im Edit-Sheet |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Foto-Geburtstags-Banner: "Heute hat X Geburtstag" auf Dashboard** | Soziale Wärme — "alles unter einem Dach" wirkt menschlich | S | Existiert evtl. teilweise (`ProfilMeilensteineCard`). Auf Dashboard als News-Card |
| **Profil-Vervollständigungs-Score mit "10 von 12 Feldern" + Sterne-Animation** | TeamSnap zeigt Profil-% nüchtern. KVWN macht es spielerisch | S | CSS-Animation auf Progress-Ring, Konfetti bei 100% (CSS-keyframes) |
| **"Mit ICS exportieren"-Knopf für Notfallkontakt → Kontakte-App** | Pragmatisch für Captain auf Auswärtsfahrt | S | Generiere VCard client-side, `data:text/vcard` download |
| **Geburtstags-Liste pro Saison im Captain-Bereich** | Captain weiß: "Wem soll ich gratulieren?" — heute Excel | S | Sort by `EXTRACT(MONTH FROM birthday)`, Liste in `AdminTab` |
| **Visualisierung: "Du bist seit X Jahren im Verein" mit Jahres-Badges** | Identifikation. Existiert evtl. via `ProfilMitgliedschaftCard` | S | Jahre-Berechnung via `formatYearsSince` (s. CLAUDE.md utils/dates.js) |
| **Foto-Upload mit "Drag and Drop"-Crop-UI in Bottom-Sheet** | Industry-Standard ist Datei-Picker; Mobile-PWA mit nativen Camera-Hooks ist Demo-WOW | M | `<input capture="user">` + `getUserMedia` für In-App-Foto. Optional cropping via canvas |

### Anti-Features (Cut for JHV)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Spieler kann eigene Rolle editieren (kapitaen vs user)** | "Empowerment!" | Bricht RLS-Modell, Sicherheits-Risiko | Captain assigniert weiterhin via `AdminRollen`. Spieler kann _anfragen_, aber nicht setzen |
| **Mitglieds-Beitrags-Status, IBAN-Eingabe für Lastschrift** | Vereinsfinanzen-Vorgriff | v2 explizit (PROJECT.md). DSGVO + SEPA-Anforderungen sind eigenes Projekt | Defer: v2 |
| **Familien-Accounts mit Sub-Profilen (Kind unter Eltern)** | "Familie/Gäste read-only Tier" wurde diskutiert | Sub-Account-Login-Flow ist eigene Achitektur. Familie/Gäste-Tier laut PROJECT.md = read-only Sichtbarkeit, nicht eigene Accounts | Read-only-Familie via separater Tier ohne Selfservice |
| **Profil-öffentlich-Toggle "Mein Foto sehen alle"** | "Privatsphäre-Granularität" | Verein ist intern, alle sehen alle. Toggle suggeriert Wahl, die nicht real existiert | Einheitliche Sichtbarkeit + Datenschutz-Hinweis |
| **Mehrere Telefonnummern, mehrere Adressen** | "Vollständigkeit" | Komplexitäts-Sprung ohne Use-Case | Ein Telefon, eine Adresse. Notfallkontakt = zweiter Slot |
| **Foto-Galerie mit mehreren Bildern pro Spieler** | "Mehr Bilder = schöner" | Storage-Kosten + Moderation + Duplikat zu Heja-Galerie | Ein Profilbild, fertig |

### Demo-vs-Production Gap

**Für 22.05.2026 nötig:**
- Migration verifizieren + fehlende Spalten ergänzen (`MEMORY.md`-Eintrag adressieren)
- Edit-Sheet funktional (Telefon, Geburtstag, Foto, Notfallkontakt)
- Profil-Vervollständigungs-Score (Demo-WOW)
- Datenschutz-Hinweis (rechtlich)

**Production-Polish nach Demo:**
- In-App-Foto-Capture
- Geburtstags-Banner-Automation
- VCard-Export

### Inter-Feature-Dependencies

- Selfservice **blockiert von** Daten-Modell-Verifikation (`MEMORY.md` → unverified player_fields)
- Foto-Upload **abhängig von** Supabase Storage Bucket-Setup (neu, nicht in Codebase)
- Geburtstags-Banner **abhängig von** Geburtstag-Feld (Selfservice-Output)
- Statistik-Dashboards **profitiert von** vollständigen Profilen (Foto + Lizenz für Spielbericht)

---

## Feature Area 3 — Statistik-Dashboards

**Brownfield-Status:** `StatsView.svelte` + `spielbetrieb` `statistiken`-Tab existieren mit Basis-Statistik. Liga-Position fehlt komplett (`MEMORY.md → project_spielbetrieb_no_league_standings.md`: keine `league_standings`-Tabelle, kein `points`-Feld). Opponent-Score blocked (s. `MEMORY.md → project_spieletab_opponent_score.md`).

**Vendor benchmarks:** Web4Kegeln (Spielerstatistik mit Schnitt + Bestleistung pro Bahn), Sportwinner Kegeln (Saison-Ergebnisse + Tabellen), BowlSheet (Performance-Trends + Stärken/Schwächen pro Pin), SportMember (Season-Timeline-Charts), STATSCORE-Style Dashboards.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Saison-Schnitt pro Spieler (Punkte / Anzahl Spiele)** | Kegel-Zentrum-Metrik. Web4Kegeln/BSKV-App machen es. Heute: nur einzelne Match-Daten, kein aggregierter Schnitt | M | View `player_season_stats` mit AVG, COUNT, MIN, MAX über `match_results`. RLS-clean (alle sehen alles im Verein) |
| **Form-Kurve: Letzte 10 Spiele als SVG-Sparkline auf Spieler-Detail-Karte** | BowlSheet macht "performance trends"; Sparkline ist die ehrliche Mini-Visualisierung | M | SVG inline, keine Chart-Library. Punkte normalisiert auf 0-100% des historischen Max |
| **Liga-Tabelle (Rang, Mannschaft, Spiele, Punkte, Differenz)** | Erwartung jedes Sport-Apps (TeamSnap, Web4Sport). Aktuell BLOCKER: Schema fehlt | M | Migration `league_standings` ODER importieren von externem ÖSKB-Feed. Demo: hardcoded JSON-Mock akzeptabel |
| **Mannschafts-Schnitt pro Saison als Vergleichs-Kontext** | "Bin ich besser oder schlechter als Schnitt?" ist Kern-Frage. Web4Kegeln zeigt das prominent | S | Aggregation auf `match_results`, dann pro Spielerprofil als Referenz-Linie |
| **Persönliche Bestleistung (Höchstes Einzelergebnis)** | Bowling-Apps zeigen "high score" prominent. Soziales Storytelling | S | `MAX()` auf `match_results.score` per Spieler |
| **Anzeige "X Spiele gespielt diese Saison" auf Profil** | Anwesenheits-Indikator analog Trainings-Statistik | S | `COUNT()` über matches mit eigenem `player_id` in lineup |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Form-Kurve mit Trend-Indikator: "↑ +12% letzte 5 Spiele"** | Macht Daten erzählbar. SportMember macht Linecharts trocken; KVWN macht Mini-Story | M | SMA(5) vs SMA(10) Differenz, Pfeil-Icon mit Farb-Code (--color-success / --color-danger) |
| **Spieler-Vergleich: "Du vs. Vereins-Schnitt vs. Bester"** | Konkurrenz-light, treibt Engagement. BowlSheet macht das zuhause | M | 3-Linien-SVG-Chart, Spieler-Linie eingefärbt mit `--color-primary` |
| **Saison-Highlights-Card: "Dein bestes Spiel war 04.03 mit 612 Pin"** | Sentiment-driven, schöne UX. Spond bringt nichts Vergleichbares | S | Top-Match je Saison, Card mit Datum + Gegner |
| **Liga-Tabellen-Animation: Verein-Reihe pulsiert sanft** | Visuelle Identifikation. CSS-Animation, nicht JS-driven | S | `@keyframes pulse-row`, gated auf own team_id |
| **Historische Vergleiche: "Saison 2024/25 vs 2025/26 — du warst da, du bist hier"** | Identitäts-Aufbau. Kein Konkurrent macht das schön | M | Zwei-Saison-Aggregation, Pfeil-Diagramm, "+34 Pin / Schnitt" |
| **"Mannschaftsabend"-Wrapped: Saison-Recap als scrollbare Story-Card** | Spotify-Wrapped-Style; massive Differenzierung. JHV-Demo-WOW Höhepunkt | L | Multi-Step-Sheet mit 5-7 Stat-Slides, einmal pro Saison-Ende. **Cut für JHV; v1.5** |
| **Bahn-Statistik: "Auf Bahn 3 spielst du 8% besser"** | Hyper-spezifisch, Kegel-Insider. BowlSheet macht "lane preferences" | M | `match_results` braucht `lane_id`-Feld, ggf. nicht vorhanden — verify |
| **Heatmap: "Welche Wochentage wirfst du am besten?"** | Persönlichkeits-Story. Spielzeiten sind primär Sa/So → ggf. dünn | M | Aggregat über `EXTRACT(DOW FROM date)` |

### Anti-Features (Cut for JHV)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **ELO-Rating / Skill-Rating zwischen Spielern** | "Wettbewerbs-Element" | Kegeln ist nicht 1v1; ELO ist konzeptuell falsch + erzeugt Konkurrenz, die Verein-Atmosphäre belastet | Schnitt + Form-Kurve macht denselben Job |
| **Live-Score-Eingabe Kegel-für-Kegel während Match** | "Modern wie Profi-Liga" | v2 explizit (PROJECT.md "Vereinsfinanzen v2"). Hardware-fragil + braucht Connectivity in Halle | Defer: v2 |
| **Predictive Analytics: "Du wirst nächstes Spiel 580 Pin werfen"** | "AI-Hype" | Daten-Volume reicht nicht (40 Spieler × 30 Spiele/Saison = ~1200 Datenpunkte). Falsche Prognosen schaden Vertrauen | Form-Kurve zeigt Trend ehrlich |
| **Cross-Verein-Vergleich: "Du bist 3-bester Wiener Neustadt-Kegler"** | "Größerer Kontext" | Multi-Tenant ist out-of-scope (PROJECT.md). Externe Daten unzuverlässig | Liga-Tabelle reicht |
| **Statistik-Export als CSV / PDF / Excel** | "Vollständigkeit" | Niemand exportiert in Praxis; Vorstand will In-App-Sicht | Skip; bei Bedarf später Bytes-Endpoint |
| **Tortendiagramme für Roundcode-Verteilung (H01-FNN)** | "Bunt-bunt" | Information-density null; Insider-Insider-Insider | Schlichte Tabelle reicht falls überhaupt |
| **Echte Live-Updates beim laufenden Spiel (WebSocket)** | "Echtzeit klingt premium" | Brownfield-Match-Workflow ist nach-Spiel. Realtime addiert Komplexität ohne Use-Case | Polling on `onMount` reicht |

### Demo-vs-Production Gap

**Für 22.05.2026 nötig:**
- Saison-Schnitt + Form-Kurve (Sparkline) auf Spielerprofil — zentrale Demo-Story
- Liga-Tabelle (Mock-Daten akzeptabel laut PROJECT.md "Statistiken/Events können Mock-Daten zeigen")
- Persönliche Bestleistung als kleine Card
- Mannschafts-Schnitt-Vergleichs-Linie

**Production-Polish nach Demo:**
- Liga-Tabelle live (echte Migration `league_standings` oder ÖSKB-Feed)
- Historische Saison-Vergleiche
- Bahn-Statistik (verify ob `lane_id` in `match_results`)
- Saison-Wrapped (v1.5)

### Inter-Feature-Dependencies

- Statistik **abhängig von** stabilem `match_results`-Datenmodell (✓ teilweise; Opponent-Score-Blocker)
- Liga-Tabelle **abhängig von** neuer Migration ODER externem Feed (BLOCKER für live-Daten — Mock OK für Demo)
- Form-Kurve **abhängig von** mind. 5+ Match-Datenpunkten pro Spieler (✓ Brownfield hat das)
- Bahn-Statistik **abhängig von** `lane_id`-Spalte in `match_results` (verify)
- Vergleichs-Kontext **profitiert von** vollständigen Spielerprofilen (Foto für Visualisierung)

---

## Feature Area 4 — Events + Umfragen + Push systematisch

**Brownfield-Status:** Events live, Google-Calendar-Sync bidirektional. Push-Infra (`/api/push/notify` + VAPID + Service Worker) live. Polls existieren als `PollCard.svelte` im Dashboard, aber unklar wie ausgereift. Push wird aktuell ad-hoc verwendet, nicht systematisch.

**Vendor benchmarks:** Spond (Polls + Time-Polls + RSVP-Auto-Reminder + recurring events), SpielerPlus (Polls für Vereinsabend / Weihnachtsfeier-Doodle-Killer), Heja (RSVP + comment), TeamSnap (Availability + Comments), easyVerein (digitale Abstimmungen).

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Event-Typen: Vereinsabend, Ausflug, Saisonschluss, Sitzung** | Spond hat das; Captain/Vorstand muss kategorisieren können | S | `events.type`-Enum erweitern. UI: Color-Code je Typ |
| **RSVP: Zusage / Absage / Vielleicht + Kommentar** | Heja/Spond/TeamSnap-Standard. Familie/Gäste read-only sehen Liste | S | `event_rsvp`-Tabelle (`event_id`, `player_id`, `status`, `comment`). RLS write own row |
| **RSVP-Liste sichtbar im EventDetailSheet** | "Wer kommt?" ist die häufigste Frage. Spond zeigt es prominent | S | Avatar-Reihe via `imgPath` + Liste mit Kommentaren |
| **Push-Notification bei neuem Event (alle Vereinsmitglieder)** | Spond/Heja: automatisch. Heute: ad-hoc. Soll systematisch werden | S | Trigger nach Event-Insert: server-side fan-out via `/api/push/notify` |
| **Push-Reminder 24h vor Event für Nicht-Antworter** | Spond hat das (48h-Variante); 24h ist Standard | M | Cron `/api/cron/event-reminders` (täglich), filtert RSVP=`null` |
| **Polls: Text-Poll mit Antwort-Optionen + Mehrfachauswahl-Toggle** | Spond/SpielerPlus haben das; Doodle-Killer | M | `polls` + `poll_options` + `poll_votes`-Tabellen. RLS: alle stimmen, nur eigene Stimme editierbar. UI bestehend (`PollCard`) erweitern |
| **Time-Poll: "Welcher Termin passt?"** | Spond's wichtigster Poll-Typ. Captain plant Vereinsabend | M | Spezial-Poll, options sind Datums-Strings; "Event aus Poll erstellen"-Button |
| **Push-Settings pro Event-Typ** | Vermeidet Push-Müdigkeit. Spond customizable per group | S | Erweitere bestehende Push-Prefs in `EinstellungenTab` |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Event-Cover-Foto / Hero-Bild im DetailSheet** | Macht Event greifbar. Spond hat plain Card, KVWN macht's schön | S | `events.cover_url` (Storage). Oder kuratierte Default-Hintergründe pro Event-Typ |
| **Geo-Pin für Event-Ort + "In Maps öffnen"** | Mobile-PWA-Feature. Spond hat Plain-Adresse | S | Bestehende `events.location` + maps-Link via `geo:`-URL-Scheme |
| **"Wer fährt mit?"-Sektion direkt im Event** | Carpool-Card (`CarpoolCard`) existiert für Spielbetrieb. Reuse für Events | M | Generalisiere `CarpoolCard` auf event-id statt match-id |
| **Live-Vote-Counter mit Animation: Balken füllt sich** | Spond zeigt nüchterne Zahlen; KVWN macht's lebendig | S | CSS `transition: width` auf Result-Bar |
| **Poll-Closing-Reminder: "Abstimmung läuft noch 24h"** | Spond hat statisches Deadline-Anzeigen; KVWN macht Push | S | Cron-Erweiterung, nutzt poll.closes_at |
| **Event-Wiederholung im Kalender + GCal-Sync** | Bestehender GCal-Sync ist Asset; iterierende Events sind Spond-Standard | M | `events.recurrence`-RRULE-Feld, GCal nimmt RRULE nativ |
| **"Probier-Modus" für Captain: Event als Draft anlegen, später posten** | Spond hat "scheduled posting". Kapitän probiert Wording | S | `events.status` = `'draft' | 'published'`, Push erst on publish |
| **Photo-Pinwand pro Event (nach dem Event Bilder hochladen)** | Heja/Spond haben das; Vereinsabend-Erinnerung erzählt sich von selbst | M | Storage Bucket `event-photos`, RLS write captain + uploader, read all |

### Anti-Features (Cut for JHV)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Geheime Abstimmungen (anonym)** | "Demokratie!" für JHV-Wahlen | DSGVO + Vertrauens-Frage; Crypto-anonyme Voting ist eigene Welt | JHV-Wahlen physisch — App ist nicht Wahlurne |
| **Bezahlte Events (Saisonschluss-Eintritt via App)** | "Convenience" | Stripe + Vereinsfinanzen v2 + Refund-Workflow | Zahlung außerhalb (Banküberweisung), Status manuell |
| **Event-Chat / Kommentar-Thread mit Reaktions-Emojis** | Slack/Discord-FOMO | Moderation + Notification-Lärm + Konkurrenz zu WhatsApp-Gruppe | RSVP-Kommentar reicht; Diskussion bleibt WhatsApp |
| **Mehrstufige Polls (Bestätigungs-Schritt nach Vorauswahl)** | "Saubere Logik" | Doodle-Killer-Komplexität; Spond hat das nicht | Einstufiger Poll, fertig |
| **Push-Notifications mit Deeplink + Custom-Action-Buttons** | "Native-App-Feature" | Web-Push hat Action-Buttons, aber nicht alle Browser; iOS-Safari-Limitierungen | Plain Push mit Click→Deeplink reicht |
| **Externe Gäste zu Event einladen (E-Mail-Token-Link)** | "Vereinsabend mit Familie!" | RLS-Modell erlaubt nur Member; Token-Flow ist eigene Auth-Achitektur | Familie/Gäste-Tier laut PROJECT.md = read-only Member, keine Token |
| **Recurring-Polls (jede Woche neuer Poll)** | "Automatisierung" | Zu spezifisch für Use-Case; manueller Captain-Trigger genug | Captain duplicates poll bei Bedarf |
| **Dashboard-Widget mit Event-Countdown ("noch 3 Tage")** | "Live!" | UpcomingEvents-Card existiert (`UpcomingEvents.svelte`); Countdown ist ablenkend | Datum + "in 3 Tagen" via `daysUntil()` reicht |

### Demo-vs-Production Gap

**Für 22.05.2026 nötig:**
- Event-Typen + Color-Code (visueller Fortschritt)
- RSVP funktional (Zusage/Absage/Vielleicht + Kommentar)
- Polls (Text + Time) mit Voting-UI
- Push bei neuem Event (systematisch statt ad-hoc) — KEY FÜR JHV-DEMO ("Push funktioniert")
- Push-Settings-Toggle in Einstellungen (Demo: "Hier kannst du steuern, was du kriegst")

**Production-Polish nach Demo:**
- Event-Cover-Fotos (Storage Bucket Setup)
- Carpool für Events (Generalisierung)
- Photo-Pinwand
- Recurring Events
- Draft-Status

### Inter-Feature-Dependencies

- Push-System **abhängig von** existierender VAPID + SW-Infra (✓ live)
- Reminder-Crons **abhängig von** Vercel-Pro-Tier (✓ confirmed laut MEMORY.md)
- Polls **abhängig von** Schema (`polls`, `poll_options`, `poll_votes` neu)
- Event-Cover-Foto **abhängig von** Supabase Storage Bucket (geteilt mit Foto-Upload aus Feature 2)
- Carpool für Events **abhängig von** Generalisierung bestehender `CarpoolCard` (Refactoring nötig)
- Time-Poll → Event-Auto-Erstellung **abhängig von** stabilem GCal-Sync (✓ live)

---

## Cross-Cutting Concerns

### Vereinsmitglieder vs. Familie/Gäste read-only

PROJECT.md erwähnt Read-only-Tier. Das berührt **alle vier** Features:

- **Trainingsbuchung:** Familie sieht Slot-Belegung, kann nicht buchen (RLS write-deny)
- **Profil-Selfservice:** Familie hat eigene minimal-Profile (Name + Verbindung) — nicht v1-Scope, defer
- **Statistik:** Familie sieht alles read-only — RLS-clean, Display-Logik gleich
- **Events + Polls:** Familie sieht Events, kann RSVP, **kann nicht** Poll-erstellen — RLS write-deny

**Empfehlung:** Familie-Tier ist eigenes Schema-Feature (`players.tier = 'member'|'family'|'guest'`), aber funktional erst nach v1-Demo notwendig.

### Push-Notification-Strategie (kritisch für alle vier Features)

Alle Features triggern Push. Risiko: **Push-Müdigkeit**. Antwort:

- **Globale Push-Frequenz-Cap:** Max 1 Push pro Spieler pro Tag (außer kritisch: Match-Reminder, Lineup-Bestätigung)
- **Pro-Typ-Toggles in EinstellungenTab:** Training-Reminder, Event-Reminder, Poll-Reminder, Statistik-Wrapped (separat ein/aus)
- **Quiet Hours:** Nichts zwischen 22:00-08:00 (cron-respect)
- **Vendor-Benchmark:** Spond per-group customizable, KVWN macht per-typ (einfacher)

### Performance-Implikationen

- **Statistik-Aggregationen** auf jeder Profil-Öffnung = teuer. Lösung: Materialized View oder vorab berechnete `player_season_stats`-Tabelle, refreshed via Cron nach Match-Eingabe
- **Kalender mit RSVP-Counts** = Subquery-Last. Lösung: `events_with_counts`-View
- **Push-Fan-Out an 40 Subscriptions** = ~40 HTTP-Requests pro Event. Lösung: parallel `Promise.all`, schon im bestehenden `/api/push/notify`

---

## Feature Dependencies (Cross-Area)

```
Feature 2 (Selfservice)
    └──blocks──> Feature 3 (Statistik nutzt Foto + Identität)
    └──blocks──> Feature 4 (Event-RSVP zeigt Avatar)
    └──blocks──> Feature 1 (Trainings-Statistik zeigt Avatar)

Feature 1 (Trainings-Reminder-Cron)
    └──templates──> Feature 4 (Event-Reminder-Cron, gleiches Pattern)

Feature 3 (Statistik)
    └──depends-on──> Match-Results-Schema (✓ live, partial)
    └──blocked-by──> Liga-Tabelle-Schema (Migration ODER Mock-Daten für Demo)
    └──blocked-by──> Opponent-Score-Spalte (MEMORY.md → game_plans.opponent_score fehlt)

Feature 4 (Push systematisch)
    └──depends-on──> VAPID-Infra (✓ live)
    └──depends-on──> Vercel-Cron-Pro-Tier (✓ live)
    └──templates-from──> Lineup-Reminder-Cron (existiert, kann gefork werden)

Feature 2 (Foto-Upload)
    └──depends-on──> Supabase Storage Bucket (NEU, nicht in Codebase)
    └──shares-bucket-with──> Feature 4 (Event-Cover-Photos)

Feature 4 (Polls)
    └──new-schema──> polls / poll_options / poll_votes (Migration nötig)

Feature 1 (Slot-Templates)
    └──extends──> training_templates (Schema laut Migration vorhanden, UI fehlt)
```

### Kritische Dependency-Notes

- **Selfservice (F2) sollte zuerst live gehen.** Foto + Stammdaten sind Voraussetzung für hübsche Statistik (F3) und schöne Event-RSVP-Listen (F4).
- **Push-Reminder-Pattern (F1 + F4)** sollte einmal sauber gebaut und dann dupliziert werden. Kandidat für gemeinsame Util-Lib.
- **Liga-Tabelle (F3)** ist der härteste Block. Empfehlung: für JHV mit hardcoded Mock-JSON arbeiten, Migration danach.
- **Storage Bucket (F2 + F4)** sollte in einem Schritt aufgesetzt werden — vermeidet doppelte Setup-Arbeit.

---

## MVP Definition (für JHV-Demo 2026-05-22)

### Launch With (JHV-Demo, 22.05.2026)

**Feature 1 — Trainingsbuchung-Vollausbau:**
- [ ] Warteliste-UI + Auto-Promote
- [ ] Trainings-Statistik (Donut + Streak) im Profil
- [ ] 24h-Push-Reminder Cron

**Feature 2 — Selfservice Stammdaten:**
- [ ] Migration verifizieren + ergänzen
- [ ] Edit-Sheet (Telefon, Geburtstag, Adresse, Notfallkontakt, Lizenz)
- [ ] Foto-Upload via Storage Bucket
- [ ] Profil-Vervollständigungs-Score

**Feature 3 — Statistik-Dashboards:**
- [ ] Saison-Schnitt + Form-Kurve (Sparkline) auf Spielerprofil
- [ ] Persönliche Bestleistung
- [ ] Mannschafts-Schnitt-Vergleichs-Linie
- [ ] Liga-Tabelle (Mock-Daten OK für Demo)

**Feature 4 — Events + Umfragen + Push:**
- [ ] Event-Typen + Color-Code
- [ ] RSVP (Zusage/Absage/Vielleicht + Kommentar)
- [ ] Polls (Text + Time) mit Voting + Result-Bars
- [ ] Push systematisch bei neuem Event
- [ ] Push-Settings-Toggle pro Event-Typ

### Add After Validation (v1.1 — Q3 2026)

- Slot-Templates UI-Builder (F1)
- "Heute frei?"-Spotlight (F1)
- In-App-Foto-Capture (F2)
- VCard-Export Notfallkontakt (F2)
- Liga-Tabelle live (F3)
- Bahn-Statistik (F3, falls `lane_id` vorhanden)
- Event-Cover-Fotos (F4)
- Carpool für Events (F4, generalisiert)
- Recurring Events (F4)

### Future Consideration (v2 — Q4 2026 / 2027)

- Saison-Wrapped Story-Card (F3, post-Saison-Endpunkt)
- Photo-Pinwand pro Event (F4)
- Bahn-Statistik mit Wochentag-Heatmap (F3)
- Familie/Gäste read-only Tier (cross-cutting)
- Live-Score Kegel-für-Kegel (laut PROJECT.md v2)
- Vereinsfinanzen / Mannschaftskasse (laut PROJECT.md v2)

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| F2 — Selfservice Edit-Sheet (basic) | HIGH | LOW | **P1** |
| F2 — Foto-Upload (Storage Bucket) | HIGH | MEDIUM | **P1** |
| F2 — Profil-Vervollständigungs-Score | MEDIUM | LOW | P1 |
| F1 — Warteliste-UI + Auto-Promote | HIGH | MEDIUM | **P1** |
| F1 — Trainings-Statistik (Donut + Streak) | HIGH | MEDIUM | **P1** |
| F1 — 24h-Push-Reminder Cron | HIGH | LOW | P1 |
| F3 — Saison-Schnitt + Form-Sparkline | HIGH | MEDIUM | **P1** |
| F3 — Mannschafts-Schnitt-Vergleich | HIGH | LOW | P1 |
| F3 — Liga-Tabelle (Mock) | MEDIUM | LOW | P1 |
| F4 — RSVP (Zusage/Absage/Vielleicht) | HIGH | LOW | **P1** |
| F4 — Polls (Text + Time) | HIGH | MEDIUM | **P1** |
| F4 — Push bei neuem Event (systematisch) | HIGH | LOW | **P1** |
| F4 — Event-Reminder-Cron | HIGH | LOW | P1 |
| F4 — Push-Settings pro Event-Typ | MEDIUM | LOW | P1 |
| F1 — Bahn-Übersicht im Kalender | MEDIUM | LOW | P2 |
| F1 — Slot-Templates | MEDIUM | MEDIUM | P2 |
| F2 — Geburtstags-Banner | MEDIUM | LOW | P2 |
| F3 — Form-Kurve mit Trend-Indikator | MEDIUM | MEDIUM | P2 |
| F3 — Persönliche Bestleistung-Card | MEDIUM | LOW | P2 |
| F3 — Saison-Highlights | MEDIUM | LOW | P2 |
| F4 — Event-Cover-Foto | MEDIUM | LOW | P2 |
| F4 — Carpool für Events | MEDIUM | MEDIUM | P2 |
| F1 — "Heute frei?"-Spotlight | LOW | MEDIUM | P3 |
| F2 — In-App-Foto-Capture | LOW | MEDIUM | P3 |
| F2 — VCard-Export | LOW | LOW | P3 |
| F3 — Saison-Wrapped Story | HIGH | HIGH | **P3** (post-v1) |
| F3 — Bahn-Statistik | LOW | MEDIUM | P3 |
| F3 — Cross-Saison-Vergleich | MEDIUM | MEDIUM | P3 |
| F4 — Photo-Pinwand | MEDIUM | MEDIUM | P3 |
| F4 — Draft-Mode Events | LOW | LOW | P3 |

**Priority key:**
- **P1 (bold):** Must have for JHV 22.05.2026
- P1 (regular): Should have for JHV
- P2: Add in v1.1 (Q3 2026)
- P3: v2 / future

---

## Competitor Feature Analysis

| Feature | Spond | TeamSnap | SpielerPlus | Heja | easyVerein | Web4Kegeln | KVWN-Approach |
|---------|-------|----------|-------------|------|------------|------------|---------------|
| Training-Buchung mit Bahn | ❌ (generic events) | ❌ | ❌ (Trainings-Sessions, keine Bahnen) | ❌ | ❌ | ⚠ (Spielbahnen, nicht Training) | ✓ Bahn-spezifisch (`book_training_lane`) — **Differentiator** |
| Warteliste mit Auto-Promote | ✓ | ⚠ | ❌ | ❌ | ⚠ | ❌ | ✓ Geplant — Standard |
| Trainings-Statistik | ❌ | ❌ | ✓ (basic counter) | ❌ | ⚠ | ❌ | ✓ Donut + Streak — **Differentiator** |
| Spieler-Selfservice Profile | ⚠ (basic) | ✓ | ✓ (Premium) | ✓ | ✓ | ❌ | ✓ Geplant + Vervollständigungs-Score — **Differentiator** |
| Foto-Upload | ✓ | ✓ | ✓ | ✓ | ✓ | ❌ | ✓ Storage Bucket geplant |
| Saison-Schnitt | ❌ | ✓ (custom stats) | ❌ | ❌ | ❌ | ✓ | ✓ Migration `player_season_stats` |
| Form-Kurve / Sparkline | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠ (Tabelle, nicht Chart) | ✓ SVG-Sparkline — **Strong Differentiator** |
| Liga-Tabelle | ❌ | ⚠ (manuell) | ⚠ | ❌ | ❌ | ✓ | ⚠ Mock für JHV, später live |
| Cross-Saison-Vergleich | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠ (Liste) | ⚠ Defer auf v1.1 |
| Events mit RSVP | ✓ | ✓ | ✓ | ✓ | ⚠ | ❌ | ✓ Geplant — Standard |
| RSVP mit Kommentar | ✓ | ✓ | ✓ | ✓ | ❌ | ❌ | ✓ Geplant — Standard |
| Polls (Text + Time) | ✓ | ❌ | ✓ | ❌ | ✓ | ❌ | ✓ Geplant — Standard |
| Time-Poll → Event-Erstellung | ✓ | ❌ | ❌ | ❌ | ❌ | ❌ | ✓ Geplant — **Differentiator** |
| Push-Reminder pro Event-Typ | ✓ (per group) | ⚠ | ⚠ | ⚠ | ❌ | ❌ | ✓ Pro Typ — **Differentiator** |
| Carpool integriert | ✓ | ❌ | ✓ | ⚠ | ❌ | ❌ | ✓ Live für Match, generalisiert auf Events |
| Mannschaftskasse / Beiträge | ✓ | ✓ | ✓ | ❌ | ✓ | ❌ | ❌ v2 (PROJECT.md) |
| Live-Score | ⚠ | ⚠ (basic) | ✓ (Spielbericht) | ❌ | ❌ | ✓ (kegel-spezifisch) | ❌ v2 (PROJECT.md) |
| Schöne UI / Design-Token-Driven | ⚠ | ⚠ | ⚠ | ✓ | ❌ | ❌ (sehr funktional) | ✓ Design-System rot/gold + Lexend — **Strong Differentiator** |
| Österreichisches Deutsch | ⚠ | ❌ | ⚠ (Deutschland-Deutsch) | ⚠ | ⚠ | ⚠ | ✓ Konsequent ("Jänner" etc.) — **Strong Differentiator** |
| Mobile-First PWA | ⚠ (App-only) | ⚠ (App-Schwerpunkt) | ⚠ (App-Schwerpunkt) | ⚠ | ❌ | ❌ | ✓ PWA First-Class — **Differentiator** |

**Key insight:** KVWN's competitive advantage liegt nicht im *Was*, sondern im *Wie*: kegel-spezifische Daten (Bahn, Schnitt, Form-Kurve) + österreichisches Deutsch + schöne Design-Token-Driven UI + alle Workflows in einer App. Vendor-Apps decken jeweils 60-70% der Funktionalität ab, aber kein einzelner Anbieter macht Kegelverein in AT charmant.

---

## Sources

**Vendor Apps (analyzed via product pages, help docs, app store listings):**
- [Spond — Sports Team Management](https://www.spond.com/) — RSVP, Polls, Reminders, Events
- [Spond — Push Notifications Help](https://help.spond.com/app/en/articles/115450-push-notifications)
- [Spond — Polls in Groups](https://help.spond.com/app/en/articles/112748-poll-in-groups)
- [Spond — Power of Invites and Reminders](https://www.spond.com/news-and-blog/invites-and-reminders-spond-app/)
- [TeamSnap — Features](https://www.teamsnap.com/teams/features) — Roster, Availability, Statistics
- [TeamSnap — Roster Profile and Member Management](https://helpme.teamsnap.com/category/1219-roster-profile-and-member-management)
- [SpielerPlus / TeamPlus — For Clubs](https://www.spielerplus.de/lp/club) — Trainings, Mannschaftskasse, Polls
- [SpielerPlus Tutorial #3 Fahrgemeinschaften](https://www.youtube.com/watch?v=l-vKf5qVlDQ)
- [Heja — Sports Team Communication](https://heja.io/) — Self-service, Carpool
- [easyVerein — Mitgliederverwaltung](https://easyverein.com/) — Self-service, digitale Abstimmungen, Inventar
- [easyVerein — Mitgliederbereich](https://next.easyverein.com/vereinssoftware/mitgliederbereich/)
- [Web4Sport / Web4Kegeln](https://www.web4sport.de/) — Kegel-spezifische Liga + Statistik
- [Sportwinner Kegeln](https://sportwinner.de/) — DE Kegelverband-Software-Standard
- [BSKV / Bayerischer Sportkegler-Verband](https://www.bskv.de/) — App-Referenz für DACH-Kegel
- [SKVS / Sportkegler-Verband Südbaden](https://www.skvs.de/)
- [BowlSheet — Bowling Score System](https://www.bowlsheet.com/) — Performance-Trends, Stärken/Schwächen
- [LaneTalk — Manual Scorekeeping](https://lanetalk.com/manual-scorekeeping/) — Live-Scoring-Vergleich (out-of-scope für KVWN)
- [Bowling Stat Master (BSM)](https://www.amazon.com/a54studio-Bowling-Stat-Master/dp/B00CEJ9LPU) — Lifetime Top-10
- [SportMember — Stat Tracker](https://www.sportmember.com/en/stat-tracker) — Season-Timelines

**Comparison & Analysis:**
- [Why switch from SpielerPlus to Spond](https://spond.com/compare/spielerplus) — Vendor-vergleichende Marketing-Aussagen
- [Apps zur Team-Organisation im Vergleich (FlagFootball.Rocks)](https://www.flagfootball.rocks/news/apps-zur-team-organisation-im-vergleich.html)
- [Top 10 Bowling Apps for Score Tracking (2025)](https://www.bowlingaddicts.com/top-10-bowling-apps-for-score-tracking/)

**KVWN-internal context (mandatory reading):**
- `C:\kvwn\.planning\PROJECT.md` — Vision-Spec, Active-Requirements, JHV-Deadline, v2-Roadmap
- `C:\kvwn\.planning\codebase\STRUCTURE.md` — Aktuelle Komponenten-Map
- `C:\kvwn\CLAUDE.md` — Routes, Subtab-Pattern, Live-Features, Design-Token-System
- `C:\Users\benni\.claude\projects\C--kvwn\memory\MEMORY.md` — Brownfield-Blocker (`game_plans.opponent_score`, `league_standings`-Schema fehlt, PLAYER_FIELDS unverified)

---

*Feature research for: KVWN Vereins-App v1 (Brownfield, 4-feature-area)*
*Researched: 2026-04-28*
*Next: feeds into REQUIREMENTS.md + Roadmap-Ordering*
