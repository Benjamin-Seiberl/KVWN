# Stack Research — KVWN v1 Additions

**Domain:** Vereins-PWA (SvelteKit 5 + Supabase + Vercel) — additive libs for v1 features
**Researched:** 2026-04-28
**Confidence:** HIGH (versions verified via npm registry; patterns verified via official docs / Supabase / Vercel)

## Stack Lock — DO NOT touch

The existing stack is locked. **No** v1 work should add a framework, an alternate DB, a TS-toolchain, a CSS-framework, a test-runner, or a build-tool. This research only adds **leaf libraries** that fit cleanly into the existing pattern (`sb` direct-from-browser, no `+page.server.js`, JS-only, runes, design tokens).

| Locked layer | Version | Status |
|--------------|---------|--------|
| Svelte | 5.55.2 | Locked |
| SvelteKit | 2.57.0 | Locked |
| Vite | 8.0.7 | Locked |
| @sveltejs/adapter-vercel | 6.3.3 | Locked |
| @supabase/supabase-js | 2.103.0 | Locked (latest 2.108+, can bump but not part of this scope) |
| googleapis | 144.0.0 | Locked |
| web-push | 3.6.7 | Locked |
| Vercel runtime | Node 22.x | Locked |
| Vercel plan | Pro | Locked (sub-daily cron + >2 cron jobs allowed) |

---

## Recommended Additions for v1

### Core Additions (one per problem area)

| Technology | Version (verified npm 2026-04-28) | Purpose | Why this one |
|------------|-----------------------------------|---------|--------------|
| **layerchart** | `2.0.0-next.59` (Svelte 5 line, published 2026-04-24) | Charting für Statistik-Dashboards (Saison-Schnitt, Form-Kurve, Liga-Tabelle, historische Vergleiche) | Composable Svelte-native, runes-first. CSS-only mode (kein Tailwind nötig — passt zu KVWN-Design-Tokens). Built on D3 → unbegrenzt anpassbar. Active development (49 next-Releases in 2026). |
| **valibot** | `1.3.1` | Schema-Validation für Selfservice-Formulare (Telefon, Adresse, Lizenznummer, Geburtstag) | ~1.4 kB gzipped — 10× kleiner als Zod 4. Pure ESM, Tree-shakeable. Funktioniert ohne Form-Bibliothek direkt mit `$state` + `$derived`. Keine SSR-Annahmen → passt zu KVWN's "DB direkt im Browser". |
| **@internationalized/date** | `3.12.1` | Datums-Picker-Backend (Geburtstag, Trainingsbuchung-Storno-Frist) | Industriestandard für Locale-aware Date-Picker. `de-AT` Locale für österreichisches Format ("Jänner"). Wird ohnehin als Peer-Dep von bits-ui gefordert, falls bits-ui later kommt. Standalone nutzbar. |

### What to NOT add (intentional)

| Avoid | Why | Use instead |
|-------|-----|-------------|
| **chart.js + svelte-chartjs** | svelte-chartjs 4.0.1 (März 2026) hat Svelte-5-Support, ABER Chart.js rendert auf `<canvas>` → keine CSS-Token-Steuerung der Farben, kein Hover-Effect via Design-Token, keine accessible SVG-Outputs. KVWN-Design lebt von rot-getönten Schatten und Token-getriebenen Farben. | layerchart (SVG-basiert, CSS-stylebar) |
| **sveltekit-superforms** | 7+ Peer-Dependencies, gebaut um `+page.server.js`-Pattern (ServerForms). KVWN macht alles browser-seitig via `sb`. Würde 30+ kB für Sache mitziehen, die `$state` + valibot in 5 Zeilen löst. | valibot direkt in `<script>` mit `$derived` für Validation-State |
| **formsnap** | Hängt an superforms (Peer-Dep) → siehe oben. | Ungated `<input>` + `bind:value` + valibot-Pipe |
| **bits-ui DatePicker** | `^5.33.0` Svelte-Peer ok, aber: 18+ kB nur für Date-Picker, native `<input type="date">` mit `lang="de-AT"` ist auf Mobile (PWA-Hauptzielgruppe) UX-überlegen (System-Picker, Touch-optimiert, Accessibility frei). | Native `<input type="date">` + `<input type="time">` mit `lang="de-AT"`; nur falls inline-Kalender gefordert → bits-ui einzeln nachziehen |
| **@vercel/blob** | Vercel Pro-Plan hat es separat zu zahlen (5 GB Free, dann $0.15/GB-Monat). KVWN hat bereits Supabase Pro mit RLS-Storage und Service-Role-Bypass. Doppelt zu pflegen + zwei Auth-Modelle. | Supabase Storage (siehe unten) |
| **cropperjs / svelte-cropperjs** | Foto-Cropping ist Nice-to-have, nicht v1-Demo-kritisch. ~30 kB für JHV-Demo überdimensioniert. | Browser-native: `canvas.drawImage()` für 1:1-Crop in JS-Util (~30 Zeilen). Falls nötig später nachreichen. |
| **browser-image-compression** | 2 kB lib, aber: Supabase Storage Image-Transformation kann das server-seitig kostenlos. Eingespart: lib-update-Tax + Build-Size. | Supabase Storage Render-API (`?width=400&quality=80` URL-Param) |
| **date-fns** (für lib-internen Gebrauch) | layerchart 2-next zieht `date-fns@^4.1.0` ohnehin via transitive Dep. KVWN's eigenes `$lib/utils/dates.js` deckt App-Formatting ab. Nicht doppelt. | Bestehende `$lib/utils/dates.js` weiternutzen |
| **svelte-french-toast** | KVWN hat bereits `$lib/stores/toast.js` mit `triggerToast`. Bewusst nicht ersetzen. | Bestehende `triggerToast`-Store |

