# KVWN Vereins-App

## What This Is

Vollumfängliche Web-App (PWA) für KV Wiener Neustadt — Kegelverein. Sie ersetzt die bisher
händischen Vereins-Workflows (WhatsApp, Excel, Papier) durch eine zentrale Plattform für
Spielbetrieb, Trainingsorganisation, Statistiken, Events und Vereinsverwaltung — schön gestaltet,
mobil-first, in österreichischem Deutsch.

## Core Value

**Alles unter einem Dach** — kein einzelnes Killer-Feature, der Wert entsteht durch die
Konsolidierung aller Vereinsworkflows in einer App, die so schön und durchdacht ist, dass
Spieler und Familie sie freiwillig nutzen.

## Requirements

### Validated

<!-- Live in Production, im täglichen Vereins-Einsatz. -->

- ✓ **Auth (Google OAuth)** — Login + Session-Persistenz über `players.email` als RLS-Brücke
- ✓ **Spielbetrieb-Cockpit** — 4 Top-Tabs (spiele · turniere · landesbewerbe · statistiken),
  Inline-Aufstellung, Match-Workflow-Karten (`mw-card`/`mw-btn`/`mw-field`)
- ✓ **Aufstellungs-Bestätigung** — Spieler bestätigen ihre Spieltag-Nominierung
- ✓ **Post-Match-Feedback** — Rotations-System mit `feedbackRotation`, getriggert via
  `/spielbetrieb?feedback=<id>` (Wiring 2026-04-27)
- ✓ **Dashboard v2** — Tabs `neuigkeiten` + `events`, geliefert für Prototype-Demo 2026-04-26/27
- ✓ **Kalender** — view-modes agenda/woche/monat, Tab-frei (lokales `$state`)
- ✓ **Profil** — uebersicht/einstellungen/admin (kapitaen-gated)
- ✓ **Push-Notifications** — Web-Push via `/api/push/notify` + VAPID-Schlüssel + Service-Worker
- ✓ **Google-Calendar-Sync** — bidirektional via `/api/cron/gcal-sync` (pull, */15 cron) und
  `/api/gcal/events` (push/patch/delete, captain-gated); Match-Datum-Dup-Guard; live seit 2026-04-23
- ✓ **Trainingsbuchung-Basis** — `book_training_lane` / `cancel_training_booking` RPCs, Bahnen
  pro Slot, `training_specials` für einmalige Sessions, `training_waitlist` (Migration
  `20260421_training_lanes.sql`)
- ✓ **Captain-Tools** — `invite-player` Edge-Function (Supabase) für Onboarding
- ✓ **Design-System** — Tokens (`--color-primary #CC0000` / `--color-secondary #D4AF37`),
  Schriften Lexend + Public Sans, Spacing-Scale, Radius/Shadow-Tokens, rot-getönte Schatten
- ✓ **PWA-Auslieferung** — Vercel Pro, Service-Worker, mobile-first

### Active

<!-- v1-Scope bis JHV 22.05.2026 (Demo-ready). -->

- [ ] **Trainingsbuchung-Vollausbau** — Warteliste-UI, Erinnerungen, Trainings-Statistik
      (wer wie oft trainiert), Slot-Templates, Storno-Workflow, Bahn-Übersicht im Kalender
- [ ] **Spieler-Selfservice Stammdaten** — Spieler tragen Telefon, Adresse, Geburtstag, Foto,
      Lizenz-Nummer und Notfallkontakt selbst ein; Kapitän nur noch für initialen Invite zuständig
- [ ] **Statistik-Dashboards** — Saison-Schnitt, Form-Kurve, Liga-Tabelle, historische Vergleiche,
      personalisierte Spieler-Statistik-Seite
- [ ] **Events + Umfragen + Push systematisch** — Event-Organisation (Vereinsabende,
      Ausflüge, Saisonschluss), In-App-Umfragen/Polls, systematische Push-Notifications für
      alle Event-Typen (nicht nur ad-hoc)

### Out of Scope

<!-- Bewusste Grenzen mit Begründung. -->

- **Multi-Tenant für andere Kegelvereine** — Vision ist KVWN-spezifisch, kein
  Plattform-Anspruch; Re-Use durch Code-Fork ok, aber keine Tenant-Architektur
- **Öffentliche Sponsor-Webseite / SEO-Marketing** — Sponsoren-Modul ist intern (Pflege,
  Akquise-Tasks, Kontaktdaten), nicht öffentliche Sichtbarkeit
- **Marketing-Website für externe Vereine / KVWN-Public-Page** — App ist Vereins-internes
  Tool, keine Außenwirkung über Mitglieder/Familie hinaus
- **Replace bestehender Stack** — kein Migration zu anderem Framework/DB; SvelteKit + Supabase
  + Vercel bleiben
