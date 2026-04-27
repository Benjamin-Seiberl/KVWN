# Spielbetrieb · Spiele-Tab — Design Spec

> Scope: `src/lib/components/spielbetrieb/SpieleTab.svelte` (Phase B des Spielbetrieb-Redesigns).
> Out of scope: Tab-Chrome (Top-Tabs), Turniere/Landesbewerbe/Statistiken-Tabs, alle bestehenden Sheets (`ResultEntrySheet`, `CarpoolOfferSheet`, `AdminAufstellung`) — die werden 1:1 reused.

---

## 1. Intent

Der Spiele-Tab ist die **Liga-Werkbank**. Spieler öffnet die App vor dem Spiel und will in unter 5 Sekunden wissen: *"War das letzte Spiel gewonnen?"* und *"Wer spielt mit mir am Sonntag, und steh ich schon fix?"*. Kapitän öffnet ihn aus dem gleichen Anlass plus *"muss ich ein Ergebnis nachtragen oder die Aufstellung schieben?"*.

Lösung: **Zwei vertikale Sektionen**, beide aus dem gleichen `mw-card`-Pattern. Letzte Ergebnisse oben (rückblickend, bestätigend) — Diese & Nächste Woche unten (vorausblickend, handlungsfordernd). Kapitän bekommt **denselben View**, plus 1–2 winzige Inline-Aktionen. Keine Pills, kein Sub-Tab-Wirrwarr.

---

## 2. Information Hierarchy

1. **Primary:** Mein nächster Match-Card mit meinem Slot prominent (= Anker für Confirm/Decline).
2. **Secondary:** Letzte Ergebnisse — Score + Win/Loss-Andeutung (Anker = Score).
3. **Tertiary:** Sektion-Header, Bewerb-Badges, Carpool-Badge, Datum.
4. **Captain-only inline-Aktionen** (Edit-Icon, Ergebnis-Button) sind im Layer **zwischen Secondary und Tertiary** — sichtbar, aber nicht dominant.

---

## 3. Layout (gesamter Tab)

```
┌─────────────────────────────────────────────────┐
│                                                 │  ← Tab-Body, beginnt unter
│  Letzte Ergebnisse                              │     Top-Tab-Leiste
│  ─────────────────                              │
│  ┌───────────────────────────────────────────┐  │
│  │ [Result-Card 1]                           │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │ [Result-Card 2]                           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Diese & nächste Woche                          │
│  ─────────────────────                          │
│  ┌───────────────────────────────────────────┐  │
│  │ [Match-Card mit Inline-Aufstellung]       │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │ [Match-Card 2]                            │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Page-Frame

| Token | Wert | Hinweis |
|---|---|---|
| Tab-Container Padding-X | `0` | Cards haben eigenen `margin: 0 var(--space-4)` (siehe `.mw-card`). |
| Tab-Container Padding-Top | `var(--space-4)` | Abstand unter Top-Tab-Leiste. |
| Tab-Container Padding-Bottom | `calc(var(--nav-height) + var(--space-5))` | Bottom-Nav-Clearance, identisch zum Dashboard-v2-Frame. |
| Section-zu-Section Abstand | `var(--space-6)` | Klar trennend zwischen "Vergangenheit" und "Zukunft". Nicht `--space-5` — die Sektionen sollen sich *anfühlen* wie zwei Zeitabschnitte. |
| Card-zu-Card Abstand (innerhalb Sektion) | `var(--space-3)` | Kommt aus dem `margin-bottom: var(--space-4)` von `.mw-card` minus Optik-Korrektur — siehe §10. |

---

## 4. Sektion-Header

Beide Sektionen verwenden denselben Header-Stil. Reuse-Pflicht: identische Klasse, **kein** Klassen-Sprawl.

```
┌─────────────────────────────────┐
│ ⚽  Letzte Ergebnisse           │   ← Icon + Titel, linksbündig
└─────────────────────────────────┘
```

| Element | Token / Wert |
|---|---|
| Wrapper Padding | `0 var(--space-5)` |
| Margin-bottom | `var(--space-3)` |
| Icon | Material Symbols `sports_score` (Letzte) / `event_upcoming` (Diese & nächste Woche), `font-size: 1.1rem`, `color: var(--color-primary)`, `font-variation-settings: 'FILL' 1` |
| Titel-Text | `font-family: var(--font-display)`, `font-size: var(--text-title-md)` (1 rem), `font-weight: 700`, `color: var(--color-on-surface)` |
| Layout | `display: flex; align-items: center; gap: var(--space-2)` |

Header-Reuse: dies ist **dieselbe Anatomie** wie `.sec-head` im Dashboard v2 (siehe `docs/design/dashboard-v2.md` §2). Frontend-dev sollte prüfen, ob `.sec-head` bereits global existiert und reusen statt neu definieren.

### Empty-States pro Sektion

**"Letzte Ergebnisse"**: keine Ergebnisse aus den letzten 14 Tagen → **Sektion komplett ausblenden**. Kein Header, kein Hinweis. (Vermeidet "leere Vergangenheit"-Effekt am Saisonstart.)

**"Diese & nächste Woche"**: keine Matches im 14-Tage-Fenster → Header bleibt, darunter ein **Empty-Row** im `.mw-card`-Look-and-feel:

```
┌───────────────────────────────────────────┐
│                                           │
│   📅  Keine Spiele in den nächsten        │
│       14 Tagen                            │
│                                           │
└───────────────────────────────────────────┘
```

| Element | Token |
|---|---|
| Card | `.mw-card`, kein zusätzliches Padding-Override |
| Icon | `event_busy`, `1.4rem`, `color: var(--color-on-surface-variant)` |
| Text | `var(--text-body-md)`, `color: var(--color-on-surface-variant)`, `text-align: center` |
| Layout | `display: flex; flex-direction: column; align-items: center; gap: var(--space-2); padding: var(--space-6) var(--space-4)` |

Wenn **beide** Sektionen leer sind: kein "Doppel-Empty" — zeige nur den Empty-Row der "Diese & nächste Woche"-Sektion. Letzte Ergebnisse bleibt ausgeblendet.

---

## 5. Result-Card (Letzte Ergebnisse)

### 5.1 Anatomie — Spieler-Sicht (gescortes Match)

```
┌───────────────────────────────────────────────────────┐
│ ▌ So, 19. Apr · LIGA              5 700 : 5 432       │
│ ▌                                  ──────   ─────     │
│ ▌ vs. SKK Wr. Neudorf 2           Wir       Sie       │
└───────────────────────────────────────────────────────┘
   ↑
   2 px Akzent-Stripe links
