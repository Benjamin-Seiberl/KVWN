# Phase 0: Cross-Cutting Foundations — Discussion Log

**Date:** 2026-04-29
**Mode:** default (4 single-question turns per area)
**Outcome:** 0-CONTEXT.md committed

This log is **for human reference only** (audit, retrospective). Downstream agents read CONTEXT.md, not this file.

---

## Gray-Area-Selektion

**Question:** Phase 0 hat 4 echte Gray-Areas — welche willst du jetzt durchdiskutieren?
**Options offered:**
- Email-Cleanup-Strategie (FOUND-01)
- RLS-Pin: Captain-Override-Pfad (FOUND-02)
- PUSH_PREFS Default-State + Schema (FOUND-05)
- imageResize API-Form (FOUND-07)

**User selected:** Alle 4.
**Notes:** FOUND-03/04/06 keine echten Gray-Areas — Implementation-Detail dem Planner überlassen.

---

## Area 1 — FOUND-01 Email-Cleanup

### Q1.1 — Dup-/NULL-Strategy
**Question:** FOUND-01 Audit-Query gibt vermutlich >0 Treffer. Wie umgehen mit duplicate-email + NULL-email?
**Options:**
- ✅ **Captain-Cleanup vor Migration** (Recommended)
- Embedded Cleanup-Heuristik (auto-placeholder-mail)
- Deploy-Block ohne Cleanup
- Soft-Migration ohne UNIQUE-Constraint

**Selection:** Captain-Cleanup vor Migration.
**Reasoning:** Sauber, ~30 min Captain-Aufwand akzeptabel; Familien-Gmail-Use-Case real laut Memory `project_v1_blocker_pitfalls.md`.

### Q1.2 — lower()-Normalisierung Scope
**Question:** Migration soll Bestand auf lowercase migrieren — retroaktiv UPDATE oder nur Trigger?
**Options:**
- ✅ **Retroaktiv UPDATE + BEFORE-INSERT/UPDATE-Trigger** (Recommended)
- Nur Trigger, neue Daten lower-cased
- CITEXT-Spalten-Typ statt lower()

**Selection:** Retroaktiv UPDATE + Trigger.
**Reasoning:** Konsistent für Bestand+Neu. CITEXT verworfen (Supabase-Extension-Risk + Implicit-Behavior weniger klar).

### Q1.3 — Audit-Tool-Form
**Question:** Wie soll Captain das Audit praktisch ausführen?
**Options:**
- ✅ **Standalone SQL-Skript + Markdown-Cleanup-Anleitung** (Recommended)
- Captain-UI in /profil/admin
- Migration-internal DO-Block mit RAISE EXCEPTION

**Selection:** Standalone SQL + Markdown-Runbook.
**Reasoning:** 1-shot Workflow; Captain-UI = Over-Engineering. DO-Block könnte als zusätzlicher Safety-Belt in Migration ergänzt werden (Planner-Discretion).

---

## Area 2 — FOUND-02 RLS-Pin Captain-Override

### Q2.1 — Captain-Path
**Question:** Wie soll Captain weiterhin Spieler-Rows updaten dürfen (heute via AdminRollen)?
**Options:**
- ✅ **Policy-Branch: self OR captain** (Recommended)
- Strict-self in RLS, Captain nur via Edge-Function
- Strict-self auf SELF-Felder, Captain auf Roster-Felder (column-level)

**Selection:** Policy-Branch self OR captain.
**Reasoning:** Kein Refactor von 2 etablierten Captain-Workflows. Akzeptiertes Trust-Modell (klein-Verein, gewählter Captain). Column-level + Edge-Function als v2-Deferred.

---

## Area 3 — FOUND-05 PUSH_PREFS

### Q3.1 — Default-State
**Question:** Opt-in (DSGVO) vs Opt-out (UX) — wie balancieren?
**Options:**
- ✅ **Mixed: lineup_confirm always-on, Rest opt-in** (Recommended)
- Strict Opt-in (alle keys default false)
- Opt-out (alle keys default true)

**Selection:** Mixed.
**Reasoning:** lineup_confirm = berechtigtes Interesse §6(1)(f) DSGVO. Andere Pushes opt-in über SELF-07-Consent-Modal.

### Q3.2 — Initial-Keys + CHECK-Constraint
**Question:** Welche Pref-Keys + wie DB unbekannte Keys ablehnen?
**Options:**
- ✅ **5 Keys + jsonb_object_keys()-CHECK** (Recommended)
- 3 Keys + lockerer ?| array-CHECK
- Whitelist via separate Lookup-Tabelle

**Selection:** 5 Keys + jsonb_object_keys()-CHECK.
**Reasoning:** Reflektiert alle v1-Phasen-Trigger (TRAIN-04, EVT-11, EVT-12, EVT-13, SELF-11). Tippfehler-Schutz aktiv.

---

## Area 4 — FOUND-07 imageResize

### Q4.1 — Resize-Mode + Format
**Question:** Square cover-crop vs configurable; WebP-only vs JPEG-fallback?
**Options:**
- ✅ **Square 512×512 cover-crop, WebP only** (Recommended)
- Configurable: crop-mode + format option
- Square 512×512 + JPEG-Fallback

**Selection:** Square cover-crop, WebP only.
**Reasoning:** Avatar-Use-Case eindeutig. WebP universell ab Safari 14. Configurable = YAGNI in Phase 0; Erweiterung bei EVT-17 (Phase 3) trivial.

### Q4.2 — EXIF-Strip
**Question:** Wie GPS-Tags strippen?
**Options:**
- ✅ **Canvas-Re-encode** (Recommended)
- ExifReader-lib + selective GPS-strip
- EXIF nicht strippen (verworfen, Pitfall C6)

**Selection:** Canvas-Re-encode.
**Reasoning:** Zero-dependency, robust, automatisch im Resize-Schritt drin. Metadata-Verlust für Profilfoto irrelevant.

---

## Deferred Ideas (out-of-Phase-0-Scope, captured)

- Column-level RLS für Captain (v2)
- `auth_user_id`-Refactor (v2/v3)
- ExifReader-lib (wenn v2 Foto-Metadata gebraucht)
- Captain-Email-Audit-UI (wenn Cleanup wiederkehrend)
- Edge-Function-Routing für Captain-Updates (`manage-player`)
- JPEG-Fallback (wenn Telemetrie alte Browser zeigt)
- ÖSKB-Feed-Import für `league_standings` (STAT-relevant, v1.1)

---

## Process Metadata

**Workflow:** `/gsd-discuss-phase 0` — default mode, multi-select gray-area selection, 4 single-question turns per area
**Prior context loaded:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/STRUCTURE.md`, memory index
**Code-Scout:** Bestätigt: `$lib/server/timezone.js`, `$lib/utils/imageResize.js`, `$lib/constants/pushPrefs.js` existieren NICHT — Phase 0 erzeugt sie
**Total Q-turns:** 8 (1 area-select + 7 decisions)

---

*Discussion log: 2026-04-29*
