// POST /api/training/cancel
//
// Server-side training-booking cancel + waitlist-promotion push.
//
// Why this exists:
//   `cancel_training_booking` is atomic in DB (booking row deleted, head of
//   waitlist promoted to that lane). The "Nachgerückt!"-Push to the promoted
//   player used to fire client-side from the cancelling user's browser — if
//   their tab was closed/backgrounded/offline, the promoted player got DB
//   promoted but never received a notification.
//
// Flow:
//   1. Validate caller via Bearer token (sb auth getUser).
//   2. Run cancel_training_booking RPC as the user (RLS-safe; the RPC
//      checks v_row.player_id <> v_pid itself).
//   3. If a player was promoted, fire the push server-side via the existing
//      /api/push/notify endpoint — same VAPID keys, same opt-in handling.
//   4. Return the RPC's jsonb result verbatim so the client can keep its
//      existing status-handling.

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL      = process.env.VITE_SUPABASE_URL      ?? '';
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY ?? '';

function jsonResponse(payload, status = 200) {
	return new Response(JSON.stringify(payload), {
		status,
		headers: { 'Content-Type': 'application/json' },
	});
}

export async function POST({ request, fetch, url }) {
	const auth = request.headers.get('authorization') ?? '';
	if (!auth.startsWith('Bearer ')) {
		return jsonResponse({ error: 'unauthorized' }, 401);
	}

	let body;
	try {
		body = await request.json();
	} catch {
		return jsonResponse({ error: 'invalid json' }, 400);
	}

	const bookingId = body?.booking_id;
	if (!bookingId) {
		return jsonResponse({ error: 'booking_id ist pflicht' }, 400);
	}

	// User-scoped client — RPC läuft mit (auth.jwt() ->> 'email') = users email,
	// d.h. der RPC-eigene Owner-Check greift.
	const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
		global: { headers: { Authorization: auth } },
		auth:   { persistSession: false, autoRefreshToken: false },
	});

	const { data, error } = await userClient.rpc('cancel_training_booking', {
		p_booking_id: bookingId,
	});

	if (error) {
		// Errors als 200 mit { error } durchreichen, damit der Client die
		// bestehende `error.message`-Logik (z.B. same_day_storno_forbidden)
		// unverändert nutzen kann.
		return jsonResponse({ error: error.message }, 400);
	}

	// Promotion → Push.
	const promoted = data?.promoted_player_id;
	if (promoted) {
		const startTime = String(data.start_time ?? '').slice(0, 5);
		const lane      = data.promoted_lane;
		const bodyText  =
			'Du bist nachgerückt! Dein Training um ' + startTime + ' Uhr' +
			(lane ? ' (Bahn ' + lane + ')' : '') + ' ist gesichert.';

		try {
			await fetch(`${url.origin}/api/push/notify`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					player_ids: [promoted],
					title:      'Nachgerückt!',
					body:       bodyText,
					url:        '/kalender',
					pref_key:   'training',
				}),
			});
		} catch (err) {
			// Push-Fehler nicht propagieren — Storno ist atomar in DB schon
			// passiert, der Spieler wurde in jedem Fall nachgerückt.
			console.error('promotion push failed', err?.message);
		}
	}

	return jsonResponse(data ?? {});
}