```

Layout-Grid (mobile):
- 2 Spalten: links Meta (60 %), rechts Score (40 %).
- Card-Höhe Ziel: ~80 px (kompakt).
- Card-Reuse: `.mw-card` aus `app.css` (border, shadow, radius bereits gesetzt). Padding bleibt `var(--space-4)`.

### 5.2 Tokens

| Element | Token |
|---|---|
| Card | `.mw-card` |
| Akzent-Stripe links (Win) | `border-left: 4px solid var(--color-success)`, ersetzt das default `border` der `.mw-card` linksseitig — siehe §10 |
| Akzent-Stripe links (Loss) | `border-left: 4px solid var(--color-primary)` |
| Akzent-Stripe (unscored, nur Kapitän) | `border-left: 4px solid var(--color-secondary)` |
| Datums-Eyebrow | `font-family: var(--font-body)`, `var(--text-label-sm)`, `font-weight: 700`, `letter-spacing: 0.06em`, `text-transform: uppercase`, `color: var(--color-on-surface-variant)` |
| Bewerb-Badge | reuse `.mw-badge` (existiert in `app.css` Zeile 3078); `LIGA` / `TURNIER` / `LANDESBEWERB` Label aus `BEWERB_LABEL` |
| Gegner-Zeile | `font-family: var(--font-display)`, `var(--text-title-sm)` (0.875 rem), `font-weight: 700`, `color: var(--color-on-surface)`, max 1 Zeile, `text-overflow: ellipsis` |
| Score (Wir + Sie) | `font-family: var(--font-display)`, `var(--text-headline-sm)` (1.375 rem), `font-weight: 800`, `tabular-nums`, `letter-spacing: -0.01em` |
| Score-Farbe (Wir, Win) | `var(--color-success)` |
| Score-Farbe (Wir, Loss) | `var(--color-primary)` |
| Score-Farbe (Sie) | `var(--color-on-surface-variant)` (immer dezent) |
| Score-Trenner ":" | `var(--color-outline)`, `font-weight: 500` (dezenter als die Zahlen) |
| Score-Eyebrow ("Wir" / "Sie") | `var(--text-label-sm)`, `var(--color-on-surface-variant)`, uppercase, gerendert unter den Zahlen |

**Anker-Entscheidung:** Score ist der visuelle Anker (linke Seite ist Datum/Gegner als Kontext). Begründung: User scant erst "haben wir gewonnen?" — die farbige große Zahl beantwortet das in <1 s. Datum ist Sekundär-Kontext.

**Win/Loss-Andeutung — dreigleisig (a11y):**
1. **Farbe** (Score-Zahl + Stripe links) — primär.
2. **Akzent-Stripe** linksseitig — taktil/visuell auch farb-blind erkennbar als "etwas markiertes".
3. **Optionales Icon** rechts neben dem "Wir"-Score: `arrow_drop_up` bei Win (success-color), `arrow_drop_down` bei Loss (primary-color), 1 rem, gefüllt. **Keine** Emoji-Trophys.

### 5.3 Layout-Grid (genauer)

```
┌───────────────────────────────────────────────────┐
│  ▌  ┌─────────────────┬─────────────────┐         │
│  ▌  │  So, 19. Apr    │   5 700 : 5 432 │         │
│  ▌  │  · LIGA  Badge  │                 │         │
│  ▌  │                 │                 │         │
│  ▌  │  vs. SKK ...    │   WIR    SIE    │         │
│  ▌  └─────────────────┴─────────────────┘         │
└───────────────────────────────────────────────────┘
```

CSS-Hint für frontend-dev (nicht implementieren — nur Spec):
- Outer: `display: grid; grid-template-columns: 1fr auto; gap: var(--space-3); align-items: center`
- Linke Spalte: `display: flex; flex-direction: column; gap: 2px`
- Rechte Spalte: `display: flex; flex-direction: column; align-items: flex-end; gap: 2px`

### 5.4 Kapitän-State: unscored Match

Card eines Match in der Vergangenheit, das noch keinen Score hat (Kapitän hat vergessen einzutragen).

```
┌───────────────────────────────────────────────────────┐
│ ▌ So, 19. Apr · LIGA                  Kein Ergebnis   │
│ ▌                                                     │
│ ▌ vs. SKK Wr. Neudorf 2          [ Ergebnis eintr. ] │  ← mw-btn--primary
└───────────────────────────────────────────────────────┘
   ↑ gold accent stripe
