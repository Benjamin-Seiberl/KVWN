// League-specific timings for the Spielbetrieb workflow.
// Kegeln (not football): Bundesliga/Landesliga dauern 3 h, A-Liga/B-Liga 2 h.
// Ankunft: Bundesliga/Landesliga 60 min davor, A-Liga/B-Liga 40 min davor.

export function leagueTiming(leagueName) {
	const n = (leagueName ?? '').toLowerCase();
	const isTop = n.includes('bundesliga') || n.includes('landesliga');
	return {
		isTop,
		arrivalOffsetMin: isTop ? 60 : 40,
		matchDurationMin: isTop ? 180 : 120,
	};
}

// match.time is "HH:MM:SS" or "HH:MM". Adds offset minutes, returns "HH:MM".
export function offsetTime(timeStr, offsetMin) {
	if (!timeStr) return null;
	const [h, m] = timeStr.split(':').map(Number);
	const total = h * 60 + m + offsetMin;
	const mm = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
	const hh = Math.floor(mm / 60);
	const rem = mm % 60;
	return String(hh).padStart(2, '0') + ':' + String(rem).padStart(2, '0');
}

// "HH:MM:SS" or "HH:MM" -> "HH:MM"
export function shortTime(timeStr) {
	return timeStr ? timeStr.slice(0, 5) : '';
}
