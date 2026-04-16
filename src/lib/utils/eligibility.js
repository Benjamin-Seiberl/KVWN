// Eligibility-Engine für Nennlisten-Regeln
//
// Tier-Reihenfolge: Bundesliga=1 (höchste) < Landesliga=2 < A-Liga=3 < B-Liga=4
//
// Regeln:
//  - Pro Runde (round_code) darf ein Spieler nur in *einer* Mannschaft spielen.
//  - Nennliste-Positionen 1..4 einer Liga sind auf diese Liga "locked".
//  - Positionen 5..6 dürfen eine Liga nach unten (Tier N und N+1).
//  - Nicht-genannte Spieler (kein Eintrag in team_rosters für die Saison)
//    dürfen überall — sofern sie in der Runde noch nicht eingesetzt sind.
//
// Parameter:
//  match: { team_id, round_code, league_tier }
//  allPlayers: Array<{ id, name, ranking_pos, active }>
//  rosters: Array<{ team_id, player_id, position, league_tier, league_name }>
//  lineupsByRound: { [round_code]: Array<{ team_id, league_tier, league_name, player_ids: string[] }> }
//
// Rückgabe: Array<{ player, eligible: boolean, reason?: string }>

export const LOCKED_POS_MAX = 4;

export function classifyPlayer({
  match,
  player,
  rosters,
  lineupsByRound,
}) {
  // 1) Schon in dieser Runde in einer anderen Mannschaft?
  const inRound = lineupsByRound?.[match.round_code] ?? [];
  const conflict = inRound.find(l =>
    l.team_id !== match.team_id && (l.player_ids || []).includes(player.id)
  );
  if (conflict) {
    return {
      eligible: false,
      reason: `Bereits in Runde ${match.round_code} für ${conflict.league_name} eingesetzt`,
    };
  }

  // 2) Nennlisten-Eintrag für diesen Spieler
  const roster = (rosters || []).filter(r => r.player_id === player.id);

  // Kein Nennlisten-Eintrag → darf überall
  if (roster.length === 0) {
    return { eligible: true };
  }

  // Finde den "höchsten" Eintrag (kleinstes Tier = höchste Liga)
  const top = [...roster].sort((a, b) => a.league_tier - b.league_tier)[0];

  // Locked (Position ≤ 4) auf genau diesem Tier
  if (top.position <= LOCKED_POS_MAX) {
    if (top.league_tier === match.league_tier) return { eligible: true };
    return {
      eligible: false,
      reason: `Nennliste-Position ${top.position} ${top.league_name} — in dieser Liga nicht zugelassen`,
    };
  }

  // Position ≥ 5: darf top.league_tier oder top.league_tier + 1
  if (match.league_tier === top.league_tier || match.league_tier === top.league_tier + 1) {
    return { eligible: true };
  }
  return {
    eligible: false,
    reason: `Nennliste-Position ${top.position} ${top.league_name} — nur eine Liga tiefer erlaubt`,
  };
}

export function eligiblePlayers({ match, allPlayers, rosters, lineupsByRound }) {
  return (allPlayers || []).map(p => ({
    player: p,
    ...classifyPlayer({ match, player: p, rosters, lineupsByRound }),
  }));
}
