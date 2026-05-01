# RLS Cross-Write-Smoke-Test (FOUND-02 Post-Deploy)

**Wann:** Nach Deploy von Plan 0-06 (Migration `20260430c_players_rls_pin.sql`).
**Wer:** Dev oder Captain.
**Aufwand:** ~10 min.
**Warum:** Verifiziert dass C1 (RLS-Cross-Write) tatsaechlich blockiert ist und keine bestehenden Captain/Self-Workflows brechen (Pitfall C11 RLS-Regression-Risk).

## Test 1: Cross-Write blockiert (Test-Case `0-02-cross`)

1. Login als Spieler A (NICHT Captain) auf https://kvwn.vercel.app
2. Browser-DevTools -> Console
3. ID eines anderen Spielers besorgen:
   ```js
   const { data: me } = await sb.auth.getUser();
   const { data } = await sb.from('players').select('id, name').neq('email', me.user.email).limit(1);
   const spielerB_id = data[0].id;
   console.log('Spieler B:', data[0].name, spielerB_id);
   ```
4. Versuch Cross-Write:
   ```js
   const { data, error } = await sb.from('players').update({ phone: 'pwned' }).eq('id', spielerB_id);
   console.log('data:', data, 'error:', error);
   ```
5. **Erwartetes Ergebnis:** `data` ist leeres Array oder null (0 rows updated, RLS hat gefiltert) ODER `error.code === '42501'` (permission denied via WITH CHECK).
6. **Failure-Signal:** `data` enthaelt die geaenderte Row -> RLS-Pin greift NICHT, sofort Migration zuruckrollen + Plan 0-06 nochmal ueberpruefen.

## Test 2: Email-Pin in WITH CHECK greift (Test-Case `0-02-emailpin`)

Login als Spieler A (eigene Row):
```js
const { data: me } = await sb.auth.getUser();
const { data: myPlayer } = await sb.from('players').select('id').eq('email', me.user.email).maybeSingle();
const { data, error } = await sb.from('players').update({ email: 'pwned@x.de' }).eq('id', myPlayer.id);
console.log('data:', data, 'error:', error);
```
**Erwartet:** 0 rows updated (existierende `players self update` WITH CHECK email-Pin blockiert).

## Test 3: Captain-Update bleibt funktional (Test-Case `0-02-captain`)

1. Login als Captain auf https://kvwn.vercel.app
2. Navigate `/profil` -> Tab "Admin" -> "Rollen verwalten"
3. Edit irgendeinen Spieler (z.B. Phone-Nummer aendern)
4. **Erwartet:** 200 OK + Toast "Gespeichert" + Reload zeigt neue Phone

## Test 4: Self-Update bleibt funktional (Test-Case `0-02-self`)

1. Login als Spieler A (NICHT Captain) auf https://kvwn.vercel.app
2. Navigate `/profil/uebersicht`
3. Phone-Nummer im ProfilDatenSheet aendern
4. **Erwartet:** 200 OK + Toast "Gespeichert" + Reload zeigt neue Phone

## Smoke-Test-Targets (5 Files mit `sb.from('players').update`)

Nach Migration-Deploy MUSS jede dieser UI-Surfaces einmal manuell getestet werden (Network-Tab: keine 401/403):

1. `src/lib/components/admin/AdminRollen.svelte` — Captain aendert Rolle (-> Test 3 oben deckt das ab)
2. `src/lib/components/profil/UebersichtTab.svelte` — Spieler aendert Stammdaten (-> Test 4 oben deckt das ab)
3. `src/lib/components/profil/EinstellungenTab.svelte` — Spieler aendert Settings (oeffnen + irgendeinen Toggle aendern)
4. `src/lib/components/profil/ProfilHeroCard.svelte` — Profil-UI-Felder (oeffnen + Avatar-Aktion triggern)
5. `src/lib/components/profil/ProfilEinwilligungenCard.svelte` — Spieler setzt consent_*-Felder (Consent-Toggle bewegen)

Jede dieser Surfaces einmal touchen, Network-Tab zeigt Status 200 (oder 0-row update wenn keine Aenderung), KEIN 401/403.

## Failure-Eskalation (Rollback-Pfad)

Falls irgendein Test failed: Migration `20260430c_players_rls_pin.sql` zuruckrollen via:
```sql
DROP POLICY "players kapitaen write" ON public.players;
-- alte Policy aus 20260422_profil_selfservice.sql Z 92-101 wiederherstellen:
CREATE POLICY "players kapitaen write" ON public.players
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  );
```
Dev re-untersucht und korrigiert.

## Referenzen

- Pitfall-Quelle: `.planning/research/PITFALLS.md` C1 + C11
- Migration-File: `supabase/migrations/20260430c_players_rls_pin.sql` (Plan 0-06)
- Bestehende RLS: `supabase/migrations/20260422_profil_selfservice.sql` Z 84-116
