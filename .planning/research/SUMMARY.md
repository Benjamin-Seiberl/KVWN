# Project Research Summary — KVWN v1

**Project:** KVWN Vereins-App (PWA für KV Wiener Neustadt)
**Domain:** Brownfield-Vereins-PWA (SvelteKit 5 + Supabase + Vercel)
**Researched:** 2026-04-28
**Confidence:** HIGH
**Hard deadline:** JHV 2026-05-22 (~24 Tage) — Demo-ready, nicht Production-ready

---

## TL;DR

- **Stack:** Existing-Stack ist gelocked. Drei additive Prod-Deps (`layerchart@2.0.0-next.59`, `valibot@1.3.1`, `@internationalized/date@3.12.1`) + Supabase Storage (NICHT Vercel Blob) + Vercel Cron erweitern (NICHT pg_cron). Keine devDependencies, kein TS, kein Form-Framework.
- **Biggest risk (BLOCKER):** RLS-Bridge auf `players.email` ohne UNIQUE/NOT-NULL/lower()-Pin lässt Cross-Spieler-Writes zu (Pitfall C1) — sobald Selfservice-Schreibrechte aktiv sind, ist das ein DSGVO-Vorfall. Zweiter BLOCKER: nackte `new Date()`-Aufrufe in Vercel-Crons driften zur DST-Boundary 29.03./27.10. (Pitfall C3). **Beide müssen in einer Phase 0 vor jeder Feature-Phase gefixt sein.**
- **Recommended phase order:** **Phase 0 (Cross-cutting Foundations) → Phase 1 (F2 Selfservice + Foto + Consent) → Phase 2 (F1 Training Vollausbau) + Phase 3 (F4 Events/Polls/Push) [parallelisierbar wenn Kapazität, sonst seriell] → Phase 4 (F3 Statistik) → Phase 5 (Demo-Härtung).** Statistik ganz hinten, weil sie Trainings-View + Foto + Liga-Tabelle aus Vorphasen verbraucht.
- **JHV-Readiness verdict:** **Realistisch erreichbar, aber nur mit Phase-0-Investment.** 24 Tage / 6 Phasen ≈ 4 Tage/Phase — passt nur, wenn Phase 0 die Cross-cutting-Items (TZ-Helper, RLS-Pin, `is_demo`-Pattern, Resize-Pipeline, zentrale `PUSH_PREFS`-Konstante) einmal sauber legt. Liga-Tabelle und Statistik-Aggregate dürfen Mock-Daten zeigen (laut PROJECT.md explizit erlaubt).
- **Demo-Hygiene non-negotiable:** `is_demo`-Flag auf allen v1-Tabellen, Demo-Account read-only, DB-Snapshot 3 Tage vor JHV. Sonst blockiert Mock-Daten-Cleanup den Sommer-Rollout 2026/27 (Pitfall C10).

---

## Key Findings

### Recommended Stack

Der KVWN-Stack ist gelocked (SvelteKit 5 Runes, Supabase, Vercel Pro, JS-only, browser-direkter `sb`, RLS via `players.email`). Research empfiehlt **drei additive Leaf-Libs** und **zwei Plattform-Pattern-Entscheidungen**.

**Core technologies (additiv, locked-versionen):**

- **`layerchart@2.0.0-next.59`** — Charting (Form-Kurve, Saison-Schnitt, Liga-Tabelle): SVG-basiert, CSS-Token-stylebar, Svelte-5-runes-first; Pre-1.0 → exakte Version pinnen.
- **`valibot@1.3.1`** — Schema-Validation für Selfservice-Formulare: ~1.4 kB gzipped, ESM-pure, 10× kleiner als Zod, integriert direkt mit `$state`/`$derived` ohne Form-Engine.
- **`@internationalized/date@3.12.1`** — Headless-Date-Layer für `de-AT`-Locale ("Jänner"); v1 nur als Fallback hinter `<input type="date" lang="de-AT">` (Mobile-PWA: System-Picker schlägt jede JS-Lib).
- **Supabase Storage über Vercel Blob** — Bucket `player-photos` (public-read, write-own via `storage.foldername(name)[1] = players.id::text`). Begründung: kein zweiter Auth-Pfad, Image-Transform built-in (`?width=400&quality=80`), RLS-Pattern 1:1 wie `attests`.
- **Vercel Cron über Supabase pg_cron** — bestehende Cron-Architektur (3 Jobs live, Pro-Tier 100/Projekt, web-push schon wired) erweitern; pg_cron würde Deno-WebCrypto + neue Auth-Pipeline bedeuten.

