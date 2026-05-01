# Aufstellung Player-Cards Design Spec

**TLDR**
- Phase 2 des AdminAufstellung-Sheets bekommt eine vertikale 1-Karte-pro-Reihe Spieler-Liste mit hochformatigem Foto links, Name + Stats rechts, Off-White Card mit goldenem Stat-Akzent und rotem Border-Left.
- Neue Sektion "Schon gespielt" oben (nur sichtbar wenn nicht-leer) zeigt Spieler aus der aktuellen Runde als runde Avatare mit Round-Code-Badge.
- PillSwitcher schaltet Sortierung Form5 (default) ↔ Saison-∅ — die aktive Spalte in jeder Card wird visuell verstärkt.
- Lineup-Slots (4 Positionen) bleiben als kompakte 2×2 Mini-Card-Grid oberhalb des Pools, nicht als full-size PlayerCards (würde 4 weitere Bildschirmhöhen kosten).

---

## Intent

Der Kapitän öffnet das Sheet 30 Minuten vor dem Spiel auf dem Handy, sieht in 2 Sekunden wer Top-Form hat (letzte 5 Spiele), wer in derselben Runde schon im Einsatz war (Doppelspiel-Vermeidung), und kann mit einem Tap einen Spieler in die Aufstellung verschieben. Die hochwertige Card-Optik signalisiert: das hier ist die Kernaufgabe der App, nicht eine Nebenfunktion.

## Information hierarchy

1. **Primary**: PlayerCards im Pool — Form5-Wert mit goldenem Akzent dominiert visuell, Name groß, Foto als Anker.
2. **Secondary**: Aufstellungs-Slots (4 Positionen) als kompakte Mini-Cards mit Position-Nummer; "Schon gespielt"-Sektion mit Runden-Avataren.
3. **Tertiary**: Match-Hero (Datum, Gegner, Liga, Round-Pill) — bleibt oben, dezent; Sort-Toggle als ruhiger Switch über dem Pool.

## Layout (Phase 2 — Aufstellung bearbeiten)

```
┌────────────────────────────────────────────────┐
│  Sheet-Handle                                   │
│ ┌────────────────────────────────────────────┐ │
│ │ [So 19. Apr]  KV vs SK Wr. Neustadt        │ │  Match-Hero (bestehend)
│ │              Bundesliga · Runde H03        │ │
│ └────────────────────────────────────────────┘ │
│                                                 │
│  SCHON GESPIELT IN DIESER RUNDE                 │  Eyebrow (nur wenn ≥1)
│  (●H03)(●H03)(●H03)                             │  Runden-Avatare 44px
│                                                 │
│  AUFSTELLUNG                                    │  Eyebrow
│ ┌────────────┬────────────┐                    │
│ │ ● Pos 1    │ ● Pos 2    │                    │  Mini-Slot-Cards
│ │   Müller   │   leer     │                    │  2×2 Grid
│ ├────────────┼────────────┤                    │
│ │ ● Pos 3    │ ● Pos 4    │                    │
│ │   leer     │   leer     │                    │
│ └────────────┴────────────┘                    │
│                                                 │
│  VERFÜGBARE SPIELER         [Letzte 5 | ∅]    │  Header + Sort-Toggle
│ ┌────────────────────────────────────────────┐ │
│ │┌──┐                            FORM5  ∅    │ │
│ ││📷│  Max Mustermann            [462]  438  │ │  PlayerCard
│ │└──┘  Eligible · 1. Mannschaft               │ │  (1 pro Reihe)
│ └────────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────────┐ │
│ │┌──┐                            FORM5  ∅    │ │
│ ││📷│  Lukas Bauer               [451]  445  │ │
│ │└──┘                                          │ │
│ └────────────────────────────────────────────┘ │
│  ...                                            │
└────────────────────────────────────────────────┘
```

## Section order rationale

