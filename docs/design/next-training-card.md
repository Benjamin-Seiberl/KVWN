# NextTrainingCard — Redesign Spec

## TL;DR (was sich visuell ändert)
1. **Goldener Akzent** statt rotem: Border-Left, Datum-Badge, Section-Icon und Label wechseln auf KVWN-Gold (`--color-secondary`). Kein roter Border mehr.
2. **Kompakter**: Card-Padding `--space-3` (war `--space-4`), Datum-Badge `54×54px` (war `62×62`), Body-Gap `2px` bleibt — Höhe sinkt um ~14px.
3. **Tagessumme statt Slot-Zeit**: Hauptzeile zeigt Plätze (`12 / 25 frei`) für den ganzen Trainingstag. Slot-Uhrzeit fällt komplett weg.
4. **Persönlicher Status hat Vorrang**: Wenn der User gebucht/auf Warteliste ist, wird das die Hauptzeile (mit Slot-Time inline), die Tagessumme rückt darunter.

---

## Intent
Die Karte soll dem Captain bzw. Spieler in 2 Sekunden zeigen: *Wann ist das nächste Training, wie voll ist es, betrifft es mich persönlich?* Eine einzelne Slot-Uhrzeit war irreführend, weil ein Trainingstag aus mehreren stündlichen Slots besteht. Der Sheet (`TrainingDetailSheet`) zeigt die Slot-Details — die Card ist nur Trigger + Übersicht.

## Information hierarchy
1. **Primär**: Datum-Badge (gold) + Hauptzeile (entweder eigener Status oder Tagessumme).
2. **Sekundär**: Eyebrow-Label (`Heute` / `Morgen` / `In 3 Tagen` · optional ` · Sondertraining`).
3. **Tertiär**: Sub-Zeile (Warteliste-Hinweis falls voll, Note-Pill falls Sondertraining-Notiz).

## Layout (ASCII)
```
┌─────────────────────────────────────────────┐
│ ⚡ Nächstes Training              (sec-head)│
│                                             │
│ ┌───────────────────────────────────────┐   │
│ ║┌────┐  HEUTE · SONDERTRAINING         │   │
│ ║│ MO │  12 / 25 Plätze frei            │ › │
│ ║│ 28 │  4 auf Warteliste               │   │
│ ║│ APR│                                  │   │
│ ║└────┘                                  │   │
│ └───────────────────────────────────────┘   │
│   ↑ gold border-left 4px                     │
└─────────────────────────────────────────────┘
```
Strukturell unverändert: `[Badge | Body | Chevron]` als Flex-Row mit `gap: var(--space-3)`.

## Card-Container
- Background: `var(--color-surface-container-lowest)` (unverändert).
- Border-Radius: `var(--radius-xl)` (unverändert).
- Box-Shadow: `var(--shadow-card)` (unverändert — bleibt rot-getönt, das ist ok als Marken-Anker).
- **Border-Left: `4px solid var(--color-secondary)`** (vorher `--color-primary`).
- **Padding: `var(--space-3)`** (vorher `--space-4`).
- Optionaler Background-Tint (subtil, empfohlen):
  `background: linear-gradient(135deg, var(--color-surface-container-lowest) 0%, color-mix(in srgb, var(--color-secondary) 4%, var(--color-surface-container-lowest)) 100%);`
  Der 4%-Tint bleibt klar unter Lesbarkeitsschwelle und gibt der Card einen warmen Schimmer ohne Kitsch.

## Datum-Badge (gold)
- Größe: **`54×54px`** (vorher 62×62) — flex-shrink: 0.
- Border-Radius: `var(--radius-lg)` (unverändert).
- Background: `linear-gradient(135deg, var(--color-secondary), color-mix(in srgb, var(--color-secondary) 60%, black))`.
  Stops bewusst dunkler als beim alten Rot-Badge, weil reines Gold auf weiß zu hell wäre.
- Text-Color: `#fff` (unverändert) — Kontrast bleibt AA, weil der Gradient unten auf ~#7a6520 abdunkelt.
- Subtile Innenkante für Premium-Look:
  `box-shadow: inset 0 0 0 1px rgba(255,255,255,0.15);`
