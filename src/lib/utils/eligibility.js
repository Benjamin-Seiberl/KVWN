// Eligibility-Engine für Aufstellungsregeln.
//
// Ligaorder (Tier): 1 = Bundesliga (höchste) … 4 = B-Liga (niedrigste)
//
// Regeln sind als eigenständige, benannte Funktionen implementiert.
// Jede Regel erhält einen Kontext-Snapshot und gibt entweder:
//   { eligible: boolean, reason?: string }  → Entscheidung getroffen (Kette stoppt)
//   null                                    → keine Meinung, nächste Regel befragen
//
// Neue Regeln können am Ende von ELIGIBILITY_RULES ergänzt werden, ohne
// bestehende Logik zu verändern.
//
// Kontext-Typ:
//   {
//     player:         { id: string, name: string, ...rest }
//     match:          { team_id: string, league_tier: number, round_code: string|null }
//     rosters:        Array<{ player_id, position, league_tier, league_name, team_id }>
//     lineupsByRound: { [round_code]: Array<{ team_id, league_tier, league_name, player_ids: string[] }> }
//   }

export const LOCKED_POS_MAX = 4;

// ─── Regeln ────────────────────────────────────────────────────────────────

/**
 * Regel 1: Spieler bereits in dieser Runde für eine andere Mannschaft aufgestellt.
 * Prüft anhand round_code (nicht cal_week), damit Liga-übergreifende Konflikte
 * auch bei unterschiedlichen Spielwochen erkannt werden.
 */
export function ruleAlreadyPlayedInRound({ player, match, lineupsByRound }) {
  if (!match.round_code) return null; // kein round_code bekannt → keine Aussage
  const inRound = lineupsByRound?.[match.round_code] ?? [];
  const conflict = inRound.find(l =>
    l.team_id !== match.team_id && (l.player_ids ?? []).includes(player.id)
  );
  if (conflict) {
    return {
      eligible: false,
      reason: `Bereits in Runde ${match.round_code} für ${conflict.league_name} aufgestellt`,
    };
  }
  return null;
}

/**
 * Regel 2: Nennliste-Position 1–4 ist auf die exakte Liga gesperrt.
 * Spieler mit Position ≤ LOCKED_POS_MAX dürfen nur in ihrer eigenen Liga spielen.
 */
export function ruleRosterPositionLocked({ player, match, rosters }) {
  const roster = (rosters ?? []).filter(r => r.player_id === player.id);
  if (!roster.length) return null; // kein Eintrag → keine Meinung

  const top = [...roster].sort((a, b) => a.league_tier - b.league_tier)[0];
  if (top.position > LOCKED_POS_MAX) return null; // Position 5+ → andere Regel

  if (top.league_tier === match.league_tier) return { eligible: true };
  return {
    eligible: false,
    reason: `Nennliste-Position ${top.position} ${top.league_name} — nur in dieser Liga erlaubt`,
  };
}

/**
 * Regel 3: Nennliste-Position 5–6 darf im eigenen Tier oder genau ein Tier tiefer spielen.
 */
export function ruleRosterPositionOneTierDown({ player, match, rosters }) {
  const roster = (rosters ?? []).filter(r => r.player_id === player.id);
  if (!roster.length) return null; // kein Eintrag → kein Einwand (freie Spieler)

  const top = [...roster].sort((a, b) => a.league_tier - b.league_tier)[0];
  if (top.position <= LOCKED_POS_MAX) return null; // Position 1–4 → Regel 2 zuständig

  if (
    match.league_tier === top.league_tier ||
    match.league_tier === top.league_tier + 1
  ) {
    return { eligible: true };
  }
  return {
    eligible: false,
    reason: `Nennliste-Position ${top.position} ${top.league_name} — maximal eine Liga tiefer erlaubt`,
  };
}

// ─── Regelkette ────────────────────────────────────────────────────────────
// Neue Regeln hier anhängen. Reihenfolge = Priorität (erste Entscheidung gewinnt).

export const ELIGIBILITY_RULES = [
  ruleAlreadyPlayedInRound,
  ruleRosterPositionLocked,
  ruleRosterPositionOneTierDown,
];

// ─── Öffentliche API ───────────────────────────────────────────────────────

/**
 * Klassifiziert einen einzelnen Spieler anhand der Regelkette.
 * @returns {{ eligible: boolean, reason?: string }}
 */
export function classifyPlayer(context) {
  for (const rule of ELIGIBILITY_RULES) {
    const result = rule(context);
    if (result !== null) return result;
  }
  return { eligible: true }; // kein Einwand → erlaubt
}

/**
 * Klassifiziert alle Spieler auf einmal.
 * @returns Array<{ player, eligible, reason? }>
 */
export function eligiblePlayers({ match, allPlayers, rosters, lineupsByRound }) {
  return (allPlayers ?? []).map(player => ({
    player,
    ...classifyPlayer({ player, match, rosters, lineupsByRound }),
  }));
}