**Deliberately not added:** chart.js, sveltekit-superforms, formsnap, bits-ui, @vercel/blob, cropperjs, browser-image-compression, date-fns-direkt, svelte-french-toast — alle dokumentiert mit Begründung in `STACK.md`.

→ Full detail: `.planning/research/STACK.md`

### Expected Features

Vier v1-Feature-Areas, jeweils mit Brownfield-Stand + Vendor-Benchmark (Spond, TeamSnap, SpielerPlus, Heja, Web4Kegeln) abgeglichen.

**Must-have (Demo-credibility floor — pro Feature-Area):**

- **F1 Training:** Warteliste-UI + Auto-Promote, Trainings-Statistik (Donut + Streak), 24h-Push-Reminder (Cron), Storno-Workflow mit Frist, Bahn-Übersicht im Detail-Sheet.
- **F2 Selfservice:** Edit-Sheet (Telefon/Geburtstag/Adresse/Notfallkontakt/Lizenz), Foto-Upload via Storage-Bucket, Profil-Vervollständigungs-Score, **DSGVO-Consent-Workflow** (rechtlich nicht optional).
- **F3 Statistik:** Saison-Schnitt + Form-Sparkline auf Spielerprofil, Persönliche Bestleistung, Mannschafts-Schnitt-Vergleichslinie, Liga-Tabelle (Mock-OK für Demo).
- **F4 Events/Polls/Push:** Event-Typen + Color-Code, RSVP (Zusage/Absage/Vielleicht + Kommentar), Polls (Text + Time), systematischer Push bei Event-Create, Push-Settings-Toggle pro Typ.

**Should-have (JHV-Differentiators):**

- **Form-Kurve mit Trend-Indikator** (`↑ +12% letzte 5 Spiele`) — kein Konkurrent macht das in DACH-Kegelvereins-Apps.
- **Liga-Tabellen-Animation** (Verein-Reihe pulsiert) — visuelle Identifikation, CSS-only.
- **Time-Poll → Event-Auto-Erstellung** — Spond's stärkster Poll-Use-Case, Captain-Pain-Point.
- **Trainings-Streak-Badge** — Gamification light, treibt Konstanz, Gold-Token (`--color-secondary`).
- **Profil-Vervollständigungs-Score mit Progress-Ring + Konfetti-Animation** — TeamSnap zeigt %, KVWN macht's spielerisch.

**Defer (cut for JHV):**

- **F1:** Kostenpflichtige Buchung (Stripe), Trainer-Bewertungen, Live-Verfügbarkeit-WebSocket, externe Gäste-Buchung.
- **F2:** Familien-Sub-Accounts, Profil-öffentlich-Toggle, Foto-Galerie, Mehrere-Telefone, IBAN-Eingabe.
- **F3:** ELO-Rating, Live-Score-Eingabe, Predictive Analytics, CSV/PDF-Export, Saison-Wrapped (v1.5).
- **F4:** Geheime Abstimmungen, bezahlte Events, Event-Chat, Mehrstufige Polls, externe Gäste-Tokens.

→ Full detail: `.planning/research/FEATURES.md` (inkl. Vendor-Comparison-Matrix)

### Architecture Approach

Alle vier Features fügen sich in **bestehende Routes** ein — kein neuer Top-Level-Slot in der BottomNav. UI-Hooks landen in `/profil` (F2 + F1-Stats-Card), `/kalender` (F1 Lane-Strip + F4 Event-Sheets), `/spielbetrieb?subtab=statistiken` (F3 mit lokalem `$state`-PillSwitcher für mannschaft|spieler|liga). Keine neuen globalen Stores. Foto-Upload nutzt Supabase Storage analog dem existierenden `attests`-Bucket. Reminder laufen über eine neue **`push_outbox`-Tabelle** + `/api/cron/scheduled-push` (alle 15min) statt browser-`setTimeout`. Statistik-Aggregationen leben als **DB-Views** (`view_player_season_stats`, `view_player_training_count`), nicht als Client-Reduce. Alles unter dem RLS-Email-Bridge-Pattern (mit Phase-0-Härtung).