---

## Supporting Patterns (no library — use platform features)

### File-Upload für Spieler-Foto → Supabase Storage

**Empfehlung:** Supabase Storage Bucket `player-avatars`, NICHT Vercel Blob.

**Begründung:**
- KVWN ist bereits Supabase-zentriert, kein zweiter Auth-Pfad nötig.
- RLS-Pattern lässt sich exakt 1:1 wie bei `players.email` weiternutzen — Bucket-Policy mit `(storage.foldername(name))[1] = (auth.jwt() ->> 'email')`-Match.
- Supabase Storage hat Image-Transformation built-in (`?width=400&quality=80`) → keine Client-Compression-Lib nötig.
- Vercel Pro-Quota (Bandwidth) wird nicht für Bilder verbrannt.
- Service-Worker cached automatisch bei PWA-Hits.

**Migration-Pattern (für Roadmap):**
```sql
-- supabase/migrations/<date>_player_avatars.sql
insert into storage.buckets (id, name, public) values ('player-avatars', 'player-avatars', true);

create policy "Spieler upload only own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'player-avatars'
    and (storage.foldername(name))[1] = (auth.jwt() ->> 'email')
  );

create policy "Avatare öffentlich lesbar"
  on storage.objects for select to public using (bucket_id = 'player-avatars');
```

**Client-Pattern (KVWN-konform):**
```js
// im <script> einer Profil-Komponente
const path = `${$user.email}/avatar.jpg`;
const { error } = await sb.storage.from('player-avatars').upload(path, file, { upsert: true });
if (error) { triggerToast('Fehler: ' + error.message); return; }
const { data: { publicUrl } } = sb.storage.from('player-avatars').getPublicUrl(path);
// Render mit Transform: `${publicUrl}?width=400&quality=80`
```

**Migration-Pfad weg vom aktuellen `static/images/<name>.jpg`:** Nicht v1. Bestehende Photos bleiben filesystem-basiert (`imgPath()`), neue Selfservice-Uploads gehen in Bucket. `players` bekommt zusätzlich `avatar_url TEXT NULL` Spalte; `imgPath()` fallback-Hierarchie: `avatar_url > photo > BLANK_IMG`.

### Scheduled Push-Notifications → Bestehende Vercel Cron erweitern

**Empfehlung:** Vercel Cron erweitern, **NICHT** zu Supabase pg_cron migrieren.

**Begründung:**
- KVWN hat bereits 3 produktive Vercel Cron-Jobs (`keyduty-check`, `lineup-reminders`, `gcal-sync`) + `web-push` 3.6.7 wired in `/api/push/notify`.
- Vercel Pro-Plan: 100 Cron-Jobs pro Projekt (Stand Jan 2026, vorher 40), keine Per-Team-Limits, sub-Minute-Genauigkeit. Headroom riesig.
- pg_cron würde Edge-Functions (Deno) als Sender nötig machen → Web-Push-Lib müsste neu wired werden (Deno-WebCrypto-API statt Node), VAPID-Schlüssel zu Vault, andere Logging-Pipeline.
- Pattern bleibt einheitlich: Tabellen-driven Reminder (z.B. `training_bookings` mit `reminder_sent_at`), Cron läuft, fetched Pending, schickt via `push.notify`.

**Konkrete neue Cron-Jobs für v1:**

