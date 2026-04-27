# Browser Test Plan — Spielbetrieb Spiele-Tab (Phase B)

Start: `npm run dev` → http://localhost:5173
Login: Google-Account **Benjamin** (Kapitän-Rolle).
Für Spieler-Sicht-Steps: entweder einen zweiten Browser-Profil mit einem Nicht-Kapitän-Account verwenden, oder die Steps als Benjamin durchführen und die kapitänsspezifischen Elemente ignorieren wo angegeben.

---

## Setup

1. Navigiere zu http://localhost:5173/spielbetrieb
   - Erwarte: Top-Tab-Leiste mit vier Chips — **Spiele | Turniere | Landesbewerbe | Statistiken**.
   - "Spiele" ist aktiv (unterstrichen / primärfarbiger Akzent).
   - Darunter lädt der Spiele-Tab (kurz Shimmer-Skeleton sichtbar, dann Inhalt).
   - Bug wenn: irgendein anderer Tab aktiv ist, Seite zeigt "404" oder leere weiße Fläche.

---

## Spieler-Sicht-Pfad

### H1: Seitenlayout und Ladevorgang

2. Beobachte den initialen Ladevorgang direkt nach Navigation.
   - Erwarte: Zwei gestapelte graue Shimmer-Boxen (eine schmale ~80 px hoch, zwei breitere ~240 px hoch) mit leichtem Glanz-Effekt (`.shimmer-box`).
   - Nach ~1 Sekunde verschwindet der Skeleton und echter Inhalt erscheint.
   - Bug wenn: Shimmer bleibt dauerhaft; Seite bleibt leer; Toast mit "Fehler:"-Präfix erscheint.

### H2: Sektion "Letzte Ergebnisse" (Spieler-Sicht)

3. Schaue auf den oberen Seitenbereich nach dem Laden.
   - Erwarte: Abschnitt-Header mit rot gefülltem `sports_score`-Icon links, Text **"Letzte Ergebnisse"** (Lexend-Font, fett, ~1 rem).
   - Darunter maximal 3 Result-Cards nebeneinander gestapelt, jeweils mit einem **4 px farbigen Stripe links** (grau-variante = `--color-outline-variant`, kein grün/rot-Akzent — das ist die bewusste neutrale Entscheidung laut Phase B).
   - Jede Card zeigt: oben links Datum im Format `"So, 19. Apr · [Ligaabkürzung]"` (kleines Uppercase), darunter `"vs. [Gegner]"` oder `"bei [Gegner]"` (fett, 1 Zeile), rechts eine große fette Zahl (Holz-Total) + Text `"HOLZ"` darunter in klein Uppercase.
   - Bug wenn: mehr als 3 Cards; Score zeigt zwei getrennte Spalten "Wir/Sie" — Phase B implementiert nur Eigenscore (`teamTotal`), keine Gegenüberstellung; Cards haben Touch-Feedback (sollten passiv sein).

4. Tippe auf eine Result-Card.
   - Erwarte: **Nichts passiert.** Keine Navigation, kein Sheet, kein Ripple-Effekt.
   - Bug wenn: ein Sheet oder eine Navigation ausgelöst wird.

### H3: Bewerb-Badge

5. Sieh dir den Badge-Text auf einer Result-Card und einer Match-Card an.
   - Erwarte: Badge zeigt den Liga-Namen aus der Datenbank (z. B. `"Landesliga"`, `"1. Liga"`, o. ä.), **nicht** den hartcodierten Fallback `"Liga"` — sofern `matches.leagues.name` in der DB einen Wert hat.
   - Falls der Name länger als 12 Zeichen ist: Badge zeigt die ersten 12 Zeichen (abgeschnitten, kein `"…"`).
   - Falls `leagues.name` leer/null: Badge zeigt `"Liga"`.
   - Bug wenn: Badge zeigt `"Liga"` obwohl in der DB ein Liganame vorhanden ist; Badge zeigt mehr als 12 Zeichen.

### H4: Sektion "Diese & nächste Woche" — Match-Card Aufbau