**Major components / DB additions:**

1. **Storage-Bucket `player-photos`** — public-read, write-own, RLS analog `attests`-Pattern; `players.photo_url` als zusätzliche Spalte; `imgPath()` erweitert um Storage-Branch (Fallback: static/images → BLANK_IMG).
2. **`push_outbox(send_at, target_kind, target_id, target_player_ids, payload, pref_key, sent_at, sent_count, …)`** — scheduled-push-Queue mit Index `WHERE sent_at IS NULL`; Cron poolt alle 15min via `/api/cron/scheduled-push` und feuert über existierendes `/api/push/notify`.
3. **`league_standings(league_id, team_name, is_kvwn, points, …, season)`** — KVWN-internal source-of-truth statt Client-Reduce; manuell befüllbar durch Kapitän, Mock-OK für JHV.
4. **`polls.target_event_id` FK + `poll_options.target_kind`** — formalisiert die existierenden Poll-Tabellen und koppelt optional an Events; `EventDetailSheet` zeigt nur Polls mit `target_event_id = ev.id`, Dashboard zeigt `target_event_id IS NULL`.
5. **Views `view_player_season_stats` + `view_player_training_count` + RPC `compare_seasons(int, int)`** — alle Stats in der DB, niemals Client-Reduce.
6. **Neue Crons (`vercel.json`):** `scheduled-push` (*/15), `training-reminders` (täglich 09:00 Vienna).

**Cron-Pattern:** Vercel-Cron mit `Bearer ${CRON_SECRET}`-Auth, ruft via `fetch('/api/push/notify')` mit Service-Role-Bypass — konsistent zu existierendem `gcal-sync`/`lineup-reminders`/`keyduty-check`. **Niemals** `+page.server.js` einführen; KVWN-Konvention bleibt browser-direkter `sb`.

→ Full detail: `.planning/research/ARCHITECTURE.md`

### Critical Pitfalls

Aus 15 dokumentierten Pitfalls die zwei **BLOCKER** + drei **HIGH** mit unmittelbarer Demo-Konsequenz:

1. **C1 BLOCKER — RLS-Cross-Write via email-bridge** (Phase 0 → Phase 1): `players.email` ist nicht NOT-NULL/UNIQUE/lower-normalized; bei doppeltem Familien-Gmail oder NULL-Email matcht die `USING`-Policy >1 Row und Spieler überschreibt fremde IBAN/Adresse. **Prevention:** Migration `email NOT NULL UNIQUE` + RLS auf `lower(email) = lower(auth.jwt()->>'email')` + `WITH CHECK (id = (SELECT id …))` Pin. Pre-deploy-Audit: `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL` muss 0 zurückgeben.
2. **C3 BLOCKER — Cron-TZ-Drift Vienna vs UTC** (Phase 0 → Phase 4): `new Date()` in `/api/cron/lineup-reminders/+server.ts:17-19` ist UTC; an DST-Boundary 29.03./27.10. driften alle Reminder um einen Tag, oder kommen doppelt/gar nicht. **Prevention:** Helper `nowVienna()`/`dateInVienna(offsetDays)` in `$lib/server/timezone.js` mit `Intl.DateTimeFormat('de-AT', { timeZone: 'Europe/Vienna' })` + `reminder_log(plan_id, kind, sent_at)`-Idempotenz. Auch der bereits-gelivete `lineup-reminders`-Cron muss nachgezogen werden.
3. **C6 HIGH — Foto-EXIF-GPS-Leak** (Phase 1): iPhone-Fotos enthalten `GPSLatitude/Longitude` der Wohnadresse. Direkt-Upload = DSGVO Art.5(1)(c)-Verstoß. **Prevention:** Browser-Canvas-Re-Encoding (entfernt EXIF automatisch beim `canvas.toBlob()`) + Resize 512×512 WebP + `octet_length < 200000`-RLS-Constraint + exiftool-Smoke-Test.
4. **C7 HIGH — DSGVO-Consent ohne Workflow** (Phase 1): `consent_photo`/`consent_liga_data`/`consent_whatsapp`/`consent_accepted_at` sind im Schema, aber kein Code-Pfad erzwingt sie. Foto-Upload ohne dokumentierte Einwilligung = DSGVO Art.7-Verletzung. **Prevention:** Onboarding-Modal blockt Profil-Editing bis Consent gegeben; Foto-Upload-Button disabled wenn `consent_photo=false`; Widerruf-Pfad in EinstellungenTab; statische `/privacy`-Seite (Vorstand-textlich gegenliest, kein Code-Task).
5. **C10 HIGH — Demo-Mock-Daten landen in Production-DB** (Phase 0 + Phase 5): Statistik-Mock-Daten ohne `is_demo`-Flag werden zum Sommer-Rollout-Blocker. **Prevention:** Alle neuen Tabellen bekommen `is_demo BOOLEAN DEFAULT false` in Phase 0; Production-Views filtern `WHERE NOT is_demo`; Cleanup-Migration vorbereitet bevor erster Mock geseedet wird.

