# Phase 0: Cross-Cutting Foundations — Research

**Phase:** 0 (Cross-Cutting Foundations)
**Researched:** 2026-04-29 (inline by orchestrator after gsd-phase-researcher stalled — Windows stdio hang)
**Source:** Direct codebase verification (Grep + Read) against `supabase/migrations/`, `src/routes/api/cron/`, `src/lib/`, `src/lib/components/`
**Phase REQs covered:** FOUND-01..07

---

## Phase Boundary

Fix die zwei BLOCKER-Pitfalls (C1 RLS-Cross-Write, C3 Cron-TZ-Drift) und liefere 5 Cross-Cutting-Helper (TZ, Resize, `is_demo`, `PUSH_PREFS`, Reminder-Idempotenz). NON-NEGOTIABLE BLOCKER vor Phase 1–4. Keine UI-Surface außer Captain-Audit-Runbook (Markdown). 7 REQs · 2 Tage · 4–5 Migrations.

---

## Domain Model

| Layer | Files touched in Phase 0 |
|-------|--------------------------|
| DB Migrations | `supabase/migrations/20260430_*.sql` (4–5 neu, Datum 2026-04-30++) + `supabase/migrations/_audit/20260430_email_pre_check.sql` (audit-only, prefix `_audit/` damit kein auto-apply) |
| Server-helpers | `src/lib/server/timezone.js` (NEU) |
| Browser-utils | `src/lib/utils/imageResize.js` (NEU) |
| Constants | `src/lib/constants/pushPrefs.js` (NEU) |
| Cron | `src/routes/api/cron/lineup-reminders/+server.ts` (REFACTOR — TZ + reminder_log) |
| Docs | `docs/runbooks/email-cleanup.md` (NEU, Captain-Anleitung) + `docs/patterns/is-demo.md` (NEU, FOUND-06) |

Keine Svelte-Komponenten in Phase 0 (Captain-Cleanup ist Markdown-Runbook + SQL-Skript, kein UI).

---

## Existing Codebase State (Verified Facts)

### `players`-Tabelle — aktueller Schema-Stand

**Migrations, die `players` definieren/ändern:**
- `20260420_uebersicht_features.sql` Z 4–5 — `ADD COLUMN IF NOT EXISTS birth_date DATE`
- `20260422_profil_selfservice.sql` Z 5–24 — 14 Spalten (jersey_number, shoe_size, emergency_contact_*, iban, account_holder, member_since, membership_status, drivers_license, default_car_seats, dietary_notes, **consent_photo, consent_liga_data, consent_whatsapp, consent_accepted_at**, attest_url) plus Constraints jersey_number_range / jersey_number_uq

**`players.email`-Constraint-Status (kritisch für FOUND-01):**
```
grep -i "players.*email.*UNIQUE|UNIQUE.*players.*email|players_email|email\s+text\s+NOT\s+NULL" supabase/migrations
→ No matches found
```

→ **`email` ist heute weder UNIQUE noch NOT NULL.** FOUND-01-Migration muss beides ergänzen, NACH Captain-Cleanup-Audit + retroaktivem `UPDATE … SET email = lower(email)`.

**`players.push_prefs` existiert NICHT:**
```
grep "push_prefs" supabase/migrations → keine Treffer in *.sql
grep "push_prefs" src/                → keine Treffer
```

→ FOUND-05-Migration muss `ADD COLUMN push_prefs JSONB DEFAULT '{}'::jsonb NOT NULL` plus CHECK-Whitelist.

### Bestehende RLS-Policies auf `public.players`

Aus `20260422_profil_selfservice.sql` Z 84–116 (verbatim):

```sql
-- 5. RLS auf public.players (erstmalig).
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

-- 5a. Alle Eingeloggten lesen alle Spieler.
CREATE POLICY "players read" ON public.players
  FOR SELECT USING (true);

-- 5b. Kapitän/Admin schreibt alles.
CREATE POLICY "players kapitaen write" ON public.players
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  );  -- ⚠ KEIN WITH CHECK

-- 5c. Self-Update: eigene Zeile, geschützte Spalten dürfen sich nicht ändern.
CREATE POLICY "players self update" ON public.players
  FOR UPDATE
  USING (email = (auth.jwt() ->> 'email'))
  WITH CHECK (
    email = (auth.jwt() ->> 'email')
    AND role              IS NOT DISTINCT FROM (SELECT role              FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND active            IS NOT DISTINCT FROM (SELECT active            FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND membership_status IS NOT DISTINCT FROM (SELECT membership_status FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND member_since      IS NOT DISTINCT FROM (SELECT member_since      FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND email             IS NOT DISTINCT FROM (auth.jwt() ->> 'email')
  );
```

