import { google } from 'googleapis';

const CLIENT_EMAIL = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL ?? '';
const PRIVATE_KEY  = (process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY ?? '').replace(/\\n/g, '\n');
const CALENDAR_ID  = process.env.GOOGLE_CALENDAR_ID ?? '';
const TIME_ZONE    = 'Europe/Vienna';

/**
 * Baut einen authentifizierten Calendar-Client (v3) via Service-Account-JWT.
 */
export function getCalendar() {
	const auth = new google.auth.JWT({
		email:  CLIENT_EMAIL,
		key:    PRIVATE_KEY,
		scopes: ['https://www.googleapis.com/auth/calendar'],
	});
	return google.calendar({ version: 'v3', auth });
}

/**
 * Listet Events aus dem Vereins-Kalender.
 * Zwei Modi:
 *   - incremental: { syncToken }            → nur Änderungen seit letztem Sync
 *   - windowed:    { timeMin, timeMax }     → Vollfenster, liefert ggf. nextSyncToken
 * Paginiert intern via pageToken. Wirft 410 bei invalidem syncToken.
 */
export async function listEvents({ timeMin, timeMax, syncToken } = {}) {
	const cal = getCalendar();
	const items = [];
	let pageToken;
	let nextSyncToken;

	do {
		const params = {
			calendarId:   CALENDAR_ID,
			singleEvents: true,
			showDeleted:  true,
			maxResults:   2500,
			pageToken,
		};
		if (syncToken) {
			params.syncToken = syncToken;
		} else {
			if (timeMin) params.timeMin = timeMin;
			if (timeMax) params.timeMax = timeMax;
			params.timeZone = TIME_ZONE;
			// Kein orderBy: Google liefert sonst keinen nextSyncToken.
		}

		const res = await cal.events.list(params);
		for (const ev of res.data.items ?? []) items.push(ev);
		pageToken     = res.data.nextPageToken;
		nextSyncToken = res.data.nextSyncToken ?? nextSyncToken;
	} while (pageToken);

	return { items, nextSyncToken };
}

/**
 * Erstellt ein Google-Event aus einem events-Row-Shape.
 * Returnt { id, etag }.
 */
export async function createEvent(fields) {
	const cal = getCalendar();
	const resource = toGoogleResource(fields);
	const res = await cal.events.insert({
		calendarId: CALENDAR_ID,
		requestBody: resource,
	});
	return { id: res.data.id, etag: res.data.etag };
}

/**
 * Aktualisiert ein Google-Event (Patch-Semantik).
 * Returnt { id, etag }.
 */
export async function updateEvent(externalId, fields) {
	const cal = getCalendar();
	const resource = toGoogleResource(fields);
	const res = await cal.events.patch({
		calendarId: CALENDAR_ID,
		eventId:    externalId,
		requestBody: resource,
	});
	return { id: res.data.id, etag: res.data.etag };
}

/**
 * Löscht ein Google-Event. 410 Gone (bereits weg) wird geschluckt.
 */
export async function deleteEvent(externalId) {
	const cal = getCalendar();
	try {
		await cal.events.delete({ calendarId: CALENDAR_ID, eventId: externalId });
	} catch (err) {
		const code = err?.code ?? err?.response?.status;
		if (code === 410) return; // already deleted
		throw err;
	}
}

/**
 * Konvertiert ein KVWN-events-Row-Shape in eine Google-Calendar-Resource.
 * - `time == null` → all-day (start.date / end.date, Ende = nächster Tag)
 * - `time != null` → start.dateTime + Europe/Vienna, Ende = Start + 1 h
 */
export function toGoogleResource(fields) {
	const { title, date, time, location, description } = fields;
	const resource = {
		summary:     title ?? '',
		location:    location ?? undefined,
		description: description ?? undefined,
	};

	if (!date) return resource;

	if (time == null || time === '') {
		// all-day
		const nextDay = new Date(date + 'T00:00:00');
		nextDay.setDate(nextDay.getDate() + 1);
		const endStr = `${nextDay.getFullYear()}-${String(nextDay.getMonth()+1).padStart(2,'0')}-${String(nextDay.getDate()).padStart(2,'0')}`;
		resource.start = { date };
		resource.end   = { date: endStr };
	} else {
		const hhmm  = String(time).slice(0, 5);
		const start = new Date(`${date}T${hhmm}:00`);
		const end   = new Date(start.getTime() + 60 * 60 * 1000); // +1 h default
		// Lokale ISO ohne Z (wir setzen timeZone separat)
		const iso = (d) => {
			const y  = d.getFullYear();
			const mo = String(d.getMonth() + 1).padStart(2, '0');
			const da = String(d.getDate()).padStart(2, '0');
			const h  = String(d.getHours()).padStart(2, '0');
			const mi = String(d.getMinutes()).padStart(2, '0');
			const se = String(d.getSeconds()).padStart(2, '0');
			return `${y}-${mo}-${da}T${h}:${mi}:${se}`;
		};
		resource.start = { dateTime: iso(start), timeZone: TIME_ZONE };
		resource.end   = { dateTime: iso(end),   timeZone: TIME_ZONE };
	}

	return resource;
}

/**
 * Konvertiert eine Google-Event-Resource in ein events-Row-Shape.
 * Gibt { external_id, source, title, date, time, location, description, etag, synced_at }.
 * time ist null bei all-day.
 */
export function fromGoogle(ev) {
	let date = null;
	let time = null;
	if (ev.start?.date) {
		// all-day
		date = ev.start.date;
		time = null;
	} else if (ev.start?.dateTime) {
		// timed event — interpret in the event's tz if given
		const dt = new Date(ev.start.dateTime);
		const y  = dt.getFullYear();
		const mo = String(dt.getMonth() + 1).padStart(2, '0');
		const da = String(dt.getDate()).padStart(2, '0');
		const h  = String(dt.getHours()).padStart(2, '0');
		const mi = String(dt.getMinutes()).padStart(2, '0');
		date = `${y}-${mo}-${da}`;
		time = `${h}:${mi}:00`;
	}

	return {
		external_id: ev.id,
		source:      'gcal',
		title:       ev.summary ?? '(ohne Titel)',
		date,
		time,
		location:    ev.location ?? null,
		description: ev.description ?? null,
		etag:        ev.etag ?? null,
		synced_at:   new Date().toISOString(),
	};
}