| Job | Schedule | Findet | Sendet |
|-----|----------|--------|--------|
| `/api/cron/training-reminders` | Daily 18:00 UTC | Trainingsbuchungen für morgen, `reminder_sent_at IS NULL` | "Morgen Training um {time} auf Bahn {n}" |
| `/api/cron/event-reminders` | Daily 09:00 UTC | Events `date = today + 1` | "Morgen: {event.title} um {time}" |
| `/api/cron/poll-deadline` | Hourly | Polls mit `closes_at` in nächsten 6 h, User noch nicht abgestimmt | "Umfrage läuft ab: {poll.title}" |

Erweiterung von `vercel.json` → kein neuer Stack-Bestandteil, nur Config + neue Routes.

**Bei welchen Pattern könnte pg_cron sinnvoll sein?** v2/v3 wenn:
- Sub-Minute-Reminders (z.B. "5 Min vor Match-Start") gefordert sind und Vercel-Cron-Drift (~1 min) zu groß wird.
- Massive Fanout (>1000 Reminder pro Run) → DB-internes Iterieren billiger als Edge-Function-Roundtrip.
- Beides ist v1 nicht relevant.

### Polls/Umfragen → DB-only, keine Library

**Empfehlung:** Schema-Pattern in Postgres + RLS, keine externe Lib.

**Begründung:**
- "Lib für Polls" gibt es nicht meaningful im Svelte-Ökosystem — alle existierenden Pakete sind UI-Renderer für Single-Choice mit Server-Mock; nichts was Multi-Tenant-RLS, Push-Trigger, Closing-Logic deckt.
- KVWN hat das Pattern bereits perfekt etabliert (`game_plans`, `match_carpools`, `task_dismissals` etc.) — Tabellen + RLS + browser-direkte `sb`-Aufrufe.
- Schema-Vorschlag (Migration in v1):
  ```sql
  create table polls (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    description text,
    multi_select boolean default false,
    closes_at timestamptz,
    created_by uuid references players(id),
    created_at timestamptz default now()
  );
  create table poll_options (
    id uuid primary key default gen_random_uuid(),
    poll_id uuid references polls(id) on delete cascade,
    label text not null,
    sort_order int
  );
  create table poll_votes (
    poll_id uuid references polls(id) on delete cascade,
    option_id uuid references poll_options(id) on delete cascade,
    player_id uuid references players(id) on delete cascade,
    voted_at timestamptz default now(),
    primary key (poll_id, option_id, player_id)
  );
  -- RLS-Pattern: Standard KVWN-Email-Bridge.
  ```

### Form-Validation für Selfservice → valibot pur, ohne Form-Lib

**Empfehlung:** `valibot` direkt in `<script>` mit Runes, keine Form-Bibliothek.

**Begründung:**
- KVWN-Pattern ist `let foo = $state('')` + Submit-Handler mit `await sb.from(...).update(...)`. Form-Libs wollen einen `<form action>`-handler, der zu `+page.server.js` führt — das macht KVWN bewusst nicht.
- valibot-Schema ist composable und tree-shakable, keine "engine" notwendig.
- Validierungs-State als `$derived` — passt nahtlos.

**Beispiel-Pattern (Spieler-Selfservice):**
```js
import * as v from 'valibot';
import { triggerToast } from '$lib/stores/toast.js';

const PlayerProfileSchema = v.object({
  phone: v.pipe(v.string(), v.regex(/^\+43|0[0-9 \-]+$/, 'Bitte österreichische Telefonnummer')),
  birthday: v.pipe(v.string(), v.isoDate('YYYY-MM-DD')),
  license_no: v.pipe(v.string(), v.regex(/^[A-Z0-9]+$/i, 'Nur Buchstaben/Zahlen')),
  emergency_contact: v.optional(v.string()),
});

let phone = $state(''), birthday = $state(''), license_no = $state(''), emergency = $state('');

const result = $derived(v.safeParse(PlayerProfileSchema, {
  phone, birthday, license_no, emergency_contact: emergency || undefined
}));
const errors = $derived(result.success ? {} : Object.fromEntries(
  result.issues.map(i => [i.path?.[0]?.key, i.message])
));
const canSave = $derived(result.success);

async function save() {
  if (!result.success) return;
  const { error } = await sb.from('players').update(result.output).eq('id', $playerId);
  if (error) { triggerToast('Fehler: ' + error.message); return; }
  triggerToast('Gespeichert.');
}
```

### Date/Time-Picker → Native HTML5 first, fallback @internationalized/date

**Empfehlung:** Native `<input type="date" lang="de-AT">` und `<input type="time">` als Standard. Nur dort `@internationalized/date` einbringen, wo Multi-Day-Range-Picking oder Custom-Visualisierung gefragt ist (v1: nicht der Fall).