**Kritische Korrektur zu CONTEXT D-04:** `WITH CHECK (id = …)`-Pin ist in der **bestehenden `players self update`-Policy bereits aktiv** (über `email = auth.jwt()` plus column-pin). C1 (Cross-Spieler-Write) ist heute über `players self update` BEREITS blockiert für Nicht-Captains, weil die Policy nur Rows mit `email = auth.jwt() ->> 'email'` selectet UND `WITH CHECK` verhindert dass `email` auf einen anderen Wert geschrieben wird.

**Was FOUND-02 tatsächlich tun muss:**
1. **WITH CHECK auch auf `players kapitaen write`** ergänzen (heute: USING only). Begründung: Kapitän kann heute `role`, `active`, `email` einer beliebigen Row auf beliebige Werte setzen — ohne Constraint. Nicht akut C1 (Captain ist trusted), aber Defense-in-depth + verhindert Tippfehler-Selbst-Demotion.
2. **Cross-Write-Smoke-Test scripten** (Spieler A → Spieler B Update) und das Ergebnis dokumentieren — sollte **bereits 403 liefern**.
3. **Audit der `consent_*`-Spalten:** sind nicht in der `IS NOT DISTINCT FROM`-Liste der `players self update`-Policy → Spieler kann eigene Consents setzen (das ist KORREKT — DSGVO-Workflow, SELF-07 abhängig).
4. CONTEXT D-04 `Policy-Branch \`self OR captain\` als COMBINED-Policy` ist eine **Vereinfachung** und würde die existierenden 2 Policies durch 1 ersetzen — gleichwertig, aber Risiko Refactor-Bug. Empfehlung Planner: NICHT die 2 Policies zu 1 verschmelzen; stattdessen Captain-Policy um WITH CHECK erweitern, Self-Update unverändert lassen.

### Bestehende Cron-Datei `/api/cron/lineup-reminders/+server.ts`

Verbatim (63 Z, TS-Datei nicht JS!):

```ts
import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL         = process.env.VITE_SUPABASE_URL         ?? '';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const CRON_SECRET          = process.env.CRON_SECRET               ?? '';

export const GET: RequestHandler = async ({ request, url, fetch }) => {
  const auth = request.headers.get('authorization') ?? '';
  if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
    return new Response('', { status: 401 });
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // tomorrow YYYY-MM-DD (local)  ⚠ DRIFT-RISIKO C3
  const t = new Date();
  t.setDate(t.getDate() + 1);
  const tomorrow = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;

  const { data: plans } = await admin
    .from('game_plans')
    .select('id, confirmation_deadline, cal_week, league_id, game_plan_players(player_id, confirmed)')
    .not('lineup_published_at', 'is', null)
    .eq('confirmation_deadline', tomorrow);

  let sent = 0;
  for (const plan of plans ?? []) {
    const pending = ((plan as any).game_plan_players ?? []).filter((e: any) => e.confirmed === null);
    if (!pending.length) continue;

    const { data: m } = await admin
      .from('matches')
      .select('opponent, leagues(name)')
      .eq('cal_week', (plan as any).cal_week)
      .eq('league_id', (plan as any).league_id)
      .maybeSingle();

    const leagueName = (m as any)?.leagues?.name ?? '';
    const opponent   = (m as any)?.opponent ?? '';

    const res = await fetch(`${url.origin}/api/push/notify`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${CRON_SECRET}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        player_ids: pending.map((e: any) => e.player_id),
        title: 'Aufstellung bestätigen – Frist morgen',
        body:  `${leagueName} vs. ${opponent}`,
        url:   '/#action-hub-lineup',
        pref_key: 'lineup_reminder',  // ⚠ pref_key heisst hier 'lineup_reminder', nicht 'lineup_confirm'
      }),
    });
    const r = await res.json().catch(() => ({ sent: 0 }));
    sent += r.sent ?? 0;
  }

  return new Response(JSON.stringify({ ok: true, sent }), { headers: { 'Content-Type': 'application/json' } });
};
```