- Innenstruktur unverändert (DOW · Day · Month, gestackt, zentriert).
- Schriftgrößen leicht reduziert wegen kleinerer Badge:
  - DOW: `0.55rem` (war 0.6)
  - Day: `1.25rem` (war 1.4) — bleibt `var(--font-display)`, weight 800.
  - Month: `0.55rem` (war 0.6)

## Body
- `flex: 1`, gap **`3px`** (vorher 2px) — minimal mehr Atmen, weil Slot-Time-Zeile wegfällt und drei Zeilen optisch näher zusammenrücken sollten.
- Eyebrow-Label (`Heute` / `Morgen` / `In X Tagen` · optional ` · Sondertraining`):
  - Font: `0.65rem`, weight 700, uppercase, letter-spacing `0.06em`.
  - **Color: `var(--color-secondary)`** (vorher `--color-primary`).
- Hauptzeile — abhängig von State:
  - Default: `12 / 25 Plätze frei`
    - Font: `var(--font-display)`, `1rem`, weight 700, `var(--color-on-surface)`.
    - Format: `{free} / {total} Plätze frei` — kompakt, ein Wort weniger als „X von Y Plätzen frei".
  - Voll belegt: `Voll belegt`
    - Gleiche Typo, aber Color `color-mix(in srgb, var(--color-primary) 75%, var(--color-on-surface))` — gedämpftes Rot signalisiert „kein Platz" ohne Alarm.
  - User gebucht: `Du bist drin · Bahn 3 · 18:00`
    - `var(--font-display)`, `1rem`, weight 700, `var(--color-on-surface)`.
    - Slot-Time darf hier auftauchen, weil sie für den User jetzt persönlich relevant ist.
  - User auf Warteliste: `Warteliste · Position 2 · 18:00`
    - Gleiche Typo, Color `var(--color-on-surface)`.