```

| Element | Token |
|---|---|
| Stripe | `border-left: 4px solid var(--color-secondary)` (Gold = "Aktion fällig") |
| "Kein Ergebnis"-Hinweis | `var(--text-label-sm)`, `color: var(--color-secondary)`, `font-weight: 700`, uppercase |
| Button | `.mw-btn .mw-btn--primary`, kompakt: `padding: var(--space-2) var(--space-3)` Override (Card soll trotzdem ~80 px hoch bleiben), Label `Ergebnis eintragen`, Icon `edit_note` davor |
| Tap | öffnet bestehendes `ResultEntrySheet` mit `match_id` |

**Wo platzieren ohne Card zu zerschießen:** Button **rechts unten** in der Card, ersetzt visuell den Score-Block (Score gibt es ja noch nicht). Datum/Gegner bleiben links genau wie bei einer normalen Result-Card. Das hält die Anatomie konsistent — Kapitän sieht "wo der Score wäre, ist jetzt ein Button".

**Spieler-Sicht** (kein Kapitän) bei demselben unscored Match: Card wird **nicht angezeigt**. Spieler sehen nur Cards mit Score. Begründung: für Spieler ist "Score noch nicht eingetragen" kein nützliches Signal.

### 5.5 Tap-Verhalten

- **Spieler-Sicht (gescort)**: ganze Card ist tap-bar → optionaler Drilldown ins Match-Detail-Sheet (Phase D liefert `MatchStatsDetailSheet`). In Phase B: Card ist **nicht tap-bar** — kein Sheet, kein Hover-State. Cursor `default`. Frontend-dev: hier nicht spekulativ verdrahten.
- **Kapitän-unscored**: nur der Button ist tap-bar; Rest der Card ist passiv.

---

## 6. Match-Card (Diese & nächste Woche) — DAS RISIKO

### 6.1 Dichte-Strategie

Die Card muss **gleichzeitig** zeigen:
1. Datum + Uhrzeit
2. Gegner + Heim/Auswärts
3. Bewerb-Badge
4. 4 Aufstellungs-Slots (Position · Avatar · Kurzname · Confirm-Status)
5. Carpool-Badge
6. Optional: Kapitän-Edit-Icon
7. Mein-Slot visuell hervorgehoben

**Strategie:** **Vertikale Slots, nicht horizontal.** Begründung:
- Horizontale Reihe (4 Avatare nebeneinander) = je <60 px Slot-Breite, Name muss abgeschnitten werden, Confirm-Status nur als Border-Color möglich → Tap-Target unklar, a11y schwach.
- Vertikale Reihe = jeder Slot ist eine eigene 44-px-Zeile. Position links, Avatar+Name mittig, Confirm-Indikator+Tap-Affordance rechts. Klar, dicht, tap-freundlich.

Card-Gesamthöhe-Ziel: 4 Slots × 44 px + Header (40 px) + Footer (32 px) + Padding ≈ 280 px. Das ist groß, aber **nicht zu groß** — User scrollt nur 1–2 solche Cards (max 2 Liga-Matches in 14 Tagen).

### 6.2 Vollständige Anatomie (Spieler-Sicht)

```
┌────────────────────────────────────────────────────────┐
│ So, 27. Apr · 09:30 Uhr        [ LIGA ]                │  ← Header-Zeile
│ Heim · vs. SKK Wr. Neudorf 2                           │  ← Subline
│ ────────────────────────────────────────────────────── │
│  1  ⓜ Lukas H.            ✓ Zugesagt                   │  ← Slot 1
│  2  ⓜ Stefan M.           · Offen                      │  ← Slot 2
│  3  ⓜ Ben S.   ◀ DU       ⓘ Antippen zum Bestätigen   │  ← Slot 3 (mein)
│  4  ⓜ Patrick K.          ✗ Abgesagt                   │  ← Slot 4
│ ────────────────────────────────────────────────────── │
│ 🚗 Mitfahrt 3/4                                         │  ← Footer
└────────────────────────────────────────────────────────┘
```

Card-Reuse: `.mw-card` (Background, Border, Shadow, Radius, Padding). **Nicht** override-en.

### 6.3 Header-Zeile (Datum / Bewerb-Badge)

| Element | Token |
|---|---|
| Layout | `display: flex; align-items: center; justify-content: space-between; gap: var(--space-3)` |
| Datum-Block | `font-family: var(--font-display)`, `var(--text-title-sm)`, `font-weight: 700`, `color: var(--color-on-surface)` |
| Datum-Format | `fmtDate(d) + ' · ' + fmtTime(t)` → `"So, 27. Apr · 09:30 Uhr"` |
| Bewerb-Badge | `.mw-badge`, Label aus `BEWERB_LABEL`. Liga-Match: Eigenes Badge `LIGA` — wenn `BEWERB_LABEL` nichts liefert (Liga-Matches sind keine `is_landesbewerb`/`is_tournament`), Frontend-dev verwendet harten String `'Liga'` als Default |

### 6.4 Subline (Gegner + Heim/Auswärts)

| Element | Token |
|---|---|
| Layout | `margin-top: 2px` |
| Heim/Auswärts-Marker | Kleines uppercase Label vor dem Gegner: `Heim` / `Auswärts`, `var(--text-label-sm)`, `font-weight: 700`, `letter-spacing: 0.06em`, `color: var(--color-on-surface-variant)`, danach mittiger `·`-Trenner |
| Gegner | `font-family: var(--font-body)`, `var(--text-body-md)`, `font-weight: 600`, `color: var(--color-on-surface)`, max 1 Zeile, `text-overflow: ellipsis` |
| `vs.`-Prefix | weglassen — Subline ist `Heim · SKK Wr. Neudorf 2` (oder `Auswärts · SKK …`). Spart eine Vokabel und das Kontext-Wort `Heim/Auswärts` ersetzt es. |

### 6.5 Trennlinie zwischen Header und Slots

| Element | Token |
|---|---|
| `border-top` | `1px solid var(--color-outline-variant)` |
| Margin oben/unten | `var(--space-3)` |

### 6.6 Slot-Zeile (4× pro Card)

```
┌──────────────────────────────────────────────────────┐
│  POS    [PHOTO]  Name             STATUS             │
│  ←32px→ ←28px→  ←flex→            ←auto→            │
└──────────────────────────────────────────────────────┘
            44 px Zeilenhöhe (min)