**FOUND-04-Refactor-Punkte konkret:**
1. Z 17–19 `tomorrow`-Berechnung mit Vercel-UTC-Process: heute `getFullYear()`/`getMonth()`/`getDate()` nutzen Process-TZ (UTC auf Vercel). Auf 2026-04-30 23:30 Vienna (= 21:30 UTC) → `t = new Date()` ergibt 2026-04-30, +1 = 2026-05-01 — korrekt; aber 2026-10-26 02:00 Vienna (DST-Wechsel) → 2026-10-26 00:00 UTC ≈ DST-Ambiguität → Drift-Risiko. **Ersetzen durch `dateInVienna(1)` aus FOUND-03.**
2. Keine `reminder_log`-Idempotenz — Doppel-Cron-Trigger schickt Doppel-Push. **Hinzufügen:** vor jedem `fetch /api/push/notify` ein `INSERT INTO reminder_log (plan_id, kind) VALUES (..., 'lineup_24h') ON CONFLICT DO NOTHING RETURNING id`; nur senden wenn RETURNING eine Row liefert.
3. **Pref-Key-Inkonsistenz mit CONTEXT D-06:** Cron sendet `pref_key: 'lineup_reminder'`, aber CONTEXT D-05 sagt `lineup_confirm` ist always-on (operativ-essentiell). **Planner-Entscheidung:** Entweder (a) `pref_key` in /api/push/notify komplett ignoriert für `lineup_*`-Keys (always-on), oder (b) Konstante `LINEUP_REMINDER_PREF` in pushPrefs.js dokumentiert dass dieser Key NICHT user-toggle-bar ist. Empfehlung: (a) — `/api/push/notify` checked nur für Keys aus `PUSH_PREFS`-Whitelist; alles andere (lineup_*) gilt als operational.

### Bestehender Vienna-TZ-Pattern als Analog für FOUND-03

`src/lib/server/gcal.js` Z 6 + Z 162–184 (verbatim, **das ist der Code-Analog für `nowVienna()` / `dateInVienna()`**):

```js
const TIME_ZONE = 'Europe/Vienna';

// timed event — explizit in Europe/Vienna lesen, sonst driftet UTC-Prozess
// (z. B. Vercel) Termine um die Zeitzonen-Differenz.
const dt = new Date(ev.start.dateTime);
const parts = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE,
  year:   'numeric',
  month:  '2-digit',
  day:    '2-digit',
  hour:   '2-digit',
  minute: '2-digit',
  hour12: false,
}).formatToParts(dt);
const get = (t) => parts.find(p => p.type === t)?.value ?? '';
const y  = get('year');
const mo = get('month');
const da = get('day');
let   h  = get('hour');
const mi = get('minute');
// Intl liefert 24 für Mitternacht in en-CA → auf 00 normalisieren
if (h === '24') h = '00';
date = `${y}-${mo}-${da}`;  // 'YYYY-MM-DD'
time = `${h}:${mi}:00`;     // 'HH:mm:ss'
```

**Empfehlung Planner für FOUND-03:** `$lib/server/timezone.js` exportiert `nowVienna()` und `dateInVienna(offsetDays = 0)` mit identischem `Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Vienna' })`-Pattern. Beide Returns als `'YYYY-MM-DD'`-String (kein Date-Object — vermeidet Ambiguität bei DST). `nowVienna()` returns `{ date: 'YYYY-MM-DD', time: 'HH:mm:ss' }`. DST-Doppel-02:00-Edge-Case ist mit `Intl.DateTimeFormat` kein Problem — Intl liefert deterministisch die DST-korrekte Local-Zeit.

### Existing `$lib`-Files (FOUND-Helper-Greenfield-Verifikation)

```
$lib/server/   →  supabase-admin.js  ·  gcal.js
                  → KEIN timezone.js — FOUND-03 greenfield ✓
$lib/utils/    →  feedbackRotation.js  ·  league.js  ·  roundCode.js  ·
                  eligibility.js  ·  matchTiming.js  ·  dates.js  ·  players.js
                  → KEIN imageResize.js — FOUND-07 greenfield ✓
$lib/constants/ → competitions.js
                  → KEIN pushPrefs.js — FOUND-05 greenfield ✓
```

### `canvas.toBlob` / Image-Resize-Usage — greenfield für FOUND-07

```
grep "canvas\.toBlob|toDataURL|imageResize" src/ → No matches found
```

→ Keine bestehende Browser-Side-Resize-Pipeline. FOUND-07 startet greenfield. Storage-Bucket `player-photos` wird in SELF-03 (Phase 1) angelegt — FOUND-07 liefert NUR die Resize-Pipeline, nicht das Upload-Wiring.

### `reminder_log` und `is_demo` — greenfield

```
grep "reminder_log" src/ supabase/ → nur in Planning-Docs, kein Code
grep "is_demo"      src/ supabase/ → nur in Planning-Docs, kein Code
```

FOUND-04 erstellt `reminder_log`-Tabelle. FOUND-06 etabliert `is_demo`-Pattern (Doku + Migration-Vorlage, KEIN retroaktives ALTER auf bestehende Tabellen — Bestand ist Real-Daten).

