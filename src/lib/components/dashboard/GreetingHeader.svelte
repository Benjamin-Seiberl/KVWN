<script>
	import { sb } from '$lib/supabase';
	import { user, playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { MONTH_FULL, toDateStr, daysUntil } from '$lib/utils/dates.js';

	const DAY_FULL = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];

	let firstName  = $state('');
	let openTasks  = $state(0);       // lineup pending + landesbewerb offen (not dismissed)
	let nextMatchDate = $state(null); // 'YYYY-MM-DD' der frühesten künftigen Aufstellung

	// Greeting + Datum werden sofort berechnet — unabhängig von Ladezustand.
	function todayLabel() {
		const d = new Date();
		return DAY_FULL[d.getDay()].toUpperCase() + ', ' + d.getDate() + '. ' + MONTH_FULL[d.getMonth()].toUpperCase();
	}

	// Status-line segments
	const statusLine = $derived.by(() => {
		const segs = [];
		if (openTasks > 0) {
			segs.push(openTasks === 1 ? '1 offen' : `${openTasks} offen`);
		}
		if (nextMatchDate) {
			const d = daysUntil(nextMatchDate);
			if (d === 0)      segs.push('Spiel heute');
			else if (d === 1) segs.push('Spiel morgen');
			else if (d >= 2)  segs.push(`Spiel in ${d}d`);
		}
		return segs.join(' · ');
	});

	// Load firstName from players table
	$effect(() => {
		if ($user?.email && !firstName) {
			sb.from('players').select('name').eq('email', $user.email).maybeSingle()
				.then(({ data, error }) => {
					if (error) { triggerToast('Fehler: ' + error.message); return; }
					if (data?.name) firstName = data.name.split(' ')[0];
				});
		}
	});

	// Load task count + next match once playerId is known
	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			loadStatus($playerId);
		}
	});

	async function loadStatus(pid) {
		const todayStr = toDateStr(new Date());
		const until = new Date();
		until.setDate(until.getDate() + 14);
		const untilStr = toDateStr(until);

		// A) Alle Matches im Fenster (für Lineup + Next-Match)
		const { data: matches, error: mErr } = await sb.from('matches')
			.select('id, date, time, cal_week, league_id')
			.gte('date', todayStr)
			.order('date').order('time');
		if (mErr) { triggerToast('Fehler: ' + mErr.message); return; }

		const windowMatches = (matches ?? []).filter(m => m.date <= untilStr);
		const calWeeks = [...new Set(windowMatches.map(m => m.cal_week).filter(Boolean))];

		// B) Game-plan players: nächstes Spiel auf dem Spieler steht, plus pending confirmations
		const { data: entries, error: eErr } = await sb
			.from('game_plan_players')
			.select('confirmed, game_plans!inner(cal_week, league_id, lineup_published_at, confirmation_deadline)')
			.eq('player_id', pid);
		if (eErr) { triggerToast('Fehler: ' + eErr.message); return; }

		// Nächstes Match, bei dem ich auf der Aufstellung stehe
		let earliest = null;
		for (const m of (matches ?? [])) {
			const hit = (entries ?? []).find(e =>
				e.game_plans?.cal_week === m.cal_week &&
				e.game_plans?.league_id === m.league_id
			);
			if (hit) { earliest = m.date; break; }
		}
		nextMatchDate = earliest;

		// Lineup-Pending (confirmed IS NULL auf published+deadline≥today game_plans in window)
		let lineupPending = 0;
		for (const e of (entries ?? [])) {
			const gp = e.game_plans;
			if (!gp?.lineup_published_at) continue;
			if (gp.confirmation_deadline && gp.confirmation_deadline < todayStr) continue;
			if (!calWeeks.includes(gp.cal_week)) continue;
			if (e.confirmed === null) lineupPending += 1;
		}

		// Landesbewerb-Offen (nicht angemeldet + nicht dismissed + Frist läuft)
		const nowIso = new Date().toISOString();
		const [lbRes, dismissRes] = await Promise.all([
			sb.from('landesbewerbe')
				.select('id, landesbewerb_registrations!landesbewerb_id(player_id)')
				.gte('date', todayStr)
				.gt('registration_deadline', nowIso),
			sb.from('dashboard_task_dismissals')
				.select('task_ref_id')
				.eq('player_id', pid)
				.eq('task_kind', 'landesbewerb'),
		]);
		if (lbRes.error)      { triggerToast('Fehler: ' + lbRes.error.message); return; }
		if (dismissRes.error) { triggerToast('Fehler: ' + dismissRes.error.message); return; }

		const dismissed = new Set((dismissRes.data ?? []).map(d => d.task_ref_id));
		const lbOpen = (lbRes.data ?? []).filter(row =>
			!dismissed.has(row.id) &&
			!((row.landesbewerb_registrations ?? []).some(r => r.player_id === pid))
		).length;

		openTasks = lineupPending + lbOpen;
	}
</script>

<header class="gh" style="--i:0">
	<p class="gh-date">{todayLabel()}</p>
	<h1 class="gh-greeting">
		Hallo{firstName ? ' ' + firstName : ''}
		<span class="gh-wave" aria-hidden="true">👋</span>
	</h1>
	{#if statusLine}
		<p class="gh-status">{statusLine}</p>
	{/if}
</header>

<style>
	.gh {
		padding: var(--space-4) var(--space-5) var(--space-3);
		animation: gh-in 0.35s cubic-bezier(0.22, 1, 0.36, 1) both;
	}
	@keyframes gh-in {
		from { opacity: 0; transform: translateY(-8px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	.gh-date {
		margin: 0 0 2px;
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.09em;
		text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.gh-greeting {
		margin: 0;
		font-family: var(--font-display);
		font-size: clamp(1.35rem, 5vw, 1.6rem);
		font-weight: 700;
		color: var(--color-on-surface);
		line-height: 1.2;
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.gh-status {
		margin: var(--space-1) 0 0;
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
	}
	.gh-wave {
		display: inline-block;
		animation: gh-wave 2.4s ease-in-out 0.8s 1;
		transform-origin: 70% 80%;
	}
	@keyframes gh-wave {
		0%,100% { transform: rotate(0deg); }
		15%      { transform: rotate(14deg); }
		30%      { transform: rotate(-8deg); }
		45%      { transform: rotate(14deg); }
		60%      { transform: rotate(-4deg); }
		75%      { transform: rotate(10deg); }
	}

	@media (prefers-reduced-motion: reduce) {
		.gh, .gh-wave { animation: none; }
	}
</style>