Match-Hero → Schon-gespielt → Aufstellung-Slots → Sort-Toggle → Pool. Begründung: der Kapitän muss zuerst sehen WAS er aufstellt (Match), dann WER nicht doppelt darf (Schon gespielt), dann den aktuellen Stand (Slots), dann die Auswahl (Pool). Sort-Toggle direkt vor dem Pool, weil er nur diesen beeinflusst.

## PlayerCard (Kernbaustein)

### Geometrie

- **Card**: Höhe 96 px, volle Sheet-Breite minus `var(--space-4)` Seitenrand, `border-radius: var(--radius-lg)` (alle 4 Ecken — siehe Foto-Entscheidung unten), `overflow: hidden`.
- **Foto-Spalte**: 72 px breit × 96 px hoch (Hochformat), bleibt komplett links bündig, `object-fit: cover; object-position: top center`.
- **Body-Spalte**: `flex: 1`, Padding `var(--space-3) var(--space-4)`, vertikal zentriert.
- **Stats-Spalte**: rechtsbündig, Padding `var(--space-3) var(--space-4)`, fixed width 96 px (zwei Spalten Form5/Saison nebeneinander).

### Foto-Ecken — Entscheidung

User-Anforderung wörtlich: "das spieler bild links und hoch keine gerundete ecken". Lesart: das Foto soll scharfkantig wirken, nicht weichgezeichnet. Lösung:

- **Card** hat `border-radius: var(--radius-lg)` an allen 4 Ecken (premium look).
- **Foto** wird im Card-Container von `overflow: hidden` an den linken Ecken automatisch geclippt, BEHÄLT aber visuell die Anmutung scharfer Kanten, weil `var(--radius-lg)` (12 px) bei 96 px Höhe nur eine subtile Rundung ist und das Foto bis zu Top, Bottom und Left fully bleed reicht. KEINE explizite `border-radius` am `<img>` — es soll wie ein Foto, nicht wie ein Avatar wirken.
- Visueller Effekt: die linke Foto-Kante ist eine harte vertikale Linie über die ganze Card-Höhe, oben/unten subtil mitgerundet vom Card-Clip. Das ist der "Polaroid-eingebettet"-Look — premium, nicht avatar-igsy.

### Hintergrund + Border

- **Background**: Off-White mit Wärme — `color-mix(in srgb, var(--color-surface-container-lowest) 94%, var(--color-secondary))`. Begründung: reines `--color-surface-container-lowest` wirkt klinisch; ein 6%-Gold-Touch macht die Card "warm", unterstützt die Premium-Anmutung.
- **Border-Left**: `4px solid var(--color-primary)` — Akzent-Strip wie in `NextTrainingCard.svelte`. Macht die Card identitätsstark KV-rot ohne dass das Foto rot getönt wird.
- **Border (Rest)**: `1px solid color-mix(in srgb, var(--color-outline-variant) 60%, transparent)` an oben/rechts/unten.
- **Box-Shadow**: `var(--shadow-card)`.

### Body (Mitte)

- **Name**: `var(--font-display)`, weight 700, `font-size: var(--text-title-md)` (1 rem), `color: var(--color-on-surface)`, `line-height: 1.2`. Verwendung von vollem Namen (NICHT `shortName`) — im Pool ist Platz, und der Kapitän will die Person eindeutig erkennen.
- **Sub-Info** (eine Zeile, optional): `var(--font-body)`, `var(--text-label-md)` (0.75 rem), `color: var(--color-on-surface-variant)`. Inhalt-Priorität (zeige nur 1):
  1. Wenn `absences` enthält pid: "Abwesend" in `var(--color-primary)`.
  2. Wenn nicht eligible für diese Liga: "Nicht spielberechtigt".
  3. Sonst: Roster-Zugehörigkeit (z. B. "1. Mannschaft").

### Stats (Rechts)

Zwei vertikale Stacks nebeneinander, je 44 px breit:

```
FORM5    ∅
[462]   438
```