### `players`-UPDATE-Call-Sites (Cross-Write-Smoke-Test-Targets)

Browser-Calls `sb.from('players').update(...)` heute in 5 Files (alle Browser-`sb`-Pfad, RLS-gegated):

1. `src/lib/components/admin/AdminRollen.svelte` — Captain ändert `role` (heute via `players kapitaen write`-Policy).
2. `src/lib/components/profil/UebersichtTab.svelte` — Spieler updates Stammdaten (via `players self update`).
3. `src/lib/components/profil/EinstellungenTab.svelte` — Spieler updates Settings (z.B. push-toggles).
4. `src/lib/components/profil/ProfilHeroCard.svelte` — Profil-UI-Felder (z.B. avatar/photo_url).
5. `src/lib/components/profil/ProfilEinwilligungenCard.svelte` — Spieler setzt `consent_*`-Felder.

**Smoke-Test-Liste für FOUND-02 nach Migration-Deploy:** alle 5 Files manuell durchklicken; Network-Tab zeigt 200, kein 401/403. Captain-Pfad zusätzlich AdminAufstellung.svelte (kein direktes `players`-UPDATE, aber gleicher Captain-Trust-Path).

### `push_subscriptions`-Tabelle (Kontext für FOUND-05)

`src/lib/push/register.js` referenziert `push_subscriptions(player_id, endpoint, p256dh, auth)`. **Diese Tabelle ist orthogonal zu FOUND-05** — `players.push_prefs` ist Pref-Toggle (welche Pushes der User WILL), `push_subscriptions` ist die Browser-Endpoint-Liste (wo Pushes hingeschickt werden). Phase 5 DEMO-08 fügt Subscription-Cleanup-Cron hinzu (nicht Phase 0).

---

## Implementation Approach (per FOUND-Req)

### FOUND-01 — `players.email NOT NULL UNIQUE` + lower()-Normalisierung + Pre-Deploy-Audit

**Files:**
- `supabase/migrations/_audit/20260430_email_pre_check.sql` — Audit-Skript (NICHT auto-applied wegen `_audit/`-Prefix)
- `supabase/migrations/20260430_email_unique.sql` — Eigentliche Migration
- `docs/runbooks/email-cleanup.md` — Captain-Anleitung (Markdown)

**Audit-Skript (`_audit/...`):**
```sql
-- Run in Supabase Studio. Output muss VOR Migration leer sein.
SELECT id, email, name FROM public.players WHERE email IS NULL;

SELECT lower(email) AS norm_email, COUNT(*), array_agg(id) AS player_ids
FROM public.players
GROUP BY lower(email)
HAVING COUNT(*) > 1;
```

**Migration (deploy nur wenn beide Queries 0 Rows):**
```sql
-- 1. Retroaktiv lowercase
UPDATE public.players SET email = lower(email) WHERE email IS NOT NULL AND email <> lower(email);

-- 2. NOT NULL + UNIQUE
ALTER TABLE public.players ALTER COLUMN email SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS players_email_uq ON public.players (email);

-- 3. Trigger forciert lowercase auf zukünftige Inserts/Updates
CREATE OR REPLACE FUNCTION public.players_email_lower()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.email := lower(NEW.email);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS players_email_lower_tg ON public.players;
CREATE TRIGGER players_email_lower_tg
  BEFORE INSERT OR UPDATE OF email ON public.players
  FOR EACH ROW EXECUTE FUNCTION public.players_email_lower();
```

**Captain-Runbook-Inhalt:** 1) Audit-Query in Supabase-Studio kopieren, 2) bei Duplikaten manuell konsolidieren (Family-Account → 1 Spieler bekommt primäre Gmail, andere bekommen plus-aliases `gmail+name@gmail.com` oder Vereins-Mail), 3) re-run bis 0 Rows, 4) Captain meldet "Audit clean" → Dev deployed Migration via `supabase db push`.

### FOUND-02 — RLS-Policy-Refactor `players` mit `WITH CHECK`-Pin

**Files:**
- `supabase/migrations/20260430_players_rls_pin.sql`
- `docs/runbooks/rls-cross-write-test.md` (kurzes Smoke-Test-Skript)

**Migration:**
```sql
-- Captain-Policy: WITH CHECK ergänzen (Defense-in-depth, verhindert Tippfehler-Self-Demotion).
-- Bestehende USING-Klausel bleibt, WITH CHECK erlaubt Captain alles ZU SETZEN solange er Captain bleibt.
DROP POLICY IF EXISTS "players kapitaen write" ON public.players;
CREATE POLICY "players kapitaen write" ON public.players
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  );

-- "players self update" bleibt UNVERÄNDERT — bestehende WITH CHECK Column-Pin ist korrekt.
-- Smoke-Test-Verifikation siehe runbook.
```