**Begründung:**
- Mobile-Safari/Chrome auf Android öffnen System-DatePicker mit voller a11y, lokal richtig, Touch-perfekt — das schlägt jede JS-Lib auf Mobile.
- `lang="de-AT"` triggert Wiener-Format korrekt.
- v1 hat nur Punkt-Selektionen (Geburtstag, Storno-Datum). Range-UIs sind v2.

**Wenn doch Picker gebraucht wird** (z.B. Kalender-Range für Statistiken): `@internationalized/date` 3.12.1 als Headless-Layer + eigene UI mit KVWN-Tokens. Nicht bits-ui (ungeklärte Tailwind-Annahmen, 18 kB für eine Sache).

---

## Installation

```bash
# Nur 3 neue Production-Deps für v1
npm install layerchart@next valibot @internationalized/date
```

Aufgelöst:
- `layerchart@2.0.0-next.59` (Svelte-5-Line, Stand 2026-04-24)
- `valibot@1.3.1`
- `@internationalized/date@3.12.1`

**Keine Dev-Dependencies hinzu.** Kein Linter, kein Test-Framework, kein Type-Generator. Bewusste Entscheidung.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| layerchart 2-next (Svelte 5) | layerchart 1.0.13 (stable, supports Svelte 5 als Peer aber Code wurde für Svelte 4 geschrieben) | Falls "next"-Tag in Praxis bricht — 1.0.13 läuft mit Svelte 5 als Peer-Dep, aber API ist Svelte-4-Patterns. Risk: Entwickler-Unklarheit, wenn LayerChart Docs schon Svelte-5-Beispiele zeigen. → **next bevorzugen.** |
| layerchart | chart.js + svelte-chartjs 4.0.1 | Falls Team Chart.js-Erfahrung hat und Canvas-Performance bei 10k+ Datenpunkten nötig. KVWN-Realität: ~50 Spieler × 30 Spiele = 1500 Punkte → SVG fully ok. |
| valibot | zod 4.3.6 | Falls bestehender zod-Code im Projekt wäre. Ist nicht. Greenfield-Choice → valibot. |
| Supabase Storage | Vercel Blob | Falls Bilder >100 MB erwartet (CDN-Edge-Vorteil). Spielerfotos sind <500 kB → kein Vorteil. |
| Vercel Cron | Supabase pg_cron | Falls sub-Minute-Drift problematisch wird oder DB-internes Fanout (>1000 pushes/run) nötig. v2-Thema. |
| Native `<input type="date">` | bits-ui DatePicker | Falls inline-Kalender (keine Modal-Picker) UX-Anforderung wird. v1: nicht. |

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `layerchart@2.0.0-next.59` | `svelte@^5.0.0` | Pre-1.0 Tag — Breaking-Changes zwischen next-Releases möglich. Lock im `package.json` mit exakter Version, kein `^`. |
| `valibot@1.3.1` | Pure ESM, keine peer | Funktioniert mit jeder JS-Runtime. Pure Function-Library. |
| `@internationalized/date@3.12.1` | Pure ESM, keine peer | Standalone, kein React/Svelte-Coupling. |
| layerchart deps `runed@^0.37.1` | `svelte@^5.0.0` | Runed ist Svelte-5-only. Kein Konflikt mit KVWN. |
| layerchart 2-next deps `date-fns@^4.1.0` | Transitive | KVWN nutzt `date-fns` nicht selbst → kein Versionskonflikt. |

---

## Confidence per Recommendation

| Item | Confidence | Reason |
|------|------------|--------|
| layerchart 2-next | MEDIUM-HIGH | Verifiziert via npm (release 2026-04-24); aktive Entwicklung; 49 next-Releases in 2026. Pre-1.0 → Risiko von Breaking-Changes. Mitigation: exakte Version pinnen, Test bei Bump. |
| valibot 1.3.1 | HIGH | Stable v1; offiziell empfohlen als Zod-Alternative; Verified über npm + Builder.io-Bundle-Studie. |
| @internationalized/date 3.12.1 | HIGH | Adobe-React-Spectrum-Stack, multi-jähriger Track-Record, used by bits-ui und ganzen React-Ecosystem. |
| Supabase Storage über Vercel Blob | HIGH | Verifiziert via Supabase-Docs (RLS-Pattern für `auth.jwt()->>'email'`). Konsistent mit KVWN-Pattern. |
| Vercel Cron über pg_cron | HIGH | Verifiziert via Vercel Changelog (100/Project, Jan 2026). Bestehende Cron-Architektur skaliert. |
| Polls als DB-Tabellen | HIGH | KVWN-Pattern dokumentiert in CLAUDE.md (`game_plans`, RLS via email). |
| Native Date/Time vs Lib | HIGH | Mobile-PWA Best-Practice, MDN dokumentiert; KVWN-mobile-first → klare Wahl. |
| valibot statt superforms | HIGH | Superforms ist explizit für `+page.server.js`-Pattern (siehe superforms.rocks); KVWN ist bewusst Browser-direkt. |