- **Tests/Lint/Format-Toolchain** — bewusst keine Test-Suite, Velocity vor Ceremony

## Context

**Vereinskontext** — KV Wiener Neustadt, Kegelverein in Niederösterreich, ~20-40 aktive Spieler,
mehrere Mannschaften (Liga + Turnier + Landesbewerbe), Trainingsbetrieb auf vereinseigenen
Bahnen. Verein hat Bedarf an Familien/Gäste-Sichtbarkeit für Spielpläne und Events.

**Sprache** — Alle UI-Strings auf österreichischem Deutsch ("Jänner" nicht "Januar",
"E-Mail" nicht "Email").

**Brownfield-Status** — App existiert seit Monaten produktiv, substanzieller Codebase
(`.planning/codebase/` 7 Files), erste Demo bei Verein vor JHV bereits gelaufen
(2026-04-26/27). Dieses GSD-Projekt definiert die Vision-Frame und die nächste Iteration
(v1 zur JHV) plus mittelfristige Roadmap (v2/v3).

**v2-Roadmap-Ausblick** (nicht v1, aber geplant — landen in REQUIREMENTS.md als Deferred):
Organisation eigener Turniere, interne Vereinsmeisterschaften, Sponsoren-Pflege intern,
Kantinen-Besetzung, Vereinsfinanzen (Beiträge/Strafen/Trainingsgebühren), Live-Score-Eingabe
während Match (Kegel-für-Kegel).

**v3-Roadmap-Ausblick** — Lagerstand Kantine (Getränke/Essen) — bewusst spät, weil hardware/
inventarisierung-Workflow erstmal andere Probleme hat.

**JHV-Demo 22.05.2026** — Stichtag ist Demo-ready bei der nächsten Jahreshauptversammlung
(JHV); dort entscheidet der Verein über App-Adoption als offizielles Tool. Demo-ready =
klick-bar, überzeugend, Daily-Use-Features funktional, Statistiken/Events können noch
Mock-Daten zeigen wo Live-Daten fehlen.

## Constraints

- **Tech-Stack**: SvelteKit 5 (Runes) + Supabase (Postgres + Google Auth) + Vercel (Node 22)
  + JavaScript only — kein TypeScript. Locked durch bestehenden Code, kein Rewrite.
- **DB-Pattern**: Alle DB-Calls browser-seitig via `sb` aus `$lib/supabase.js`, KEINE
  `+page.server.js`. RLS-Bridge: `auth.jwt() ->> 'email'` ↔ `players.email`.
- **Sprache**: UI durchgehend österreichisches Deutsch.
- **Timeline**: JHV 22.05.2026 — Demo-ready (nicht Production-ready) für alle 4 v1-Features.
- **Design-System**: Nur Tokens aus `src/app.css`, niemals hardcoded Farben/Spacing/Radien;
  Schatten rot-getönt (nie `rgba(0,0,0,x)`).
- **Mobile-first PWA**: Spieler nutzen primär Smartphone, Desktop sekundär.
- **Datenschutz**: Spieler-Stammdaten + Vereinsfinanzen sind sensibel — RLS muss bei jedem
  Selfservice-Feature mitgedacht werden, kein Server-Bypass.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Vision-Spec-Frame statt Re-Spec ground-up | Bestehender Code substanziell, kein Rewrite-Budget; Validated = live, Roadmap = was fehlt | — Pending |
| Core Value = Konsolidierung statt einzelnes Killer-Feature | "Alles unter einem Dach" treibt Verein-Adoption stärker als jedes Einzel-Feature | — Pending |
| v1 Demo-ready zur JHV statt Production-ready | 24 Tage zu kurz für 4 Production-Features; Demo überzeugt JHV genauso | — Pending |
| Read-only-Tier für Familie/Gäste | Verein lebt von Community-Sichtbarkeit, Spielpläne/Events öffentlich für engsten Kreis | — Pending |
| Multi-Tenant ausgeschlossen | Fokus auf KVWN, kein Plattform-Anspruch — vermeidet Tenant-Komplexität | — Pending |
| Sponsoren-Modul rein intern | Sponsor-Marketing nicht Kern-Aufgabe; öffentliche Sichtbarkeit braucht Vereinsseite, nicht App | — Pending |
| Vereinsfinanzen v2 (nicht v1) | Hochsensibel + komplex (Beiträge, Strafen, Trainingsgebühren); braucht eigenen Diskurs vor Bau | — Pending |
| Lagerstand Kantine erst v3 | Hardware/Inventarisierungs-Workflow noch unklar, andere Pains haben Vorrang | — Pending |
| Stack-Lock SvelteKit + Supabase + Vercel | Keine Migration; Velocity > Stack-Modernisierung | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-28 after initialization*