```

| Element | Token |
|---|---|
| Zeile | `display: flex; align-items: center; gap: var(--space-2); min-height: 44px; padding: 6px 0` |
| Position-Label | `min-width: 28px`, `font-family: var(--font-display)`, `var(--text-label-sm)`, `font-weight: 800`, `color: var(--color-on-surface-variant)`, gerendert als `1.` / `2.` / `3.` / `4.` |
| Avatar | `width: 28px; height: 28px; border-radius: var(--radius-full); object-fit: cover; object-position: top center; background: var(--color-surface-container); flex-shrink: 0`. Quelle: `imgPath(player.photo, player.name)`, Fallback `BLANK_IMG`. Border bei normalen Slots: keine. |
| Name | `font-family: var(--font-display)`, `var(--text-body-md)`, `font-weight: 700`, `color: var(--color-on-surface)`, `flex: 1`, `min-width: 0`, `text-overflow: ellipsis`. Quelle: `shortName(player)`. |
| Status-Indikator (rechts) | siehe §6.7 |

**Falls ein Slot leer ist** (Aufstellung noch nicht voll oder Spieler ausgetragen): Position-Label bleibt, Avatar wird zu einem gestrichelten Kreis (`border: 1.5px dashed var(--color-outline-variant)`, transparent), Name wird zu `Frei`, `color: var(--color-on-surface-variant)`, `font-style: italic`. Status-Indikator-Slot bleibt leer.

### 6.7 Confirm-Status-Indikator

Drei States, jeder mit **Icon + Text-Label** (a11y: nicht nur Farbe):

| State | Icon | Label | Token |
|---|---|---|---|
| Confirmed (Zugesagt) | `check_circle` filled | `Zugesagt` | `color: var(--color-success)` |
| Pending (Offen) | `radio_button_unchecked` | `Offen` | `color: var(--color-on-surface-variant)` |
| Declined (Abgesagt) | `cancel` filled | `Abgesagt` | `color: var(--color-primary)` |

Layout des Indikators: `display: inline-flex; align-items: center; gap: 4px; font-family: var(--font-body); font-size: var(--text-label-sm); font-weight: 700`. Icon `1rem`, `font-variation-settings: 'FILL' 1`.

**Wichtig:** Indikator ist für *fremde* Slots **nicht** tap-bar (passive Anzeige). Nur für den eigenen Slot ist die ganze Zeile interaktiv (siehe §6.8).

### 6.8 Mein Slot (visuell hervorgehoben)

Der Slot des eingeloggten Spielers ist die **Kern-Aktion** des gesamten Tabs — er muss eindeutig erkennbar und tap-bar sein.

```
┌──────────────────────────────────────────────────────┐
│  3   [PHOTO]  Ben S.  ◀ DU      ⓘ Tippen zum Best.  │  ← pending, mein
└──────────────────────────────────────────────────────┘
   ↑ background tint + linke Akzent-Linie 3 px primary