---

## Conflicts/Duplications with Existing Stack

| Existing | New | Conflict? | Resolution |
|----------|-----|-----------|------------|
| `$lib/utils/dates.js` | layerchart's transitive `date-fns@4` | None | Transitive only; KVWN-App-Code ruft date-fns nicht direkt auf. |
| `$lib/stores/toast.js` (`triggerToast`) | — | — | Keine Toast-Lib einführen. |
| `web-push@3.6.7` (Node, server-side) | — | — | Keep as-is. Neue Cron-Routes nutzen es. |
| `$lib/utils/players.js` `imgPath()` | Supabase-Storage-URLs | Soft conflict | imgPath() um `avatar_url`-Fallback erweitern (siehe Storage-Pattern oben). |
| `players` Tabelle | Neue Spalten (`avatar_url`, `phone`, `birthday`, `license_no`, `emergency_contact`) | None | Migration in v1 ohnehin nötig — Selfservice-Stammdaten. |

**Keine Konflikte mit JS-only-Constraint:** valibot, layerchart, @internationalized/date sind alle in TS geschrieben, aber via npm als kompiliertes JS+`.d.ts` ausgeliefert. KVWN-Code bleibt JS pure.

**Keine Konflikte mit Test/Lint/Format-Lock:** Keine devDependencies werden hinzugefügt.

---

## Stack Patterns by Variant

**Falls layerchart 2-next-Tag in Praxis Probleme macht (z.B. API-Bruch zwischen next.59 und next.65):**
- Fallback: layerchart 1.0.13 mit `<script>`-Glue-Code (klein, weil KVWN nur 4–6 Charts braucht)
- Oder: D3-direkt in eigenen Komponenten — KVWN-Charts sind nicht so komplex (Bar/Line/Donut), 30–80 Zeilen pro Chart-Komponente realistisch

**Falls Supabase Storage Bandwidth-Quota knapp wird:**
- Cloudflare R2 oder Vercel Blob-Migration v2-Thema
- Mitigation v1: Image-Transform `?width=400` aggressiv nutzen, Service-Worker cache-aggressive für `/storage/v1/object/public/player-avatars/*`

**Falls Push-Volume hochskaliert (>1000/run):**
- Cron-Job-Splitting (chunked Sends) reicht weit. pg_cron-Migration erst bei >50k Events/Tag relevant.

---

## Sources

- npm registry queries (verified 2026-04-28):
  - `layerchart@1.0.13` (latest), `layerchart@2.0.0-next.59` (next)
  - `valibot@1.3.1`
  - `@internationalized/date@3.12.1`
  - `chart.js@4.5.1`, `svelte-chartjs@4.0.1` (released 2026-03-15)
  - `sveltekit-superforms@2.30.1`, `formsnap@2.0.1`, `bits-ui@2.18.0`
  - `zod@4.3.6` (für Vergleich)
- Context7 — `/techniq/layerchart` (Library ID resolved, 35 snippets, High Reputation, Score 80.9)
- Supabase Docs — [Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control) (avatar RLS pattern verified)
- Supabase Docs — [Cron Quickstart](https://supabase.com/docs/guides/cron/quickstart) (pg_cron capabilities)
- Vercel Changelog — [Cron jobs now support 100 per project](https://vercel.com/changelog/cron-jobs-now-support-100-per-project-on-every-plan) (Jan 2026)
- Vercel Docs — [Cron Jobs Usage and Pricing](https://vercel.com/docs/cron-jobs/usage-and-pricing)
- Builder.io — [Valibot bundle size analysis](https://www.builder.io/blog/valibot-bundle-size) (1.37 kB vs Zod's 17.7 kB)
- LayerChart — [Releases / Changelog](https://github.com/techniq/layerchart/releases) (Svelte 5 = 2.0-next line)
- KVWN existing code — `CLAUDE.md`, `.planning/codebase/STACK.md`, `.planning/codebase/INTEGRATIONS.md` (current architecture)

---

*Stack research for: KVWN v1 additions on top of locked SvelteKit 5 + Supabase + Vercel*
*Researched: 2026-04-28*
