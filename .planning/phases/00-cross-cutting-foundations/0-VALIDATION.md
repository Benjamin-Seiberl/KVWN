---
phase: 0
slug: cross-cutting-foundations
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-30
---

# Phase 0 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> KVWN hat KEIN Test-Framework (kein Jest/Vitest/Playwright im Repo). Alle Verifikationen sind **manual-sql / manual-cli / manual-browser / manual-doc**. Daher `nyquist_compliant: false` — Validation gewährleistet durch Captain-Smoke-Tests + SQL-Audit-Snippets + Browser-DevTools-Probes, nicht durch CI-Suite.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none (KVWN hat kein Test-Framework, Wave 0 installiert auch keines — Phase 0 ist 2-Tage-Sprint, Test-Infrastruktur explizit out-of-scope) |
| **Config file** | none |
| **Quick run command** | `(manual)` — siehe Per-Task-Map unten |
| **Full suite command** | `(manual)` — siehe Manual-Only-Verifications |
| **Estimated runtime** | ~30 min (alle 20 Test-Cases manuell) |

---

## Sampling Rate

- **After every task commit:** Manual-Verifikation gemäß Acceptance-Criteria im PLAN.md (orientiert sich an Per-Task-Verification-Map unten).
- **After every plan wave:** Browser-Smoke-Test der bestehenden Captain-Workflows (Pitfall C11 — keine 401/403 Regressions in `/profil/admin`, `/spielbetrieb`, `/kalender`).
- **Before `/gsd-verify-work`:** Alle 20 Test-Cases (Per-Task-Map + Manual-Only) müssen grün sein.
- **Max feedback latency:** ~2 min pro Test-Case (manueller SQL/Browser-Probe).

---

## Per-Task Verification Map

> Jede Zeile referenziert einen Test-Case aus `0-RESEARCH.md` § Validation Architecture (Z 575–598). `Test Type` immer `manual-*`. `Automated Command` enthält das exakte SQL/curl/grep zum copy-paste in Captain-Console.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 0-01-pre | 01 | 1 | FOUND-01 | C1 (RLS-Cross-Write) | Audit zeigt 0 Duplikate/NULL vor Migration | manual-sql | `SELECT email, COUNT(*) FROM players GROUP BY email HAVING COUNT(*)>1 OR email IS NULL;` muss 0 Rows | ❌ W0 | ⬜ pending |
| 0-01-post | 01 | 2 | FOUND-01 | C1 | Trigger lowercased email beim Insert | manual-sql | `INSERT INTO players (id, name, email) VALUES (gen_random_uuid(),'Test','Test@X.DE'); SELECT email FROM players WHERE name='Test';` returns `'test@x.de'` | ❌ W0 | ⬜ pending |
| 0-02-cross | 02 | 2 | FOUND-02 | C1 | Spieler A kann Spieler B NICHT updaten | manual-browser | DevTools als Spieler A: `await sb.from('players').update({phone:'x'}).eq('id', '<spieler_b_id>')` → error code `42501` ODER 0 rows | ❌ W0 | ⬜ pending |
| 0-02-captain | 02 | 2 | FOUND-02 | — | Captain-Update bleibt funktional | manual-browser | Login Captain → `/profil` → AdminRollen → Phone eines Spielers ändern → 200 OK + Reload zeigt neue Phone | ❌ W0 | ⬜ pending |
| 0-02-self | 02 | 2 | FOUND-02 | — | Self-Update bleibt funktional | manual-browser | Login Spieler A → `/profil/uebersicht` → Phone ändern → 200 OK + Reload zeigt neue Phone | ❌ W0 | ⬜ pending |
| 0-02-emailpin | 02 | 2 | FOUND-02 | C1 | Email-Pin in WITH CHECK greift | manual-browser | DevTools als Spieler A: `await sb.from('players').update({email:'X'}).eq('id', '<own_id>')` → 0 rows updated | ❌ W0 | ⬜ pending |
| 0-03-dst | 03 | 1 | FOUND-03 | C3 (TZ-Drift) | DST-Übergang ändert Vienna-Datum nicht falsch | manual-cli | `node -e "import('./src/lib/server/timezone.js').then(m=>console.log(m.dateInVienna(new Date('2026-10-26T01:30Z'))))"` muss `'2026-10-26'` liefern | ❌ W0 | ⬜ pending |
| 0-03-utc | 03 | 1 | FOUND-03 | C3 | UTC-Process liefert Vienna-Wallclock | manual-cli | `TZ=UTC node -e "import('./src/lib/server/timezone.js').then(m=>console.log(m.dateInVienna(new Date(),1)))"` muss am Vienna-Mittwoch das Donnerstag-Datum liefern (nicht UTC-Datum) | ❌ W0 | ⬜ pending |
| 0-04-idem | 04 | 3 | FOUND-04 | C3 | Cron ist idempotent via reminder_log | manual-cli | `curl -H "Authorization: Bearer $CRON_SECRET" $URL/api/cron/lineup-reminders` zweimal → 1. response `{sent: N>0}`, 2. response `{sent: 0}` | ❌ W0 | ⬜ pending |
| 0-04-log | 04 | 3 | FOUND-04 | C3 | reminder_log dokumentiert jeden Send | manual-sql | `SELECT plan_id, kind, sent_at FROM reminder_log ORDER BY sent_at DESC LIMIT 10;` zeigt 1 Row pro plan_id+kind nach Cron-Run | ❌ W0 | ⬜ pending |
| 0-04-tz | 04 | 3 | FOUND-04 | C3 | Cron nutzt timezone-Helper | manual-cli | Cron-Log Timestamp + `dateInVienna(1)`-Output stimmen mit Vienna-Wallclock überein (nicht UTC) | ❌ W0 | ⬜ pending |
| 0-05-check | 05 | 1 | FOUND-05 | — | CHECK-Constraint blockt unbekannte Keys | manual-sql | `UPDATE players SET push_prefs='{"event_remminder":true}'::jsonb WHERE id='<own_id>';` → `check_violation` Error | ❌ W0 | ⬜ pending |
| 0-05-valid | 05 | 1 | FOUND-05 | — | CHECK-Constraint lässt valide Keys durch | manual-sql | `UPDATE players SET push_prefs='{"event_new":true}'::jsonb WHERE id='<own_id>';` → 200 OK | ❌ W0 | ⬜ pending |
| 0-05-single | 05 | 1 | FOUND-05 | — | Konstante existiert genau einmal | manual-cli | `grep -rn "PUSH_PREFS\|push_prefs" src/ \| grep -v "from '\$lib/constants/pushPrefs"` zeigt keine Inline-Listen, nur Imports | ❌ W0 | ⬜ pending |
| 0-06-doc | 06 | 1 | FOUND-06 | — | is_demo-Pattern dokumentiert | manual-doc | `test -f docs/patterns/is-demo.md && grep -q "is_demo BOOLEAN DEFAULT false" docs/patterns/is-demo.md` → exit 0 | ❌ W0 | ⬜ pending |
| 0-06-ref | 06 | 1 | FOUND-06 | — | Phase 4 referenziert das Pattern | manual-doc | `grep -n "is-demo.md" .planning/ROADMAP.md` zeigt Treffer in Phase-4-Sektion | ❌ W0 | ⬜ pending |
| 0-07-exif | 07 | 1 | FOUND-07 | — | EXIF-Strip entfernt GPS | manual-cli | iPhone-Photo durch `resizeImage()` → Output-Blob mit `exiftool` prüfen → keine `GPS*`-Tags | ❌ W0 | ⬜ pending |
| 0-07-size | 07 | 1 | FOUND-07 | — | Output unter 200 KB | manual-cli | 5 Sample-Fotos (Querformat, Hochformat, gross, klein, EXIF-heavy) → `output.size < 200_000` für alle | ❌ W0 | ⬜ pending |
| 0-07-crop | 07 | 1 | FOUND-07 | — | Center-Crop liefert 512×512 | manual-cli | Hochformat-Foto durch `resizeImage()` → Output ist 512×512px (Canvas-Inspect) + Motiv visuell zentriert | ❌ W0 | ⬜ pending |
| 0-07-mime | 07 | 1 | FOUND-07 | — | Output ist WebP | manual-cli | `output.type === 'image/webp'` für alle 5 Sample-Fotos | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

