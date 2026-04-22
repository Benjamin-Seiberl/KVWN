import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL         = process.env.VITE_SUPABASE_URL         ?? '';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const CRON_SECRET          = process.env.CRON_SECRET               ?? '';

export const GET: RequestHandler = async ({ request, url, fetch }) => {
	const auth = request.headers.get('authorization') ?? '';
	if (!CRON_SECRET || auth !== `Bearer ${CRON_SECRET}`) {
		return new Response('', { status: 401 });
	}

	const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

	// tomorrow YYYY-MM-DD (local)
	const t = new Date();
	t.setDate(t.getDate() + 1);
	const tomorrow = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;

	const { data: plans } = await admin
		.from('game_plans')
		.select('id, confirmation_deadline, cal_week, league_id, game_plan_players(player_id, confirmed)')
		.not('lineup_published_at', 'is', null)
		.eq('confirmation_deadline', tomorrow);

	let sent = 0;
	for (const plan of plans ?? []) {
		const pending = ((plan as any).game_plan_players ?? []).filter((e: any) => e.confirmed === null);
		if (!pending.length) continue;

		// game_plans ↔ matches joined via cal_week + league_id (not match_id FK)
		const { data: m } = await admin
			.from('matches')
			.select('opponent, leagues(name)')
			.eq('cal_week', (plan as any).cal_week)
			.eq('league_id', (plan as any).league_id)
			.maybeSingle();

		const leagueName = (m as any)?.leagues?.name ?? '';
		const opponent   = (m as any)?.opponent ?? '';

		const res = await fetch(`${url.origin}/api/push/notify`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				player_ids: pending.map((e: any) => e.player_id),
				title: 'Aufstellung bestätigen – Frist morgen',
				body:  `${leagueName} vs. ${opponent}`,
				url:   '/#action-hub-lineup',
				pref_key: 'lineup_reminder',
			}),
		});
		const r = await res.json().catch(() => ({ sent: 0 }));
		sent += r.sent ?? 0;
	}

	return new Response(JSON.stringify({ ok: true, sent }), { headers: { 'Content-Type': 'application/json' } });
};