Weitere HIGH-Severity-Items mit Phase-Mapping in `.planning/research/PITFALLS.md`: C4 (Stat Cross-Saison-Mix → Phase 4 Schema-Migration `season`-Spalte), C5 (Poll-Vote-Manipulation → Phase 3 RLS `WITH CHECK (now() < closes_at)`), C9 (Push-Opt-Out via Tippfehler bypass-bar → Phase 0 zentrale `PUSH_PREFS`-Konstante), C11 (RLS-Activation bricht Captain-Workflow → Phase 1 Audit-Sweep), C14 (GCal-Dup-Guard skipped Vereins-Termine am Match-Tag → Phase 3 Guard auf `external_id` umstellen), C15 (Demo-Snapshot fehlt → Phase 5 Operational).

→ Full detail mit Recovery-Strategien: `.planning/research/PITFALLS.md`

---

## Implications for Roadmap

**Reconciliation note:** FEATURES.md schlägt Selfservice → Training+Events parallel → Statistik vor; ARCHITECTURE.md proposes linear Selfservice → Training → Events/Push → Statistik; PITFALLS.md fordert Phase 0 + Phase 5 für 5+ Phasen / 24-Tage-Budget. **Diese Roadmap reconciliiert auf 6 Phasen mit klarer Sequenz und einem optionalen Parallelfenster (Phase 2 + Phase 3).**

### Phase 0 — Cross-Cutting Foundations (NON-NEGOTIABLE)

**Rationale:** Die zwei BLOCKER-Pitfalls (C1 RLS-Pin, C3 TZ-Helper) müssen vor jeder Feature-Phase fixed sein. Außerdem zahlen sich Cross-cutting-Investments (`is_demo`, `PUSH_PREFS`-Konstante, Resize-Util) in **jeder** Folgephase aus. Wenn Phase 0 übersprungen wird, ist jede Feature-Phase entweder unsicher oder wiederholt dieselbe Implementierung 4×.

**Delivers:**
- Migration `players.email NOT NULL UNIQUE` + lower()-Normalisierung + Pre-Deploy-Audit-Script.
- RLS-Policy-Refactor mit `WITH CHECK (id = …)`-Pin auf `players.self update`.
- `$lib/server/timezone.js` mit `nowVienna()`/`dateInVienna(offsetDays)` + Refactor des bereits-gelieferten `lineup-reminders`-Cron.
- `reminder_log(plan_id, kind, sent_at)`-Tabelle für Idempotenz-Guard.
- `$lib/constants/pushPrefs.js` zentrale Konstante + DB-CHECK auf JSONB-Keys.
- `is_demo BOOLEAN DEFAULT false` als Pattern-Doku + Migration-Vorlage.
- `$lib/utils/imageResize.js` Browser-Canvas-Resize-Helper (512×512 WebP, EXIF-strip).

**Avoids:** C1, C3, C6, C9, C10 (Demo-Mock-Trap), und partial C5/C11.
**Duration:** 2 Tage. **Key risks:** RLS-Activation-Audit könnte unentdeckte 401/403-Pfade zutage fördern (Pitfall C11 — Mitigation: Browser-Network-Tab nach Migration-Deploy auf 401/403-Spike beobachten).

### Phase 1 — F2 Spieler-Selfservice + Foto + Consent

**Rationale:** Selfservice ist isoliert (`/profil` only), brownfield-Risiko-frei, **und** Foundation für Phase 4 (Statistik braucht Foto + Identität in PlayerStatsView) und Phase 3 (Event-RSVP-Listen mit Avatar). Migration `20260422_profil_selfservice.sql` hat 80% der DB-Spalten bereits gelegt — reine Frontend-Arbeit + Storage-Bucket + Consent-Workflow.