**Cross-Write-Smoke-Test (`docs/runbooks/rls-cross-write-test.md`):**
- Login als Spieler A (nicht Captain).
- DevTools-Console: `await sb.from('players').update({ phone: 'pwned' }).eq('id', '<spieler-b-id>')`.
- Erwartet: `error.code === 'PGRST204'` (no rows updated, RLS hat gefiltert) oder `error.code === '42501'` (permission denied via WITH CHECK).
- Wiederholen mit `update({ email: 'pwned@x.de' })`: muss von WITH CHECK email-Pin abgelehnt werden.

### FOUND-03 — `$lib/server/timezone.js` mit `nowVienna()` / `dateInVienna(offsetDays)`

**File:** `src/lib/server/timezone.js` (neu, server-only weil in Cron + Edge-Functions genutzt; Browser braucht es nicht)

**API:**
```js
// $lib/server/timezone.js
const TIME_ZONE = 'Europe/Vienna';

const VIENNA_FORMATTER = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE,
  year:   'numeric',
  month:  '2-digit',
  day:    '2-digit',
  hour:   '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

function partsOf(date) {
  const parts = VIENNA_FORMATTER.formatToParts(date);
  const get = (t) => parts.find(p => p.type === t)?.value ?? '';
  let h = get('hour');
  if (h === '24') h = '00';  // Intl 24:xx Mitternacht-Edge-Case
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    time: `${h}:${get('minute')}:${get('second')}`,
  };
}

/** Aktuelle Zeit als Vienna-local. Returns { date: 'YYYY-MM-DD', time: 'HH:mm:ss' }. */
export function nowVienna() {
  return partsOf(new Date());
}

/** Datum +offsetDays in Vienna-local (DST-aware). Returns 'YYYY-MM-DD'. */
export function dateInVienna(offsetDays = 0) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return partsOf(d).date;
}
```

**DST-Argumentation:** `Intl.DateTimeFormat` mit `timeZone: 'Europe/Vienna'` rechnet automatisch um (DST-aware). Edge-Case 02:00 doppelt am 2026-10-26: Vienna fällt von UTC+2 auf UTC+1 zurück. `dateInVienna(0)` am 2026-10-26 01:30 UTC liefert `'2026-10-26'` (CEST, vor DST-Wechsel) — korrekt. Test via Vercel-Cron-Logs vor/nach 26.10.

### FOUND-04 — Refactor `lineup-reminders`-Cron + `reminder_log`

**Files:**
- `supabase/migrations/20260430_reminder_log.sql` (NEU)
- `src/routes/api/cron/lineup-reminders/+server.ts` (REFACTOR)

**Migration:**
```sql
CREATE TABLE IF NOT EXISTS public.reminder_log (
  plan_id    UUID NOT NULL REFERENCES public.game_plans(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('lineup_24h')),
  sent_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (plan_id, kind)
);

ALTER TABLE public.reminder_log ENABLE ROW LEVEL SECURITY;
-- Niemand schreibt direkt — nur Service-Role über Cron.
```

**Cron-Refactor (`+server.ts`):**
```ts
import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import { dateInVienna } from '$lib/server/timezone.js';

const SUPABASE_URL         = process.env.VITE_SUPABASE_URL         ?? '';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const CRON_SECRET          = process.env.CRON_SECRET               ?? '';

export const GET: RequestHandler = async ({ request, url, fetch }) => {
  const auth = request.headers.get('authorization') ?? '';
  if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
    return new Response('', { status: 401 });
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  const tomorrow = dateInVienna(1);  // ← FOUND-03 Helper, DST-safe

  const { data: plans } = await admin
    .from('game_plans')
    .select('id, confirmation_deadline, cal_week, league_id, game_plan_players(player_id, confirmed)')
    .not('lineup_published_at', 'is', null)
    .eq('confirmation_deadline', tomorrow);

  let sent = 0;
  for (const plan of plans ?? []) {
    const pending = ((plan as any).game_plan_players ?? []).filter((e: any) => e.confirmed === null);
    if (!pending.length) continue;

    // Idempotenz-Guard: Insert reminder_log; bei Duplicate (zweiter Cron-Run) skip.
    const { data: logged, error: logErr } = await admin
      .from('reminder_log')
      .insert({ plan_id: (plan as any).id, kind: 'lineup_24h' })
      .select('plan_id')
      .maybeSingle();
    if (logErr || !logged) continue;  // schon gesendet → skip

    const { data: m } = await admin
      .from('matches')
      .select('opponent, leagues(name)')
      .eq('cal_week', (plan as any).cal_week)
      .eq('league_id', (plan as any).league_id)
      .maybeSingle();

    const leagueName = (m as any)?.leagues?.name ?? '';
    const opponent   = (m as any)?.opponent ?? '';

    const res = await fetch(`${url.origin}/api/push/notify`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${CRON_SECRET}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        player_ids: pending.map((e: any) => e.player_id),
        title: 'Aufstellung bestätigen – Frist morgen',
        body:  `${leagueName} vs. ${opponent}`,
        url:   '/#action-hub-lineup',
        pref_key: 'lineup_reminder',  // bleibt — operational, NICHT in PUSH_PREFS-Whitelist
      }),
    });
    const r = await res.json().catch(() => ({ sent: 0 }));
    sent += r.sent ?? 0;
  }

  return new Response(JSON.stringify({ ok: true, sent }), { headers: { 'Content-Type': 'application/json' } });
};
```