6. Scrolle zur Sektion **"Diese & nächste Woche"** (Header mit `event_upcoming`-Icon).
   - Erwarte: Abschnitt-Header wie in H2, Icon-Name ist `event_upcoming`.
   - Darunter Match-Cards (eine pro Ligaspiel in den nächsten 14 Tagen).

7. Betrachte eine Match-Card genau (für ein Auswärts-Spiel mit publizierter Aufstellung).
   - Erwarte Aufbau von oben nach unten:
     - **Header-Zeile**: Links Datum+Uhrzeit `"So, 27. Apr · 09:30 Uhr"` (Lexend, fett), rechts Bewerb-Badge + (falls Kapitän:) Edit-Icon.
     - **Subline**: `"Auswärts · [Gegnername]"` — "Auswärts" in kleinem Uppercase grau, `·` Trenner, Gegnername in normaler Schrift. Kein `"vs."` in der Subline.
     - **Trennlinie**: 1 px `outline-variant` Farbe.
     - **Slot-Liste**: 4 Zeilen, je mit Positionsnummer (`1.`, `2.`, `3.`, `4.`), Avatar-Foto (28×28 px, rund), Kurzname, Statusindikator rechts.
     - **Carpool-Footer**: Trennlinie + Auto-Icon + Label + Chevron-right. (Nur bei Auswärts.)
   - Bug wenn: Subline zeigt `"vs. Gegner"` statt `"Auswärts · Gegner"`; Carpool-Footer fehlt bei Auswärts; Edit-Icon als normaler Spieler sichtbar.

### H5: Mein-Slot Hervorhebung