**Delivers:**
- Migration `20260429_player_photos.sql` (Bucket + `photo_url`-Spalte + RLS-Policies).
- `ProfilDatenSheet` erweitert (alle Felder) mit valibot-Validation.
- `ProfilFotoSheet` NEU mit Resize-Pipeline (Phase-0-Util).
- `imgPath()` Storage-Branch.
- DSGVO-Consent-Onboarding-Modal + statische `/privacy`-Seite.
- Profil-Vervollständigungs-Score (Progress-Ring + Konfetti).

**Addresses (FEATURES.md):** F2 alle table-stakes + Vervollständigungs-Score-Differentiator.
**Avoids:** C2, C6, C7, C11.
**Duration:** 4-5 Tage. **Key risks:** `imgPath()`-Erweiterung bricht alte Avatare bei Aufstellungen — Smoke-Test alle Lineup-Listen; Consent-Modal-UX bei Bestands-Spielern (Force-Through-Flow planen).

### Phase 2 — F1 Trainingsbuchung-Vollausbau

**Rationale:** DB-Foundation steht (RPCs `book_training_lane`/`cancel_training_booking` live). Phase 4 (Statistik) braucht `view_player_training_count` — die View muss exist + UI-getestet sein, bevor Stats darauf bauen. Berührt Kalender nur read-only (Lane-Strip-Visualisierung).

**Delivers:**
- `TrainingDetailSheet` erweitert (Warteliste-UI, Storno mit Frist).
- Auto-Promote-RPC `promote_waitlist_on_cancel(p_date, p_start)` + Push-Trigger (über `push_outbox` aus Phase 3, oder direkt-fire wenn Phase 3 noch nicht steht).
- `TrainingsListeAdminSheet` NEU (Kapitän).
- `TrainingsStatsCard` (Donut + Streak) im Profil.
- `LaneStrip`-Primitive in WocheTab/MonatTab.
- `/api/cron/training-reminders` (24h-Voraus).
- `book_training_lane` RPC-Patch: `EXCEPTION WHEN unique_violation → status='lane_just_taken'` (Pitfall C8).

**Addresses (FEATURES.md):** F1 alle table-stakes.
**Avoids:** C8 (Booking-Race-UX).
**Duration:** 4-5 Tage. **Key risks:** Lane-Strip in MonatTab könnte visuell brechen — **Designer-Spec vor Frontend-Implementation** ist hier hartes Gate.

### Phase 3 — F4 Events + Polls + Push systematisch

**Rationale:** Push-Outbox-Pattern ist die größte Neu-Infra der v1 — eigene Phase verdient. Polls-Schema-Formalisierung (`target_event_id` FK) muss vor Event-Sheet-Erweiterung stehen. GCal-Dup-Guard-Refactor (C14) muss vor Event-Bau, sonst verschwinden Vereins-Events am Match-Tag. **Parallelisierbar mit Phase 2** (disjunkte UI-Scopes: Phase 2 = Kalender-Training-Sheets, Phase 3 = Kalender-Event-Sheets + Dashboard-Polls; gemeinsamer Push-Cron-Pattern aber Phase 0 hat den Helper schon gelegt). **Default: seriell nach Phase 2**, weil 24-Tage-Budget knapp ist und Reviewer-Phase pro Phase nicht skippable.

**Delivers:**
- Migration `20260430_push_outbox.sql` (queue + RLS).
- Migration `20260501_poll_event_link.sql` (`polls.target_event_id` FK).
- GCal-Dup-Guard-Refactor auf `external_id` (C14).
- `/api/cron/scheduled-push` (15min, idempotent via `sent_at IS NULL`).
- `EventCreateSheet` erweitert (Reminder-Toggle + optional gekoppelter Poll).
- `EventDetailSheet` erweitert (Poll-Liste via `PollCard`-Reuse).
- `PollCreateSheet` NEU (kapitän, Dashboard-Action).
- Push-Settings pro Event-Typ in EinstellungenTab (nutzt Phase-0-`PUSH_PREFS`-Konstante).
- Vote-Once-PK + RLS `WITH CHECK (now() < closes_at)` auf `poll_responses` (C5).