**Doppelter-Trigger-Test:** `curl -H "Authorization: Bearer $CRON_SECRET" $URL/api/cron/lineup-reminders` zweimal. Erwartet: erster Aufruf sent>0, zweiter sent=0 (reminder_log ON CONFLICT).

### FOUND-05 — `$lib/constants/pushPrefs.js` + DB-CHECK

**Files:**
- `src/lib/constants/pushPrefs.js` (NEU)
- `supabase/migrations/20260430_players_push_prefs.sql` (NEU)

**Konstante (CONTEXT D-06 verbatim):**
```js
// $lib/constants/pushPrefs.js
export const PUSH_PREFS = {
  training_24h:    'Training 24h vorher',     // TRAIN-04
  event_new:       'Neues Event',              // EVT-11
  event_reminder:  'Event 24h vorher',         // EVT-12
  poll_close:      'Umfrage schließt',         // EVT-13
  birthday:        'Geburtstags-Banner Push'   // SELF-11
};

// Operational pref-keys NICHT in PUSH_PREFS — werden ignoriert vom CHECK.
// 'lineup_reminder' wird vom Cron immer gesendet (Vereins-Lineup-Workflow §6(1)(f) DSGVO).
export const PUSH_PREF_KEYS = Object.keys(PUSH_PREFS);
```

**Migration:**
```sql
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS push_prefs JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.players
  DROP CONSTRAINT IF EXISTS players_push_prefs_keys;

ALTER TABLE public.players
  ADD CONSTRAINT players_push_prefs_keys CHECK (
    jsonb_typeof(push_prefs) = 'object'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(push_prefs) k
      WHERE k NOT IN ('training_24h','event_new','event_reminder','poll_close','birthday')
    )
  );
```

**Verifikation:** `INSERT INTO players (..., push_prefs) VALUES (..., '{"event_remminder": true}'::jsonb)` (Tippfehler) muss `check_violation` werfen.

### FOUND-06 — `is_demo` Pattern-Doku + Migration-Vorlage

**Files:**
- `docs/patterns/is-demo.md` (NEU, Markdown — Pattern-Beschreibung)
- (KEIN Migration-File, kein Code-Helper — Pattern wird in Phase 4 STAT-03/05 angewendet)

**`docs/patterns/is-demo.md`-Inhalt (Skelett, Planner finalisiert):**

> # `is_demo`-Pattern für Mock-Daten (FOUND-06)
> Jede neue v1-Tabelle, die Mock-Seeds für JHV-Demo aufnimmt, bekommt:
> ```sql
> ALTER TABLE … ADD COLUMN is_demo BOOLEAN DEFAULT false NOT NULL;
> ```
> Production-Reads filtern via View oder Query-WHERE: `WHERE NOT is_demo`.
> Cleanup-Migration post-JHV: `DELETE FROM <table> WHERE is_demo` (DEMO-03).
> Retroaktiv NICHT auf Bestandstabellen anwenden — Bestand sind Real-Daten.
>
> Erste Anwendung: `league_standings` (STAT-03/05, Phase 4).

### FOUND-07 — `$lib/utils/imageResize.js` Browser-Canvas-Helper

**File:** `src/lib/utils/imageResize.js` (NEU)

