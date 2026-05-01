# `is_demo`-Pattern fuer Mock-Daten (FOUND-06)

**Phase:** 0 (Cross-Cutting Foundations)
**Pitfall-Quelle:** `.planning/research/PITFALLS.md` C10 (Mock-Daten-Cleanup)
**Erstmals angewendet in:** Phase 4 STAT-03 (`league_standings`), STAT-05 (Mock-Seed JHV-Demo)
**Cleanup-Migration:** Phase 5 DEMO-03

## Regel

Jede neue v1-Tabelle, die Mock-Seeds fuer JHV-Demo aufnehmen kann, bekommt eine `is_demo`-Spalte:

```sql
ALTER TABLE <table> ADD COLUMN is_demo BOOLEAN DEFAULT false NOT NULL;
```

Bei einer komplett neuen Tabelle ist die Spalte direkt im `CREATE TABLE` enthalten.

## Anwendung

### 1. Beim Insert von Mock-Daten

```sql
INSERT INTO <table> (..., is_demo) VALUES (..., true);
```

Production-Daten lassen `is_demo` weg -> DEFAULT `false` greift.

### 2. Beim Read in Production-Views

```sql
-- View fuer Production-UI: filtert Mock-Daten raus
CREATE VIEW v_<table>_live AS
  SELECT * FROM <table> WHERE NOT is_demo;
```

ODER inline im Query:

```sql
SELECT * FROM <table> WHERE NOT is_demo ORDER BY ...;
```

### 3. Cleanup post-JHV (Phase 5 DEMO-03)

```sql
-- Idempotente Cleanup-Migration, deploybar nach JHV-Demo
DELETE FROM <table> WHERE is_demo;
```

Diese Migration ist VORBEREITET (commited als File), aber NICHT auto-applied. Manuell freigegeben nach JHV.

## Wo NICHT anwenden

**Bestehende Tabellen NICHT retroaktiv aendern.** `players`, `matches`, `game_plans`, `training_*`, `events`, etc. enthalten Real-Daten. Eine `ADD COLUMN is_demo` retroaktiv:
- Erzeugt Default-Spalte ohne semantischen Wert
- Verlangt Backfill-Strategie (welche Rows sind heute "demo"? Antwort: KEINE)
- Loest Pitfall C10 nicht (Cleanup-Pfad existiert nicht fuer Bestandsdaten)

**Regel:** `is_demo` nur auf Tabellen die in Phase 1-4 NEU erstellt werden UND Mock-Seeds aufnehmen.

## Erste Anwendung (Phase 4)

`league_standings`-Tabelle (STAT-03):

```sql
CREATE TABLE public.league_standings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id   UUID NOT NULL REFERENCES public.leagues(id),
  team_name   TEXT NOT NULL,
  is_kvwn     BOOLEAN NOT NULL DEFAULT false,
  points      INT NOT NULL DEFAULT 0,
  games       INT NOT NULL DEFAULT 0,
  season      TEXT NOT NULL,
  is_demo     BOOLEAN NOT NULL DEFAULT false,  -- FOUND-06 Pattern
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Mock-Seed (STAT-05) inserted Rows mit `is_demo = true` fuer JHV.

Cleanup (DEMO-03) ist `DELETE FROM public.league_standings WHERE is_demo;`.

## Audit / Verifikation

Wo Mock-Daten existieren:

```sql
SELECT 'league_standings' AS tbl, COUNT(*) AS demo_rows
FROM public.league_standings WHERE is_demo
UNION ALL
SELECT '<andere_table>', COUNT(*) FROM public.<andere_table> WHERE is_demo;
```

Erwartet vor JHV: `>0` Rows. Nach DEMO-03 Cleanup: `0` Rows.

## Referenzen

- Pitfall: `.planning/research/PITFALLS.md` C10
- REQ-Definition: `.planning/REQUIREMENTS.md` Section FOUND-06
- Erste Anwendung: `.planning/REQUIREMENTS.md` Section STAT-03 + STAT-05
- Cleanup: `.planning/REQUIREMENTS.md` Section DEMO-03
