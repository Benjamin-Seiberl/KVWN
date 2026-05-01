# Email-Cleanup-Runbook (FOUND-01 Pre-Deploy)

**Wann:** Vor `supabase db push` der Migration `20260430b_email_unique.sql` (Plan 0-06).
**Wer:** Captain (Vereinsleitung).
**Aufwand:** ~30 min einmalig.
**Warum:** Migration `players.email NOT NULL UNIQUE` wuerde auf Bestandsdaten fehlschlagen wenn Duplikate oder NULL-Werte existieren. Bekannte Faelle: Familien-Gmail (mehrere Spieler teilen `family@gmail.com`).

## Captain-Schritte

### 1. Audit-Query in Supabase Studio ausfuehren

1. Oeffne https://supabase.com/dashboard/project/<project-id>/sql
2. Kopiere kompletten Inhalt von `supabase/migrations/_audit/20260430_email_pre_check.sql`
3. Run -> 2 Result-Sets erscheinen:
   - **Query 1 (NULL-Emails):** Liste der Spieler ohne Email
   - **Query 2 (Duplicate-Emails):** Liste der Email-Adressen die >=2 Spieler teilen

### 2. Konflikte beheben

**NULL-Emails:**
- Captain fragt betroffenen Spieler nach gueltiger Email-Adresse.
- Update via Supabase Studio (Table Editor -> players -> row edit) ODER via SQL:
  ```sql
  UPDATE public.players SET email = 'spieler@beispiel.at' WHERE id = '<player-id>';
  ```

**Duplicate-Emails (Familien-Gmail-Fall, "family"-Konsolidierung):**
- 1 Spieler behaelt die primaere Gmail-Adresse (z.B. Familienoberhaupt).
- Andere bekommen entweder:
  - Plus-Aliases: `family+max@gmail.com`, `family+anna@gmail.com` (Gmail leitet alle an `family@gmail.com` weiter, aber Auth zaehlt sie als getrennte Identitaeten)
  - ODER eigene Vereins-Email: `max.mustermann@kvwn.at`
- Update wie oben.

### 3. Re-run Audit bis 0 Rows

Wiederhole Schritt 1 bis BEIDE Queries 0 Rows liefern.

### 4. Captain meldet "Audit clean"

Schreibe an Dev: "FOUND-01 Audit clean — kann deployen". Dev startet Plan 0-06 (Migration + RLS Pin) via `supabase db push`.

## Was passiert NACH Captain-Freigabe (Plan 0-06)

1. `UPDATE public.players SET email = lower(email)` (retroaktive lowercase-Normalisierung)
2. `ALTER TABLE players ALTER COLUMN email SET NOT NULL`
3. `CREATE UNIQUE INDEX players_email_uq ON players (email)`
4. BEFORE-INSERT/UPDATE-Trigger forciert lowercase auf alle zukuenftigen Inserts/Updates

## Rollback-Pfad

Falls Migration unerwartet failed: Migration ist atomar (eine Transaktion). Bei Failure ist Schema unveraendert. Captain bekommt Error-Message, Dev untersucht.

## Referenzen

- Pitfall-Quelle: `.planning/research/PITFALLS.md` C1 (RLS-Cross-Write)
- Migration-File: `supabase/migrations/20260430b_email_unique.sql` (wird in Plan 0-06 erstellt)
- Audit-File: `supabase/migrations/_audit/20260430_email_pre_check.sql`