- **Eyebrow** (Label oben): `var(--font-display)`, weight 700, `font-size: 0.625rem` — 10 px ist nötig für "FORM5"; `--text-label-sm` (0.6875rem) ist die nächstgrößere Token-Option und akzeptabel. Letterspacing 0.08em, uppercase, `color: color-mix(in srgb, var(--color-secondary) 80%, var(--color-on-surface))`.
- **Wert** (Zahl unten): `var(--font-display)`, weight 700, `font-size: var(--text-title-md)` (1rem), `color: var(--color-on-surface)`. Bei fehlendem Wert: `–` in `var(--color-on-surface-variant)`.
- **Aktive Sort-Spalte** (Form5 oder Saison) zusätzlich:
  - Eyebrow weight 800, `color: var(--color-secondary)` (volles Gold statt mix).
  - Wert in einer goldenen Pill: `background: color-mix(in srgb, var(--color-secondary) 14%, transparent)`, `padding: 2px 8px`, `border-radius: var(--radius-md)`.
  - Inaktive Spalte: opacity 0.7.

### Action-States (Overlay auf Foto)

- **Im Lineup**: rechts-oben auf dem Foto eine Position-Pill `Pos 1` — `background: var(--color-secondary)`, `color: var(--color-on-secondary)` (dunkles Browntone, im Token), `padding: 2px 6px`, `border-radius: var(--radius-md)`, `font: 700 var(--text-label-sm)/1 var(--font-display)`, `position: absolute; top: 4px; right: 4px` (relativ zum Foto-Container). Die ganze Card hat zusätzlich einen subtilen Gold-Glow: `box-shadow: var(--shadow-card), 0 0 0 1.5px color-mix(in srgb, var(--color-secondary) 40%, transparent)`.
- **Abwesend**: Card opacity 0.55, Name mit `text-decoration: line-through; text-decoration-color: var(--color-primary)`. Kein Action-Indikator nötig — die Sub-Info-Zeile sagt es bereits.
- **Nicht eligible**: Card opacity 0.7, ansonsten unverändert. Card bleibt klickbar (sortier-Logik kennt sie), aber Tap zeigt Toast "Nicht spielberechtigt" statt Lineup-Add.
- **Schon in Runde gespielt**: Card erscheint NICHT im Pool — wird in "Schon gespielt"-Sektion oben gerendert. Saubere mentale Trennung.

## "Schon gespielt"-Sektion

- **Sektion-Header**: `var(--font-display)`, weight 700, `font-size: var(--text-label-md)` (0.75 rem), uppercase, letter-spacing 0.06em, `color: var(--color-on-surface-variant)`. Text: `Schon gespielt in dieser Runde`. Margin `var(--space-4) 0 var(--space-2)`.
- **Layout**: `display: flex; flex-wrap: wrap; gap: var(--space-3); padding: 0 var(--space-1)`.
- **Runden-Avatar** (1 pro betroffenem Spieler):
  - Container: `position: relative; width: 56px; height: 64px` (Avatar 48 px + Badge-Überstand + Name-Stub).
  - Foto: 48×48 px, `border-radius: 50%`, `border: 2px solid var(--color-secondary)`, `box-shadow: 0 2px 6px color-mix(in srgb, var(--color-primary) 18%, transparent)`.
  - Round-Badge (unten rechts auf Foto): `position: absolute; bottom: 12px; right: -2px`, `background: var(--color-primary)`, `color: white`, `padding: 1px 5px`, `border-radius: var(--radius-full)`, `font: 800 var(--text-label-sm)/1 var(--font-display)`. Inhalt: `selectedMatch.round_code` (z. B. `H03`). Pattern angelehnt an `.sb-me-badge`.
  - Optional: kleine Initialen-Zeile darunter (`shortName(name)`, 2 Wörter, `var(--text-label-sm)`, `var(--color-on-surface-variant)`, text-align center, max-width 56 px, ellipsis). Verbessert Erkennbarkeit ohne Tap.
- **Empty-State**: Sektion komplett ausblenden (kein Header, kein Container). Nicht "leer-anzeigen" — der Kapitän soll bei freier Runde keine Pseudo-Sektion sehen.
- **Tap auf Avatar**: scrollt im Pool zum Spieler-Card und highlightet sie kurz (200 ms `box-shadow` Pulse mit `var(--shadow-float)`).