```

Visuelle Diff zu fremden Slots:

| Element | Mein Slot |
|---|---|
| Background | `background: color-mix(in srgb, var(--color-primary) 6%, transparent)` |
| Linker Akzent | `box-shadow: inset 3px 0 0 var(--color-primary)` (statt zusätzlichem Border, damit Slot-Höhe stabil bleibt) |
| Border-Radius | `var(--radius-md)` — Slot wirkt als eigene Mini-Card im Card |
| Padding-Left | erhöht auf `var(--space-2)` (sonst überdeckt der inset-shadow den Position-Label) |
| Avatar-Border | `2px solid var(--color-primary)` |
| "DU"-Marker | nach dem Namen: `font-family: var(--font-display)`, `var(--text-label-sm)`, `font-weight: 800`, `color: var(--color-primary)`, padded `2px var(--space-2)`, `background: color-mix(in srgb, var(--color-primary) 10%, transparent)`, `border-radius: var(--radius-full)`. Optisch wie ein Mini-Pill. |
| Status-Hint (rechts) bei pending | Statt `· Offen` zeige `Tippen zum Bestätigen` mit Icon `touch_app`. `color: var(--color-primary)`, `font-weight: 700`. Macht klar dass die Zeile interaktiv ist. |

### 6.9 Mein-Slot Interaktions-States

Mobile-first, ganze Zeile ist die Tap-Area:

| State | Visuelle Diff |
|---|---|
| Default (pending) | wie §6.8 |
| Active (während Tap) | `transform: scale(0.98)`, `transition: transform 80ms ease`. Reuse-Pattern aus `.mw-btn:active`. |
| After-Tap (confirmed) | Background-Tint wechselt zu `color-mix(in srgb, var(--color-success) 8%, transparent)`, Akzent-Inset zu `var(--color-success)`, Status-Indikator zu `Zugesagt` mit `check_circle`. Optimistic UI — kein Loading-Spinner, falls Toast-Error → Rollback. |
| After-Tap (declined) | Tint wechselt zu `color-mix(in srgb, var(--color-primary) 6%, transparent)` (gleich), Akzent bleibt primary. |
| Disabled | Aufstellung nicht published / Deadline vorbei → Status-Indikator zeigt geltenden State, "Tippen zum Bestätigen"-Hint wird ersetzt durch `Geschlossen` (`color: var(--color-on-surface-variant)`). Tap = no-op + Toast `'Bestätigung geschlossen'`. |

**Confirm/Decline-Logik:** Erste Frage in Phase B: *Wie wird zwischen Confirm und Decline unterschieden?* Empfehlung: **Tap** = toggle pending↔confirmed. **Decline** läuft über ein separates kleines Icon rechts in derselben Zeile (kein eigener Tap-Bereich für die ganze Zeile, weil Decline destruktiv ist):

```
│  3  [PHOTO] Ben S. ◀ DU     ⓘ Tippen zum Best.  ✕  │
                                                    ↑
                                              decline-icon
