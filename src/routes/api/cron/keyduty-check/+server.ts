import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL         = process.env.VITE_SUPABASE_URL         ?? '';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const CRON_SECRET          = process.env.CRON_SECRET               ?? '';

export const GET: RequestHandler = async ({ request, url, fetch }) => {
	const auth = request.headers.get('authorization') ?? '';
	if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
		return new Response('unauthorized', { status: 401 });
	}

	const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

	// tomorrow in local YYYY-MM-DD (cron runs at 10:00 UTC → timezone offset small enough)
	const t = new Date();
	t.setDate(t.getDate() + 1);
	const tomorrow = `${t.getFullYear()}-${String(t.getMonth()+1).padStart(2,'0')}-${String(t.getDate()).padStart(2,'0')}`;

	const [{ data: bookings }, { data: duties }] = await Promise.all([
		admin.from('training_bookings').select('player_id').eq('date', tomorrow),
		admin.from('training_key_duties').select('player_id').eq('date', tomorrow),
	]);

	const playerIds = Array.from(new Set((bookings ?? []).map(b => b.player_id).filter(Boolean)));

	if ((duties ?? []).length > 0) {
		return new Response(JSON.stringify({ skipped: 'keyholder exists', date: tomorrow, bookings: playerIds.length }));
	}

	if (!playerIds.length) {
		return new Response(JSON.stringify({ skipped: 'no bookings', date: tomorrow }));
	}

	const res = await fetch(`${url.origin}/api/push/notify`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			player_ids: playerIds,
			title: 'Schlüssel-Dienst offen',
			body:  'Niemand hat den Schlüssel für morgen! Wer sperrt auf?',
			url:   '/kalender',
		}),
	});
	const out = await res.json();

	return new Response(JSON.stringify({ date: tomorrow, bookings: playerIds.length, ...out }));
};