**Addresses (FEATURES.md):** F4 alle table-stakes + Time-Poll-Differentiator.
**Avoids:** C5, C9, C12, C14.
**Duration:** 5-6 Tage. **Key risks:** Outbox-Cron muss idempotent bleiben (Vercel-Retries); `EventCreateSheet`-Erweiterung darf bestehenden GCal-Push-Flow nicht brechen (additive Felder only).

### Phase 4 — F3 Statistik-Dashboards

**Rationale:** Read-only-Feature → kein Datenkorruption-Risiko, sicherer "Nachzügler". Profitiert von Phase 1 (Foto in PlayerStatsView), Phase 2 (`view_player_training_count`), Phase 0 (`is_demo`-Flag für Mock-Liga). Bietet beste JHV-Demo-Wirkung — chronologisch nahe am 22.05. ausliefern für maximale Frische.

**Delivers:**
- Migration `20260502_stats_views.sql` (`view_player_season_stats`, `view_player_training_count`, RPC `compare_seasons`).
- Migration `20260503_league_standings.sql` (Tabelle + RLS).
- Schema-Härtung gegen Cross-Saison-Mix: `season`-Spalte oder `match_id`-FK auf `game_plans` (C4).
- `StatsView` mit 3 Sub-Tabs (mannschaft|spieler|liga) via lokalem `$state`.
- `PlayerStatsView`, `LeagueTableCard`, `FormCurveChart` (layerchart oder inline-SVG), `ComparisonSheet`.
- Mini-Stats-Card auf `/profil` (Reuse `PlayerStatsView`).
- Mock-Liga-Tabelle-Seed (`is_demo=true`).

**Addresses (FEATURES.md):** F3 alle table-stakes + Form-Trend-Indikator-Differentiator.
**Avoids:** C4 (Cross-Saison), C13 (Stat-Performance — wenn Mat-View nötig wird, in Phase 5 nachziehen).
**Duration:** 5-6 Tage. **Key risks:** Liga-Tabelle erfordert Konkurrenten-Daten — Captain-Tool zum manuellen Befüllen oder hardcoded JSON-Mock; Schema-Migration `season`-Spalte rückwärts-befüllen ist riskant bei Bestandsdaten.

### Phase 5 — Demo-Härtung + Reviewer-Pass

**Rationale:** Pitfall C15 (kein Snapshot vor Demo) + "Looks Done But Isn't"-Checklist (10 Items) sind Operational, kein Code-Feature, aber blockierend für eine vertrauenswürdige JHV-Demo. Auch: jeder gesammelte Pitfall-Verification-Schritt aus Phase 0-4 wird hier final geprüft. Reviewer-Phase ist explizit not-skippable laut PITFALLS.md Cross-Phase-Concern.

**Delivers:**
- DB-Snapshot 3 Tage vor JHV (Supabase Pro Backup + lokale Kopie).
- Demo-Login = read-only-Account, niemals Captain-Rolle.
- Cleanup-Migration vorbereitet (`DELETE … WHERE is_demo`).
- Vollständige "Looks Done But Isn't"-Checklist abarbeiten (Pitfalls-File Zeile 617-630).
- Reviewer-Pass über alle Phase-1-4-Diffs.
- Smoke-Test 1-Minuten-Reminder-Outbox vor JHV (C3-Verifikation).
- exiftool-Test auf 5 Sample-Avatars (C6-Verifikation).
- Concurrent-Booking-Test mit zwei Sessions (C8-Verifikation).
- Push-Subscription-Cleanup-Cron initial deployen (C12).

**Addresses:** Operational-Quality, kein Feature.
**Avoids:** C15 (Demo-Datenverlust), reduziert alle Restrisiken aus Phase 1-4.
**Duration:** 2-3 Tage. **Key risks:** Reviewer-Findings könnten Re-Work in Phase 1-4 triggern — Buffer im 24-Tage-Budget bewusst dafür.

### Phase Ordering Rationale

