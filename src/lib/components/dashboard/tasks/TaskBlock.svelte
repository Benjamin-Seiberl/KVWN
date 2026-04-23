<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { toDateStr } from '$lib/utils/dates.js';
	import LineupConfirmTask from './LineupConfirmTask.svelte';
	import LandesbewerbTask  from './LandesbewerbTask.svelte';

	let lineupItems  = $state([]);   // [{ gamePlanPlayerId, match, position, teammates, myName }]
	let landesItems  = $state([]);   // [{ match }]
	let myName       = $state(null);
	let loading      = $state(true);

	async function loadAll(pid) {
		loading = true;
		try {
			const todayStr = toDateStr(new Date());

			// Meinen Namen laden (für Decline-Push-Notifications)
			const [meRes, lineupRes, landesRes, dismissRes] = await Promise.all([
				sb.from('players').select('name').eq('id', pid).maybeSingle(),
				loadLineup(pid, todayStr),
				loadLandesbewerb(pid, todayStr),
				sb.from('dashboard_task_dismissals')
					.select('task_ref_id')
					.eq('player_id', pid)
					.eq('task_kind', 'landesbewerb'),
			]);

			if (meRes.error) {
				triggerToast('Fehler: ' + meRes.error.message);
				return;
			}
			if (dismissRes.error) {
				triggerToast('Fehler: ' + dismissRes.error.message);
				return;
			}

			myName = meRes.data?.name ?? null;
			lineupItems = lineupRes;

			const dismissed = new Set((dismissRes.data ?? []).map(d => d.task_ref_id));
			landesItems = landesRes.filter(lb => !dismissed.has(lb.id));
		} finally {
			loading = false;
		}
	}

	async function loadLineup(pid, todayStr) {
		// Künftige Matches (14-Tage-Fenster reicht analog ActionHub).
		const until = new Date();
		until.setDate(until.getDate() + 14);

		const { data: matches, error: matchErr } = await sb.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', todayStr)
			.lte('date', toDateStr(until))
			.order('date').order('time');
		if (matchErr) { triggerToast('Fehler: ' + matchErr.message); return []; }
		if (!matches?.length) return [];

		const calWeeks = [...new Set(matches.map(m => m.cal_week).filter(Boolean))];
		if (!calWeeks.length) return [];

		const { data: plans, error: planErr } = await sb.from('game_plans')
			.select('id, cal_week, league_id, confirmation_deadline, game_plan_players(id, confirmed, position, player_id, player_name, players!game_plan_players_player_id_fkey(name, photo))')
			.in('cal_week', calWeeks)
			.not('lineup_published_at', 'is', null)
			.gte('confirmation_deadline', todayStr);
		if (planErr) { triggerToast('Fehler: ' + planErr.message); return []; }
		if (!plans?.length) return [];

		const items = [];
		for (const plan of plans) {
			const myEntry = plan.game_plan_players?.find(e => e.player_id === pid);
			if (!myEntry || myEntry.confirmed !== null) continue;

			const match = matches.find(m => m.cal_week === plan.cal_week && m.league_id === plan.league_id);
			if (!match) continue;

			const teammates = (plan.game_plan_players ?? [])
				.slice()
				.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));

			items.push({
				gamePlanPlayerId: myEntry.id,
				position:         myEntry.position,
				match,
				teammates,
			});
		}
		return items;
	}

	async function loadLandesbewerb(pid, todayStr) {
		const nowIso = new Date().toISOString();
		const { data, error } = await sb.from('landesbewerbe')
			.select('id, title, typ, location, date, time, registration_deadline, landesbewerb_registrations(player_id)')
			.gte('date', todayStr)
			.gt('registration_deadline', nowIso)
			.order('registration_deadline', { ascending: true });
		if (error) { triggerToast('Fehler: ' + error.message); return []; }
		// Wer bereits angemeldet ist, braucht die Aufgabe nicht mehr.
		return (data ?? []).filter(row => !(row.landesbewerb_registrations ?? []).some(r => r.player_id === pid));
	}

	// Reload-Callback für Child-Komponenten (nach Aktion, wenn Fade fertig ist).
	function reload() {
		if ($playerId) loadAll($playerId);
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			loadAll($playerId);
		}
	});

	let totalOpen = $derived(lineupItems.length + landesItems.length);
</script>

{#if !loading && totalOpen > 0}
	<div class="tb">
		<div class="sec-head">
			<span class="material-symbols-outlined sec-icon">bolt</span>
			<h3 class="sec-title">Offene Aufgaben</h3>
			<span class="tb-badge">{totalOpen}</span>
		</div>

		<div class="tb-list">
			{#each lineupItems as entry (entry.gamePlanPlayerId)}
				<LineupConfirmTask {entry} myName={myName} onReload={reload} />
			{/each}
			{#each landesItems as lb (lb.id)}
				<LandesbewerbTask {lb} onReload={reload} />
			{/each}
		</div>
	</div>
{/if}

<style>
	.tb {
		padding: 0 var(--space-5);
	}

	.sec-head {
		display: flex;
		align-items: center;
		gap: 7px;
		margin-bottom: var(--space-3);
	}
	.sec-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sec-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}
	.tb-badge {
		margin-left: auto;
		min-width: 1.4rem;
		height: 1.4rem;
		padding: 0 var(--space-2);
		background: var(--color-primary);
		color: #fff;
		border-radius: var(--radius-full);
		font-family: var(--font-display);
		font-size: 0.72rem;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.tb-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
</style>
