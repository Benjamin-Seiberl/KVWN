// Deterministic rotation of feedback questions.
// Each (match, player) pair gets exactly one question, but across many matches
// the same player sees many different questions. Stable over reloads.

function hashStr(str) {
	// 32-bit FNV-1a
	let h = 0x811c9dc5;
	for (let i = 0; i < str.length; i++) {
		h ^= str.charCodeAt(i);
		h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
	}
	return h >>> 0;
}

export function pickQuestion(questions, matchId, playerId) {
	if (!questions?.length) return null;
	const key = String(matchId ?? '') + '|' + String(playerId ?? '');
	const idx = hashStr(key) % questions.length;
	return questions[idx];
}
