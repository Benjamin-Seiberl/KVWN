# Pitfalls Research

**Domain:** Amateur-Sportverein-PWA (KVWN v1 — Trainingsbuchung, Selfservice-Stammdaten, Statistik, Events/Umfragen/Push)
**Researched:** 2026-04-28
**Confidence:** HIGH (project-specific, derived from migrations, shipped code, CONCERNS.md, plus domain experience with brownfield deadline crunches)
**Deadline:** JHV 2026-05-22 (~24 days from now)

This file enumerates concrete failure modes for the four v1 features, with pre-shipping checks and phase mapping. Generic "test thoroughly" advice is omitted — every entry below has a code/config-level prevention.

---

## Critical Pitfalls

### Pitfall C1: Selfservice-RLS lässt Spieler die Trikotnummer/IBAN/Adresse anderer Spieler überschreiben

**What goes wrong:**
The current `players self update` policy (Migration `20260422_profil_selfservice.sql:106-116`) only freezes `role`, `active`, `membership_status`, `member_since`, `email`. ALL other columns — `iban`, `account_holder`, `phone`, `address`, `birthdate`, `jersey_number`, `emergency_contact_*`, even `attest_url` — are protected solely by `USING (email = auth.jwt() ->> 'email')`. That means: a logged-in player runs `UPDATE players SET iban='AT...attacker' WHERE id = '<other-player-id>'` and the policy filters via `email`, so the malicious row is filtered out — but if `players.email` is NULL or shared between multiple rows (e.g., legacy data, family-shared Gmail), the `USING` clause matches multiple rows and the player can write across them.

Compounding risk: there is **no `auth_user_id` FK** to `auth.users` (CONCERNS.md "RLS email-bridge model lacks auth_user_id"). Email is the only bridge.

**Why it happens:**
"Use email as natural key" feels simple in dev. Nobody runs the `players.email IS NULL` query before shipping. Family Gmail accounts (parent/child same address) are common in amateur-sports clubs.

**How to avoid:**
1. Add hard schema guarantees BEFORE any selfservice write goes live:
   ```sql
   ALTER TABLE public.players ALTER COLUMN email SET NOT NULL;
   ALTER TABLE public.players ADD CONSTRAINT players_email_unique UNIQUE (email);
   ```
2. Lowercase-normalize email at insert/update + on auth comparison:
   ```sql
   USING (lower(email) = lower(auth.jwt() ->> 'email'))
   ```
3. Add a `WITH CHECK` for self-update that pins `id` (not just email):
   ```sql
   WITH CHECK (id = (SELECT id FROM public.players WHERE lower(email) = lower(auth.jwt() ->> 'email')))
   ```
4. Run a pre-deploy audit: `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*) > 1 OR email IS NULL`. Must return zero rows.

**Warning signs:**
- Two players with the same Google account in the family (Vater + Sohn auf seiberl@gmail.com).
- `null` or empty-string emails in `players` table.
- Selfservice form successfully saves but the changes appear on someone else's profile.
- Postgres log shows `UPDATE players` affecting >1 row.

**Phase to address:** Phase 1 (Selfservice). Must precede any UI deployment for IBAN/Adresse.

**Severity:** BLOCKER

---

### Pitfall C2: Foto-Upload ohne Server-Side-Resize bombt Supabase-Storage und CDN-Bandbreite

**What goes wrong:**
Spieler nutzen Smartphone-Kamera direkt → 12 MP iPhone-Foto = 4-6 MB JPEG. Bei 37 Spielern × Re-Upload jedes Mal wenn Foto wechselt = Storage füllt sich mit großen Original-Files, Avatar-Listen (Aufstellung, Statistik, Match-Card) ziehen Megabytes pro Listing. Mobile-Datenverbrauch explodiert, Page-Load auf Liga-Match-Tag (15 Mannschaftsmitglieder × 5 MB) = ~75 MB pro Listing.

Dazu: Supabase Free-Tier-Storage hat 1 GB. KV-Wiener-Neustadt ist auf Pro, aber 50 Mitglieder × 5 MB × 5 Re-Uploads = 1.25 GB nur für Avatare.

**Why it happens:**
"Foto-Upload" wirkt wie ein simples `<input type="file">`. Resize-Pipeline (Browser-canvas oder serverless-thumbnailer) wird unter Zeitdruck weggekürzt.

**How to avoid:**
1. **Browser-Resize VOR Upload** — Pflicht, nicht optional:
   ```js
   // canvas.drawImage in 512x512, dann canvas.toBlob({ type: 'image/webp', quality: 0.85 })
   // 4 MB JPEG → ~50 KB WebP
   ```
2. **Storage-Bucket mit max-size-policy + content-type allowlist**:
   ```sql
   -- public bucket, aber RLS-INSERT-policy mit size check
   CREATE POLICY "avatar size limit" ON storage.objects
     FOR INSERT WITH CHECK (
       bucket_id = 'avatars'
       AND octet_length(content) < 200000  -- 200 KB hard cap
       AND (metadata->>'mimetype') IN ('image/webp','image/jpeg')
     );
   ```
3. **Storage-Pfad = `avatars/<player_id>/avatar.webp`** (deterministisch, kein Random-Suffix) — re-upload überschreibt, bloated nicht.
4. **Cache-Bust nach Re-Upload** über Query-Param: `imgPath = url + '?v=' + updated_at_unix`. Sonst sehen User altes Foto wegen Service-Worker-Cache.
5. **EXIF strippen** beim Resize — Smartphone-Fotos enthalten GPS-Koordinaten der Wohnung des Spielers. Canvas-Re-Encoding entfernt EXIF automatisch.

**Warning signs:**
- Storage-Größe wächst >100 MB/Woche.
- Vercel-Bandwidth-Alerts.
- Mobile-User berichten "neues Foto wird nicht angezeigt" (Cache-Problem).
- User berichten "ich sehe die Adresse anderer Spieler im EXIF" (Privacy-Disaster — siehe Pitfall S2).

**Phase to address:** Phase 1 (Selfservice mit Foto-Upload).

**Severity:** HIGH

---

### Pitfall C3: Cron-Reminder rechnet `tomorrow` in UTC, aber UI zeigt Europe/Vienna → Reminder kommt am falschen Tag