`File Exists` Spalte: ❌ W0 = Test-Infrastruktur existiert nicht (kein Framework-Setup). Akzeptiert für Phase 0 — alle Tests sind manual.

---

## Wave 0 Requirements

**KEINE Wave-0-Tasks.** Phase 0 verzichtet bewusst auf Test-Framework-Install:
- 24-Tage-v1-Budget zu knapp für Vitest/Playwright-Setup + CI-Wiring.
- KVWN-Stack hat noch nie Tests gehabt → Setup wäre eigenes Mini-Projekt.
- Phase-0-Scope ist Cross-Cutting-Helpers, nicht Test-Infrastruktur (siehe `.planning/PROJECT.md` Decision 3 "v1 = Demo-ready, nicht Production-ready").

→ **Test-Infrastruktur-Install ist v1.1-Backlog** (separat zu erfassen via `/gsd-add-backlog` falls gewünscht).

*Konsequenz:* `nyquist_compliant: false` bleibt für ganze v1. Alle Phasen 0–5 nutzen die hier etablierte Manual-Validation-Pattern.

---

## Manual-Only Verifications

ALLE 20 Test-Cases aus § "Per-Task Verification Map" sind manual-only — keine Automatisierung in v1.

Zusätzliche **Cross-Phase-Smoke-Tests** nach Phase-0-Deploy:

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bestehende Captain-Workflows weiterhin 200 OK | C11 (RLS-Regression-Risk) | Browser-Network-Tab Inspect, kein Test-Harness | DevTools `/profil/admin` → Spieler-Edit; `/spielbetrieb` → Lineup-Edit; `/kalender` → Event-Create. Network-Tab: keine 401/403 in Supabase-Calls. |
| Cron läuft 7 Tage täglich + DST-Wechsel ohne Drift | FOUND-03 + FOUND-04 | Vercel-Cron-Log-Inspect über Zeit | Vercel Dashboard → `/api/cron/lineup-reminders` → 7 Tage Logs prüfen, Sent-Counts plausibel, kein 500. |
| Email-Migration hat keine User-Daten verloren | FOUND-01 | Manual-Vergleich pre/post-Migration | `SELECT COUNT(*) FROM players WHERE email IS NOT NULL` pre vs post Migration → identisch. Captain-Verifikation per Hand. |

---

## Validation Sign-Off

- [ ] Alle 20 Test-Cases haben einen `manual-*` Verify-Befehl
- [ ] Sampling-Continuity: jeder PLAN.md hat acceptance_criteria die mind. 1 Test-Case referenzieren
- [ ] Wave 0 explizit als "skipped — kein Test-Framework in v1" dokumentiert
- [ ] Keine watch-mode Flags (entfällt — kein Framework)
- [ ] Feedback-Latency akzeptiert ~2 min/Test (manual)
- [ ] `nyquist_compliant: false` set in frontmatter (intentional für v1)
- [ ] Cross-Phase-Smoke-Tests definiert für post-Phase-0

**Approval:** pending (Captain bestätigt Manual-Validation-Strategie nach FOUND-01-Audit-Run)
