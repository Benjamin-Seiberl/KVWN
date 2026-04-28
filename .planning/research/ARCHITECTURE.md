# Architecture Research

**Domain:** Vereins-PWA (Brownfield-Erweiterung KVWN)
**Researched:** 2026-04-28
**Confidence:** HIGH (basiert direkt auf bestehender ARCHITECTURE.md / STRUCTURE.md / STACK.md + tatsächlichen Migrations + bestehender Push/Poll-Infra)

> **Wichtig:** Das ist KEIN Greenfield. Die Architektur ist gelocked: SvelteKit 5 (Runes) + Supabase + Vercel,
> alle DB-Calls browser-seitig via `sb`, RLS-Bridge `auth.jwt() ->> 'email' ↔ players.email`,
> Subtab-Router (`PAGE_CONFIG` + `currentSubtab`), `BottomSheet` als Modal-Primitive,
> `.mw-card`/`.mw-btn` als Match-Workflow-Klassen, alle Strings österreichisches Deutsch.
> Diese Research dokumentiert, **wie** die 4 v1-Features konformistisch reingewebt werden — nicht ob.

---

## System Overview (Ist + v1-Erweiterungen)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  SvelteKit 5 (Runes) — Browser SPA                       │
│  src/routes/(app)/  — Auth-guarded shell (BottomNav, Spotlight, …)      │
├──────────┬─────────────┬──────────────┬──────────┬──────────────────────┤
│Dashboard │  Kalender   │ Spielbetrieb │  Profil  │  + statistiken (NEU) │
│ (existiert)│ (existiert)│ (existiert) │(existiert)│ Top-Level oder Subtab│
│          │             │              │          │  → siehe Phase 3     │
└────┬─────┴──────┬──────┴──────┬───────┴────┬─────┴──────────┬───────────┘
     │            │             │            │                │
     │  v1-Hooks  │ v1-Hooks    │ v1-Hooks   │ v1-Hooks       │
     │  Polls     │ TrainingTab │ (neutral)  │ Selfservice +  │ Drill-down
     │  EventCard │ erweitert   │            │ Foto-Upload    │ aus Spielbetrieb
     ▼            ▼             ▼            ▼                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Component-Layer — $lib/components/{dashboard,kalender,spielbetrieb,    │
│                                      profil,admin,statistiken,events,   │
│                                      training (NEU)}                    │
│  Reuse: BottomSheet, .mw-card, .mw-btn, .mw-field, ToggleSwitch, Pill…  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  State / Stores — $lib/stores/{auth,subtab,toast,spotlight,scroll}      │
│  + KEINE neuen globalen Stores für v1 nötig (per-Feature `$state`)      │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Browser Supabase Client `sb` (anon, RLS-gated)                         │
│  RLS-Bridge: auth.jwt() ->> 'email' ↔ public.players.email              │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  PostgreSQL (Supabase)                                                  │
│  Bestehend: players, matches, game_plans, events, polls, poll_options, │
│  poll_votes, event_rsvps, training_*, push_subscriptions, ...           │
│  v1 NEU:                                                                 │
│   - push_outbox (scheduled push queue)                                   │
│   - poll_options.target_kind / target_event_id (poll ↔ event Bindung)   │
│   - mv_player_season_stats / view_team_form (Statistik-Aggregationen)   │
│   - Storage-Bucket `player-photos` (Foto-Upload, RLS analog `attests`)  │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  Server-Layer — src/routes/api/*  +  src/lib/server/*                   │
│  Bestehend: /api/cron/{gcal-sync,lineup-reminders,keyduty-check}        │
│             /api/gcal/events, /api/push/notify, /api/training/cancel    │
│  v1 NEU:                                                                 │
│   - /api/cron/scheduled-push         (alle 15min, leert push_outbox)    │
│   - /api/cron/training-reminders     (täglich, Erinnerung 24h vorher)   │
│   - /api/events/poll                 (optional, bei Multi-Choice-CRUD)  │
└─────────────────────────────────────────────────────────────────────────┘
```

**Ergebnis-Verdict:**

| v1-Feature                      | Eingriff | Risiko ggü. shipped Code | Build-Order |
|---------------------------------|----------|--------------------------|-------------|
| Spieler-Selfservice + Foto      | gering   | minimal (Profil ist isoliert) | **Phase 1** |
| Trainingsbuchung-Vollausbau     | mittel   | gering (Training ist eigene Domain) | **Phase 2** |
| Events + Umfragen + Push        | mittel   | gering (Events/Polls existieren als Tische) | **Phase 3** |
| Statistik-Dashboards            | mittel   | gering (read-only, separater Top-Tab) | **Phase 4** |

Build-Order-Begründung steht ausführlich am Ende.

---

## Komponenten-Verantwortlichkeiten (pro v1-Feature)

### Feature 1 — Spieler-Selfservice Stammdaten + Foto-Upload

| Komponente                          | Verantwortung                                                                                | Datei (NEU/erweitern)                                       |
|-------------------------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| `ProfilDatenSheet.svelte`           | Bestehendes Edit-Sheet **erweitert** um Adresse/Tel/Geburtstag/Lizenz/Notfallkontakt-Felder | erweitern (`src/lib/components/profil/ProfilDatenSheet.svelte`) |
| `ProfilFotoSheet.svelte` (NEU)      | Upload via `<input type="file">`, Crop (square 512x512), Upload zu Storage-Bucket           | `src/lib/components/profil/ProfilFotoSheet.svelte`          |
| `ProfilHeroCard.svelte`             | Liest Foto via `imgPath()` mit neuem Storage-Path-Branch                                    | erweitern (Zeile rund um `imgPath()`)                       |
| `imgPath()` in `$lib/utils/players` | Erweitern: erst `players.photo_url` (Storage-Public-URL) prüfen, sonst Fallback auf `static/images/<photo>.jpg` | erweitern                                                   |

**Wo lebt das?**
Kein neuer Top-Level-Route. Reine **Erweiterung** der `/profil` Subtabs `uebersicht` + `einstellungen`.
Migration `20260422_profil_selfservice.sql` hat die DB-Spalten + Storage-Bucket `attests`-Pattern bereits gelegt;
das Foto bekommt dasselbe Pattern in einem **neuen** Bucket `player-photos`.

---

### Feature 2 — Trainingsbuchung-Vollausbau

| Komponente                          | Verantwortung                                                                                | Datei (NEU/erweitern)                                       |
|-------------------------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| `TrainingDetailSheet.svelte`        | Bestehend; **erweitern** um Warteliste-Anzeige (Position) + Storno-Button                   | erweitern (`src/lib/components/kalender/TrainingDetailSheet.svelte`) |
| `TrainingBookingSheet.svelte`       | Bestehend (Dashboard); **erweitern** um Lane-Picker + Waitlist-Hinweis                      | erweitern (`src/lib/components/dashboard/TrainingBookingSheet.svelte`) |
| `TrainingsStatsCard.svelte` (NEU)   | Card auf Profil/Übersicht: "Du warst diese Saison X/Y mal beim Training"                    | `src/lib/components/profil/TrainingsStatsCard.svelte`       |
| `TrainingsListeAdminSheet.svelte` (NEU) | Kapitän sieht alle Buchungen pro Slot inkl. Warteliste, kann manuell verschieben        | `src/lib/components/admin/TrainingsListeAdminSheet.svelte`  |
| `WocheTab` / `MonatTab`             | **Erweitern**: Bahn-Belegung als kleine Lane-Strip-Visualisierung pro Trainingsslot         | erweitern (`src/lib/components/kalender/{WocheTab,MonatTab}.svelte`) |
| `/api/cron/training-reminders/+server.js` (NEU) | Vercel-Cron, ruft `push_outbox`-Queue indirekt via `/api/push/notify` auf          | `src/routes/api/cron/training-reminders/+server.js`         |

**Wo lebt das?**
Kein neuer Top-Level-Route — die UI-Hooks liegen in **existierenden** Bereichen:
- Buchen/Storno-Sheet im Kalender (`TrainingDetailSheet`)
- Dashboard-Quick-Action (`TrainingBookingSheet`)
- Spielerstatistik im Profil (`TrainingsStatsCard`)
- Admin-Übersicht im Profil-Admin-Tab (neue Card → öffnet `TrainingsListeAdminSheet`)

---

### Feature 3 — Events + Umfragen + Push (systematisch)

| Komponente                                  | Verantwortung                                                                                | Datei (NEU/erweitern)                                       |
|---------------------------------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| `EventCreateSheet.svelte`                   | Bestehend; **erweitern** um optional gekoppelten Poll (z.B. "Welcher Termin?" 3 Optionen)   | erweitern (`src/lib/components/kalender/EventCreateSheet.svelte`) |
| `EventDetailSheet.svelte`                   | Bestehend; **erweitern** um Polls die zu diesem Event gehören (Reuse `PollCard`)            | erweitern (`src/lib/components/kalender/EventDetailSheet.svelte`) |
| `PollCreateSheet.svelte` (NEU)              | Standalone-Poll-Erstellung (kapitän-only) — auch ohne Event möglich                         | `src/lib/components/dashboard/PollCreateSheet.svelte`       |
| `PollCard.svelte`                           | Bestehend (Dashboard); **wiederverwenden** in `EventDetailSheet` (Props-API existiert)      | unverändert                                                 |
| `EventReminderConfig.svelte` (NEU)          | Im EventCreate: "Erinnerung 24h vorher: [Toggle]"; schreibt Zeile in `push_outbox`          | `src/lib/components/kalender/EventReminderConfig.svelte`    |
| `/api/cron/scheduled-push/+server.js` (NEU) | Vercel-Cron alle 15min: liest `push_outbox WHERE send_at <= now()`, ruft `/api/push/notify`, markiert sent | `src/routes/api/cron/scheduled-push/+server.js`             |

**Wo lebt das?**
- Event-Erstellung lebt **weiterhin im Kalender** (`/kalender` → CreateButton → `EventCreateSheet`).
- Poll-Standalone-Erstellung kommt als **kapitän-Action im Dashboard** (Kachel "+ Umfrage starten" auf `Neuigkeiten`-Tab).
- Push-Erinnerungen sind **kein UI-Feature**, sondern transparent: jeder Event-Create kann optional eine Outbox-Zeile anlegen.

---

### Feature 4 — Statistik-Dashboards

| Komponente                          | Verantwortung                                                                                | Datei (NEU/erweitern)                                       |
|-------------------------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| `StatsView.svelte`                  | Bestehend (Mannschaftsschnitt); **erweitern** um Saison-Schnitt, Form-Kurve                 | erweitern (`src/lib/components/statistiken/StatsView.svelte`) |
| `PlayerStatsView.svelte` (NEU)      | Personalisierte Spieler-Seite: Schnitt, beste 5 Spiele, Form-Kurve, Training-Häufigkeit     | `src/lib/components/statistiken/PlayerStatsView.svelte`     |
| `LeagueTableCard.svelte` (NEU)      | Liga-Tabelle (KVWN + Konkurrenten); liest `view_league_standings` (NEU)                     | `src/lib/components/statistiken/LeagueTableCard.svelte`     |
| `FormCurveChart.svelte` (NEU)       | Inline-SVG-Chart (kein chart.js — vermeide Bundle-Bloat); 80px hoch, last-5-Spiele          | `src/lib/components/statistiken/FormCurveChart.svelte`      |
| `ComparisonSheet.svelte` (NEU)      | Drill-down: Vergleich Spieler A vs B oder aktuelle Saison vs Vorsaison                     | `src/lib/components/statistiken/ComparisonSheet.svelte`     |

**Wo lebt das?**
- Spielbetrieb hat bereits Top-Tab `statistiken` → **dort bleiben** (kein neuer Top-Level-Route).
  Erweitert um Tabs **innerhalb** der StatsView: `mannschaft | spieler | liga` (lokales `$state`,
  analog Kalender — kein neuer PAGE_CONFIG-Eintrag, weil sub-sub-tabs in `subtab.js` keinen
  Präzedenzfall haben).
- **Drill-down per Klick** auf Spieler-Reihe → `BottomSheet` mit `PlayerStatsView`.
- Spieler-Stats erscheinen **zusätzlich** als Mini-Card auf `/profil` (Reuse `PlayerStatsView` als Section).

---

## Empfohlene Projekt-Struktur (Diff zu Ist)

```
src/
├── routes/
│   ├── (app)/
│   │   ├── +page.svelte                  # Dashboard — Reminder-Setup-Hint hinzu
│   │   ├── kalender/+page.svelte         # +Lane-Strip in Woche/Monat
│   │   ├── spielbetrieb/+page.svelte     # statistiken-Tab erweitert
│   │   └── profil/+page.svelte           # +TrainingsStats-Card, +Foto-Upload-Trigger
│   └── api/
│       ├── cron/
│       │   ├── gcal-sync/+server.js          (existiert)
│       │   ├── lineup-reminders/+server.ts   (existiert)
│       │   ├── keyduty-check/+server.ts      (existiert)
│       │   ├── scheduled-push/+server.js     # NEU — leert push_outbox
│       │   └── training-reminders/+server.js # NEU — 24h-Voraus-Push
│       └── push/notify/+server.ts             (existiert — wird wiederverwendet)
└── lib/
    ├── components/
    │   ├── profil/
    │   │   ├── ProfilDatenSheet.svelte           (erweitern)
    │   │   ├── ProfilFotoSheet.svelte            # NEU
    │   │   └── TrainingsStatsCard.svelte         # NEU
    │   ├── kalender/
    │   │   ├── TrainingDetailSheet.svelte        (erweitern: Warteliste)
    │   │   ├── EventCreateSheet.svelte           (erweitern: +Poll +Reminder)
    │   │   ├── EventDetailSheet.svelte           (erweitern: +Poll-Liste)
    │   │   ├── EventReminderConfig.svelte        # NEU
    │   │   ├── WocheTab.svelte                   (erweitern: Lane-Strip)
    │   │   └── MonatTab.svelte                   (erweitern: Lane-Strip)
    │   ├── dashboard/
    │   │   ├── TrainingBookingSheet.svelte       (erweitern: Lane-Picker)
    │   │   └── PollCreateSheet.svelte            # NEU
    │   ├── admin/
    │   │   └── TrainingsListeAdminSheet.svelte   # NEU
    │   └── statistiken/
    │       ├── StatsView.svelte                  (erweitern: 3 Tabs)
    │       ├── PlayerStatsView.svelte            # NEU
    │       ├── LeagueTableCard.svelte            # NEU
    │       ├── FormCurveChart.svelte             # NEU
    │       └── ComparisonSheet.svelte            # NEU
    ├── utils/
    │   ├── players.js                            (imgPath erweitern: Storage-Branch)
    │   ├── stats.js                              # NEU — pure helpers (avg, slope, formCurve)
    │   └── pushSchedule.js                       # NEU — pure: build outbox-row aus Event/Training
    └── server/
        └── pushOutbox.js                         # NEU — server-only: dequeue + dispatch loop
supabase/
└── migrations/
    ├── 20260429_player_photos.sql                # NEU — Storage-Bucket + RLS analog attests
    ├── 20260430_push_outbox.sql                  # NEU — queue table + RLS (kapitän-write/system-read)
    ├── 20260501_poll_event_link.sql              # NEU — poll_options.target_event_id FK
    ├── 20260502_stats_views.sql                  # NEU — view_player_season_stats, view_team_form
    └── 20260503_league_standings.sql             # NEU — league_standings table (KVWN-internal source-of-truth)
```

**Strukturelle Begründung:**
- **Neue Tabs vs. neue Routes** — alle 4 v1-Features fügen sich in **bestehende Routes** ein.
  Begründung: BottomNav hat 4 fixe Slots (Home/Kalender/Spielbetrieb/Profil); +1 Slot würde
  visuell crowded → eher Subtabs als Routes.
- **Keine neuen globalen Stores** — pro Feature reicht lokales `$state` im Sheet/Tab.
  Begründung: Stores sind teuer (Cross-Component-Sync); Daten leben im Sheet, das sie zeigt.
- **Foto separat von Atteste** — bewusst zwei Buckets, weil `attests` privat (kapitän-read)
  während `player-photos` semi-public (alle eingeloggten Mitglieder) sein muss.

---

## Architektur-Patterns (zum Befolgen)

### Pattern 1 — Subtab-Router-Pattern (existiert, weiterführen)

**Was:** Ein `+page.svelte` ist Thin Router (`{#if $currentSubtab === 'foo'}<FooTab />{/if}`),
PAGE_CONFIG in `$lib/stores/subtab.js` definiert Tabs pro Route.

**Wann:** Top-Level-Tabs (`spiele|turniere|landesbewerbe|statistiken`) — sichtbar in PagePill.

**Trade-off:** URL ändert sich nicht (kein Deep-Link auf Tab) — bewusst akzeptiert.

**Beispiel — Statistiken-Sub-Tabs IM `statistiken`-Tab (lokales `$state`, NICHT subtab.js):**
```svelte
<!-- src/lib/components/statistiken/StatsView.svelte -->
<script>
  let view = $state('mannschaft'); // mannschaft | spieler | liga
</script>
<PillSwitcher bind:value={view} options={[
  { key:'mannschaft', label:'Mannschaft' },
  { key:'spieler',    label:'Spieler' },
  { key:'liga',       label:'Liga-Tabelle' },
]} />
{#if view === 'mannschaft'}<TeamStats />{/if}
{#if view === 'spieler'}<PlayerStatsList />{/if}
{#if view === 'liga'}<LeagueTableCard />{/if}
```

**Begründung:** Sub-Sub-Tabs sind nicht in `subtab.js` modelliert — Kalender macht das schon
mit lokalem `$state`. Konsistent bleiben.

---

### Pattern 2 — Sheet-Anchor-Pattern (Manage vs. Detail)

**Was:** `ManageSheet` (Edit/Create) wird **nur** aus Tabs/Listen aufgerufen, nicht aus
DetailSheets — sonst Rekursion (siehe MEMORY: spielbetrieb_managesheet_trap).

**Wann:** Immer wenn ein Sheet eine Liste rendert, deren Items klickbar sind.

**Beispiel — neues `TrainingsListeAdminSheet` darf Detail aus Liste öffnen, aber Detail darf
das Manage-Sheet nicht zurück-öffnen:**
```
TurniereTab → opens → TournamentManageSheet → renders match cards (read-only) ✓
TournamentMatchCard → opens → TournamentDetailSheet (read-only) ✓
TournamentDetailSheet → opens TournamentManageSheet ❌ (Rekursion!)
```

---

### Pattern 3 — RLS-Policy-Pattern (alle neuen Tische)

**Was:** Drei Standard-Policy-Schablonen, alle neuen Tische **müssen** eine davon nutzen:

```sql
-- A) Read-für-alle-Eingeloggten (Liste sichtbar, schreibrecht über andere Policy):
CREATE POLICY "<table> read"
  ON public.<table> FOR SELECT TO authenticated USING (true);

-- B) Own-Row-Write (Spieler darf eigene Zeile ändern):
CREATE POLICY "<table> manage own"
  ON public.<table> FOR ALL TO authenticated
  USING (player_id = (SELECT id FROM players WHERE email = (auth.jwt() ->> 'email') LIMIT 1))
  WITH CHECK (player_id = (SELECT id FROM players WHERE email = (auth.jwt() ->> 'email') LIMIT 1));

-- C) Kapitän/Admin-Write (alles):
CREATE POLICY "<table> kapitaen write"
  ON public.<table> FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM players WHERE email = (auth.jwt() ->> 'email')
                                          AND role IN ('kapitaen','admin')));
```

**Begründung:** Diese 3 Patterns decken die existierenden Tische zu 100 % ab (geprüft an
`event_rsvps`, `players`, `training_*`). Alles Sondergebackene wäre nicht-konformistisch.

---

### Pattern 4 — Server-Outbox statt Frontend-Cron-Trigger

**Was:** Statt im Frontend `setTimeout` für Erinnerungen (geht eh nicht — User schließt App),
schreibt der Frontend eine Zeile in `push_outbox(send_at, target_player_ids, payload)`.
Vercel-Cron `/api/cron/scheduled-push` poolt alle 15min und feuert via `/api/push/notify`.

**Beispiel — Event-Create plant Reminder:**
```js
// EventCreateSheet.svelte (Auszug)
async function createEvent(form) {
  const { data: ev, error } = await sb.from('events').insert({...form}).select().single();
  if (error) { triggerToast('Fehler: '+error.message); return; }

  if (form.remind_24h) {
    // Reminder-Zeile in Outbox
    await sb.from('push_outbox').insert({
      send_at:    new Date(new Date(ev.start_date).getTime() - 24*60*60*1000).toISOString(),
      target_kind:'event',
      target_id:  ev.id,
      payload:    { title: ev.title, body: 'Morgen: '+ev.title, url:`/kalender?event=${ev.id}` },
      pref_key:   'event',
    });
  }
}
```

**Trade-off:** 15min-Granularität (wie GCal-Sync). Für "morgen 8 Uhr Erinnerung" reicht das.
Sub-Minuten-Genauigkeit wäre unnötig (kein Live-Feature).

---

### Pattern 5 — Aggregationen als DB-Views, nicht Client-Reduce

**Was:** Statistik-Berechnungen als PostgreSQL-View oder Materialized View, NICHT als
Client-side `reduce()` über alle game_plan_players.

**Wann:**
- View (live, auto-aktualisiert): wenn Daten klein bleiben (< 10k Zeilen) → `view_player_season_stats`.
- Materialized View (snapshot, manuell refresh): wenn Aggregation teuer und nicht-Echtzeit-kritisch
  → `mv_player_career_stats` mit nightly Cron-Refresh.

**Trade-off-Tabelle für Stats:**

| Aggregation                      | Empfehlung                          | Begründung                                                |
|----------------------------------|-------------------------------------|-----------------------------------------------------------|
| Saison-Schnitt pro Spieler       | View `view_player_season_stats`     | Kleine Datenmenge (~30 Spieler × 30 Spiele = 900 rows)    |
| Form-Kurve (last 5 matches)      | Client-Reduce in `FormCurveChart`   | Nur 5 Werte; zu klein für SQL-Window-Function             |
| Liga-Tabelle KVWN+Konkurrenten   | Tabelle `league_standings` + Trigger | Punkte-Logik komplex (2:0=2pkt, 1:1=1pkt etc.); Trigger auf matches.UPDATE
| Trainings-Häufigkeit pro Saison  | View `view_player_training_count`   | Reines COUNT(*) GROUP BY → trivialer View                 |
| Historischer Vergleich          | RPC `compare_seasons(p_a int, p_b int)` | Parametrisiert, Spielerlist + Stats für 2 Saisonen      |

**Begründung gegen Client-Reduce für Bigger-Stats:**
- RLS verschickt sonst alle Rohdaten an alle Spieler (Bandbreite + Privacy).
- Client-Reduce duplicated Logik bei 2+ Komponenten (Profil + Statistiken).

---

### Pattern 6 — Storage-Bucket-RLS analog `attests`

**Was:** Foto-Upload bekommt eigenen Bucket `player-photos` mit RLS-Policy analog dem
existierenden `attests`-Bucket aus `20260422_profil_selfservice.sql` — Spieler liest/schreibt
nur eigenen Ordner via `storage.foldername(name)[1] = player_id`.

**Public oder Private?** **Public-Read** (semi-public via `bucket_id` only), weil Fotos in
allen Lineups/Listen sichtbar sein müssen, aber **Write** nur Owner.

```sql
-- supabase/migrations/20260429_player_photos.sql
INSERT INTO storage.buckets (id, name, public)
  VALUES ('player-photos', 'player-photos', true)  -- public-read
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "photos write own" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'player-photos'
    AND (storage.foldername(name))[1] = (
      SELECT id::text FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  );
-- (analog UPDATE/DELETE)

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS photo_url text;  -- gespeicherte Storage-Public-URL
```

**Coexistenz mit `static/images/`:** `imgPath()` in `$lib/utils/players.js` erweitern:

```js
export function imgPath(player) {
  if (player.photo_url) return player.photo_url;            // 1. Storage (NEU)
  if (player.photo)     return `/images/${player.photo}.jpg`; // 2. static (Bestand)
  return BLANK_IMG;                                          // 3. Fallback
}
```

**Begründung:** Migration ist zero-risk — alte Spieler ohne `photo_url` rendern wie bisher.
Kein Breaking-Change für gerade-eingeloggte Sessions.

---

## Datenfluss-Diagramme

### Datenfluss 1 — Trainingsbuchung mit Warteliste (Feature 2)

```
[User in Kalender Wochenansicht] tippt Lane 3 für Mi 19:00
   ↓
TrainingDetailSheet öffnet sich (BottomSheet)
   ↓
User klickt "Buchen"
   ↓
sb.rpc('book_training_lane', { p_date, p_start, p_lane:3 })
   ↓
PG-Funktion (SECURITY DEFINER): RLS check via auth.jwt()->>'email'
   ↓
Resultat:
  • {status:'booked', lane:3}        → Toast "Bahn 3 gebucht"
  • {status:'waitlisted', position:2}→ Toast "Warteliste Position 2"
  • {status:'lane_taken'}            → Toast "Bahn vergeben, andere wählen"
   ↓
TrainingDetailSheet re-fetched lanes via sb.from('training_bookings')...
   ↓
[Sheet bleibt offen, Lane-Strip aktualisiert]
```

### Datenfluss 2 — Foto-Upload (Feature 1)

```
[User in Profil-UebersichtTab] tippt Avatar
   ↓
ProfilFotoSheet öffnet sich
   ↓
<input type="file" accept="image/*" capture="user">
   ↓
Client-side crop to square 512×512 (canvas)
   ↓
sb.storage.from('player-photos').upload(`${$playerId}/avatar.jpg`, blob, { upsert:true })
   ↓
RLS-Policy "photos write own" prüft (storage.foldername(name))[1] = $playerId
   ↓
{ data: { path }, error }  →  Public-URL via sb.storage.from(...).getPublicUrl(path)
   ↓
sb.from('players').update({ photo_url: publicUrl }).eq('id', $playerId)
   ↓
RLS "players self update" passt (email match) — erlaubt photo_url-Update
   ↓
ProfilHeroCard re-rendered (auth-Store fetched players-Row neu) — Avatar zeigt neues Foto
```

### Datenfluss 3 — Event mit Reminder + Poll (Feature 3)

```
[Kapitän in Kalender] tippt "+ Event"
   ↓
EventCreateSheet öffnet sich
   ↓
Felder: Titel, Datum, Ort, "Erinnerung 24h vorher" Toggle, "Umfrage anhängen" Toggle
   ↓
Bei Submit, parallele Inserts via sb:
  1. sb.from('events').insert({...}).select() → ev
  2. (optional) sb.from('polls').insert({question:'Kommst Du?', target_event_id:ev.id})→ poll
  3. (optional) sb.from('poll_options').insert([{poll_id, label:'Ja'}, {label:'Nein'}, {label:'Vielleicht'}])
  4. (optional) sb.from('push_outbox').insert({send_at:ev.start - 24h, target_kind:'event', target_id:ev.id, payload, pref_key:'event'})
   ↓
[Vercel-Cron alle 15min: /api/cron/scheduled-push]
   ↓
sbAdmin.from('push_outbox').select().lte('send_at', now()).is('sent_at', null)
   ↓
für jede Zeile:
   target_kind='event' → players_to_notify = alle aktiven Mitglieder
                          (oder via target_player_ids JSON-Array wenn explizit gesetzt)
   ↓
fetch /api/push/notify { player_ids, title, body, url, pref_key:'event' }
   ↓
push_subscriptions geladen (RLS-bypass via service-role)
   ↓
webpush.sendNotification(...)  für jede Subscription
   ↓
sbAdmin.from('push_outbox').update({sent_at:now(), sent_count:N}).eq('id', row.id)
```

### Datenfluss 4 — Statistik-View für Spieler-Drill-down (Feature 4)

```
[User in /spielbetrieb?subtab=statistiken] view='spieler' → Liste aller Spieler
   ↓
sb.from('view_player_season_stats').select('*').eq('season', currentSeason)
   ↓
Liste rendert: Name, Schnitt, Spiele, Form (mini-Sparkline)
   ↓
User tippt Spieler X
   ↓
ComparisonSheet öffnet sich (BottomSheet) mit player_id=X
   ↓
parallel:
  • sb.from('view_player_season_stats').select().eq('player_id', X)
  • sb.from('game_plan_players').select('match_id, score, ...').eq('player_id', X) für Form-Kurve
  • sb.from('view_player_training_count').select().eq('player_id', X)
   ↓
PlayerStatsView render → FormCurveChart (Client-Reduce auf 5 Spiele) + Stats-Cards
```

---

## DB-Additions (komplett enumeriert)

### NEU: Tabellen

```sql
-- 20260430_push_outbox.sql ----------------------------------------------------
CREATE TABLE public.push_outbox (
  id              uuid       PRIMARY KEY DEFAULT gen_random_uuid(),
  send_at         timestamptz NOT NULL,
  target_kind     text       NOT NULL CHECK (target_kind IN ('event','training','match','custom')),
  target_id       uuid,
  target_player_ids uuid[],
  payload         jsonb      NOT NULL,
  pref_key        text       NOT NULL DEFAULT 'general',
  sent_at         timestamptz,
  sent_count      int,
  failed_count    int,
  created_by      uuid       REFERENCES public.players(id),
  created_at      timestamptz DEFAULT now()
);
CREATE INDEX idx_push_outbox_pending ON public.push_outbox(send_at) WHERE sent_at IS NULL;

ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY "outbox kapitaen all" ON public.push_outbox FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.players WHERE email=(auth.jwt()->>'email') AND role IN ('kapitaen','admin')));

CREATE POLICY "outbox owner read" ON public.push_outbox FOR SELECT TO authenticated
  USING (created_by = (SELECT id FROM public.players WHERE email=(auth.jwt()->>'email') LIMIT 1));
-- Cron-Endpoint nutzt service-role → keine extra Policy nötig.

-- 20260503_league_standings.sql ----------------------------------------------
CREATE TABLE public.league_standings (
  id          uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id   uuid    NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  team_name   text    NOT NULL,
  is_kvwn     boolean DEFAULT false,
  matches_played int  DEFAULT 0,
  wins int DEFAULT 0, draws int DEFAULT 0, losses int DEFAULT 0,
  points int DEFAULT 0,
  total_score int DEFAULT 0,
  season int NOT NULL,
  updated_at  timestamptz DEFAULT now(),
  UNIQUE (league_id, team_name, season)
);
ALTER TABLE public.league_standings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "standings read" ON public.league_standings FOR SELECT TO authenticated USING (true);
CREATE POLICY "standings kapitaen write" ON public.league_standings FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.players WHERE email=(auth.jwt()->>'email') AND role IN ('kapitaen','admin')));
```

### NEU: Spalten

```sql
-- 20260501_poll_event_link.sql -----------------------------------------------
ALTER TABLE public.polls
  ADD COLUMN IF NOT EXISTS target_event_id uuid REFERENCES public.events(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_polls_event ON public.polls(target_event_id);

-- 20260429_player_photos.sql -------------------------------------------------
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS photo_url text;
```

### NEU: Views & RPCs

```sql
-- 20260502_stats_views.sql ---------------------------------------------------
CREATE OR REPLACE VIEW public.view_player_season_stats AS
SELECT
  gp.player_id,
  EXTRACT(YEAR FROM m.date)::int AS season,
  COUNT(*)                      AS games_played,
  ROUND(AVG(gp.score)::numeric,1) AS avg_score,
  MAX(gp.score)                 AS best_score,
  MIN(gp.score)                 AS worst_score,
  SUM(CASE WHEN gp.win THEN 1 ELSE 0 END) AS sp_wins
FROM public.game_plan_players gp
JOIN public.matches m ON m.id = gp.match_id
WHERE gp.score IS NOT NULL
GROUP BY gp.player_id, EXTRACT(YEAR FROM m.date);

CREATE OR REPLACE VIEW public.view_player_training_count AS
SELECT
  tb.player_id,
  EXTRACT(YEAR FROM tb.date)::int AS season,
  COUNT(*) AS training_count
FROM public.training_bookings tb
WHERE tb.date <= CURRENT_DATE
GROUP BY tb.player_id, EXTRACT(YEAR FROM tb.date);

-- Views erben RLS von Underlying-Tables → keine extra Policy nötig.

-- RPC für Vergleich (parametrisiert):
CREATE OR REPLACE FUNCTION public.compare_seasons(p_a int, p_b int)
RETURNS TABLE (player_id uuid, season int, avg_score numeric, games int)
LANGUAGE sql STABLE AS $$
  SELECT player_id, season, avg_score, games_played
  FROM public.view_player_season_stats
  WHERE season IN (p_a, p_b);
$$;
GRANT EXECUTE ON FUNCTION public.compare_seasons(int,int) TO authenticated;
```

### NEU: Storage-Bucket

```sql
-- (in 20260429_player_photos.sql, oben gezeigt)
INSERT INTO storage.buckets (id, name, public)
  VALUES ('player-photos', 'player-photos', true)
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "photos read all" ON storage.objects FOR SELECT
  USING (bucket_id = 'player-photos');
CREATE POLICY "photos write own" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id='player-photos'
    AND (storage.foldername(name))[1]=(SELECT id::text FROM public.players WHERE email=(auth.jwt()->>'email')));
CREATE POLICY "photos update own" ON storage.objects FOR UPDATE
  USING (bucket_id='player-photos'
    AND (storage.foldername(name))[1]=(SELECT id::text FROM public.players WHERE email=(auth.jwt()->>'email')));
CREATE POLICY "photos delete own" ON storage.objects FOR DELETE
  USING (bucket_id='player-photos'
    AND (storage.foldername(name))[1]=(SELECT id::text FROM public.players WHERE email=(auth.jwt()->>'email')));
```

---

## Scheduled-Push-Pattern (Detail-Begründung)

**Frage:** Supabase pg_cron in Outbox-Tabelle, oder Vercel-Cron poolt direkt?

**Antwort: Vercel-Cron poolt Outbox.** Begründung:

| Kriterium                                  | Supabase pg_cron      | Vercel-Cron + Outbox (gewählt) |
|-------------------------------------------|------------------------|--------------------------------|
| Existiert schon im Stack?                  | nein                   | **ja** (3 Jobs aktiv)          |
| Free in Supabase Free-Tier?                | nein (Pro+)            | n/a                            |
| Wo lebt die `webpush`-Library?             | nicht in PG            | **bereits in `/api/push/notify`** |
| Sub-Minuten-Genauigkeit?                   | ja                     | nein (15min)                   |
| Konsistent mit `gcal-sync`-Pattern?        | nein                   | **ja**                         |
| Auth-Pattern `Bearer ${CRON_SECRET}`?      | nein                   | **ja**                         |

**Konkrete Implementation:**

```js
// src/routes/api/cron/scheduled-push/+server.js  (NEU)
import { sbAdmin } from '$lib/server/supabase-admin';

export async function POST({ request, fetch }) {
  if (request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  const admin = sbAdmin();

  const { data: due, error } = await admin
    .from('push_outbox')
    .select('*')
    .lte('send_at', new Date().toISOString())
    .is('sent_at', null)
    .limit(50); // batch-cap

  if (error) return new Response(JSON.stringify({error:error.message}), {status:500});

  for (const row of due ?? []) {
    // Resolve target_player_ids: explicit OR derived from target_kind
    let players = row.target_player_ids;
    if (!players?.length && row.target_kind === 'event') {
      const { data: rsvps } = await admin.from('event_rsvps').select('player_id').eq('event_id', row.target_id).eq('response','yes');
      players = rsvps?.map(r => r.player_id) ?? [];
    }
    if (!players?.length && row.target_kind === 'training') {
      const { data: bks } = await admin.from('training_bookings').select('player_id').eq('id', row.target_id);
      players = bks?.map(b => b.player_id) ?? [];
    }

    // Fire push via existing endpoint
    const res = await fetch('/api/push/notify', {
      method:'POST',
      headers:{ 'authorization':`Bearer ${process.env.CRON_SECRET}`, 'content-type':'application/json' },
      body: JSON.stringify({ player_ids: players, pref_key: row.pref_key, ...row.payload }),
    });
    const { sent } = await res.json();

    await admin.from('push_outbox').update({ sent_at: new Date().toISOString(), sent_count: sent }).eq('id', row.id);
  }
  return new Response(JSON.stringify({ processed: due?.length ?? 0 }));
}
```

**`vercel.json` Erweiterung:**
```json
{
  "crons": [
    { "path": "/api/cron/gcal-sync",          "schedule": "*/15 * * * *" },
    { "path": "/api/cron/lineup-reminders",   "schedule": "0 7 * * *"  },
    { "path": "/api/cron/keyduty-check",      "schedule": "0 10 * * *" },
    { "path": "/api/cron/scheduled-push",     "schedule": "*/15 * * * *" },
    { "path": "/api/cron/training-reminders", "schedule": "0 9 * * *"  }
  ]
}
```

`training-reminders` ist ein **schmaler Special-Case-Cron** der für jede Buchung `morgen` einen
Push direkt feuert (nicht via Outbox), weil die "morgen" Logik im Code stehen kann ohne Outbox-Zeile.

---

## Polls/Umfragen — Schema-Entscheidung

**Frage:** Polls als separate Tabellen oder an Events angehängt?

**Antwort: Separate Tabellen mit OPTIONALEM Event-Link.**

Begründung:
- `polls`/`poll_options`/`poll_votes` **existieren bereits** (wird im Dashboard via `PollCard.svelte`
  konsumiert, geprüft mit Grep). Schema in DB-Production aber **nicht** in `supabase/migrations/`
  versioniert (analog `event_rsvps` vor `20260427` — Migrations-Refactor wäre Cleanup).
- Polls existieren auch **standalone** (Dashboard-Umfrage "Beste Trainingszeit?") — nicht jeder
  Poll braucht ein Event.
- Aber: viele Polls **gehören** zu einem Event ("Was bringst Du zum Saisonschluss mit?"). Daher
  optional `polls.target_event_id` FK (NEU, Migration `20260501_poll_event_link.sql`).

**Schema:**
```
polls(id, question, deadline, multi_select, target_event_id?, created_by, created_at)
poll_options(id, poll_id, label, order_index, target_kind?, target_event_id?)
poll_votes(poll_id, option_id, player_id, created_at)  -- composite PK
```

**Verwendung:**
- `EventDetailSheet` zeigt alle Polls mit `target_event_id = ev.id` via `PollCard`-Reuse.
- `Dashboard NewsFeed` zeigt **nur** Polls ohne Event-Link (`target_event_id IS NULL`).
- Kapitän-Create: aus EventCreate-Sheet (mit Event-Link) **oder** Dashboard-PollCreateSheet.

---

## Komponenten-Reuse-Matrix

| Bestehendes Primitive    | Wird wiederverwendet von             | Erweiterung nötig? |
|--------------------------|---------------------------------------|--------------------|
| `BottomSheet`            | ProfilFotoSheet, PollCreateSheet, ComparisonSheet, TrainingsListeAdminSheet, EventReminderConfig | nein |
| `.mw-card` / `.mw-btn`   | TrainingsStatsCard, LeagueTableCard, alle neuen Cards | nein |
| `.mw-field`              | Alle neuen Form-Sheets (ProfilFoto, PollCreate, EventReminderConfig) | nein |
| `PillSwitcher` (`ui/`)   | StatsView (3 Sub-Tabs), ProfilFotoSheet (Source-Switcher) | nein |
| `ToggleSwitch` (`ui/`)   | EventReminderConfig (Reminder-Toggle), Push-Prefs-Erweiterung | nein |
| `IOSSlider` (`ui/`)      | (unnötig für v1) | nein |
| `triggerToast`           | Alle neuen Komponenten | nein |
| `imgPath()`              | Alle Foto-Renderings | **ja**: Storage-URL-Branch |
| `BEWERB_TYPEN/LABEL`     | Statistik-Filter | nein |
| `fmtDate/fmtTime`        | Alle Datumsanzeigen | nein |

**Welche NEUEN Primitives sind nötig?**

| NEUE Primitive         | Begründung                                                                |
|------------------------|---------------------------------------------------------------------------|
| `FormCurveChart.svelte`| Inline-SVG-Sparkline; gerne klein (no chart.js) → eigener Mini-Chart      |
| `LaneStrip.svelte`     | 4-Lane-Visualisierung (• ○ • ○) für TrainingDetailSheet + Wochenkalender  |
| `PhotoUploader.svelte` | Wiederverwendbar: File-Picker + Crop + Upload (auch für Atteste relevant) |

Alle drei sind **Feature-lokal** in ihrem jeweiligen Order — kein neues `ui/`-Primitive
nötig (würde nur das `ui/`-Folder aufblähen).

---

## Skalierungs-Überlegungen

| Skala                                       | Architektur-Anpassung                                                              |
|---------------------------------------------|------------------------------------------------------------------------------------|
| Heutiger Stand: ~30 Spieler, ~50 Matches/J  | Alles inline ok — kein materialized view nötig                                     |
| 100 Spieler, 200 Matches/J (3 Jahre)        | Stats-Views weiterhin live; Form-Kurve-Reduce auf last-5 bleibt billig             |
| 500 Spieler (mehrere Vereine im Fork)       | Out of Scope (Multi-Tenant explizit ausgeschlossen in PROJECT.md)                  |

**Erste Bottlenecks (realistisch):**
1. **`view_player_season_stats` Performance** — bei > 5k `game_plan_players` rows: Materialized View
   mit nightly refresh statt live View. Mitigation: heutiger Bestand << 1k → keine Aktion v1.
2. **`push_outbox` Backlog** — wenn > 50 fällige Reminders gleichzeitig: Cron-Batch raise
   von 50 auf 200 + Pagination. Mitigation: Outbox-Tabelle hat Index; v1 unkritisch.
3. **Storage-Quota player-photos** — 30 Spieler × 100KB Avatar = 3MB. Vernachlässigbar.

---

## Anti-Patterns (Spezifisch für KVWN-v1)

### Anti-Pattern 1 — `+page.server.js` einführen für "ist server-side ja besser?"

**Was passiert:** Versuchung Stats-Aggregation in `+page.server.js` zu rechnen für SEO/Speed.

**Warum falsch:** Die App ist auth-only PWA. Kein SEO. Die `sb`-Anon-Pattern ist die Konvention
(siehe CLAUDE.md). Eine Insel `+page.server.js` würde Auth-Token-Forwarding erzwingen, das
heute nicht existiert.

**Stattdessen:** DB-View + browser-fetch via `sb`. Wenn wirklich server-side nötig (Service-Role)
→ `/api/...` Endpoint, nicht `+page.server.js`.

---

### Anti-Pattern 2 — Globalen `pollStore` einführen

**Was passiert:** "Polls werden in Dashboard und EventDetail gezeigt → globaler Store!"

**Warum falsch:** Polls sind seitenspezifisch (Dashboard zeigt unverlinkte, EventDetail zeigt
verlinkte). Geteilter Store würde nur Filter-Bugs erzeugen. Kein Bestands-Pattern dafür.

**Stattdessen:** Lokales `$state` in jedem Sheet/Tab + dedupe via DB-Query (`target_event_id IS NULL` vs. `= ev.id`).

---

### Anti-Pattern 3 — Foto-Upload via base64-data-URL in `players.photo_url`

**Was passiert:** "Spart Storage-Bucket-Setup → einfach data-URL in DB."

**Warum falsch:** Postgres-row-size explodiert (≥100KB pro Spieler), `players.select('*')` wird
zur Bandbreitenbombe (jeder Match-Lineup-Fetch lädt 30 Spieler × 100KB).

**Stattdessen:** Storage-Bucket wie oben (Pattern 6).

---

### Anti-Pattern 4 — Reminder via `setTimeout` im Browser

**Was passiert:** Quick-Win-Versuchung: User-tab offen → `setTimeout(..., 24h)` für Erinnerung.

**Warum falsch:** PWA-Tab ist nach 24h zu, Service-Worker macht keine schedule-API (kein
`navigator.scheduling.scheduleTask` in Safari). Eine geplante Erinnerung MUSS server-seitig sein.

**Stattdessen:** `push_outbox` (Pattern 4).

---

### Anti-Pattern 5 — `client-reduce` für Liga-Tabelle

**Was passiert:** "Wir holen alle matches und rechnen Punkte client-side."

**Warum falsch:** (1) Punkte-Logik ist nicht-trivial (2:0=2pkt, 1:1=1pkt etc.) und gehört in
**eine** Quelle. (2) Dieselbe Logik wird im Spielbetrieb-Tab (Liga-Card) und Statistiken-Tab
(Liga-Tabelle) gebraucht — Doppel-Implementierung garantiert Drift.

**Stattdessen:** `league_standings`-Tabelle + DB-Trigger auf `matches UPDATE` der Punkte
recomputed. Single Source of Truth.

---

## Integration-Points

### Externe Services

| Service          | Pattern                                            | Gotchas                                                                  |
|------------------|----------------------------------------------------|--------------------------------------------------------------------------|
| Google Calendar  | Bereits via `/api/cron/gcal-sync` + `/api/gcal/events` | v1 berührt das nicht; Events-Reminder läuft **parallel** zu GCal-Sync — beide sind `events.source = 'manual' OR 'gcal'`-aware. |
| Web Push (VAPID) | `/api/push/notify` + `push_subscriptions` Tabelle   | `pref_key` gating! Reminder muss neue `pref_key` (`event`, `training`) zu `players.push_prefs` hinzufügen oder `general` reusen. |
| Supabase Storage | Buckets `attests` (existiert) + `player-photos` (NEU) | `(storage.foldername(name))[1]` liefert UUID-string — muss zu `players.id::text` matchen. |

### Interne Boundaries

| Boundary                                | Kommunikation                                              | Anmerkungen                                                  |
|-----------------------------------------|------------------------------------------------------------|--------------------------------------------------------------|
| Frontend Component ↔ Supabase           | Direkt via `sb` (anon, RLS-gated)                          | Konvention: kein `+page.server.js`                           |
| Frontend ↔ `/api/...` (Server-Routes)   | `fetch()` mit `Bearer ${CRON_SECRET}` (cron) oder Session-Auth (captain) | Frontend nutzt API nur für (a) push-trigger, (b) GCal-write, (c) cancel-training-storno |
| API-Route ↔ Supabase                    | Service-Role via `sbAdmin()`                               | Bypass RLS — niemals service-role-key im Browser bundlen     |
| Cron ↔ Cron                             | HTTP via `fetch('/api/push/notify')` mit CRON_SECRET       | Alternative: direkter Lib-Import von `webpush` — wir bleiben bei HTTP für Konsistenz |

---

## Empfohlene Build-Order (Phasen für Roadmap)

**Build-Order — mit Begründung:**

### Phase 1 — Spieler-Selfservice + Foto-Upload  (LOW RISK, HIGH UX-VALUE)

**Warum zuerst:**
- Komplett **isoliert** (nur `/profil`-Bereich). Null Risiko für Spielbetrieb/Match-Workflow.
- Foundation für Phase 4: Spieler-Stats brauchen Spieler-Identität (Foto, Name, Position) —
  besser zu sehen wenn Profile vollständig.
- Migration `20260422_profil_selfservice.sql` hat 80% der DB-Spalten **schon gelegt** —
  reine Frontend-Arbeit + 1 neuer Storage-Bucket.

**Lieferumfang:**
- ProfilDatenSheet erweitert (alle Felder bedienbar)
- ProfilFotoSheet NEU (Upload + Crop)
- Migration `20260429_player_photos.sql` (Bucket + `photo_url` Spalte)
- `imgPath()` Storage-Branch

**Risiko-Hotspot:** Foto-URL-Migration könnte alte `<img src="/images/...">` brechen, wenn
`imgPath()`-Erweiterung nicht idempotent. → Smoke-Test alle Lineup-Listen + Avatar-Stellen.

---

### Phase 2 — Trainingsbuchung-Vollausbau (LOW-MED RISK)

**Warum als zweites:**
- DB-Foundation steht (Migrations `20260421_training_*.sql` komplett, RPCs `book_training_lane`
  + `cancel_training_booking` live).
- Phase 4 (Statistik) braucht Trainings-Buchungs-Daten (`view_player_training_count`) — die
  müssen erst exist + UI-getestet sein, bevor Stats darauf bauen.
- Berührt Kalender (Lane-Strip) **read-only** — kein Schreibrisiko auf shipped Code.

**Lieferumfang:**
- TrainingDetailSheet erweitert (Warteliste, Storno)
- TrainingsListeAdminSheet NEU (Kapitän)
- TrainingsStatsCard NEU (Profil-Hook)
- LaneStrip-Primitive (in WocheTab/MonatTab)
- `/api/cron/training-reminders` NEU

**Risiko-Hotspot:** Lane-Strip in `MonatTab` darf das Monatsraster nicht visuell brechen
(viele Slots gleichzeitig). → Designer-Spec **vor** Frontend-Implementation.

---

### Phase 3 — Events + Umfragen + Push (MED RISK)

**Warum drittens:**
- Push-Outbox-Pattern ist die größte **Neu-Infrastruktur** der v1 — eigene Phase verdient.
- Polls/Events existieren als Tabellen, aber `target_event_id` ist neu → Migrations-First.
- Berührt Kalender (`EventCreateSheet`) → mittleres Risiko (existing flow).

**Lieferumfang:**
- Migration `20260430_push_outbox.sql` + `20260501_poll_event_link.sql`
- `/api/cron/scheduled-push` NEU
- EventCreateSheet erweitert (Reminder + Poll)
- EventDetailSheet erweitert (Poll-Liste)
- PollCreateSheet NEU (Dashboard-Action)
- vercel.json Erweiterung

**Risiko-Hotspot:** Outbox-Cron muss idempotent sein (re-run bei Vercel-Retry darf nicht doppel-pushen).
→ `sent_at IS NULL`-Filter ist Single-Source.

---

### Phase 4 — Statistik-Dashboards (LOW-MED RISK, READ-ONLY)

**Warum zuletzt:**
- **Read-only-Feature** — kein Risiko für Datenkorruption. Sicherer "Nachzügler".
- Profitiert von Phase 1 (Foto in PlayerStatsView), Phase 2 (`view_player_training_count`).
- Reine UI-Arbeit auf existierende Daten + neue Views.
- Bietet beste **JHV-Demo-Wirkung** ("Schau was die App alles kann!") — chronologisch
  nahe am 22.05.2026 ausliefern für maximale Frische.

**Lieferumfang:**
- Migration `20260502_stats_views.sql` + `20260503_league_standings.sql`
- StatsView mit 3 Sub-Tabs (mannschaft|spieler|liga)
- PlayerStatsView, LeagueTableCard, FormCurveChart, ComparisonSheet
- Mini-Stats-Card auf `/profil` (Reuse PlayerStatsView)

**Risiko-Hotspot:** Liga-Tabelle braucht KVWN+Konkurrenten-Daten in `league_standings` —
Initial-Seed manuell durch Kapitän? → Designer-Spec klärt.

---

## Risiken zum shipped Code

| Risiko                                                 | Phase | Mitigation                                                            |
|---------------------------------------------------------|-------|----------------------------------------------------------------------|
| `imgPath()`-Erweiterung bricht alte Avatare             | 1     | Backward-compat in `imgPath()` — Storage-URL nur wenn `photo_url IS NOT NULL` |
| Lane-Strip macht Monatskalender visuell unlesbar        | 2     | Designer-Spec mit MonatTab-Mockup vor Frontend-Code                  |
| `EventCreateSheet`-Erweiterung bricht GCal-Push-Flow     | 3     | Bestehende `manual`-Events-Path **unangetastet** lassen — Reminder + Poll sind additive Felder |
| `push_outbox`-Cron räumt versehentlich `sent_at` zurück   | 3     | RLS verhindert Frontend-write; nur service-role kann; Cron-Code-Review |
| Stats-View-Performance auf alten Match-Daten (vor 2025) | 4     | View-Filter `WHERE m.date >= '2025-01-01'` als Default in StatsView UI |
| Liga-Tabelle erfordert Konkurrenten-Daten die niemand hat | 4     | Phase-4-Mockable: Demo-Daten seedbar via Captain-Tool; nicht JHV-blockierend |

**Größtes Single-Risk:** Phase 3 Push-Outbox — neue Infra-Komponente. Mitigation: Smoke-Test
mit 1-Minuten-Reminder vor JHV.

---

## Sources

- C:\kvwn\.planning\codebase\ARCHITECTURE.md (existierende Layer-Analyse)
- C:\kvwn\.planning\codebase\STRUCTURE.md (folder-conventions)
- C:\kvwn\.planning\codebase\STACK.md (env vars, vercel cron config)
- C:\kvwn\.planning\PROJECT.md (Vision, v1-Scope, JHV-Stichtag)
- C:\kvwn\CLAUDE.md (RLS-pattern, design-token-rules, conventions)
- C:\kvwn\supabase\migrations\20260421_training_lanes.sql (Training-RPC-Pattern)
- C:\kvwn\supabase\migrations\20260422_profil_selfservice.sql (Storage-RLS-Vorlage `attests`)
- C:\kvwn\supabase\migrations\20260427_event_rsvps.sql (own-row-RLS-Pattern)
- C:\kvwn\src\routes\api\push\notify\+server.ts (push_subscriptions + pref_key gating)
- C:\kvwn\src\lib\components\dashboard\PollCard.svelte (Poll-Schema discovered)
- C:\kvwn\src\lib\components\dashboard\NewsFeed.svelte (poll_options FK-name)

---

*Architecture research für: KVWN v1 (4 Features bis JHV 22.05.2026)*
*Researched: 2026-04-28*
*Confidence: HIGH (alle Aussagen durch existierenden Code/Migrations verifiziert)*
