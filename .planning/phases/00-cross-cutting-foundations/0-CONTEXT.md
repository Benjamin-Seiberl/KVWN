# Phase 0: Cross-Cutting Foundations - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix die zwei BLOCKER-Pitfalls (C1 RLS-Cross-Write, C3 Cron-TZ-Drift) und liefer 5 Cross-Cutting-Helper (TZ, Resize, `is_demo`, `PUSH_PREFS`, Reminder-Idempotenz) sauber, sodass die nachfolgenden Feature-Phasen 1–4 nicht 4× dieselbe Plumbing wiederholen oder Sicherheits-Lücken einschleppen. Phase 0 ist NON-NEGOTIABLE BLOCKER vor jeder Feature-Phase.

7 Reqs (FOUND-01..07), Duration 2 Tage, keine UI-Surface außer Captain-Audit-Runbook.

</domain>

<decisions>
## Implementation Decisions

### FOUND-01 — Email-Audit + lower()-Normalisierung + Pre-Deploy-Audit

- **D-01:** **Captain-Cleanup VOR Migration deploy.** Pre-Deploy-Audit-Skript listet alle Rows mit duplicate-email (z.B. Familien-Gmail) oder NULL-email. Captain konsolidiert manuell (Family-Account → 1 Spieler bekommt primäre Gmail, andere bekommen plus-aliases `gmail+name@gmail.com` oder Vereins-Mail). Migration FOUND-01 wird erst `supabase db push`'ed wenn Audit = 0. Erwartete Captain-Aufwand: ~30 min.
- **D-02:** **Retroaktiv UPDATE + BEFORE-INSERT/UPDATE-Trigger für lowercase.** Migration: zuerst `UPDATE players SET email = lower(email)` (nach Captain-Cleanup, vor UNIQUE-Constraint), dann ALTER TABLE NOT NULL UNIQUE, dann Trigger der jeden zukünftigen INSERT/UPDATE auf `lower()` forciert. Konsistent für alle Bestand- + Neu-Daten. Audit muss VOR retroactive UPDATE laufen, weil lowercase neue Duplikate erzeugen kann (`A@b.de` + `a@b.de`).
- **D-03:** **Audit-Tool = Standalone SQL-Skript + Markdown-Runbook.** Datei `supabase/migrations/_audit/20260430_email_pre_check.sql` (Prefix `_audit/` damit Supabase es nicht als Migration auto-applies) + `docs/runbooks/email-cleanup.md` (Captain-Anleitung: Query in Supabase-Studio kopieren, Liste ansehen, manuell fixen, re-run bis 0). CITEXT verworfen (Extension-Risiko Supabase). Captain-UI verworfen (Over-Engineering für 1-shot).

### FOUND-02 — RLS-Policy-Refactor `players` mit `WITH CHECK`-Pin

- **D-04:** **Policy-Branch `self OR captain`.** RLS UPDATE-Policy auf `players`: `WITH CHECK (id = (SELECT id FROM players WHERE email = (auth.jwt() ->> 'email')) OR EXISTS (SELECT 1 FROM players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin')))`. AdminRollen.svelte + AdminAufstellung.svelte bleiben auf normalem `sb`-Browser-Client, kein Edge-Function-Refactor nötig. Akzeptiertes Risiko: kompromittierter Captain-Account = alle Spieler-Rows änderbar (Captain ist trusted, kleines Verein-Setup; v2 könnte column-level oder Edge-Function-Routing nachziehen wenn Vorstand verlangt).
- **Cross-Write-Smoke-Test:** Spieler A versucht via DevTools Spieler B's Row zu updaten → muss 403 zurückgeben. Test-Skript-Anleitung in Phase-0-Runbook.

### FOUND-05 — `PUSH_PREFS`-Konstante + DB-CHECK