8. Suche in der Slot-Liste deinen eigenen Slot (Benjamin).
   - Erwarte: Zeile hat einen **roten linken Balken** (3 px `box-shadow inset`, `--color-primary` = #CC0000), leicht rötlichen Hintergrund-Tint.
   - Avatar hat einen **2 px roten Rahmen**.
   - Nach dem Namen erscheint ein kleiner rot-hinterlegter Pill mit Text **"DU"** (Lexend, fett, ~0.75 rem).
   - Rechts der Status-Indikator — falls noch nicht bestätigt: `touch_app`-Icon + Text **"Tippen zum Bestätigen"** in primärrot.
   - Bug wenn: kein DU-Pill; kein roter Akzent-Streifen; Status-Text zeigt `"Offen"` statt `"Tippen zum Bestätigen"` für den eigenen unbestätigten Slot.

### H6: Mein-Slot 3-State-Toggle

9. Tippe einmal auf deinen Slot (Status muss `pending` sein = "Tippen zum Bestätigen").
   - Erwarte: Optimistische UI — **sofort** (ohne Netzwerk-Wartezeit) wechselt der Status-Indikator:
     - Icon: `check_circle` (grün/gefüllt), Text: **"Zugesagt"** in grüner Farbe (`--color-success`).
     - Hintergrund-Tint wechselt von Rot-Tint zu **Grün-Tint** (`color-success` 8 %).
     - Linker Akzentstreifen wird **grün** (`--color-success`).
     - Avatar-Rahmen wird grün.
     - DU-Pill wird grün.
     - Statuswechsel animiert: Status-Indikator faded (Opacity-Übergang ~150 ms).
   - Bug wenn: Seite neu lädt; Toast erscheint ohne dass ein Datenbankfehler vorliegt; Status bleibt unverändert; kein visueller Unterschied zwischen pending und confirmed.

10. Tippe ein zweites Mal auf denselben Slot (Status ist jetzt `confirmed` = "Zugesagt").
    - Erwarte: Status wechselt zu **"Abgesagt"**:
      - Icon: `cancel` (rot/gefüllt), Text: **"Abgesagt"** in primärrot (`--color-primary`).
      - Hintergrund-Tint wechselt zurück zu Rot-Tint.
      - Linker Akzentstreifen bleibt rot.
      - Ein **Toast-Benachrichtigung** erscheint (an Kapitäne wird eine Push-Notification gesendet; der Toast selbst ist nicht direkt sichtbar, aber kein Fehler-Toast).
    - Bug wenn: Status springt von confirmed direkt zu pending (überspringt declined); ein Fehler-Toast erscheint.

11. Tippe ein drittes Mal auf denselben Slot (Status ist jetzt `declined` = "Abgesagt").
    - Erwarte: Status wechselt zurück zu **"Tippen zum Bestätigen"** (pending):
      - Icon: `touch_app`, Text: **"Tippen zum Bestätigen"** in primärrot.
      - Tint bleibt Rot-Tint (pending und declined haben denselben Tint laut Code).
    - Bug wenn: 3. Tap tut nichts; Status bleibt declined.

### H7: A11y — aria-pressed beim Toggle

12. Öffne DevTools (F12) → Elements-Panel → klicke auf deinen Slot-`<li>` im DOM.
    - Erwarte: `role="button"`, `tabindex="0"` vorhanden.
    - Bei pending-State: `aria-pressed="mixed"`.
    - Nach 1. Tap (confirmed): `aria-pressed="true"`.
    - Nach 2. Tap (declined): `aria-pressed="false"`.
    - Nach 3. Tap (pending): `aria-pressed="mixed"`.
    - Bug wenn: `aria-pressed` fehlt gänzlich; Wert wechselt nicht; Wert ist immer `"false"` oder `"true"` unabhängig vom State.

### H8: Carpool-Footer Format

13. Suche ein Auswärts-Match mit **genau einer** Fahrgemeinschaft in der DB, die noch freie Plätze hat (z. B. 3 Plätze total, 1 besetzt).
    - Erwarte: Footer-Label zeigt `"Mitfahrt 1/3"` (besetzt/gesamt) — also `Mitfahrt {seats_taken}/{seats_total}`.
    - Kein `"Fahrten"`-Wort bei einer einzigen Fahrt.
    - Bug wenn: Label zeigt `"1 Fahrten · 2 freie Plätze"` bei nur einer Fahrt.

14. Suche (oder prüfe in der DB) ein Auswärts-Match mit **zwei oder mehr** Fahrgemeinschaften.
    - Erwarte: Footer-Label zeigt `"2 Fahrten · N freie Plätze"` (Anzahl Fahrten · aggregierte freie Plätze).
    - Bug wenn: Label zeigt `"Mitfahrt X/Y"` obwohl mehrere Fahrten existieren.

15. Tippe auf den Carpool-Footer eines Auswärts-Matches.
    - Erwarte: `BottomSheet` öffnet sich von unten mit Titel **"Fahrgemeinschaft"** in der Sheet-Header-Leiste.
    - Kurz ein Lade-Spinner/Icon sichtbar (directions_car-Icon mit Opacity 0.4), dann Fahrten-Inhalt.
    - Beim Tippen: leichter scale-down Effekt (0.98) auf dem Footer.
    - Bug wenn: Sheet öffnet nicht; Seite navigiert weg; kein Ladeindikator bei langsamem Netz.

---

## Kapitän-Sicht-Pfad (als Benjamin eingeloggt)

### K1: Edit-Icon sichtbar

16. Schaue auf eine Match-Card in "Diese & nächste Woche".
    - Erwarte: Rechts in der Header-Zeile, **nach dem Bewerb-Badge**, ein kleines **`edit`-Icon** (runder Button, transparent, ~44×44 px Tap-Fläche).
    - Icon-Farbe: `--color-on-surface-variant` (grau), bei Hover/Focus wechselt zu `--color-primary` (rot) mit leichtem roten Hintergrundtint.
    - Bug wenn: Icon fehlt; Icon ist vor dem Bewerb-Badge; Icon hat keinen Hover-Effekt.

17. Tippe das Edit-Icon.
    - Erwarte: `AdminAufstellung`-Sheet öffnet sich (Bottom Sheet) mit dem Lineup-Editor für genau diesen Match geladen.
    - Bug wenn: Sheet öffnet nicht; falsches Match wird geladen; Sheet öffnet leer ohne Daten.

18. Schließe das Sheet (Swipe down oder X-Button je nach Sheet-Implementierung).
    - Erwarte: Sheet schließt, Spiele-Tab lädt die Daten **neu** (loadData() wird nach Sheet-Schließen getriggert — kurzer Shimmer kann erscheinen).
    - Bug wenn: Seite friert ein; Sheet schließt nicht; Daten werden nicht aktualisiert.

### K2: Kapitän sieht unscored Match in "Letzte Ergebnisse"

19. Schaue auf die "Letzte Ergebnisse" Sektion (als Kapitän).
    - Falls ein vergangenes Ligaspiel **kein eingetragenes Ergebnis** hat:
    - Erwarte: Card hat einen **gold-farbigen linken Stripe** (`--color-secondary` = #D4AF37, 4 px).
    - Rechts oben steht **"Kein Ergebnis"** in Gold-Farbe, kleines Uppercase.
    - Darunter ein roter Button `[ edit_note  Ergebnis eintragen ]`.
    - Bug wenn: Card fehlt ganz; Card hat denselben grauen Stripe wie normale Result-Cards; Button fehlt.

20. Tippe den Button **"Ergebnis eintragen"**.
    - Erwarte: `ResultEntrySheet` öffnet sich mit dem richtigen Match vorausgewählt.
    - Bug wenn: Sheet öffnet sich mit leerem Match-Select; Sheet öffnet nicht.

---

## Edge Cases

### E1: Heim-Match — kein Carpool-Footer

21. Suche eine Match-Card, bei der die Subline **"Heim ·"** zeigt.
    - Erwarte: Die gesamte Carpool-Footer-Zeile (Trennlinie + Auto-Icon + Label + Chevron) **fehlt komplett** — kein leerer Platzhalter, kein ausgegrauter Footer.
    - Bug wenn: Carpool-Footer ist sichtbar (auch ausgegraut) bei einem Heim-Match.

### E2: Auswärts-Match — Carpool-Footer vorhanden

22. Suche eine Match-Card, bei der die Subline **"Auswärts ·"** zeigt.
    - Erwarte: Carpool-Footer ist sichtbar, auch wenn noch keine Fahrgemeinschaft angelegt ist (Label zeigt dann `"Mitfahrt anbieten"`).
    - Bug wenn: Carpool-Footer fehlt bei einem Auswärts-Match.

### E3: Empty State — keine Spiele in 14 Tagen

23. (Wenn kein Ligaspiel in den nächsten 14 Tagen existiert — ggf. auf eine spielfreie Saison-Phase testen oder DB kurzfristig bereinigen.)
    - Erwarte: Sektion **"Diese & nächste Woche"** bleibt mit Header sichtbar.
    - Darunter eine einzelne graue Card mit `event_busy`-Icon (zentriert) und Text `"Keine Spiele in den nächsten 14 Tagen"` in grauer `--color-on-surface-variant`-Farbe.
    - Bug wenn: Sektion verschwindet komplett; Text fehlt; leere weiße Fläche ohne Karte.

### E4: Aufstellung nicht published — Frei-Slots

24. Suche ein Match, für das noch keine Aufstellung published ist (`lineup_published_at` = null).
    - Erwarte: Slot-Liste zeigt 4 Zeilen mit:
      - Positions-Label (`1.` / `2.` / `3.` / `4.`)
      - **Gestrichelter Kreis** anstelle eines Avatars (1.5 px dashed `--color-outline-variant`, transparent).
      - Text `"Frei"` in grau-kursiv (`--color-on-surface-variant`, italic).
      - Kein Status-Indikator rechts.
    - Unterhalb der Slots: ein graues Hint-Feld mit `schedule`-Icon + Text **"Aufstellung folgt"**.
    - Kein DU-Pill, kein Tint, kein "Tippen zum Bestätigen" — Slot ist nicht interaktiv.
    - Bug wenn: Namen von Spielern sichtbar obwohl Aufstellung nicht published; Slots sind tap-bar.

---

## A11y Spotcheck

### A1: Keyboard-Navigation

25. Navigiere per **Tab-Taste** durch eine Match-Card.
    - Erwarte: Fokus-Reihenfolge innerhalb der Card (DOM-Reihenfolge):
      1. Edit-Icon (falls Kapitän): roter 2 px Fokus-Ring.
      2. Mein Slot-`<li>`: roter 2 px Fokus-Ring (`outline: 2px solid var(--color-primary); outline-offset: 2px`).
      3. Carpool-Footer-Div: roter 2 px Fokus-Ring.
    - Bei Fokus auf Mein Slot: **Leertaste oder Enter** löst denselben State-Wechsel aus wie ein Tap (pending → confirmed).
    - Bug wenn: Fokus-Ring nicht sichtbar; Keyboard-Aktivierung triggert nichts; Fokus springt in falsche Reihenfolge.

### A2: Avatar alt-Text

26. Öffne DevTools → Elements → klicke ein Avatar-`<img>` in einem Slot.
    - Erwarte: `alt`-Attribut enthält den **vollen Spielernamen** (z. B. `alt="Benjamin Seiberl"`), nicht den Kurznamen.
    - Bug wenn: `alt=""` (leer); `alt="Ben S."` (Kurzname); `alt`-Attribut fehlt.

---

## Regression Checks

### R1: Andere Spielbetrieb-Tabs nicht gecrasht

27. Tippe auf den Top-Tab-Chip **"Turniere"** in der Tab-Leiste.
    - Erwarte: Inhalt wechselt zu `TurniereTab`, kein leerer Screen, keine Konsolen-Fehler (DevTools).
    - Tippe auf **"Landesbewerbe"**: Inhalt wechselt zu `LandesbewerbeTab`.
    - Tippe auf **"Statistiken"**: Inhalt wechselt zu `StatsView`.
    - Tippe zurück auf **"Spiele"**: Inhalt wechselt zu `SpieleTab`, Daten laden neu (kurzer Shimmer möglich).
    - Bug wenn: Tab-Wechsel führt zu weißem Screen; Konsole zeigt `TypeError` oder `ReferenceError`.

### R2: Andere Routes nicht gecrasht

28. Navigiere per Bottom-Navigation zu **"/"** (Dashboard).
    - Erwarte: Dashboard lädt normal (Cockpit-Cards, Greeting sichtbar).
29. Navigiere zu **"/kalender"**.
    - Erwarte: Kalender öffnet in der zuletzt aktiven View (Agenda/Woche/Monat) — kein Crash.
30. Navigiere zu **"/profil"**.
    - Erwarte: Profil-Seite mit Übersicht-Tab — kein Crash.
31. Navigiere zurück zu **"/spielbetrieb"** (Bottom-Nav).
    - Erwarte: Spiele-Tab ist wieder aktiv (Default-Tab), Daten sind korrekt geladen.
    - Bug wenn: Tab-State bleibt auf einem anderen Tab als "Spiele" nach Rückkehr von anderer Route.

---

## Was ich NICHT geprüft habe

- **Visuelles Pixelperfekt-Spacing** (Padding-Werte, Font-Größen im Millimeter-Vergleich mit Design-Spec).
- **Push-Notification auf dem Gerät** wenn Decline ausgelöst wird — nur der Fire-and-Forget-fetch im Code ist abgedeckt, nicht der tatsächliche Empfang.
- **Offline-Verhalten** (kein Service Worker, kein Offline-Test).
- **Sehr langsame Netzwerke** (Throttling in DevTools — nur der initiale Shimmer wurde beschrieben, nicht das Verhalten bei Timeout).
- **Match-Detail-Drilldown** aus Result-Cards (Phase D, noch nicht implementiert).
- **Decline-Benachrichtigung**: ob die Kapitan-Push-Notification auf dem Empfangsgerät korrekt dargestellt wird.
- **Spielbetrieb → Aufstellung-Tab** (`AufstellungenTab.svelte`) — nicht Teil von Phase B.
- **Mehrere gleichzeitige Spieler** die denselben Slot bestätigen (Race-Condition-Szenario).
- **Matches die genau heute stattfanden** (Zeitzone-Grenzfall zwischen "vergangen" und "kommend").
