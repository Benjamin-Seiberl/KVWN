/**
 * @typedef {Object} MissingField
 * @property {string} key      Spaltenname in `players`
 * @property {string} label    Anzeigetext (Austrian-German)
 * @property {string} section  logischer Bereich im Profil (kontakt | notfall | sport)
 */

const FIELDS = [
	{ key: 'phone',                   label: 'Telefonnummer',          section: 'kontakt' },
	{ key: 'address',                 label: 'Adresse',                section: 'kontakt' },
	{ key: 'birth_date',              label: 'Geburtsdatum',           section: 'kontakt' },
	{ key: 'emergency_contact_name',  label: 'Notfallkontakt-Name',    section: 'notfall' },
	{ key: 'emergency_contact_phone', label: 'Notfallkontakt-Telefon', section: 'notfall' },
	{ key: 'shirt_size',              label: 'Trikotgröße',            section: 'sport'   },
	{ key: 'spielerpass_nr',          label: 'Spielerpass-Nr.',        section: 'sport'   },
];

function isEmpty(value) {
	if (value === null || value === undefined) return true;
	if (typeof value === 'string' && value.trim() === '') return true;
	return false;
}

/**
 * Liefert alle Profil-Felder, die noch leer sind.
 * @param {Record<string, any> | null | undefined} player
 * @returns {MissingField[]}
 */
export function getMissingProfileFields(player) {
	if (!player) return [];
	return FIELDS.filter(f => isEmpty(player[f.key]));
}