- **Phase 0 zuerst non-negotiable**, weil C1 + C3 BLOCKER sind und in jeder Folgephase Re-Implementation kostet, wenn nicht zentral gelöst.
- **Phase 1 (Selfservice) sequentiell zweite**, weil Foto + Identität Voraussetzung für hübsche Statistik (Phase 4) und schöne Event-RSVP-Listen (Phase 3). FEATURES.md `Feature Dependencies (Cross-Area)` belegt das explizit (`F2 blocks F3 & F4 & F1-Stats`).
- **Phase 2 (Training) und Phase 3 (Events/Push) können parallel**, weil disjunkte UI-Files (Kalender-Training-Sheets vs. Kalender-Event-Sheets + Dashboard-Polls) und der gemeinsame Push-Cron-Pattern bereits in Phase 0 vorbereitet ist. **Default-Empfehlung: seriell** (Phase 2 → Phase 3), weil 24-Tage-Budget mit 6 Phasen knapp ist und parallele Kapazität nicht garantiert. ARCHITECTURE.md ordnet linear, FEATURES.md erlaubt parallel — beide sind kompatibel.
- **Phase 4 (Statistik) zuletzt**, weil sie Trainings-Daten + Foto + (optional) Liga-Tabelle aus Vorphasen verbraucht und read-only ist (sicherster Nachzügler).
- **Phase 5 (Demo-Härtung) operational nicht skippable**, weil Reviewer-Pass und Backup-Strategie laut Pitfalls C10/C15 sonst Sommer-Rollout-Blocker werden.

### Research Flags

Phasen, die während Plan-Phase noch tiefere Research brauchen (`/gsd-research-phase`):

- **Phase 4 (Statistik):** Liga-Tabelle-Datenquelle (manueller Captain-Seed vs. ÖSKB-Feed-Import) ist offen — Designer/Plan-Phase muss klären, ob Mock-Daten reichen oder echter Feed-Import Sinn macht. Auch: `lane_id` in `match_results` für Bahn-Statistik-Differentiator — verifizieren bevor Bahn-Statistik geplant wird.
- **Phase 1 (Selfservice):** DSGVO-`/privacy`-Seite ist text-getrieben, kein Code-Task — Vorstand-Workflow für Gegenlesen muss vor Phase 1 klar sein. Auch: `MEMORY.md → project_player_fields_unverified` muss aufgelöst werden (welche Spalten existieren tatsächlich vs. UI-Referenzen).
- **Phase 3 (Events/Push):** GCal-Dup-Guard-Refactor (C14) berührt Production-Sync — Edge-Cases (was passiert mit existierenden skipped Events?) brauchen kurze Research.

Phasen mit Standard-Patterns (skip research-phase):

- **Phase 0:** Reine Cross-cutting-Implementierung, alle Pattern dokumentiert.
- **Phase 2 (Training):** Brownfield-Erweiterung, RPC + UI-Pattern etabliert.
- **Phase 5 (Demo-Härtung):** Operational-Checklist, kein Feature-Research nötig.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Alle Versionen via npm-Registry verifiziert (2026-04-28); Patterns via Supabase/Vercel-Docs bestätigt; layerchart 2-next ist Pre-1.0 → einziger MEDIUM-Punkt, mitigiert durch exakte Version-Pin. |
| Features | HIGH | 10+ Vendor-Apps systematisch verglichen (Spond, TeamSnap, SpielerPlus, Heja, easyVerein, Web4Kegeln, Sportwinner, BowlSheet, LaneTalk); Brownfield-Status pro Feature gegen Codebase + MEMORY.md verifiziert; Demo-Deadline 22.05. hart-bounded. |
| Architecture | HIGH | Alle Aussagen durch existierenden Code/Migrations verifiziert; Patterns 1:1 aus shipped `.planning/codebase/ARCHITECTURE.md` + STRUCTURE.md + STACK.md übernommen; keine Greenfield-Spekulation. |
| Pitfalls | HIGH | Project-spezifisch: jede C1-C15 hat code/config-level prevention mit konkretem File:Line-Verweis; CONCERNS.md (live audit 2026-04-28) als Basis, plus DSGVO/DSG-2018-Recherche und Web Push API Spec (RFC 8030). |

**Overall confidence:** HIGH — gestützt durch Brownfield-Realität (Code existiert, Migrations sind real lesbar), nicht durch Greenfield-Annahmen.

### Gaps to Address

