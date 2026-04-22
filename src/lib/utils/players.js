// Shared helpers for displaying players.

// Returns a public URL for a player's photo.
// Uses `photo` (filename stem) if present, otherwise falls back to `name`.
export function imgPath(photo, name) {
	const key = photo || name;
	return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
}

// "Maximilian Klaus" -> "Maximilian K."
export function shortName(name) {
	if (!name) return '–';
	const parts = name.trim().split(' ');
	if (parts.length < 2) return name;
	return parts[0] + ' ' + parts[parts.length - 1].charAt(0) + '.';
}

// 1x1 transparent gif for broken-image fallback.
export const BLANK_IMG =
	'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

// 'AT611904300234573201' -> 'AT.. …3201'. null/short -> null.
export function formatIbanMasked(iban) {
	if (!iban) return null;
	const clean = String(iban).replace(/\s+/g, '');
	if (clean.length < 6) return null;
	const head = clean.slice(0, 2);
	const tail = clean.slice(-4);
	return head + '.. …' + tail;
}