```

| Element | Token |
|---|---|
| Decline-Icon-Button | `width: 32px; height: 32px; border-radius: var(--radius-full); display: flex; align-items: center; justify-content: center; background: transparent; color: var(--color-on-surface-variant)` |
| Tap-Target | 32 × 32 ist **unter** 44 px — daher `padding: 6px` außen rum auf den Button gesetzt, sodass die effektive Tap-Fläche 44 × 44 ist. Visuell bleibt das Icon klein und dezent. |
| Hover | `background: color-mix(in srgb, var(--color-primary) 10%, transparent)` |
| Tap | öffnet eine Confirm-Dialog (1-line `BottomSheet` mit "Wirklich absagen?") oder direkt — entscheidet planner; nicht designer-relevant. |

Falls die Confirm-Logik im bestehenden Code ein single-tap-toggle ist, kann der Decline-Icon entfallen und Tap toggelt 3-fach (pending → confirmed → declined → pending). Für die Spec ist die explizite Decline-Variante sicherer (a11y, Vermeidung versehentlicher Absage).

### 6.10 Carpool-Badge (Footer)

```
┌────────────────────────────────────────────────────────┐
│ ────────────────────────────────────────────────────── │
│ 🚗 Mitfahrt 3/4                                         │  ← Footer
└────────────────────────────────────────────────────────┘
```

| Element | Token |
|---|---|
| Trennlinie oberhalb | `border-top: 1px solid var(--color-outline-variant); margin-top: var(--space-3); padding-top: var(--space-2)` |
| Layout | `display: flex; align-items: center; gap: var(--space-2)` |
| Icon | Material `directions_car`, `1.1rem`, `var(--color-on-surface-variant)`. **Kein** Emoji. |
| Label | `font-family: var(--font-body)`, `var(--text-body-md)`, `font-weight: 600` |
| Counter-Format | `Mitfahrt 3/4` (besetzt/Plätze gesamt). Falls keine Plätze angeboten: Label `Mitfahrt anbieten`. Falls voll: Label `Mitfahrt voll`, Farbe `var(--color-on-surface-variant)`. |
| Tap-Bereich | gesamte Footer-Zeile (`min-height: 36px`), öffnet `CarpoolOfferSheet` |
| Active-State | `background: var(--color-surface-container); border-radius: var(--radius-md); margin: var(--space-2) calc(-1 * var(--space-2)) 0` (negative margin um Card-Padding zu überlappen, damit Background bis an die Card-Edge reicht) |
| Affordance | rechts ein `chevron_right`-Icon, `var(--color-on-surface-variant)`, `1rem`, signalisiert "es geht weiter" |

**Position-Begründung:** Footer (eigene Zeile unten) statt Header-Zeile, weil:
1. Carpool ist **Sekundär** zur Aufstellung (kein Carpool wenn man nicht spielt).
2. Footer-Position macht Carpool zum optionalen "Drilldown am Ende" — User scannt zuerst die Aufstellung, dann erst Carpool.
3. Header-Zeile ist schon dicht (Datum + Badge).

### 6.11 Kapitän-Edit-Icon

```
┌────────────────────────────────────────────────────────┐
│ So, 27. Apr · 09:30 Uhr        [ LIGA ]      ⋯        │  ← Header mit Edit
│ Heim · vs. SKK Wr. Neudorf 2                           │
│ ...                                                    │
└────────────────────────────────────────────────────────┘
```

| Element | Token |
|---|---|
| Position | rechts in der Header-Zeile, **nach** dem Bewerb-Badge |
| Icon | `edit` (oder `more_horiz` falls eine Sammlung von Aktionen entsteht — Phase B: nur `edit`) |
| Größe | Icon `1.1rem`, Tap-Button 36 × 36 px (Padding 8 px), Tap-Effective-Area 44 × 44 px durch Outset-Hit |
| Background | `transparent` default, `color-mix(in srgb, var(--color-primary) 8%, transparent)` on hover |
| Color | `var(--color-on-surface-variant)` default, `var(--color-primary)` on hover/focus |
| Border-Radius | `var(--radius-full)` |
| `aria-label` | `Aufstellung bearbeiten` |
| Tap | öffnet bestehendes `AdminAufstellung`-Sheet mit `match_id` |

**Dezent vs. prominent:** **Dezent** — Begründung: das ist eine Power-User-Aktion (nur ~2 Kapitäne im Verein). Prominenter Edit-Button würde Spieler verwirren ("muss ich da was tun?"). Dezent + on-hover-Akzent reicht. Falls in der Praxis Kapitäne ihn übersehen, kann Phase E das Icon-Tinten konsistent zu `var(--color-primary)` setzen.

**Sichtbarkeit:** Icon nur für `playerRole === 'kapitaen'`. Spieler sehen den Slot im Header gar nicht — kein leerer Platz, kein Spacer. Layout adaptiert via flex.

---

## 7. Spacing & Rhythm — Tabelle

| Stelle | Token | Begründung |
|---|---|---|
| Tab-Container Padding-Top | `var(--space-4)` | konsistent mit Dashboard-v2 |
| Tab-Container Padding-Bottom | `calc(var(--nav-height) + var(--space-5))` | Bottom-Nav-Clearance |
| Section-Header Padding-X | `var(--space-5)` | matched `.mw-card`-Margin von `var(--space-4)` plus 4 px optisch (Header schiebt sich nicht ganz an Card-Edge) |
| Section-Header Margin-Bottom | `var(--space-3)` | |
| Section-zu-Section Abstand | `var(--space-6)` | klare Zeitabschnitt-Trennung |
| Card Padding (innen) | `var(--space-4)` | aus `.mw-card` — nicht override-en |
| Card-Margin (außen, X+Y) | `0 var(--space-4) var(--space-3)` | Override des `.mw-card`-Defaults von `var(--space-4)` auf `var(--space-3)` für die Spiele-Tab-Cards (dichter — siehe §10) |
| Slot-Reihe Gap (intern) | `var(--space-2)` | |
| Slot-Reihe Padding-Y | `6px` | bringt min-height auf 44 px bei 28 px Avatar |
| Footer (Carpool) Padding-Top | `var(--space-2)` | über der Trennlinie |
| Edit-Icon Margin-Left | `var(--space-1)` | in Header neben Bewerb-Badge |

---

## 8. Reuse-Constraints (zwingend)

Frontend-dev darf **nur** dies importieren bzw. reusen:

### Bestehende CSS-Klassen

| Klasse | Quelle | Verwendung in Spiele-Tab |
|---|---|---|
| `.mw-card` | `app.css` Zeile 3040 | Result-Card + Match-Card + Empty-Card |
| `.mw-badge`, `.mw-badge--primary` | `app.css` Zeile 3078 | Bewerb-Badge in beiden Card-Typen |
| `.mw-btn`, `.mw-btn--primary` | `app.css` Zeile 3099 | Kapitän-"Ergebnis eintragen"-Button |

### Bestehende Helper

| Helper | Quelle | Verwendung |
|---|---|---|
| `imgPath(photo, name)` | `$lib/utils/players.js` | Slot-Avatar |
| `shortName(player)` | `$lib/utils/players.js` | Slot-Name |
| `BLANK_IMG` | `$lib/utils/players.js` | Avatar-Fallback bei `onerror` |
| `BEWERB_LABEL` | `$lib/constants/competitions.js` | Bewerb-Badge-Text für Turnier/Landesbewerb-Matches |
| `fmtDate(d)` | `$lib/utils/dates.js` | `'So, 27. Apr'` |
| `fmtTime(t)` | `$lib/utils/dates.js` | `'09:30 Uhr'` |
| `daysUntil(dateStr)` | `$lib/utils/dates.js` | 14-Tage-Fenster-Berechnung |
| `triggerToast(msg)` | `$lib/stores/toast.js` | Confirm-Fehler, Disabled-State-Hinweis |

### Bestehende Sheets (NICHT neu bauen)

| Sheet | Verwendung |
|---|---|
| `ResultEntrySheet` | Kapitän öffnet zum Score-Nachtragen |
| `CarpoolOfferSheet` | jeder öffnet zum Mitfahren / Anbieten |
| `AdminAufstellung` | Kapitän öffnet zum Lineup-Editieren |
| `BottomSheet` | falls eine Decline-Bestätigung gebaut wird (siehe §6.9) |

### Verboten

- Neue `--color-*`-Definitionen.
- `rgba(0, 0, 0, x)` für Schatten — alle Schatten via `var(--shadow-card)` oder existierende `box-shadow`-Patterns aus `.mw-btn--primary`.
- Hardcoded Hex-Farben außerhalb der Tokens.
- `<emoji>` als Funktions-Icons (Material Symbols only). Emojis nur falls explizit als Persönlichkeits-Element gebraucht (z. B. im Empty-State darf ein `📅` stehen, aber selbst da ist Material `event_busy` vorzuziehen).
- Neue `font-family`. Nur `var(--font-display)` und `var(--font-body)`.
- Neue Spacing-Werte außerhalb `--space-*`-Skala.

---

## 9. A11y Notes

| Element | Anforderung |
|---|---|
| Slot-Reihe (mein) | `role="button"`, `tabindex="0"`, `aria-pressed={confirmed}` (true wenn confirmed), `aria-label="Slot 3, Ben Seiberl, Status: offen, Antippen zum Bestätigen"` |
| Slot-Reihe (fremd) | KEIN `role="button"`. Nur `aria-label="Slot 1, Lukas Huber, zugesagt"` auf einem `<div>` mit `role="listitem"`. |
| Slot-Container | `role="list"`, `aria-label="Aufstellung"` |
| Avatar `img` | `alt={player.name}` (voller Name, nicht Kurzname) |
| Confirm-Status | nicht nur Farbe — Icon **und** Text (`Zugesagt` / `Offen` / `Abgesagt`) sind beide für Screen-Reader vorhanden. Visuell auch sichtbar. |
| Decline-Icon-Button | `aria-label="Slot absagen"`, `type="button"` |
| Carpool-Footer | `role="button"`, `aria-label="Mitfahrt: 3 von 4 Plätzen besetzt. Antippen zum Öffnen."` |
| Kapitän-Edit-Icon | `aria-label="Aufstellung bearbeiten"`, `aria-haspopup="dialog"` |
| Result-Card (Score) | `aria-label="Spiel vom 19. April: 5700 zu 5432 gegen SKK Wiener Neudorf 2 — gewonnen"` (Win/Loss als Wort, nicht Symbol) |
| Result-Card unscored Button | `aria-label="Ergebnis eintragen für Spiel vom 19. April"` |
| Tap-Targets | mindestens 44 × 44 px effektiv. Slot-Zeile via `min-height: 44px`. Decline-Icon via 6 px Outset-Padding. Edit-Icon via 8 px Padding. |
| Focus-Outline | mein Slot bei Keyboard-Focus: `outline: 2px solid var(--color-primary); outline-offset: 2px`. Decline-Icon: `outline: 2px solid var(--color-primary); outline-offset: 1px`. |
| Keyboard-Navigation | Tab durchläuft: Carpool-Footer → Edit-Icon → mein Slot → Decline-Icon → nächste Card (in Reihenfolge der DOM-Elemente). Result-Cards: Kein Focus für Spieler-Sicht (nicht tap-bar); Kapitän-Sicht: nur der "Ergebnis eintragen"-Button ist focus-bar. |

---

## 10. Edge Cases

| Fall | Verhalten |
|---|---|
| Match liegt **heute** in der Vergangenheit (Spiel war heute Vormittag) | Erscheint in **Letzte Ergebnisse** sobald Score eingetragen ist. Vor Score-Eintrag erscheint es bei Spielern weder oben noch unten (es ist nicht "kommend", nicht "Ergebnis"). Bei Kapitän erscheint es in **Letzte Ergebnisse** mit unscored-State (§5.4) — bewusst, damit der Kapitän an die Aktion erinnert wird. |
| Keine Aufstellung published | Match-Card zeigt 4 leere Slots (`Frei`). "Mein Slot"-Logik geht nicht — kein Tint, kein DU-Marker. Bewerb-Badge + Datum + Carpool bleiben. |
| Aufstellung published aber ich bin nicht drauf | Card erscheint normal, aber **kein** Slot ist als "mein" markiert. Card ist passive Information. Carpool-Badge bleibt tap-bar (man kann auch ohne zu spielen mitfahren / als Fan). |
| Kapitän-Edit auf einer Card ohne Aufstellung | Edit-Icon öffnet trotzdem `AdminAufstellung` — dort kann der Kapitän die initiale Aufstellung erstellen. |
| Match in 16+ Tagen | Nicht im 14-Tage-Fenster → erscheint nicht. Wenn Saison frisch startet und nichts in 14 Tagen ist: Empty-Row §4. |
| Mehrere Spiele am gleichen Tag (z.B. Doppelrunde) | Beide Cards untereinander, gleicher Datum-Text. Optional: Cards eines Tages in einem Sub-Header gruppiert (`So, 27. Apr` über beiden Cards). **Phase B: keine Gruppierung** — zwei Cards mit jeweils komplettem Datum. Lieber redundant als implizit. |
| Aufstellung hat 5+ Slots (einige Ligen?) | Spec geht von 4 fix aus (KV WN Liga = 4 Bahnen). Wenn `lineup.players.length > 4`: alle Slots rendern, Card wird höher. Kein Truncation, keine "+N"-Pille. |
| Alle 4 Slots haben "Offen" | Card zeigt das so an — kein Edge-Case-Wrapping nötig. Mein Slot bleibt visuell hervorgehoben falls ich auf der Aufstellung bin. |
| Carpool: Heim-Match | Carpool-Footer wird **ausgeblendet**. Heim heißt jeder fährt selbst zum eigenen Lokal. (Auswärts-Tag-Logik in Header-Subline: "Heim" steht da, nicht "Auswärts" → Footer-Logik kann darauf hängen.) |
| Mein Slot: ich bin Kapitän + auf der Aufstellung | DU-Marker bleibt. Edit-Icon im Header bleibt auch. Kein Konflikt. |

---

## 11. Motion

Alle Transitionen sind **purpose-driven**, max 200 ms, nur `transform` und `opacity` (Performance, GPU-accelerated).

| Stelle | Motion | Dauer | Easing |
|---|---|---|---|
| Slot-Tap (mein) | `transform: scale(0.98)` | 80 ms | `ease` |
| Slot-State-Wechsel pending → confirmed | Status-Indikator: `opacity 0 → 1`, neuer Icon faded ein, alter Icon faded raus simultan | 150 ms | `ease-out` |
| Slot-Background-Tint-Wechsel | `background: ...` mit `transition: background 150ms ease` — **NICHT** auf `box-shadow` transitionen (laggy) | 150 ms | `ease` |
| Carpool-Footer Tap | `transform: scale(0.98)` | 80 ms | `ease` |
| Edit-Icon Hover | `background-color`-Fade | 150 ms | `ease` |
| Card-Erscheinen beim ersten Mount | optional `.animate-fade-float` (existiert global) — 1× pro Card mit `--i`-Stagger wie Dashboard. **Nicht** beim Refetch wiederholen. |
| Sheet-Öffnen | bereits Teil der `BottomSheet`-Komponente — nicht hier definieren |
| Card-zu-Card Hover/Active | **kein** Hover-State für Result-Cards (nicht tap-bar in Phase B). Match-Cards: nur Slot, Carpool, Edit haben Active-States. |

**Ausdrücklich NICHT:**
- Kein Layout-Shift beim Confirm (Card-Höhe bleibt stabil).
- Keine Slide-In von rechts beim Tab-Wechsel — der Top-Tab-Switch ist instant.
- Keine `@keyframes`-Pulse auf "Tippen zum Bestätigen" — das wäre dekorativ und erzeugt Aufmerksamkeits-Lärm. Statisch reicht.

---

## 12. Open Questions for User

1. **Confirm-Logik:** Soll die `mein-Slot`-Tap-Action ein 3-State-Toggle sein (pending → confirmed → declined → pending) oder soll Decline einen separaten kleinen Icon-Button rechts haben (siehe §6.9)? Die Spec geht aktuell von **separater Decline-Icon** aus, weil Decline destruktiv ist. Frontend-dev / planner: bitte mit existierender RPC abgleichen — wenn die nur `confirmed/pending` toggelt, Decline-Icon kann später rein.

2. **Carpool bei Heim-Matches:** Die Spec sagt: Footer ausblenden bei Heim. Bestätigt? (Alternative: bei Heim-Matches als "Anfahrts-Treff" reused — z. B. "Kommst du eher an die Bar oder direkt an die Bahn?". Aus Phase B wahrscheinlich out-of-scope.)

3. **Bewerb-Badge "LIGA":** `BEWERB_LABEL` deckt Turniere und Landesbewerbe ab. Liga-Matches haben kein eigenes Bewerb-Label. Die Spec verwendet hartcodiertes `'Liga'`. Falls bevorzugt: Der Liga-Name aus `matches.leagues.name` (z. B. `Landesliga`) als Badge — kürzer und konkreter. **Empfehlung Designer:** `matches.leagues.name`, gekürzt auf max 12 Zeichen, wenn vorhanden, sonst `'Liga'`.

4. **Result-Card Tap:** Phase B ist hier passiv. Soll bereits in Phase B ein Drilldown ins Match-Detail (z. B. via existierendes `MatchDetailSheet`) verdrahtet werden, oder erst in Phase D? **Empfehlung:** Phase D — vermeidet Cross-Phase-Abhängigkeit.
