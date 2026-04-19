/** German/Austrian short day names. Index matches Date.getDay() (0 = Sunday). */
export const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

/** German/Austrian abbreviated month names. Index matches Date.getMonth(). */
export const MONTH_SHORT = ['Jän', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

/** German/Austrian full month names. Index matches Date.getMonth(). */
export const MONTH_FULL = ['Jänner', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

/** '2026-04-19' → 'So, 19. Apr' */
export function fmtDate(dateStr) {
	const d = new Date(dateStr + 'T12:00');
	return DAY_SHORT[d.getDay()] + ', ' + d.getDate() + '. ' + MONTH_SHORT[d.getMonth()];
}

/** '09:30:00' or '09:30' → '09:30 Uhr' */
export function fmtTime(timeStr) {
	return timeStr ? timeStr.slice(0, 5) + ' Uhr' : '';
}

/** Date object → 'YYYY-MM-DD' */
export function toDateStr(d) {
	return d.getFullYear() + '-' +
		String(d.getMonth() + 1).padStart(2, '0') + '-' +
		String(d.getDate()).padStart(2, '0');
}

/** How many full days until dateStr (negative = already past). */
export function daysUntil(dateStr) {
	const diff = new Date(dateStr + 'T00:00') - new Date();
	return Math.ceil(diff / 86_400_000);
}