- **Liga-Tabelle-Datenquelle (Phase 4):** Captain-Manuell vs. externer Feed (ÖSKB/NÖSKB) ungeklärt. **Handle in Plan-Phase Phase 4:** Default-Empfehlung Captain-Manuell + `is_demo`-Mock; Feed-Import als v1.1-Backlog.
- **Bahn-Statistik (`lane_id` in `match_results`):** existiert vs. fehlt unverifiziert. **Handle in Plan-Phase Phase 4:** Schema-Verify im Researcher-Brief; falls fehlt → Bahn-Statistik aus Phase 4 cut, nach v1.1 schieben.
- **Liga-Position-Schema (`league_standings`):** Migration in Phase 4, aber Punkte-Logik (2:0=2pkt, 1:1=1pkt etc.) noch nicht validiert mit Vereins-Realität — Captain/Vorstand-Rückfrage in Plan-Phase.
- **PLAYER_FIELDS unverified (MEMORY.md):** Profil/UebersichtTab referenziert Spalten, die laut MEMORY in keiner Migration definiert sind. **Handle in Phase 1 Plan-Briefing:** Researcher-Sweep vor Frontend-Dev.
- **Reviewer-Phase-Kapazität:** Cross-Phase-Concern (PITFALLS.md Zeile 681-690) warnt vor Velocity-Trap. **Handle:** Phase 5 explizit als Reviewer-Slot, jede Phase 1-4 hat 0.5-Tag-Reviewer-Budget eingerechnet.
- **Familien/Gäste read-only-Tier:** PROJECT.md-Constraint, aber laut FEATURES.md "Familie-Tier ist eigenes Schema-Feature, funktional erst nach v1-Demo notwendig". **Handle:** Aus v1-Scope cut, in Roadmap-Out-of-Scope mit Verweis dokumentieren.

---

## Sources

### Primary (HIGH confidence)

- **Stack Research:** npm registry queries (verified 2026-04-28) für `layerchart@2.0.0-next.59`, `valibot@1.3.1`, `@internationalized/date@3.12.1`; Context7 `/techniq/layerchart`; Supabase Storage Access Control docs; Vercel Cron Pricing/Changelog.
- **Architecture Research:** `C:\kvwn\.planning\codebase\ARCHITECTURE.md`, `STRUCTURE.md`, `STACK.md`; Migrations `20260421_training_lanes.sql`, `20260422_profil_selfservice.sql`, `20260423_gcal_sync.sql`, `20260427_event_rsvps.sql`; live API-Routes `/api/push/notify`, `/api/cron/lineup-reminders`.
- **Pitfalls Research:** `.planning/codebase/CONCERNS.md` (live audit 2026-04-28); shipped Cron-Code mit identifizierten Bugs; DSGVO/DSG 2018 (Austrian implementation, Art.5/6/7/15-17/34); Web Push API spec RFC 8030.
- **Features Research:** Vendor-Product-Pages + Help-Docs für Spond, TeamSnap, SpielerPlus, Heja, easyVerein, Web4Kegeln/Sportwinner Kegeln, BowlSheet, LaneTalk, BSKV-App.

### Secondary (MEDIUM confidence)

- LayerChart Releases/Changelog (2-next = Svelte 5 line, 49 next-Releases in 2026 — aktive Entwicklung, aber Pre-1.0).
- Builder.io Valibot Bundle-Size-Analysis (1.37 kB vs Zod 17.7 kB).
- Spond/TeamSnap/SpielerPlus comparative marketing claims (`spond.com/compare/spielerplus`, FlagFootball.Rocks).

### Tertiary (LOW confidence)

- (keine — alle Aussagen entweder durch existierenden Code oder durch HIGH-Quelle gestützt)

### KVWN-internal Context (mandatory reading)

- `C:\kvwn\.planning\PROJECT.md` (Vision, v1-Active-Requirements, JHV-Stichtag, v2-Roadmap-Ausblick)
- `C:\kvwn\CLAUDE.md` (Routes, Subtab-Pattern, Live-Features, Design-Token-System, RLS-Patterns)
- `C:\Users\benni\.claude\projects\C--kvwn\memory\MEMORY.md` (Brownfield-Blocker: `game_plans.opponent_score`, `league_standings`-Schema fehlt, PLAYER_FIELDS unverified, Spielbetrieb-ManageSheet-Trap)

---

*Research completed: 2026-04-28*
*Ready for roadmap: yes*
*Total research budget consumed: 4 parallel researcher agents + 1 synthesizer = 5 agent-runs*