**API (CONTEXT D-07/D-08):**
```js
// $lib/utils/imageResize.js
const SIZE = 512;
const QUALITY = 0.82;

/**
 * Resize + Center-Crop ein File auf 512×512 WebP. EXIF wird durch Canvas-Re-encode entfernt.
 * @param {File} file
 * @returns {Promise<{ blob: Blob, mime: 'image/webp' }>}
 */
export async function resizeImage(file) {
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement('canvas');
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext('2d');

  // Center-Crop: nimm das kleinere Quadrat aus dem Original.
  const srcSize = Math.min(bitmap.width, bitmap.height);
  const sx = (bitmap.width  - srcSize) / 2;
  const sy = (bitmap.height - srcSize) / 2;
  ctx.drawImage(bitmap, sx, sy, srcSize, srcSize, 0, 0, SIZE, SIZE);

  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob(b => b ? resolve(b) : reject(new Error('toBlob returned null')), 'image/webp', QUALITY);
  });
  bitmap.close?.();
  return { blob, mime: 'image/webp' };
}
```

**Verifikation:**
1. iPhone-GPS-Sample-Foto durchschicken; `exiftool <output.webp>` zeigt 0 GPS-Tags.
2. Mehrere Sample-Fotos: `octet_length(blob)` < 200 KB bei `quality=0.82`.
3. WebP-Browser-Support: Safari 14+ (alle Mainstream-iOS), Chrome/Firefox/Edge problemlos.

---

## Validation Architecture (Nyquist) — REQUIRED

| Req | Validation Type | Concrete Test |
|-----|-----------------|---------------|
| FOUND-01 | Pre-deploy SQL audit | `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL` muss 0 Rows liefern VOR `supabase db push` |
| FOUND-01 | Trigger-Test | Insert mit `email='Test@X.DE'` → `SELECT email FROM players WHERE id=...` returns `'test@x.de'` |
| FOUND-02 | Cross-Write-Smoke-Test (Browser) | Login als Spieler A; DevTools `sb.from('players').update({phone:'x'}).eq('id', spieler_b_id)` → error mit code `42501` ODER 0 rows updated |
| FOUND-02 | Captain-Smoke-Test | Login als Captain; AdminRollen.svelte ändern eines Spielers — muss weiterhin 200 OK |
| FOUND-02 | Self-Update-Smoke-Test | Login als Spieler A; UebersichtTab Telefon ändern — muss 200 OK |
| FOUND-02 | Email-Pin-Test | Login als Spieler A; Versuch `update({email:'X'})` → muss 0 rows updated (WITH CHECK email-pin existing) |
| FOUND-03 | DST-Boundary-Test | Vor 2026-10-26 02:00 Vienna: `dateInVienna(0)` = '2026-10-26'; nach: gleiches Ergebnis (Intl-Format ist DST-aware, kein Drift) |
| FOUND-03 | UTC-vs-Vienna-Test | Auf Vercel (UTC-Process): `dateInVienna(1)` muss am Vienna-Mittwoch korrekt 'Donnerstag-Datum' liefern, nicht UTC-basiert |
| FOUND-04 | Cron-Idempotenz-Test | `curl Bearer-Auth $URL/api/cron/lineup-reminders` zweimal hintereinander → erster `{sent: N}`, zweiter `{sent: 0}` |
| FOUND-04 | reminder_log-Verifikation | `SELECT * FROM reminder_log WHERE plan_id=...` zeigt 1 Row pro plan_id+kind nach Cron-Run |
| FOUND-04 | TZ-Plug-Test | Cron-Log Timestamp + `dateInVienna(1)`-Output stimmen mit Vienna-Wallclock überein, nicht UTC |
| FOUND-05 | CHECK-Constraint-Test | `UPDATE players SET push_prefs='{"event_remminder":true}'::jsonb WHERE id=...` → `check_violation` Error |
| FOUND-05 | Valid-Key-Test | `UPDATE players SET push_prefs='{"event_new":true}'::jsonb WHERE id=...` → 200 OK |
| FOUND-05 | Constant-Single-Source | `grep PUSH_PREFS src/` zeigt: nur Imports aus `$lib/constants/pushPrefs.js`, keine duplizierte Liste |
| FOUND-06 | Doku-Existenz | `docs/patterns/is-demo.md` existiert + Migration-Vorlage drin |
| FOUND-06 | Anwendungs-Verweis | Phase 4 STAT-03/05 in ROADMAP referenziert das Pattern |
| FOUND-07 | EXIF-Strip-Test | iPhone-Photo durch `resizeImage` → `exiftool output.webp` zeigt keine `GPS*`-Tags |
| FOUND-07 | Größen-Test | Output-Blob `octet_length < 200_000` bei 5 Sample-Fotos |
| FOUND-07 | Center-Crop-Test | Hochformat-Foto → 512×512 Output mit zentriertem Motiv (visuell + Pixel-Dimension-Check) |
| FOUND-07 | WebP-Mime-Test | Output-Blob.type === 'image/webp' |