- **D-05:** **Mixed Default — `lineup_confirm` always-on, Rest opt-in.** `lineup_confirm` ist NICHT als Pref-Key ausgewiesen — wird hardcoded gesendet wenn Spieler in Lineup ist (operativ-essentiell, vergleichbar Banking-OTP, DSGVO-Argumentation: berechtigtes Interesse §6(1)(f) Vereins-Funktion). Alle anderen Keys default `false`, Spieler aktiviert via EinstellungenTab + SELF-07-Consent-Modal.
- **D-06:** **5 Initial-Keys + jsonb_object_keys()-CHECK-Whitelist.** Konstante `PUSH_PREFS` in `$lib/constants/pushPrefs.js`:
  ```js
  export const PUSH_PREFS = {
    training_24h:    'Training 24h vorher',     // TRAIN-04
    event_new:       'Neues Event',              // EVT-11
    event_reminder:  'Event 24h vorher',         // EVT-12
    poll_close:      'Umfrage schließt',         // EVT-13
    birthday:        'Geburtstags-Banner Push'   // SELF-11
  };
  ```
  DB-CHECK auf `players.push_prefs` (JSONB):
  ```sql
  CHECK (
    jsonb_typeof(push_prefs) = 'object'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(push_prefs) k
      WHERE k NOT IN ('training_24h','event_new','event_reminder','poll_close','birthday')
    )
  )
  ```
  Tippfehler-Insert (`event_remminder`) schlägt fehl. Neue Keys = neue Migration die CHECK-Constraint ersetzt.

### FOUND-07 — `imageResize.js` Browser-Canvas-Helper

- **D-07:** **Square 512×512 cover-crop, WebP only output.** API: `resizeImage(file: File): Promise<{ blob: Blob, mime: 'image/webp' }>`. Center-Crop auf Square (Avatar-Standard), WebP universell ab Safari 14 — KVWN-User-Base auf aktuellem iOS/Android, kein Fallback nötig. Octet_length<200000 leicht erreichbar bei quality≈0.82. Event-Cover (EVT-17, Phase 3) erweitert API später um optional `mode: 'square'|'wide'` wenn 16:9 gebraucht — kein YAGNI-Surface in Phase 0.
- **D-08:** **EXIF-Strip via Canvas-Re-encode.** Canvas drawImage + canvas.toBlob('image/webp') verliert EXIF/GPS automatisch (Pixel-only Output). Zero-dependency, robust, beweisbar via `exiftool` auf Output-Sample (kein GPS-Tag findbar). Verlustig für Aufnahme-Datum/Kamera-Metadata — für Profilfoto irrelevant. ExifReader-lib verworfen (+30KB Dep für Edge-Case).

### Claude's Discretion (Planner darf entscheiden)

- **FOUND-03 TZ-Helper API-Form** — `nowVienna()` / `dateInVienna(offsetDays)`: Return-Typ (string `'YYYY-MM-DD'` vs. Date-Object), DST-Edge-Case-Handling (02:00 doppelt). Standard-Pattern via `Intl.DateTimeFormat('de-AT', { timeZone: 'Europe/Vienna' })`.
- **FOUND-04 `reminder_log`-Schema-Detail** — Composite-Unique `(plan_id, kind)` als PK oder Surrogate `id` mit UNIQUE-Constraint. `kind`-Spalte Type (TEXT vs CHECK-Whitelist).
- **FOUND-04 lineup-reminders-Cron-Refactor-Strategy** — In-place-Refactor des bestehenden `+server.ts` oder neue Datei + alte deprecaten. Beide OK solange `reminder_log`-Idempotenz greift.
- **FOUND-06 `is_demo`-Pattern Anwendungsbereich** — Migration-Vorlage als Markdown-Doku genügt (Pattern, kein Code-Helper). Neue v1-Tabellen bekommen `is_demo BOOLEAN DEFAULT false NOT NULL`. Production-Views filtern `WHERE NOT is_demo`. Retroaktiv auf bestehende Tabellen NICHT erforderlich (Bestand ist real-Daten).
- **Reihenfolge der Reqs innerhalb Phase 0** — Dependency-Graph: FOUND-01 → FOUND-02 (Email-Audit muss vor RLS-Pin), FOUND-03 → FOUND-04 (TZ-Helper vor Cron-Refactor). FOUND-05/06/07 sind voneinander unabhängig, können parallel.
- **Test-/Verifikations-Skripts** — RLS-Cross-Write-Test, DST-Simulation, EXIF-Strip-Verifikation: Form (Markdown-Anleitung vs. Bash-Skript) im Planner-Ermessen.

</decisions>

<specifics>
## Specific Ideas