## Sort-Toggle

- **Komponente**: `<PillSwitcher>` aus `$lib/components/ui/`.
- **Items** (achte auf das `key`-Feld, nicht `value` — die Komponente erwartet `key`):
  - `{ key: 'form5', label: 'Letzte 5' }`
  - `{ key: 'season', label: 'Saison-∅' }`
- **Default**: `'form5'`.
- **Position**: in derselben Zeile wie der "VERFÜGBARE SPIELER"-Header — Header links, Switcher rechts, `justify-content: space-between`. Der Switcher darf max. 180 px breit sein (sonst dehnt PillSwitcher auf full width).
- **Sortierung im Pool**: DESC nach gewähltem Feld; Spieler ohne Wert werden ans Ende geschoben (sekundärer Sort: alphabetisch nach Name).

## Aufstellungs-Slots (4 Positionen) — Mini-Card-Variante

**Entscheidung: Variante A** (kompakte 2×2 Mini-Card-Grid). Begründung: 4 Full-Size-PlayerCards würden ~400 px Höhe vor dem Pool kosten — auf einem iPhone-SE-Viewport bleibt dann kaum Pool sichtbar. Der Kapitän braucht den Pool im Sichtfeld, weil er DARAUS auswählt.

- **Mini-Slot-Card** (Größe ca. 50% Höhe einer Pool-Card, ca. 72 px hoch):
  - Selbe Card-Sprache: Off-White + 4 px roter Border-Left + `--shadow-card`.
  - Layout: `[Foto 48×48 rund | Pos-Nummer + Name | × Remove-Icon]`.
  - Foto hier RUND (`border-radius: 50%`, 48 px), weil im Slot-Kontext die Person "im Spiel" ist und ein Avatar-Look passender ist als das Polaroid-Format des Pools.
  - **Leerer Slot**: gestrichelte Border `1.5px dashed var(--color-outline-variant)`, kein Border-Left-Akzent, Plus-Icon zentriert, Text "Pos N · leer" in `var(--color-on-surface-variant)`.
  - **Belegter Slot**: Position-Badge oben links (gold pill, gleicher Stil wie das Pool-Card-Overlay), Name `var(--text-label-md)` weight 700.
- **Grid**: `display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2)`.
- **Sektion-Header**: gleicher Eyebrow-Stil wie "SCHON GESPIELT".

## Visual System Recap

- **Off-White Background** der Card: 6% Gold-Wärme, nicht klinisch.
- **Rote Akzente**: Border-Left (4 px), Round-Badge im Runden-Avatar, Abwesend-Strikethrough, Hover-Glow.
- **Goldene Akzente**: Stats-Eyebrow, aktive Sort-Pill um den Wert, Position-Badge im Lineup, Runden-Avatar-Border. Maximal 2 Gold-Touchpoints gleichzeitig sichtbar pro Card (im Default-Zustand: Eyebrow + Wert-Pill; im Lineup-Zustand: + Position-Badge — kurzfristig 3, akzeptabel).
- **Verbot**: keine Gold-Flächen über 30% der Card-Fläche; kein Gold-Gradient als Background; kein schwarzer Schatten — alle Shadows aus den `--shadow-*` Tokens.

## Interaction states

- **Default**: Card ruhig, `--shadow-card`, Border-Left rot.
- **Hover** (Desktop): `box-shadow: var(--shadow-float)`, Border-Left wird zu 5 px.
- **Active / Tap**: `transform: scale(0.99)`, 120 ms ease.
- **Selected** (im Lineup): Gold-Glow-Ring (siehe Action-States oben), Position-Badge auf dem Foto.
- **Disabled** (nicht eligible): opacity 0.7, Cursor `not-allowed` bleibt aus (Card bleibt tappable für Toast-Feedback).
- **Focus-visible**: `outline: 2px solid var(--color-secondary); outline-offset: 2px`.