**Cross-Phase-Validation:**
- Nach Phase 0 Deploy: Browser-Network-Tab beobachten (Pitfall C11) — keine 401/403 in bestehenden Captain-Workflows.
- Nach FOUND-04 Deploy: `/api/cron/lineup-reminders` läuft nächste 7 Tage täglich + DST-Wechsel (falls in Saison).

---

## Open Questions / Risks

1. **CONTEXT D-04 vs Existing Code-Mismatch:** CONTEXT spricht von `Policy-Branch \`self OR captain\` als WITH CHECK`-Pin-Refactor — bestehende Code-Realität ist 2 separate Policies, beide korrekt strukturiert. Planner sollte die EXISTING-2-Policy-Struktur respektieren und nur `WITH CHECK` zur Captain-Policy hinzufügen. NICHT zu 1 combined Policy refactoren.
2. **`pref_key: 'lineup_reminder'` Inkonsistenz:** Cron sendet operational. CONTEXT D-05 sagt `lineup_confirm` (anderer Name). Planner muss klären ob Rename nötig oder ob `lineup_reminder` der korrekte operational-Key ist (heutiger Code-Stand). Empfehlung: Status quo behalten (`lineup_reminder` operational, NICHT in PUSH_PREFS-Whitelist).
3. **`/api/push/notify` PUSH_PREFS-Filter:** Bestehender Endpoint filtert vermutlich nicht nach `push_prefs`. FOUND-05 selbst erfordert KEINE notify-Endpoint-Änderung (Phase-0-Scope), aber Phase 1+ (SELF-07/EVT-13) müssen `players.push_prefs[pref_key]=true`-Filter ergänzen. **Out-of-Scope für Phase 0**, aber im Plan dokumentieren.
4. **`reminder_log` orphan-cleanup:** wenn `game_plans` gelöscht wird, kaskadiert (`ON DELETE CASCADE`) — keine Sorge. Aber wenn Cron failed nachdem `reminder_log` insert aber vor `/api/push/notify` → false-positive log entry. Akzeptabel: Verlust 1× 24h-Reminder pro Cron-Failure, kein Doppel-Push (Idempotenz wichtiger).
5. **Migration-Reihenfolge bei `supabase db push`:** Reihenfolge alphabetisch by filename. Vorschlag: `20260430a_email_audit.sql` (audit-prefix), `20260430b_email_unique.sql`, `20260430c_players_rls_pin.sql`, `20260430d_reminder_log.sql`, `20260430e_players_push_prefs.sql`. Audit-File MUSS in `_audit/`-Subordner damit Supabase es nicht als Migration anwendet.

---

## Pattern References (analog files in codebase)

| For | Existing analog | Why |
|-----|-----------------|-----|
| FOUND-03 timezone helper | `src/lib/server/gcal.js` Z 162–184 | Exakt gleicher `Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Vienna' })`-Pattern, mirror direkt |
| FOUND-02 Captain-Gate-RLS | `supabase/migrations/20260421_training_codify.sql` Z 67–73 (`training_templates captain`) | Captain-EXISTS-Subquery-Pattern — exakte Vorlage |
| FOUND-02 Self-Update-RLS | `supabase/migrations/20260422_profil_selfservice.sql` Z 105–116 (`players self update`) | Bestehende Policy bleibt, nur Captain-Policy ergänzt |
| FOUND-04 Cron-Auth | bestehende `+server.ts` Z 9–12 | Bearer-CRON_SECRET-Pattern bleibt unverändert |
| FOUND-04 reminder_log-Tabelle | `supabase/migrations/20260420_uebersicht_features.sql` Z 8–15 (`training_key_duties` PK + UNIQUE) | analog für composite-PK-Insert-Idempotenz |
| FOUND-05 JSONB-CHECK | (kein direkter Analog im Code, aber `players_jersey_number_range` Z 30–31 als CHECK-Pattern-Vorlage) | Pattern: `ADD CONSTRAINT … CHECK (…)` mit DROP IF EXISTS davor |
| FOUND-07 Browser-Canvas | (keiner — greenfield) | Standard-Pattern, kein KVWN-Analog |
| FOUND-01 Trigger | (keiner — greenfield) | Standard plpgsql BEFORE-INSERT/UPDATE Pattern |

---

## RESEARCH COMPLETE

7 REQs durchgesprochen, alle Codebase-Annahmen aus CONTEXT verifiziert, 5 Major Findings (`email`-Constraint fehlt, Self-Update-RLS bereits korrekt, Captain-RLS braucht WITH CHECK, `push_prefs` greenfield, gcal.js als FOUND-03-Analog). Validation Architecture mit 20 konkreten Test-Cases. Open Questions sind Plan-Phase-resolvable, kein Researcher-Blocker.