- Sub-Zeile (nur bei „Voll belegt" oder wenn relevant):
  - `4 auf Warteliste` — `var(--text-body-sm)`, `var(--color-on-surface-variant)`.
  - Bei eigener Buchung optional: `noch X Plätze frei für andere` (entscheidet frontend-dev, ob das überflüssig ist — kann auch entfallen).
- Note-Pill (nur wenn `slot.note` existiert):
  - Unverändert (`background: var(--color-surface-container)`, `border-radius: var(--radius-full)`, `padding: 2px 8px`, `font-size: 0.7rem`, `var(--color-on-surface-variant)`).

## Chevron
- Icon: `chevron_right`, `font-size: 1.1rem` (war 1.2 — minimal kompakter).
- **Color: `color-mix(in srgb, var(--color-secondary) 50%, var(--color-outline))`** — leicht goldgetönter Outline-Ton, statt reinem Outline-Grau. Hält den goldenen Akzent in jeder Ecke der Card.

## Section-Header (sec-head)
- `sec-icon` Color: **`var(--color-secondary)`** (vorher `--color-primary`).
- `sec-title` unverändert (`var(--color-on-surface)`, display-font, weight 700, 1rem).
- Margin-Bottom unverändert (`var(--space-3)`).

## States — Mapping
| Zustand | Eyebrow | Hauptzeile | Sub-Zeile |
|---|---|---|---|
| Default (Plätze frei) | `HEUTE` | `12 / 25 Plätze frei` | — |
| Voll belegt | `HEUTE` | `Voll belegt` (gedämpftes Rot) | `4 auf Warteliste` |
| User gebucht | `HEUTE` | `Du bist drin · Bahn 3 · 18:00` | (optional) `12 / 25 Plätze frei` |
| User auf Warteliste | `HEUTE` | `Warteliste · Position 2 · 18:00` | `Voll · 4 wartend` |
| Sondertraining | `HEUTE · SONDERTRAINING` | (wie oben) | + Note-Pill falls Note vorhanden |

Hierarchie-Regel: Der **persönlichste** Fakt gewinnt die Hauptzeile. Wenn der User drin ist → Buchung. Sonst → Tagessumme. Sonst → Voll-Status.

## Interaction states
- **Default**: wie oben.
- **Hover** (Desktop): `box-shadow` von `--shadow-card` zu `--shadow-float`, 120ms ease.
- **Active / Tap**: `transform: scale(0.99)` (unverändert).
- **Focus-visible**: `outline: 2px solid var(--color-secondary); outline-offset: 2px;` — gold passt zur Card-Identität.
- **Skeleton**: unverändert — Border-Left bleibt `var(--color-outline-variant)`, Badge-Shimmer-Box `54×54px` (an neue Größe anpassen).
- **Empty**: unverändert — Border-Left `var(--color-outline-variant)`, Icon `event_busy` in `var(--color-outline)`, Text „Kein Training geplant".

## Motion
- Tap: `transform: scale(0.99)`, 120ms ease (unverändert).
- Keine Mount-Animation — die Card lebt im Dashboard-Stream und nutzt das globale `.animate-fade-float` falls der Parent das setzt.
- Kein Übergang zwischen States (Tagessumme ↔ User-gebucht ändert sich nur beim Reload, dann ist ein Flash ok).

## A11y
- `<button>` bleibt erhalten, `aria-label` erweitern auf z. B. `aria-label="Training Heute, 12 von 25 Plätzen frei. Details öffnen"` — generiert dynamisch aus den gleichen Daten wie die Hauptzeile.
- Bei Voll/eigener Buchung das aria-label entsprechend anpassen, damit Screenreader nicht die generische „Training buchen"-Meldung liefern.
- Kontrast-Check:
  - Gold-Eyebrow auf surface-container-lowest (#fff): `#D4AF37` auf weiß ist **2.3:1** — das wäre zu wenig für Body-Text, aber für **uppercase weight-700 Eyebrow ≥ 14px** zählt es als „large text" (3:1 Pflicht), und wir liegen knapp drüber. **Trotzdem absichern**: Eyebrow-Color zu `color-mix(in srgb, var(--color-secondary) 80%, black)` (~#aa8c2c) → ergibt **3.6:1**, AA für large text bestätigt.
  - Hauptzeile in `--color-on-surface`: unverändert AA.
  - Datum-Badge weiß auf Gold-Gradient: untere Hälfte des Gradients (~#7a6520) gegen Weiß = **5.8:1**, AA klar.
- Tap-Target: Card ist ≥ 70px hoch (Badge 54 + Padding 2× 12) → ok.

## Edge cases
- **Keine Slots heute, aber morgen**: Card zeigt morgen, Eyebrow „MORGEN", Tagessumme funktioniert identisch.
- **Slot ohne Capacity-Info** (sollte nie passieren, aber defensiv): Hauptzeile fällt zurück auf nur Eyebrow + Sub `Termin offen` — `frontend-dev` entscheidet das defensiv, hier nur erwähnt.
- **`daySlots` enthält gemischte Capacity** (Templates haben i.d.R. `lane_count=5`, Specials evtl. anders): Summe über alle Slots ist korrekt — `total = Σ slot.capacity`, `free = total − Σ bookings`.
- **0 Slots aber Special-Note**: nicht möglich (Special hat immer Slot). Skip.

## Was bleibt unverändert (Garantie für frontend-dev)
- Sec-head-Pattern (`.sec-head`, `.sec-icon`, `.sec-title`) — nur Icon-Color wechselt.
- Card ist `<button>`, öffnet `TrainingDetailSheet` via `bind:open={bookingOpen}`.
- Skeleton- und Empty-State-Layout (nur Badge-Größe 54px nachziehen).
- Card-Shadow (`--shadow-card`), Border-Radius (`--radius-xl`).
- Note-Pill-Styling.
- Datenfluss-Pattern (`load()` in `$effect`, Reload via `onReload={load}`).

## Was ändert sich im Datenfluss (nur als Hinweis)
- Statt einem `slot` lädt die Card jetzt `daySlots` (alle Slots des nächsten Trainingstags) + alle zugehörigen Bookings/Waitlist.
- `freeSpots` wird zur Tagessumme: `Σ capacity − Σ bookings`.
- `myBooking` / `myWait` referenzieren weiterhin den konkreten Slot, in dem der User drin ist (für die `· Bahn X · HH:MM` Sub-Info).
- Datum-Badge nutzt das Datum des Tages (alle Slots haben gleiches Datum).
