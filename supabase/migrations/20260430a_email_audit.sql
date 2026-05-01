-- KVWN — FOUND-01 Schritt 1/2: Retroaktive Email-Lowercase-Normalisierung
--
-- VORAUSSETZUNG: Captain hat Audit-Skript `_audit/20260430_email_pre_check.sql`
-- ausgefuehrt und beide Result-Sets zeigen 0 Rows. Siehe `docs/runbooks/email-cleanup.md`.
--
-- WARUM SEPARAT VON 20260430b_email_unique: lower() koennte neue Duplikate erzeugen
-- (z.B. 'A@b.de' + 'a@b.de'). Audit MUSS lower()-bewusst sein (Plan 0-01 Audit benutzt
-- bereits `GROUP BY lower(email)`). Nach diesem Step ist Email-Spalte sauber lowercase
-- — UNIQUE in 20260430b kann dann ohne weitere Konflikte greifen.

-- Retroaktiv lowercase. Nur Rows mit non-null + non-lowercase Email.
UPDATE public.players
SET email = lower(email)
WHERE email IS NOT NULL
  AND email <> lower(email);