**What goes wrong:**
`/api/cron/lineup-reminders/+server.ts:17-19` (live!) berechnet:
```ts
const t = new Date();
t.setDate(t.getDate() + 1);
const tomorrow = `${t.getFullYear()}-${String(t.getMonth()+1)...`
```
Das ist `new Date()` auf Vercel = **UTC**. Cron läuft `0 7 * * *` UTC = 09:00 Europe/Vienna im Winter, 09:00 in Sommer (CEST = UTC+2 → Cron läuft 09:00 Vienna ja, aber `tomorrow` ist UTC-tomorrow, nicht Vienna-tomorrow).

Konkretes Failure-Szenario: Match am Sonntag 26.04.2026 18:00 Vienna. `confirmation_deadline` ist Samstag 25.04.2026. Cron läuft Freitag 24.04.2026 07:00 UTC = 09:00 Vienna. `tomorrow` (UTC) = Samstag 25.04.2026 — passt zufällig. ABER: am Tag der DST-Umstellung (29.03.2026, 27.10.2026), oder wenn `confirmation_deadline` knapp vor Mitternacht Vienna gesetzt wurde, drift dieser Vergleich um einen Tag und der Reminder kommt **gar nicht** (oder doppelt).

Selbe Bug-Klasse zieht sich durch alle künftigen v1-Reminder: Trainings-Erinnerung, Event-RSVP-Frist, Polls-Schließung.

**Why it happens:**
JavaScript `Date` ist defaulthaft Browser-Locale, auf Node-Server aber UTC. Vercel-Doku sagt "crons are UTC" aber Code-Reviewer denken nur an die Cron-Schedule, nicht an die Date-Arithmetik im Handler.

**How to avoid:**
1. Helper schreiben: `nowVienna()` und `dateInVienna(offsetDays)` — beide nutzen `Intl.DateTimeFormat('de-AT', { timeZone: 'Europe/Vienna' })` oder explizit `date-fns-tz`'s `utcToZonedTime`. Niemals nackt `new Date()` in einem Cron-Handler.
2. Alle Cron-Schedules im `vercel.json` mit Vienna-Time-Kommentar dokumentieren:
   ```json
   { "path": "/api/cron/lineup-reminders", "schedule": "0 7 * * *" }
   // = 08:00 Vienna im Winter, 09:00 Vienna im Sommer (CEST). Akzeptiert für Lineup-Reminder.
   ```
3. Bei DST-Übergang (Last-Sunday-March + Last-Sunday-Oct) Cron-Output manuell prüfen.
4. Idempotenz-Schutz im Reminder: pro `(plan_id, reminder_type)` einmal. Tabelle `reminder_log(plan_id, kind, sent_at)`. Vor Send: `SELECT 1 FROM reminder_log WHERE plan_id=? AND kind='deadline_T-1'`. Verhindert Doppel-Send wenn Cron retried oder Bug durchschlägt.

**Warning signs:**
- "Ich habe gestern Abend bestätigt aber heute Früh trotzdem den Reminder bekommen."
- Ende März / Ende Oktober plötzlich keine Reminders mehr (DST-Drift).
- `reminder_log` hat Duplikate für selben Plan.

**Phase to address:** Phase 4 (Events + Push). Helper sofort einbauen — auch für die bereits gelivete Lineup-Reminder.

**Severity:** HIGH

---

### Pitfall C4: Statistik-Joins über `cal_week + league_id` produzieren stille Cross-Saison-Vermischung

**What goes wrong:**
Per CLAUDE.md ist `game_plans ↔ matches` über `(cal_week, league_id)` verknüpft, nicht via `match_id` FK. `cal_week` wiederholt sich jedes Jahr (Woche 12 in 2025 UND 2026). Wenn die Statistik-Aggregation nicht zusätzlich auf Saison/Datum filtert, summiert sie alle historischen Spiele derselben Liga in derselben Woche — d.h. Saison-Schnitt mischt 2024/25 mit 2025/26.

Aus `SpieleTab.svelte:77-149` (CONCERNS.md "SpieleTab data loading N+1") wird klar: der Join wird client-side gemacht, ohne Saison-Constraint.

**Why it happens:**
Schema entstand iterativ. `cal_week` reichte solange nur eine Saison existierte. JHV-Demo zeigt erste Stat-Dashboards → niemand merkt die Cross-Saison-Vermischung weil 2024/25-Daten vielleicht noch gar nicht migriert sind. **Sommer-Rollout 2026/27 → erstes Spiel Woche 38, plötzlich erscheinen 2025/26-Spiele als "diese Woche"**.

**How to avoid:**
1. **Vor Stat-Dashboard-Bau**: Migration die Saison eindeutig macht. Entweder:
   - `season text` (z.B. '2025/26') auf `matches` UND `game_plans`, alle Joins erweitern auf `(season, cal_week, league_id)`, oder
   - `match_id uuid REFERENCES matches(id)` auf `game_plans`. Empfohlen — eliminiert die ganze Klasse.
2. Statistik-Queries **nie ohne Datum-Filter**: `WHERE matches.date BETWEEN saison_start AND saison_ende`.
3. Off-Season-Empty-State explizit modellieren: `if (matches.length === 0) showEmpty('Saison startet am DD.MM.')` — sonst zeigen Cards "0 Spiele, Schnitt 0" wie ein Bug-Symptom.
4. Materialisierte View `player_season_stats` mit `season` als PK-Bestandteil (CONCERNS.md "StatsView 1300 lines with inline calculations").

**Warning signs:**
- Spielzahl in Statistik > Spielzahl in `matches` filtered by season.
- Saison-Schnitt sinkt/steigt nach Schema-Migration unerklärt.
- Nach erster Vorbereitungsspiel-Eingabe in 2026/27 erscheinen 2025/26-Werte.
- Widerspruch zwischen "Letzte 5 Spiele"-Liste und Saison-Schnitt-Karte.

**Phase to address:** Phase 3 (Statistik). Schema-Migration vorab, sonst ist alles Sand-Castle.

**Severity:** BLOCKER (für Phase 3) / HIGH (für Sommer-Rollout)

---

### Pitfall C5: Vote-Once-RLS für Polls leakt vote-änderungs-Rechte an alle Spieler

**What goes wrong:**
"Spieler darf seine eigene Stimme ändern" wird oft als `FOR ALL USING (player_id = me)` policy implementiert — ABER ohne `WITH CHECK` lassen sich beim UPDATE die `player_id` und `poll_id` umschreiben (Spieler ändert seine Stimme zur Stimme eines anderen Spielers). Anonymisierte Polls (`anonymous: true`) sind besonders verlockend zum Mitlesen via Stat-Aggregation, wenn die `poll_responses`-Tabelle für alle lesbar ist.

Zusätzliche Trap bei "Late-Vote-Handling": wenn `closes_at` clientseitig geprüft wird, aber RLS keine Zeit-Constraint hat, kann ein Spieler nach Ablauf via direktem `sb.from('poll_responses').upsert(...)` voten — gerade in einer Vereins-Demo "der Verein dachte Umfrage sei abgeschlossen, aber Spieler X hat nachträglich noch geändert".

**Why it happens:**
RLS `FOR ALL` ist bequem (eine Policy für alle CRUD-Ops). `WITH CHECK` ist optional und wird oft vergessen. Closing-Zeit ist ein UX-Detail, nicht offensichtlich ein Sicherheitsrisiko.

**How to avoid:**
1. **Schema mit Hard-Constraints**:
   ```sql
   CREATE TABLE poll_responses (
     poll_id uuid REFERENCES polls(id) ON DELETE CASCADE,
     player_id uuid REFERENCES players(id) ON DELETE CASCADE,
     option_id uuid REFERENCES poll_options(id),
     created_at timestamptz DEFAULT now(),
     updated_at timestamptz DEFAULT now(),
     PRIMARY KEY (poll_id, player_id)
   );
   ```
   PRIMARY KEY (poll_id, player_id) → Postgres erzwingt Vote-Once mechanisch.

2. **Separate INSERT- und UPDATE-Policies, beide mit WITH CHECK**:
   ```sql
   CREATE POLICY "poll vote insert" ON poll_responses
     FOR INSERT TO authenticated
     WITH CHECK (
       player_id = (SELECT id FROM players WHERE lower(email)=lower(auth.jwt()->>'email'))
       AND EXISTS (SELECT 1 FROM polls WHERE id=poll_id AND now() < closes_at)
     );
   CREATE POLICY "poll vote update" ON poll_responses
     FOR UPDATE TO authenticated
     USING (player_id = (SELECT id FROM players WHERE lower(email)=lower(auth.jwt()->>'email')))
     WITH CHECK (
       player_id = (SELECT id FROM players WHERE lower(email)=lower(auth.jwt()->>'email'))
       AND EXISTS (SELECT 1 FROM polls WHERE id=poll_id AND now() < closes_at)
       AND (SELECT allow_change FROM polls WHERE id=poll_id) = true
     );
   ```

3. **Anonyme Polls**: Kein direktes Lesen von `poll_responses`. Stattdessen RPC `poll_results(poll_id)` SECURITY DEFINER, das nur aggregierte Counts zurückgibt. Direkte SELECT-Policy = block.

4. **Server-validate `closes_at`** zusätzlich zur clientseitigen Disabled-Button-Logik.

**Warning signs:**
- Poll-Tabelle erlaubt `INSERT` ohne `WITH CHECK`.
- Aggregate Counts in Anon-Poll != Anzahl unique `player_id`s in `poll_responses` (würde Anon-Verstoß bedeuten).
- Postgres-Log: `UPDATE poll_responses` nach `closes_at`.
- Demo-User ändert Stimme nachträglich, Demo platzt.

**Phase to address:** Phase 4 (Events + Umfragen).

**Severity:** HIGH

---

### Pitfall C6: Foto-Upload-EXIF leakt GPS-Koordinaten der Wohnadresse

**What goes wrong:**
iPhone/Android-Foto enthält EXIF-Tags `GPSLatitude/Longitude/Altitude/Direction`. Spieler macht Selfie zu Hause hoch → andere Spieler/Captains laden das Foto runter → können in EXIF die exakten GPS-Koordinaten der Wohnung extrahieren. Das ist DSGVO-Art.5(1)(c) "Datenminimierung"-Verstoß und in einem Verein, wo "wer hat im Frühjahr noch nicht trainiert?" alle wissen, ein direkter Privacy-Disaster.

**Why it happens:**
Niemand denkt an EXIF. Standard-`<input type="file">` + Supabase-Storage-Upload schickt das Original-Byte-für-Byte hoch.

**How to avoid:**
- Browser-Resize via Canvas (siehe Pitfall C2) re-encodet das Bild → EXIF wird im Standard-`canvas.toBlob()` **nicht** übernommen. Single-Mitigation für sowohl Größe als auch EXIF.
- Test: After-Upload-Foto runterladen, mit `exiftool` prüfen — darf KEIN GPS-Tag enthalten.
- Server-side fallback: `imagemagick -strip` in einer Edge Function, falls Browser-Resize aus irgendeinem Grund umgangen wird.

**Warning signs:**
- Direkt-Upload ohne Canvas-Re-Encoding-Pfad.
- File-Size auf Storage > 1 MB (wahrscheinlich Original-Foto mit EXIF).
- `exiftool foto.jpg` zeigt `GPS Position`.

**Phase to address:** Phase 1 (Selfservice mit Foto-Upload). Bundeled mit C2 (Resize-Pipeline).

**Severity:** HIGH (DSGVO-relevant, Vereins-Reputation)

---

### Pitfall C7: DSGVO-Consent-Checkboxen sind im Schema vorhanden aber ohne Workflow → keine Einwilligung dokumentiert

**What goes wrong:**
`20260422_profil_selfservice.sql:20-23` führt `consent_photo`, `consent_liga_data`, `consent_whatsapp`, `consent_accepted_at` ein — aber kein Code-Pfad, der Einwilligung beim Onboarding zwingend abfragt. Ergebnis: Spieler-Daten werden gespeichert/verarbeitet ohne dokumentierte Einwilligung, DSGVO Art.7 verletzt. Bei Beschwerde: Verein steht ohne Beweis da.

Zusätzlich: in Österreich ist DSGVO über `DSG 2018` mit länderspezifischen Verschärfungen (Verarbeitung von Gesundheitsdaten — z.B. das `attest_url`-Feld!) hochsensibel.

**Why it happens:**
Schema wurde "vorbereitend" angelegt; UI nachgereicht.

**How to avoid:**
1. **Onboarding-Block**: erste Anmeldung → Modal mit Consent-Checkboxen, save UND `consent_accepted_at = now()`. Keine Profil-Editing möglich, bevor Consent gegeben ist.
2. **Widerruf-Pfad** (DSGVO Art.7(3)): in Profil/Einstellungen muss Widerruf ein-klick-möglich sein. Widerruf → automatischer Trigger der entsprechende Daten löscht oder anonymisiert.
3. **Datenschutzerklärung** als statische Markdown-Seite `/privacy` mit Stand-Datum, verlinkt im Onboarding-Modal. Muss enthalten:
   - Zweck der Verarbeitung (Vereinsorganisation, Liga-Übermittlung)
   - Empfänger (LV NÖ Kegeln, Liga-Datenbanken)
   - Speicherdauer (z.B. "5 Jahre nach letzter Aktivität")
   - Rechte (Auskunft, Berichtigung, Löschung — Art.15-17)
   - Verantwortlicher (Verein, Adresse, Kontakt)
4. **Foto-Upload nur wenn `consent_photo = true`**, sonst Upload-Button disabled mit Hinweis "Einwilligung in Profil-Einstellungen erforderlich".
5. **Liga-Daten-Übermittlung** (Spielerpass, Lizenznummer) nur wenn `consent_liga_data = true`.

**Warning signs:**
- Spielerprofile mit `consent_accepted_at IS NULL` und gleichzeitig befüllten sensiblen Spalten.
- Foto-Upload möglich obwohl `consent_photo = false`.
- Keine `/privacy`-Route oder Stand-Datum > 12 Monate alt.

**Phase to address:** Phase 1 (Selfservice). Privacy-Erklärung kann von Vereins-Vorstand textlich gegenliest werden — das ist keine Code-Aufgabe und sollte als externes-Dokument-Task geplant werden.

**Severity:** BLOCKER für Production-Rollout (nicht Demo). Demo bei JHV ohne Consent-Workflow OK, **aber Mitglieder-Daten dürfen nur Mock sein**, nie reale Mitgliederdaten der unbeteiligten Spieler.

---

### Pitfall C8: Trainingsbuchung-Race-Condition bei letzter Bahn — RPC ist NICHT atomar genug

**What goes wrong:**
`book_training_lane` (Migration `20260421_training_lanes.sql:49-119`) checkt Capacity, dann checkt Lane belegt, dann `INSERT`. Ohne expliziten Lock-Statement (kein `LOCK TABLE`, keine `SELECT FOR UPDATE`) könnten zwei concurrente Aufrufe beide den Capacity-Check bestehen und beide auf dieselbe Lane schreiben. **ABER**: das `UNIQUE (date, start_time, lane_number)`-Constraint (Zeile 41-43) fängt das ab — der zweite INSERT failt mit Constraint-Violation und Postgres throwt eine Exception.

Das Problem ist nicht Datenverlust (Constraint hält), sondern **UX**: der zweite User bekommt eine kryptische Postgres-Exception zurück (`'duplicate key value violates unique constraint "training_bookings_lane_unique"'`) statt eines sauberen `'lane_just_taken'`-Status. UI zeigt `triggerToast('Fehler: ' + err.message)` mit der raw exception → Demo-Zerstörung.

**Why it happens:**
RPC vertraut auf Constraint, fängt Exception aber nicht in eine bessere Status-Response. RPC-Tester testen nur sequentiell.

**How to avoid:**
1. RPC um `EXCEPTION WHEN unique_violation THEN ...` erweitern:
   ```sql
   BEGIN
     INSERT INTO training_bookings(...) VALUES (...);
   EXCEPTION WHEN unique_violation THEN
     RETURN jsonb_build_object('status', 'lane_just_taken');
   END;
   ```
2. Oder explizit `SELECT ... FOR UPDATE` auf den Slot-Range zur Serialisierung — overkill für Vereins-Skala (max 8 concurrent Buchungen pro Slot), aber eindeutig korrekt.
3. **Concurrent-Booking-Test im DB**:
   ```sql
   -- Two parallel sessions, beide gleicher slot/lane:
   BEGIN; SELECT book_training_lane('2026-05-01','19:00',3); -- session A: nicht commit
   BEGIN; SELECT book_training_lane('2026-05-01','19:00',3); -- session B: muss gracefully fail
   ```
4. UI: bei `lane_just_taken` automatisch State refreshen + Toast `'Bahn wurde gerade belegt — wähle eine andere'`.

**Warning signs:**
- User-Report: "Beim Klicken kam ein roter Fehler mit `duplicate key`".
- Sentry/Vercel-Log: `unique_violation` aus `book_training_lane`.
- `training_bookings`-Konflikte (sollten unmöglich sein, aber wenn doch: Migration prüfen).

**Phase to address:** Phase 2 (Trainingsbuchung-Vollausbau). RPC-Patch ist 5 Zeilen Code.

**Severity:** MEDIUM (Daten OK, UX zerstört → Demo-Risiko)

---

### Pitfall C9: Push-Reminder ignoriert Opt-Out und sendet trotz `push_prefs[key] = false`

**What goes wrong:**
`/api/push/notify` (Zeile 45-46) filtert per `push_prefs[pref_key] ?? true !== false`. Das ist **opt-out** (default = senden). Wenn ein Spieler bewusst `push_prefs.training_reminder = false` setzt, aber das UI eine andere Schreibweise verwendet (z.B. `trainings_reminder` mit s, oder camelCase `trainingReminder`), wird der Filter umgangen — der `?? true` Fallback bedeutet: Tippfehler im pref_key = jeder bekommt jeden Push.

Dazu: alle Cron-Aufrufer müssen exakt denselben pref_key-String benutzen. Es gibt keine zentrale Konstante.

**Why it happens:**
JSONB ist schemalos; Tippfehler bleiben unentdeckt bis ein User sich beschwert.

**How to avoid:**
1. **Zentrale Konstante** in `$lib/constants/pushPrefs.js`:
   ```js
   export const PUSH_PREFS = {
     LINEUP_REMINDER:   'lineup_reminder',
     TRAINING_REMINDER: 'training_reminder',
     EVENT_REMINDER:    'event_reminder',
     POLL_OPEN:         'poll_open',
     KEYDUTY:           'keyduty'
   };
   ```
   Server- und Client-Code importieren ausschließlich aus dieser Liste.

2. **CHECK constraint** auf der Settings-UI: nur diese Keys dürfen ins JSONB:
   ```sql
   CHECK (jsonb_typeof(push_prefs) = 'object' AND
          NOT EXISTS (SELECT 1 FROM jsonb_object_keys(push_prefs) k
                      WHERE k NOT IN ('lineup_reminder','training_reminder','event_reminder','poll_open','keyduty')))
   ```

3. **Default-Verhalten dokumentieren**: bei JHV das Verein-Vorstand fragen "Wollt ihr Opt-In oder Opt-Out?" — DSGVO Art.6 erlaubt Opt-Out für vereinsinterne Kommunikation, aber Mitglieder müssen den Widerruf-Pfad finden können.

**Warning signs:**
- User: "Ich hab Trainings-Reminder deaktiviert aber kriege sie trotzdem."
- DB: `push_prefs` mit ungewöhnlichen Keys (`trainingsReminder`, `Lineup_Reminder`, `lineup-reminder`).

**Phase to address:** Phase 4 (Events + Push). Konstante VOR neuen Push-Typen einbauen.

**Severity:** HIGH (Vertrauensverlust + DSGVO-relevant)

---

### Pitfall C10: Demo-Mock-Daten landen in Production-DB und blocken Sommer-Rollout

**What goes wrong:**
Für JHV-Demo (22.05.2026) werden Statistik-Cards mit Mock-Daten befüllt — z.B. "Spieler X hat 8 Spiele Schnitt 542" obwohl keine echten Liga-Daten existieren. Mock-Daten wandern direkt in `players`, `matches`, `game_plans`, weil "ist ja eh dieselbe DB". Nach JHV will man sie aufräumen → aber Statistik-FK-Cascade (events → game_plans → game_plan_players) macht Cleanup riskant.

Real-world: Verein startet Sommer-Saison 2026/27, erste echte Match-Eingabe enthält Spieler-Statistik mit "Vorsaison-Schnitt 542 (Mock)". Vorstand fragt warum.

**Why it happens:**
Unter Zeitdruck wird "richtig vs. fake-Daten" nie sauber separiert. Mock-Daten haben keine `is_demo`-Flag.

**How to avoid:**
1. **Boolean `is_demo`** auf jeder neu-eingebauten Tabelle (events, polls, statistik-Aggregate). Default `false`. Mock-Daten → `is_demo=true`.
2. **Production-View filtert**: `CREATE VIEW v_matches AS SELECT * FROM matches WHERE NOT is_demo;`. UI nutzt Views, nicht Tabellen. Demo-Modus toggelt feature-flag und nutzt Original-Tabellen.
3. **Cleanup-Migration vor Sommer-Rollout** vorbereitet, bevor erste Mocks rein gehen:
   ```sql
   -- migration "20260601_clear_demo.sql"
   DELETE FROM events WHERE is_demo;
   DELETE FROM polls WHERE is_demo;
   -- usw.
   ```
4. **Alternativ**: separate Supabase-Branch (Pro-Tier kann Branches) für JHV-Demo. Production bleibt clean. Risiko: Auth-Sync schwierig.
5. **Bei Demo-Bug**: Spieler-Namen die eindeutig fake sind ("Test Spieler 1", "Mustermann"). Nie real-anmutende Namen.

**Warning signs:**
- `is_demo` fehlt auf neu eingeführten Tabellen.
- Mock-Daten haben echte Spieler-Namen + UUIDs.
- Nach JHV: Cleanup-SQL > 100 Zeilen weil Cascading.

**Phase to address:** Phase 0 (Cross-cutting, vor allen Demo-Vorbereitungen).

**Severity:** HIGH (Sommer-Rollout-Blocker)

---

### Pitfall C11: Brownfield-Coupling — Selfservice-Schreib-Policies brechen bestehende Captain-Aufstellungs-Workflow

**What goes wrong:**
`20260422_profil_selfservice.sql` aktiviert `RLS` auf `public.players` ZUM ERSTEN MAL (Zeile 85). Vorher hatte `players` keine RLS, also liefen alle Captain-Workflows (AdminAufstellung, AdminFeedback, Invite) ohne Policy-Constraint. Jetzt ist nur noch `kapitaen-write` und `self-update` erlaubt — wenn ein bestehender Code-Pfad als "user" (nicht-Captain) auf andere Spieler-Felder schreibt (z.B. `last_seen_at`, `notification_token`, `dashboard_dismissed_*`), failt das jetzt silently.

CONCERNS.md "PLAYER_FIELDS unverified": Profil/UebersichtTab referenziert `push_prefs`, `avatar_url`, `photo` — diese Spalten existieren womöglich nicht oder sind nicht in der `self update` Policy whitelist.

**Why it happens:**
RLS-Activation ist ein irreversibler Produktiv-Schalter. Niemand testet alle bestehenden Code-Pfade nach RLS-On.

**How to avoid:**
1. **Pre-Activation-Audit**: `grep -rE "sb\.from\('players'\)\.update" src/` UND `sb.from('players').upsert` UND `.insert`. Jede Stelle gegen Policy-Whitelist prüfen.
2. **Telemetrie**: in dev nach RLS-Activation alle PostgREST-`401`/`403` loggen. Liste der gebrochenen Code-Pfade ist sofort sichtbar.
3. **Push-Prefs-Pfad**: Spieler ändert eigenes `push_prefs` JSONB → erfordert `players self update`-Policy mit `push_prefs` NICHT in der Frozen-Liste. **Aktuell ist es korrekt** (push_prefs ist nicht gefreezt), aber bei jedem Whitelist-Update prüfen.
4. **`last_seen_at`-Update** durch User selbst → erlaubt? Wenn ja: ok. Wenn nein: in Trigger oder API verlagern.
5. **Dashboard-Task-Dismissal** (Migration `20260423b_dashboard_task_dismissals.sql`): separate Tabelle, nicht `players` — eh ok.

**Warning signs:**
- 403-Spike in Browser-Network-Tab nach Migration-Deploy.
- Bestehende Funktionalität (z.B. "Ich war hier"-Heartbeat) failt silently.
- Captain-Aufstellung kann Spieler nicht mehr bearbeiten weil Conditional-Where-Clause auf `email` nicht greift bei Spielern ohne email.

**Phase to address:** Phase 1 (Selfservice). RLS-Activation ist ein einmaliger Schritt, danach laufen alle weitere Phasen unter dem RLS-Regime.

**Severity:** HIGH (regression risk)

---

### Pitfall C12: Push-Subscription-Cleanup-Gap — alte iPhone-Tokens akkumulieren Storage

**What goes wrong:**
`/api/push/notify` löscht Subscription nur bei `410 Gone` oder `404`. Aber: viele iOS-Push-Subscriptions sterben mit anderen Status-Codes (`403` wenn VAPID-Mismatch, Network-Errors die nicht propagiert werden). Auch: User wechselt Browser → alte Subscription bleibt orphan in DB. `push_subscriptions` wächst monoton.

Nicht direkt sicherheitsrelevant, aber: `/api/push/notify` iteriert ALLE Subscriptions pro Empfänger sequentiell (`for (const sub of subs)` — Zeile 61 von notify-handler). 50 Spieler × 3 stale subs = 150 webpush.sendNotification-Calls = >5 Sekunden = Vercel-Timeout.

**Why it happens:**
Web-Push-Spec ist messy. Apple/Google ändern Status-Codes ohne Ankündigung. Cleanup wird "irgendwann später" geplant.

**How to avoid:**
1. **Last-Success-Timestamp** auf `push_subscriptions`. Nightly cron löscht Subscriptions wo `last_success_at < now() - interval '90 days'`.
2. **Bei Re-Registrierung in `register.js:41` `upsert` mit `onConflict: 'endpoint'`** (existiert bereits) → ok.
3. **Parallel webpush-Calls** statt sequentiell: `Promise.allSettled(subs.map(sub => sendNotification(sub, payload)))`. Vercel-Timeout-fest.
4. **Index** auf `push_subscriptions(player_id)` (sollte existieren — verifizieren).

**Warning signs:**
- `push_subscriptions`-Zeilen > 3 × Spielerzahl.
- `/api/push/notify` Vercel-Logs zeigen Timeouts (>10s).
- Pages-Funktion-Cost auf Vercel-Dashboard steigt.

**Phase to address:** Phase 4 (Events + Push). Cleanup-Cron ist 1-Tages-Aufgabe.

**Severity:** MEDIUM

---

### Pitfall C13: Statistik-Caching-Strategie fehlt → 1300-Zeilen-Komponente neu-rendert bei jedem Tab-Wechsel

**What goes wrong:**
`StatsView.svelte` (1300 Zeilen, CONCERNS.md) berechnet Aggregationen inline bei jedem Mount. Wenn der Spielbetrieb-Stat-Tab nach jedem Match-Detail-Sheet neu mounted wird (Subtab-Router-Pattern), läuft die ganze Aggregation 50-100 Mal pro Session.

Bei 200 Spielen × 6 Spielern × Score-Records = 1200 Zeilen client-side Math. Initial OK, aber bei Saison 2026/27 mit einem Jahr Daten: 800+ matches → spürbares Lag (>500ms initial render).

**Why it happens:**
"Kommt schon auf Demo-Skala", "Caching machen wir später". `derived`-Stores werden in Svelte 5 Runes oft missbraucht, ohne dass das memoization gewünscht ist.

**How to avoid:**
1. **Materialized View `player_season_stats`**: nightly refresh (Vercel-Cron + Supabase RPC `REFRESH MATERIALIZED VIEW CONCURRENTLY`).
2. **Pre-aggregated** speichern, nicht client-side berechnen. Schemata:
   ```sql
   CREATE MATERIALIZED VIEW player_season_stats AS
   SELECT player_id, season,
     COUNT(*) games_played,
     AVG(score) avg_score,
     ...
   GROUP BY player_id, season;
   ```
3. **Client cache** mit `playerStatsCache = $state(new Map())`, key = `(player_id, season)`. Cache-Bust bei Match-Result-Update via store-message.
4. **Lazy load**: Statistik-Tab fetcht nur on `currentSubtab === 'statistiken'`, nicht in Page-Mount.
5. **Refactor parallel zur Mat-View**: `StatsView.svelte` aufsplitten in `SeasonOverviewCard`, `FormCurveCard`, `ComparisonCard` — 1300 → 3×~300 Zeilen.

**Warning signs:**
- Stat-Tab Initial-Render > 1s.
- Mobile-User berichtet "App hängt nach Match-Eingabe".
- Mat-View `last_refresh > now() - interval '24h'` (cron broken).
- Stat-Werte stale weil Mat-View nicht refreshed.

**Phase to address:** Phase 3 (Statistik). Mat-View vor UI-Bau, sonst wird UI neu geschrieben.

**Severity:** MEDIUM (Demo OK auf 200-Spiel-Skala, Production-Risiko)

---

### Pitfall C14: GCal-Events-Doppelguard schlägt zu aggressiv, Vereins-Termine verschwinden

**What goes wrong:**
CONCERNS.md "GCal sync duplicate-guard timing": Cron skipped Google-Events deren `events.start_date == matches.date`. Wenn ein Verein-Event am Match-Tag stattfindet (z.B. Vereinsabend nach Heimspiel), wird das Event als vermeintliches Duplikat skipped. Es erscheint nicht im Kalender.

Phase 4 (Events + Umfragen) wird diese Bug-Klasse vergrößern: jeder neue Event-Typ konkurriert mit Match-Datum. "Saisonabschluss-Feier am 22.05.2026" am JHV-Tag → wird nicht synchronisiert.

**Why it happens:**
Der Dup-Guard wurde unter Übergangssaison-Druck geschaffen, ohne Trennungs-Kriterium außer Datum. Time-of-Day, Event-Type, External-ID werden nicht berücksichtigt.

**How to avoid:**
1. **Dup-Guard auf `external_id` umstellen**: nur skipen wenn `external_id` bereits in `matches.external_id` existiert (echtes Sync-Duplikat). Datum allein reicht nicht.
2. **Zeitliche Disambiguierung**: nur skipen wenn `events.start_time` im Range eines existierenden `matches.start_time ± 2h` liegt.
3. **Event-Type-Whitelist**: GCal-Events mit Title-Pattern `Match:` sind Match-bezogen, alle anderen Events ignorieren den Dup-Guard.
4. **Sync-Audit-Log**: jede skipped event mit Grund loggen. Sichtbar machen warum ein Event nicht erscheint.

**Warning signs:**
- "Saisonabschluss am 22.05. fehlt im Kalender."
- `gcal-sync`-Log: "skipped due to match date overlap" für Nicht-Match-Events.
- Match-Tag-Doppel-Events in `events`-Tabelle (Inverse-Bug).

**Phase to address:** Phase 4 (Events + Umfragen). Vor Event-Feature-Bau Dup-Guard fixen.

**Severity:** HIGH (Phase 4 hängt davon ab)

---

### Pitfall C15: Demo-vs-Production — JHV-Demo zeigt Production-Daten ohne Backup

**What goes wrong:**
Eine Live-DB hat keine Snapshot-Strategie dokumentiert. JHV-Demo läuft auf realer Production-Supabase. Während Demo schreibt jemand falsche Stats → kein Rollback.

**Why it happens:**
Supabase Pro hat automatische daily backups (7 Tage), aber Restore = whole-database-Restore, kein per-table. Vereinsmitglieder kennen den Restore-Pfad nicht.

**How to avoid:**
1. **Vor JHV (3 Tage vorher)**: Manuellen DB-Snapshot via Supabase-Dashboard ziehen, lokale Kopie speichern.
2. **Demo-User hat NIEMALS Captain-Rolle**. Demo-Login = read-only-Spieler-Account. Demo zeigt Workflow ohne Schreib-Aktionen.
3. **Backup-Restore-Plan dokumentiert**: Wer macht Snapshot, wer macht Restore, wie lange dauert es (10 min auf Pro).
4. **Demo-Accounts in `is_demo=true`**, separate Spieler-Reihen die nach JHV gelöscht werden können.

**Warning signs:**
- Vor JHV: kein dokumentierter Snapshot-Pfad.
- Captain-Account wird für Demo benutzt.
- DB-Schema-Migration am Demo-Tag (irreversibel).

**Phase to address:** Phase 5 (Demo-Vorbereitung) explicit als Phase einplanen.

**Severity:** HIGH (operational, kein Code)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Foto-Upload ohne Resize-Pipeline | -2 Tage Implementation | Storage-Bloat, EXIF-Leak, schlechte Mobile-UX | **Niemals** — Mitigation < 1 Tag |
| `is_demo`-Flag weglassen | -3h Setup | Schmerzhafter Cleanup vor Sommer-Rollout | Niemals (3h investment vs. mehrtägiger Cleanup) |
| Materialized View deferred zu Phase 5 | -1 Tag | Stat-Tab langsam ab Saison 2026/27 | Wenn Demo-Daten <100 Matches und Mat-View vor Sommer-Rollout nachgezogen wird |
| `auth_user_id`-Migration deferred | -2 Tage | Email-Change bricht Auth, kein Audit-Trail | Bis Sommer 2026 OK; danach blocker für Multi-Verein-Vision (out of scope) |
| Browser-side Stat-Berechnung | -1 Tag | StatsView.svelte 1300 Zeilen unwartbar | **Niemals neu** — bestehender Code refactor in Phase 3 |
| Single-Cron-Schedule für alle Reminder | -2h | TZ-Drift, kein per-Reminder Tuning | Wenn TZ-Helper eingebaut + reminder_log existiert |
| Mock-Daten in Production-Tabellen ohne `is_demo` | -1h | Cleanup-Migration nach JHV, Sommer-Rollout-Blocker | Niemals |
| RLS-Pin auf `email` ohne `lower()`-Normalisierung | -10min | Case-Sensitive-Login-Bug bei Gmail-Aliases | Niemals |
| Foto-Upload ohne Cache-Bust | -30min | "Mein neues Foto erscheint nicht" für 24h pro User | Niemals |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Supabase Storage (Avatar) | Public bucket ohne Size-Constraint | Public bucket + RLS-INSERT-policy mit `octet_length < 200000` + content-type allowlist |
| Supabase Storage (Attest, sensible PDFs) | Public bucket | Private bucket (`public: false`) + signed URLs + folder-per-player RLS (bereits korrekt in `20260422_profil_selfservice.sql`) |
| Supabase RLS auf `players` | `email = auth.jwt() ->> 'email'` ohne `lower()`-Normalisierung | `lower(email) = lower(auth.jwt() ->> 'email')` UND Pre-Insert-Normalisierung der `email`-Spalte |
| Web Push API | Sendet Original-Subscription auch nach 30+ Tagen Idle | `last_success_at` tracken, Subscriptions >90d delete |
| Vercel Cron | `new Date()` in Handler ohne TZ-Context | `Intl.DateTimeFormat('de-AT', { timeZone: 'Europe/Vienna' })` oder `date-fns-tz` |
| Vercel Cron Schedule | "0 7 * * *" ohne Vienna-Konvertierung dokumentiert | Comment in vercel.json: `// = 09:00 CEST / 08:00 CET` |
| GCal Sync Token | Token expiry nicht behandelt | Catch 410 Gone → Fallback Time-Window-Sync (CONCERNS.md "GCal sync incremental token expiry") |
| GCal Push API | Kein etag-Check vor Update | `etag`-Match before PATCH; bei 412 Precondition Failed → re-pull dann retry |
| webpush Library | Sequentielle Sends in Schleife | `Promise.allSettled(subs.map(...))`, Vercel-Timeout-fest |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Stat-Aggregation client-side | Stat-Tab-Mount > 1s | Mat-View nightly refresh + cached Map in Store | ~800 Spiele (etwa 3 Saisons) |
| `push_subscriptions` ohne Cleanup | webpush-Loop > 5s | `last_success_at` + 90-day-delete-cron | Nach 1 Jahr Push-Service |
| GCal-Sync-Token Idle-Expiry | Cron failt nach 30+ Tagen ohne Run | 410-Catch + Fallback-Window | Sommer-Pause oder Deployment-Outage |
| Avatar-Listing ohne Resize | 75 MB pro Match-Card-Listing | Browser-Resize 512×512 WebP | Bereits ab 5 Avatars im Listing |
| `game_plans` Cross-Saison-Mix | Stat-Werte unrealistisch | `season`-Spalte oder `match_id`-FK | Sommer-Rollout 2026/27 (Saison-Wechsel) |
| StatsView 1300-Zeilen-Re-Render | App hängt 500ms+ bei Tab-Wechsel | Komponenten-Split + lazy-load | Bei Match-Volume > 200 |
| Sequentielle webpush sends | Vercel 60s-Timeout | `Promise.allSettled` | Bei >30 active subs UND langsamer FCM |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| `email` als Auth-Bridge ohne UNIQUE+NOT NULL | Cross-write zwischen Spielern mit shared Gmail | Schema-Constraints + Migration vor RLS-Aktivierung |
| `consent_*`-Spalten ohne erzwungenen Workflow | DSGVO Art.7 Verletzung | Onboarding-Modal blockt Profil-Editing bis Consent gegeben |
| Foto-Upload ohne EXIF-Strip | GPS-Koordinaten der Wohnadresse leaked | Browser-Canvas-Re-Encoding (entfernt EXIF automatisch) + exiftool-Test |
| Anonyme Polls direkt SELECTable | Anon-Garantie gebrochen | RPC `poll_results()` SECURITY DEFINER, kein direkter Zugriff |
| Late-Vote ohne RLS-time-check | Demo-Sabotage durch nachträgliche Stimmänderung | `WITH CHECK (now() < closes_at)` |
| `attest_url` ohne Private-Bucket | Medizinische Daten leaked | Bereits korrekt in `20260422_profil_selfservice.sql:39-41` (`public: false`) |
| Captain-Demotion ohne Session-Invalidation | Demoteder Captain hat noch Schreibrechte bis Logout | Auf Demotion: `auth.signOut()` für betroffenen User triggern, oder JWT-Lifetime auf 15min |
| Service-Account-Key in `.env` ohne Rotation | Bei Leak: ganze GCal-Integration kompromittiert | CONCERNS.md "Google Calendar integration auth chain" — Rotation-Plan, nicht Phase 1 aber dokumentiert |
| `push_prefs` ohne CHECK-constraint auf Keys | Tippfehler bypass-t Opt-Out | CHECK auf JSONB-Keys + zentrale Konstante in `$lib/constants/pushPrefs.js` |
| Direct console.log statt triggerToast bei DB-Errors | Silent fail, User merkt nichts | Bereits dokumentiert in CLAUDE.md Coding-Conventions |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Foto-Upload-Fortschritt nicht sichtbar | User klickt erneut, mehrfach-Upload | Disabled Button + Spinner während Upload, Toast bei Success/Error |
| "Bahn 3 belegt"-Toast statt automatischem Refresh | User sieht stale Bahnen-Liste | Bei `lane_just_taken` automatisch refetch + "Bahn 3 wurde gerade belegt"-Toast |
| Late-Vote ohne klares Closed-Indicator | User stimmt ab, denkt es zählt, aber "abgeschlossen seit gestern" | Clear `closes_at`-Anzeige UND disabled-Button + erklärung |
| Statistik mit 0-Werten in Off-Season | "Schnitt 0, klingt wie Bug" | Empty-State-Card "Saison startet am 14.09.2026" |
| Push-Reminder ohne Deep-Link | Tap auf Push → Dashboard, nicht zur Aufgabe | Deep-Link `/spielbetrieb#action-hub-lineup` (bereits korrekt in lineup-reminders) — alle künftigen Push-Typen müssen folgen |
| Foto-Crop nach Upload ohne Preview | User lädt Querformat hoch, sieht Avatar-Quadrat-Crop schneidet Gesicht | Crop-UI mit Preview (z.B. `svelte-easy-crop`) BEFORE Upload |
| Selfservice-Form save ohne Feedback | "Hat es gespeichert? Habs jetzt nochmal geklickt" | Toast `'Profil gespeichert'` + disabled-Save-button bis Diff |
| Trainings-Reminder am Tag-vor-Slot ohne Storno-Frist-Hinweis | User vergisst, "habe doch storniert!", Strafe | Reminder-Body: "Storno bis 23:59 möglich" |
| Polls ohne sichtbare Eigenstimme | "Habe ich schon abgestimmt?" → falsche Doppelabstimmung | UI zeigt eigene Stimme highlighted + "Du hast für X abgestimmt — ändern?"-Button |

---

## "Looks Done But Isn't" Checklist

Vor JHV-Demo, mindestens 5 Tage vorher pro Item prüfen:

- [ ] **Foto-Upload:** Resize-Pipeline aktiv? exiftool-Test grün? Upload-Größe < 200 KB? Cache-Bust beim Re-Upload? Avatar zeigt sich auch nach Hard-Reload?
- [ ] **Selfservice-Stammdaten:** Onboarding-Consent-Flow blockiert Profil-Editing? `email IS NOT NULL` UND `UNIQUE` validated? `lower(email)`-RLS aktiv? IBAN-Format-Validation client-side?
- [ ] **Trainingsbuchung:** Concurrent-Booking-Test mit zwei Sessions auf gleicher Lane → eine kommt mit Status `lane_just_taken`, nicht raw exception? Storno-Frist-Logik (23:59 day-before) auch in UI deaktiviert?
- [ ] **Statistik-Dashboard:** Cross-Saison-Filter aktiv? Empty-State für Off-Season vorhanden? Mat-View nightly refresh läuft? Sample-Daten = `is_demo=true`?
- [ ] **Events+Umfragen:** Vote-Once via PRIMARY KEY erzwungen? RLS `WITH CHECK (now() < closes_at)`? Anonyme Polls via RPC, nicht direkter SELECT? Eigene Stimme im UI highlighted?
- [ ] **Push-Reminder:** Cron im UTC-vs-Vienna-Test grün (DST-Boundary 29.03.2026 betrachtet)? `reminder_log` verhindert Doppel-Send? Push-Prefs-Key zentrale Konstante? Deep-Link funktional?
- [ ] **GCal-Sync:** Dup-Guard auf `external_id` umgestellt (nicht nur Datum)? Token-410-Fallback eingebaut?
- [ ] **DSGVO:** `/privacy`-Seite vorhanden + Vorstand-gegengelesen? Consent-Widerruf-Pfad funktional? Foto-Upload disabled wenn `consent_photo=false`? Demo zeigt KEINE realen Mitgliederdaten?
- [ ] **Demo-Hygiene:** `is_demo`-Flag auf allen neuen Tabellen? DB-Snapshot 3 Tage vor JHV gezogen? Demo-Account ist read-only? Cleanup-Migration vorbereitet?
- [ ] **Brownfield-Coupling:** Browser-Network-Tab nach Selfservice-Migration: keine 401/403-Spike? Bestehende Captain-Workflow (AdminAufstellung, Invite) funktioniert? Match-Workflow Spielbetrieb-Cockpit unverändert?

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| C1 (Cross-Spieler-Write) | HIGH | Sofortiger DB-Snapshot, geänderte Felder identifizieren via WAL/audit, manuelles Restore. Public-Disclosure an betroffene Spieler nötig (DSGVO Art.34). |
| C2 (Storage-Bloat) | LOW | Cron der alle Avatars > 200 KB durchläuft, Re-Resize via Edge-Function, replace. ~2 Tage Sprint. |
| C3 (TZ-Reminder-Drift) | LOW | Helper einbauen + reminder_log + manuelles Re-Send von Missed-Reminders. ~1 Tag. |
| C4 (Cross-Saison-Stat) | MEDIUM | Migration `season`-Spalte rückwärts befüllen via SQL `CASE WHEN matches.date BETWEEN '...' AND '...' THEN '2025/26' ELSE '2024/25' END`. Recompute Mat-View. ~3 Tage. |
| C5 (Poll-Manipulation) | HIGH wenn unentdeckt | Vote-Once-PK-Migration, Audit aller bisherigen Polls, ggf. Poll-Erneuerung. Bei Demo-Sabotage: Trust-Verlust zum Verein. |
| C6 (EXIF-GPS-Leak) | HIGH (DSGVO) | Alle bestehenden Avatars via exiftool prüfen + strippen. Disclosure an betroffene User. |
| C7 (Consent fehlt) | MEDIUM-HIGH | Onboarding-Flow nachträglich einbauen, alle bestehenden User durchschleusen ("Bitte bestätige Einwilligung"), bei Verweigerung Datenanonymisierung. |
| C8 (Booking-Race) | LOW | Exception-Handler in RPC + UI-Refresh-Logic. ~3h. |
| C9 (Push-Opt-Out missachtet) | MEDIUM | Zentrale Konstante einbauen, push_prefs in DB normalisieren via Migration. ~1 Tag. |
| C10 (Mock in Production) | HIGH | Cleanup-Migration mit `WHERE is_demo=true` deletes — wenn `is_demo` nie eingebaut, manuelle ID-Liste pro Tabelle. ~2-5 Tage. |
| C11 (RLS bricht Captain-Workflow) | LOW-MEDIUM | RLS-Policy patchen, fehlende Whitelist-Spalten ergänzen. ~1 Tag wenn früh erkannt. |
| C12 (Push-Sub-Bloat) | LOW | Cleanup-Cron + `last_success_at`-Migration. ~3h. |
| C13 (Stat-Performance) | MEDIUM | Mat-View nachziehen, StatsView refactoren. 3-5 Tage. |
| C14 (GCal-Dup-Guard) | LOW | Guard auf `external_id` umstellen. ~3h. |
| C15 (Demo-Datenverlust) | HIGH ohne Snapshot | Mit Snapshot: Restore-Path, 10min auf Supabase Pro. Ohne: Daten verloren. |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| **C1** Cross-write via email-bridge | Phase 1 (Selfservice) — Schema-Migration vor Selfservice-UI | Pre-deploy SQL: `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL` returns 0 |
| **C2** Foto-Upload ohne Resize | Phase 1 (Selfservice) — Resize Pflicht-Komponente | Upload-Test: 4 MB iPhone-Foto → Storage-File < 200 KB |
| **C3** Cron-TZ-Drift | Phase 4 (Push) — TZ-Helper als Cross-cutting | DST-Boundary-Test: Mock `new Date('2026-03-29T01:00:00Z')` → Helper liefert Vienna-Datum |
| **C4** Stat Cross-Saison | Phase 3 (Statistik) — Schema vor UI | Stat-Tab in Off-Season zeigt Empty-State, nicht 0-Werte |
| **C5** Poll-Vote-Manipulation | Phase 4 (Polls) — RLS mit time-check | Manueller Test: `closes_at < now()` UPDATE failt |
| **C6** EXIF-GPS-Leak | Phase 1 (Selfservice) — gebündelt mit C2 | exiftool auf gehoichten File: kein GPS-Tag |
| **C7** DSGVO-Consent fehlt | Phase 1 (Selfservice) — Onboarding-Modal | Foto-Upload disabled wenn `consent_photo=false` |
| **C8** Booking-Race-UX | Phase 2 (Training) — RPC-Patch | Concurrent-2-Session-Test → graceful status |
| **C9** Push-Opt-Out | Phase 4 (Push) — zentrale Konstante | DB: alle `push_prefs`-Keys aus PUSH_PREFS-Set |
| **C10** Demo-Daten-Trap | Phase 0/Pre-Demo — `is_demo`-Pattern | Schema: alle neuen Tabellen haben `is_demo` |
| **C11** Brownfield-RLS-Coupling | Phase 1 (Selfservice) — Audit | Browser-Network nach Migration: keine 401/403-Spike |
| **C12** Push-Sub-Cleanup | Phase 4 (Push) — Cleanup-Cron | `push_subscriptions`-Count < 3× Spielerzahl |
| **C13** Stat-Performance | Phase 3 (Statistik) — Mat-View | Stat-Tab Initial-Render < 500ms |
| **C14** GCal-Dup-Guard | Phase 4 (Events) — Guard-Refactor vor Event-Bau | Vereinsabend am Match-Tag erscheint im Kalender |
| **C15** Demo-Backup | Phase 5 (Demo-Vorbereitung) — Operational | Snapshot-Datei vor JHV vorhanden |

---

## Cross-Phase-Concern: Brownfield Velocity Trap

Über alle Phasen: bei 24 Tagen für 4 Features besteht hohes Risiko, dass jede Phase zu Lasten der Vorphase geht. Konkrete Anti-Patterns:

- **Phase 1 (Selfservice) blockt durch Consent-Workflow → Foto-Upload-Phase 2 wird vorgezogen "wir machen das später" → Phase 3 Statistik wird gerushed → Phase 4 Push hat keinen Test-Buffer mehr.**
- **Schema-Migrationen kumulieren** (CONCERNS.md "Migration Sprawl 22 in 14 days"). Jede neue Phase fügt 2-3 Migrationen hinzu. Bei JHV-Stand: ~30+ Migrationen, Schema-Drift sehr wahrscheinlich.
- **Reviewer-Phase wird übersprungen** ("ist eh nur Demo"). Aber RLS-Bugs (C1, C5, C7) sind nach Demo nicht reversibel ohne Datenverlust.

**Mitigation in Roadmap:**
- Jede Phase hat eine 1-Tages-Reviewer-Phase **nicht-skippable**.
- Schema-Migrationen werden pro Phase in EINE Migration gebündelt (kein 7-Migration-Sprint pro Phase).
- Phase 0 = Cross-cutting Investments (TZ-Helper, `is_demo`, zentrale `PUSH_PREFS`-Konstante, Resize-Pipeline-Lib) BEVOR Feature-Phasen starten. Spart in jeder Folgephase Re-Implementation.

---

## Sources

- `C:\kvwn\.planning\codebase\CONCERNS.md` (live audit 2026-04-28: PLAYER_FIELDS unverified, RLS email-bridge ohne auth_user_id, Migration Sprawl, GCal sync duplicate-guard, push subscription bloat)
- `C:\kvwn\.planning\codebase\ARCHITECTURE.md` (Subtab Router Pattern, RLS-Based Authorization, Server-Only Layer Constraints)
- `C:\kvwn\CLAUDE.md` (RLS write patterns, key DB facts: `game_plans ↔ matches` via cal_week+league_id, Coding conventions)
- `C:\kvwn\supabase\migrations\20260422_profil_selfservice.sql` (current self-update RLS policy, attest storage policies, players consent columns)
- `C:\kvwn\supabase\migrations\20260421_training_lanes.sql` (book_training_lane RPC, UNIQUE constraint, exception handling gap)
- `C:\kvwn\supabase\migrations\20260423_gcal_sync.sql` (sync_token, external_id, etag — token expiry not handled)
- `C:\kvwn\supabase\migrations\20260427_event_rsvps.sql` (RSVP RLS pattern as basis for poll RLS)
- `C:\kvwn\src\routes\api\cron\lineup-reminders\+server.ts` (live UTC-vs-Vienna TZ bug)
- `C:\kvwn\src\routes\api\push\notify\+server.ts` (push opt-out filter, dead-sub cleanup gap, sequential webpush calls)
- `C:\kvwn\src\lib\push\register.js` (subscription upsert with onConflict)
- `C:\kvwn\vercel.json` (cron schedule UTC, no Vienna comment)
- `C:\kvwn\static\images\*.jpg` (37 player photos shipped as static assets — establishes baseline that Foto-Upload is greenfield, not migration)
- DSGVO/DSG 2018 (Austrian implementation, Art.5/6/7/15-17/34 — consent, processing limits, breach disclosure)
- Web Push API spec (RFC 8030) — subscription expiry semantics, 410 Gone handling

---
*Pitfalls research for: KVWN v1 — Trainingsbuchung, Selfservice, Statistik, Events/Umfragen/Push*
*Researched: 2026-04-28*
*Severity legend: BLOCKER = ship-stopper, HIGH = ships but causes harm, MEDIUM = ships and causes friction*
