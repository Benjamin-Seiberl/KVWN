// $lib/server/timezone.js
//
// Vienna-local Time-Helper fuer Cron + Server-Routes.
// Nutzt Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Vienna' }) — DST-aware.
// Server-only (Browser braucht es nicht — wuerde im Bundle landen wenn unter $lib/utils/).
//
// Pattern-Analog: src/lib/server/gcal.js Z 162-184.
// Pitfall-Source: .planning/research/PITFALLS.md C3 (Cron-TZ-Drift).
// Spec: .planning/phases/00-cross-cutting-foundations/0-RESEARCH.md (Z 334-378).

const TIME_ZONE = 'Europe/Vienna';

const VIENNA_FORMATTER = new Intl.DateTimeFormat('en-CA', {
	timeZone: TIME_ZONE,
	year:   'numeric',
	month:  '2-digit',
	day:    '2-digit',
	hour:   '2-digit',
	minute: '2-digit',
	second: '2-digit',
	hour12: false,
});

function partsOf(date) {
	const parts = VIENNA_FORMATTER.formatToParts(date);
	const get = (t) => parts.find(p => p.type === t)?.value ?? '';
	let h = get('hour');
	// Intl liefert '24' fuer Mitternacht in en-CA -> auf '00' normalisieren
	if (h === '24') h = '00';
	return {
		date: `${get('year')}-${get('month')}-${get('day')}`,
		time: `${h}:${get('minute')}:${get('second')}`,
	};
}

/**
 * Aktuelle Vienna-local Zeit.
 * @returns {{ date: string, time: string }} z.B. { date: '2026-04-30', time: '14:23:05' }
 */
export function nowVienna() {
	return partsOf(new Date());
}

/**
 * Datum +offsetDays (default 0) in Vienna-local. DST-aware via Intl.
 * @param {number} offsetDays — z.B. 1 fuer "morgen Vienna-local"
 * @returns {string} 'YYYY-MM-DD' (Vienna-local)
 */
export function dateInVienna(offsetDays = 0) {
	const d = new Date();
	// setUTCDate verschiebt um exakt N*86400s; Intl rechnet danach in Vienna um (DST-korrekt).
	d.setUTCDate(d.getUTCDate() + offsetDays);
	return partsOf(d).date;
}