- **Captain-Cleanup-UX:** Captain bekommt Tabelle "Email-Konflikte" — kein UI-Tool, sondern Markdown-Runbook + SQL-Query. Ist 1-shot, Aufwand ~30 min, kein wiederkehrender Workflow.
- **DSGVO-Argumentation für `lineup_confirm` always-on:** Berechtigtes Interesse §6(1)(f) DSGVO — Vereins-Lineup-Workflow ist Kernfunktion ohne die App-Nutzen wegfällt. Kein Marketing-Push. Vergleichbar mit Transactional-Email-Kategorie. Argumentation steht in `/privacy`-Seite (SELF-08).
- **WebP-only:** Bewusste Stack-Entscheidung — User-Base ist KVWN-Mitglieder mit modernen Smartphones, kein Long-Tail-Browser-Support nötig.
- **Captain-Trust-Modell:** Klein-Verein-Setup (~20-40 Spieler), Captain ist gewählt + bekannt. Strict-self-only-RLS würde 2 etablierte Workflows brechen (AdminRollen, AdminAufstellung) ohne realen Sicherheits-Gewinn proportional zum Refactor-Aufwand.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these before research/planning.**

### Phase-Scope + Requirements
- `.planning/ROADMAP.md` §Phase 0 — Goal, Success Criteria 1-6, Key risks, Duration estimate
- `.planning/REQUIREMENTS.md` §FOUND (Tablestakes-Tabelle FOUND-01..07) — Source-PITFALLS-Mapping pro Req

### Pitfall-Detail (BLOCKER-Mitigations)
- `.planning/research/PITFALLS.md` C1 (RLS-Cross-Write, C-Severity) — FOUND-01 + FOUND-02 fixen
- `.planning/research/PITFALLS.md` C3 (Cron-TZ-Drift, C-Severity) — FOUND-03 + FOUND-04 fixen
- `.planning/research/PITFALLS.md` C6 (EXIF-GPS-DSGVO) — FOUND-07 fix
- `.planning/research/PITFALLS.md` C9 (Push-Pref-Bypass) — FOUND-05 fix
- `.planning/research/PITFALLS.md` C10 (Mock-Daten-Cleanup) — FOUND-06 fix
- `.planning/research/PITFALLS.md` C11 (RLS-401/403-Pfade) — Phase-0-Risk, post-deploy beobachten

### Codebase-Konventionen
- `.planning/codebase/CONCERNS.md` §"RLS email-bridge model lacks auth_user_id column" — bestätigt v1-Scope: KEIN auth_user_id-Refactor
- `.planning/codebase/CONCERNS.md` §"PLAYER_FIELDS unverified" — Open-Q3 für Phase 1 (NICHT Phase 0, aber Researcher muss es kennen)
- `.planning/codebase/CONVENTIONS.md` — RLS write patterns, Supabase-error-handling, Svelte-5-runes
- `.planning/codebase/STRUCTURE.md` §"Where to Add New Code" — Migrations-Konvention `YYYYMMDD_*.sql`, `$lib/server/`, `$lib/utils/`, `$lib/constants/`
- `.planning/codebase/STACK.md` — SvelteKit 5 + Supabase + Vercel Pro

### Project-Constraints
- `C:\kvwn\CLAUDE.md` §"Key DB facts" — RLS-Bridge-Pattern
- `C:\kvwn\CLAUDE.md` §"RLS write patterns" — bestehende Captain-Gate-Snippets (FOUND-02-Vorlage)
- `C:\kvwn\CLAUDE.md` §"Coding conventions" — `triggerToast` statt local-msg, `$state` runes, `loading`-Pattern
- `C:\kvwn\CLAUDE.md` §"Where things live" — Helper-Datei-Locations

### Memory (User-spezifisches Kontext)
- `~/.claude/projects/C--kvwn/memory/project_v1_blocker_pitfalls.md` — bestätigt RLS+Cron-Phase-0-Priorität
- `~/.claude/projects/C--kvwn/memory/feedback_supabase_key_debug.md` — JWT-payload-Decode-Pattern bei RLS-Debug

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`$lib/server/supabase-admin.js` → `sbAdmin()`** — service-role Client für Migrations-Workflow oder Edge-Function-Calls; FOUND-02-Captain-Override verzichtet bewusst darauf, bleibt im normalen Browser-`sb`.
- **`$lib/stores/toast.js` → `triggerToast()`** — KEINE locale `msg`-State; FOUND-02-Cross-Write-403 muss via `triggerToast('Fehler: ' + error.message)` flow.
- **`$lib/utils/dates.js`** — bestehende Date-Helper (`fmtDate`, `fmtTime`, `toDateStr`, `daysUntil`); FOUND-03 TZ-Helper soll dort NICHT mit-leben (server-only-Concern, neuer File `$lib/server/timezone.js`).
- **Migration-Konvention** — `supabase/migrations/YYYYMMDD_*.sql`, jüngste `20260427`. FOUND-01..06 erzeugen 4-5 Migrations, Datum 2026-04-30++.