## Motion

- **Card-Tap**: `transform: scale(0.99)`, 120 ms ease.
- **Sortierwechsel**: harter Re-Render, KEIN FLIP/Reorder-Animation — würde bei 15+ Spielern zu Reise-Übelkeit führen und ist Performance-Risiko.
- **Pool → Lineup verschieben**: keine Flug-Animation. Stattdessen kurzer (180 ms) Gold-Glow-Pulse auf der Ziel-Slot-Card als Bestätigung.
- **Sektion ein/ausblenden** (Schon-gespielt erscheint nach Match-Auswahl): `opacity 0 → 1` über 150 ms, kein height-Animate (CLS).

## A11y notes

- Jede PlayerCard ist `<button type="button">`. `aria-label`: `"Max Mustermann, Form fünf 462, Saison-Schnitt 438, im Lineup auf Position 1"` — komplett gesprochener Status, weil VoiceOver-Nutzer die Position-Pill sonst überlesen.
- `aria-pressed="true"` wenn im Lineup, zusätzlich zur visuellen Goldring-Markierung — Screenreader bekommen den Toggle-Status ohne Farbe.
- Sort-Toggle nutzt das bestehende `role="tab"` aus PillSwitcher (kommt gratis).
- Round-Avatar-Buttons: `aria-label="Lukas Bauer hat in Runde H03 schon gespielt, zum Pool scrollen"`.
- Color-Independent: Lineup-Status zusätzlich durch Position-Badge-Text (`Pos 1`) ausgedrückt, nicht nur durch Gold-Glow. Abwesend zusätzlich durch Strikethrough + Sub-Info-Text, nicht nur Opacity.
- Tap-Targets: PlayerCard 96 px hoch — weit über 44 px. Mini-Slots 72 px hoch. Runden-Avatare 48 px breit, OK.

## Edge cases

- **Empty Pool** (alle Eligible bereits in Lineup oder in Schon-gespielt): zentrierte Empty-State-Card mit Icon `groups`, Text "Keine weiteren Spieler verfügbar", `var(--color-on-surface-variant)`.
- **Loading**: 4 Skeleton-PlayerCards mit `.shimmer-box` (vorhanden in `app.css`). Foto-Spalte (72×96), Name-Linie (60% width × 16 px), zwei Stat-Werte (32×24 px).
- **Spieler ohne Stats** (neu, kein Score): Form5/Saison als `–`, Card sortiert ans Ende, Sub-Info "Noch keine Spielwerte".
- **Ein Spieler steht im Lineup UND ist in Schon-gespielt**: kann nicht passieren (Schon-gespielt-Filter zeigt nur Spieler, die in DIESER round_code mit `played=true` existieren — die wären beim Aufstellen automatisch geblockt). Falls doch Daten-Race: priorisiere Schon-gespielt-Sektion, nimm Spieler aus Pool/Lineup raus.
- **Sehr lange Namen**: Body-Spalte `min-width: 0; overflow: hidden`, Name `text-overflow: ellipsis; white-space: nowrap` auf einer Zeile. Verlust akzeptabel — Foto reicht zur Identifikation.
- **Save-Fehler**: bestehendes `triggerToast`-Pattern, kein UI-State-Change.

## Was bleibt unverändert (Garantie für frontend-dev)

- Phase 1 (Match-Auswahl-Liste, Z. 390–410 in `AdminAufstellung.svelte`) — komplett unverändert.
- Datenfluss: `playerStats`, `lineupsByRound`, `gamePlan`, `lineup`, `rosters`, `absences` — alle bleiben; nur Render-Layer ändert sich.
- Persistenz-Pattern `sb.from('game_plan_players').insert/upsert/delete` — unverändert.
- Match-Hero-Komponente am Sheet-Top — funktional unverändert; visuell nur an die neue Card-Sprache angepasst falls nötig (gleiches Off-White, gleicher Border-Left), aber das ist optional und kann in einem Follow-up.
