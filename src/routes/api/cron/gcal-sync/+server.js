import { sbAdmin } from '$lib/server/supabase-admin.js';
import { listEvents, fromGoogle } from '$lib/server/gcal.js';
import { toDateStr } from '$lib/utils/dates.js';

const CRON_SECRET = process.env.CRON_SECRET    ?? '';
const CALENDAR_ID = process.env.GOOGLE_CALENDAR_ID ?? '';

async function handle(request) {
	const auth = request.headers.get('authorization') ?? '';
	if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
		return new Response('unauthorized', { status: 401 });
	}

	const admin = sbAdmin();

	// ── Sync-State laden (sync_token für incremental, sonst windowed Full-Pull) ──
	const { data: stateRow } = await admin
		.from('gcal_sync_state')
		.select('*')
		.eq('calendar_id', CALENDAR_ID)
		.maybeSingle();

	const now   = new Date();
	const start = new Date(now); start.setDate(now.getDate() - 30);
	const end   = new Date(now); end.setDate(now.getDate() + 180);
	const windowStart = toDateStr(start);
	const windowEnd   = toDateStr(end);

	// ── Events von Google holen ──────────────────────────────────────────────
	let items;
	let nextSyncToken;
	let usedSyncToken = !!stateRow?.sync_token;

	try {
		if (stateRow?.sync_token) {
			const res = await listEvents({ syncToken: stateRow.sync_token });
			items = res.items;
			nextSyncToken = res.nextSyncToken;
		} else {
			const res = await listEvents({
				timeMin: start.toISOString(),
				timeMax: end.toISOString(),
			});
			items = res.items;
			nextSyncToken = res.nextSyncToken;
		}
	} catch (err) {
		const code = err?.code ?? err?.response?.status;
		if (code === 410 && usedSyncToken) {
			// Sync-Token abgelaufen → Full-Window als Fallback
			const res = await listEvents({
				timeMin: start.toISOString(),
				timeMax: end.toISOString(),
			});
			items = res.items;
			nextSyncToken = res.nextSyncToken;
			usedSyncToken = false;
		} else {
			return new Response(
				JSON.stringify({ error: err?.message ?? 'gcal list failed' }),
				{ status: 500, headers: { 'Content-Type': 'application/json' } },
			);
		}
	}

	// ── Match-Duplikat-Guard ─────────────────────────────────────────────────
	// Google-Events an Tagen, an denen wir bereits ein Match haben, ignorieren
	// (solange es nicht schon als gcal-Row in events existiert). Schützt vor
	// Doppel-Rendering während der Übergangsphase (alte Saison pflegt Matches
	// noch in Google, neue Saison wird nur noch in KVWN gepflegt).
	const { data: matchRows } = await admin
		.from('matches')
		.select('date')
		.gte('date', windowStart)
		.lte('date', windowEnd);
	const matchDateSet = new Set((matchRows ?? []).map(r => r.date));

	// Welche external_ids sind bereits als gcal-Row in events? (damit wir existierende
	// Google-Events nicht löschen, die auf einen Match-Tag fallen).
	const incomingIds = items.map(ev => ev.id).filter(Boolean);
	let existingSet = new Set();
	if (incomingIds.length) {
		const { data: existingRows } = await admin
			.from('events')
			.select('external_id')
			.in('external_id', incomingIds);
		existingSet = new Set((existingRows ?? []).map(r => r.external_id));
	}

	// ── Verarbeitung ─────────────────────────────────────────────────────────
	let upserted = 0;
	let deleted  = 0;
	let skipped_match_dates = 0;

	for (const ev of items) {
		if (ev.status === 'cancelled') {
			const { error } = await admin
				.from('events')
				.delete()
				.eq('external_id', ev.id);
			if (!error) deleted++;
			continue;
		}

		const row = fromGoogle(ev);
		if (!row.date) continue; // kein verwertbares Datum

		// Match-Tag-Guard: nur skippen, wenn noch nicht als gcal-Row bekannt
		if (matchDateSet.has(row.date) && !existingSet.has(ev.id)) {
			skipped_match_dates++;
			continue;
		}

		const { error } = await admin
			.from('events')
			.upsert(row, { onConflict: 'external_id' });
		if (!error) upserted++;
	}

	// ── Sync-State schreiben ─────────────────────────────────────────────────
	const nowIso = new Date().toISOString();
	const patch  = {
		calendar_id:       CALENDAR_ID,
		sync_token:        nextSyncToken ?? null,
		last_run_at:       nowIso,
		last_full_sync_at: usedSyncToken ? (stateRow?.last_full_sync_at ?? null) : nowIso,
	};
	await admin.from('gcal_sync_state').upsert(patch, { onConflict: 'calendar_id' });

	return new Response(
		JSON.stringify({
			upserted,
			deleted,
			skipped_match_dates,
			next_sync_token: nextSyncToken ?? null,
		}),
		{ headers: { 'Content-Type': 'application/json' } },
	);
}

export async function GET({ request }) {
	return handle(request);
}

export async function POST({ request }) {
	return handle(request);
}