### Established Patterns

- **RLS email-bridge** — `email = (auth.jwt() ->> 'email')`. FOUND-02 baut auf diesem Pattern; kein auth_user_id-Refactor in v1 (bestätigt CONCERNS.md).
- **Captain-Gate-Pattern** — `EXISTS (SELECT 1 FROM players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin'))`. FOUND-02 nutzt exact diese Subquery in `OR`-Branch.
- **Browser-only DB-Calls** — Alle Supabase-Calls via `sb` aus `$lib/supabase.js`, keine `+page.server.js`. FOUND-02 RLS muss daher auf Browser-`sb`-Pfad funktionieren (deshalb nicht service-role-Bypass).
- **Cron-Pattern** — `src/routes/api/cron/<name>/+server.ts` mit Bearer `CRON_SECRET`-Auth. FOUND-04 refactored bestehenden `lineup-reminders/+server.ts`.

### Integration Points

- **`AdminRollen.svelte`** — heutige `players`-UPDATE-Surface (Captain ändert Rolle/Roster). Nach FOUND-02-Deploy: muss weiterhin funktionieren (RLS-Captain-Branch). Smoke-Test-Pflicht.
- **`AdminAufstellung.svelte`** — Captain ändert Lineup-Felder (`game_plan_players`-Tabelle, NICHT `players` direkt). FOUND-02 betrifft das nicht direkt, aber Phase-0-Reviewer-Sweep prüft alle Captain-Workflows (Pitfall C11).
- **`/api/cron/lineup-reminders/+server.ts`** — bestehender Cron, FOUND-04 refactored auf TZ-Helper + `reminder_log`. Doppelter Trigger-Test (manueller curl 2× hintereinander) muss zeigen: kein Doppel-Push.
- **`src/lib/push/register.js`** + `static/sw.js` — Push-Subscription-Pipeline; FOUND-05 hängt sich an `players.push_prefs`-Spalte (existiert? Researcher muss verifizieren — falls nicht, FOUND-05-Migration legt sie an).
- **Storage-Bucket `player-photos`** — wird in SELF-03 (Phase 1) angelegt, FOUND-07 nicht direkt davon abhängig. FOUND-07 liefert nur die Resize-Pipeline, Upload-Wiring ist Phase 1.

</code_context>

<deferred>
## Deferred Ideas

- **Column-level RLS für granularere Captain-Branch** — wenn Vorstand später verlangt dass Captain nicht alle PII-Spalten sehen darf: column-level-CHECK oder split-tables. v2-Thema.
- **`auth_user_id`-Refactor** — eliminiert email-bridge-Risiko (CONCERNS.md). v2/v3, brauchen Migration-Pfad + Coexistence-Phase.
- **ExifReader-lib** — falls v2 Foto-Metadaten (Aufnahme-Datum) für Galerie-View gebraucht wird, ExifReader nachziehen.
- **Captain-Email-Audit-UI** — falls Email-Cleanup wiederkehrend wird (mehr-Mitglieder-Onboarding-Welle), AdminTab-Sub-Tab. Heute 1-shot, daher Runbook genug.
- **Edge-Function-Routing für Captain-Updates** — falls Sicherheits-Audit in v2 RLS-Branch ablehnt: `manage-player`-Edge-Function (Erweiterung von `invite-player`).
- **JPEG-Fallback für imageResize** — falls Telemetrie zeigt dass User-Base alte Browser hat.
- **ÖSKB-Feed-Import für `league_standings`** — STAT-relevant, nicht FOUND. v1.1.

</deferred>

---

*Phase: 00-cross-cutting-foundations*
*Context gathered: 2026-04-29*
