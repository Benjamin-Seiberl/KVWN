import type { RequestHandler } from './$types';
import webpush from 'web-push';
import { createClient } from '@supabase/supabase-js';

// Server-only env vars (kein VITE_-Prefix → nicht im Browser-Bundle)
const VAPID_PUBLIC_KEY        = process.env.VAPID_PUBLIC_KEY        ?? '';
const VAPID_PRIVATE_KEY       = process.env.VAPID_PRIVATE_KEY       ?? '';
const SUPABASE_URL            = process.env.VITE_SUPABASE_URL       ?? '';
const SUPABASE_SERVICE_KEY    = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

export const POST: RequestHandler = async ({ request }) => {
	if (!VAPID_PRIVATE_KEY || !VAPID_PUBLIC_KEY) {
		return new Response(JSON.stringify({ error: 'VAPID keys not configured' }), { status: 500 });
	}

	webpush.setVapidDetails('mailto:admin@kvwn.at', VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

	const { player_ids, title, body, url = '/spielbetrieb', pref_key = 'lineup' } = await request.json() as {
		player_ids: string[];
		title: string;
		body: string;
		url?: string;
		pref_key?: string;
	};

	if (!player_ids?.length) {
		return new Response(JSON.stringify({ sent: 0 }));
	}

	// Service-Role-Client umgeht RLS (liest alle Subscriptions)
	const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

	// Subscriptions für die Spieler laden, aber nur wenn push_prefs[pref_key] !== false
	const { data: players } = await admin
		.from('players')
		.select('id, push_prefs')
		.in('id', player_ids);

	const optedIn = (players ?? [])
		.filter(p => (p.push_prefs?.[pref_key] ?? true) !== false)
		.map(p => p.id);

	if (!optedIn.length) {
		return new Response(JSON.stringify({ sent: 0 }));
	}

	const { data: subs } = await admin
		.from('push_subscriptions')
		.select('endpoint, p256dh, auth')
		.in('player_id', optedIn);

	const payload = JSON.stringify({ title, body, link: url });
	let sent = 0;

	for (const sub of subs ?? []) {
		try {
			await webpush.sendNotification(
				{ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
				payload
			);
			sent++;
		} catch {
			// Abgelaufene Subscriptions stillschweigend ignorieren
		}
	}

	return new Response(JSON.stringify({ sent }));
};
