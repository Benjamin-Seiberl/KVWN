import { leagueTiming } from '$lib/utils/league.js';

// Returns true if the match (with date + time) has ended, inclusive of
// arrival, match duration, and a delay buffer. Shared helper to keep
// the "ended" semantics consistent across the app.
export function matchEnded(m) {
	if (!m?.date || !m?.time) return false;
	const t = leagueTiming(m.leagues?.name ?? m.league_name);
	const endMs = new Date(`${m.date}T${m.time}`).getTime()
		+ (t.arrivalOffsetMin + t.matchDurationMin + t.delayBufferMin) * 60_000;
	return Date.now() > endMs;
}
