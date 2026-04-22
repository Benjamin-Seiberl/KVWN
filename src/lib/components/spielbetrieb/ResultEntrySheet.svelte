<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import MatchResultEditor from '$lib/components/spielbetrieb/MatchResultEditor.svelte';
	import { sb } from '$lib/supabase.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import { matchEnded } from '$lib/utils/matchTiming.js';

	let { open = $bindable(false), onPublished = () => {}, preselectedMatchId = null } = $props();

	let step       = $state('list');   // 'list' | 'edit'
	let candidates = $state([]);
	let loading    = $state(false);
	let selected   = $state(null);     // { match, gamePlanId, players, initialMode, initialPublishedAt }

	// Reset whenever the sheet closes
	$effect(() => {
		if (!open) {
			step = 'list';
			selected = null;
		}
	});

	// Load candidates when sheet opens (or jump straight to edit if preselected)
	$effect(() => {
		if (open) {
			if (preselectedMatchId) pickPreselected();
			else loadCandidates();
		}
	});

	async function pickPreselected() {
		if (!preselectedMatchId) return;
		loading = true;
		const { data: m, error } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, is_tournament, is_landesbewerb, is_friendly, leagues(name), game_plans(id, result_published_at, result_mode, lineup_published_at)')
			.eq('id', preselectedMatchId)
			.maybeSingle();
		if (error || !m) {
			triggerToast('Match nicht gefunden');
			loading = false;
			return;
		}
		await pickMatch(m);
		loading = false;
	}

	async function loadCandidates() {
		loading = true;
		const today  = toDateStr(new Date());
		const from60 = toDateStr(new Date(Date.now() - 60 * 86400000));

		const { data, error } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, is_tournament, is_landesbewerb, is_friendly, leagues(name), game_plans(id, result_published_at, result_mode, lineup_published_at)')
			.not('league_id', 'is', null)
			.eq('is_tournament', false)
			.eq('is_landesbewerb', false)
			.eq('is_friendly', false)
			.gte('date', from60)
			.lte('date', today)
			.order('date', { ascending: false });

		if (error) {
			triggerToast('Fehler: ' + error.message);
			loading = false;
			return;
		}

		candidates = (data ?? []).filter(m => {
			if (!matchEnded(m)) return false;
			const gps = m.game_plans ?? [];
			if (!gps.length || !gps[0]?.id) return false;
			return gps.every(gp => !gp.result_published_at);
		});
		loading = false;
	}

	async function pickMatch(m) {
		const gp = m.game_plans?.[0];
		if (!gp?.id) {
			triggerToast('Kein Spielplan vorhanden');
			return;
		}

		// Replicate the fetch pattern from SpielbetriebeTab.selectMatch (lines 73–119)
		const { data: gpFull, error } = await sb
			.from('game_plans')
			.select('id, result_mode, result_published_at, game_plan_players(id, position, player_id, player_name, score, played, result_state, players(name, photo), game_plan_player_lanes(bahn, volle, abraeumen))')
			.eq('id', gp.id)
			.maybeSingle();

		if (error) {
			triggerToast('Fehler: ' + error.message);
			return;
		}

		const players = (gpFull?.game_plan_players ?? [])
			.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));

		selected = {
			match: m,
			gamePlanId: gp.id,
			players,
			initialMode: gpFull?.result_mode ?? 'gesamt',
			initialPublishedAt: gpFull?.result_published_at ?? null,
		};
		step = 'edit';
	}
</script>

<BottomSheet bind:open title="Ergebnis eintragen">
	{#if step === 'list'}
		{#if loading}
			<div class="re-empty">
				<span class="material-symbols-outlined">hourglass_top</span>
				<p>Lädt…</p>
			</div>
		{:else if candidates.length === 0}
			<div class="re-empty">
				<span class="material-symbols-outlined">check_circle</span>
				<p>Keine offenen Ergebnisse</p>
			</div>
		{:else}
			<ul class="re-list">
				{#each candidates as m (m.id)}
					<li>
						<button class="re-row" onclick={() => pickMatch(m)}>
							<div class="re-row-body">
								<span class="re-row-title">
									{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}
								</span>
								<span class="re-row-sub">
									{fmtDate(m.date)}{m.time ? ' · ' + shortTime(m.time) + ' Uhr' : ''}{m.leagues?.name ? ' · ' + m.leagues.name : ''}
								</span>
							</div>
							<span class="material-symbols-outlined re-row-chev">chevron_right</span>
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}

	{#if step === 'edit' && selected}
		{#if !preselectedMatchId}
			<button class="re-back" onclick={() => { step = 'list'; selected = null; }}>
				<span class="material-symbols-outlined">arrow_back</span>
				Zurück
			</button>
		{/if}
		<div class="re-edit-head">
			<span class="re-row-title">
				{selected.match.home_away === 'HEIM' ? 'vs. ' : 'bei '}{selected.match.opponent}
			</span>
			<span class="re-row-sub">{fmtDate(selected.match.date)}</span>
		</div>
		<MatchResultEditor
			gamePlanId={selected.gamePlanId}
			match={selected.match}
			players={selected.players}
			initialMode={selected.initialMode}
			initialPublishedAt={selected.initialPublishedAt}
			onPublished={() => { open = false; onPublished(); }}
		/>
	{/if}
</BottomSheet>

<style>
	.re-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.re-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-3);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		-webkit-tap-highlight-color: transparent;
	}

	.re-row-body {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		flex: 1;
	}

	.re-row-title {
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
	}

	.re-row-sub {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}

	.re-row-chev {
		color: var(--color-outline);
		font-size: 1.2rem;
		flex-shrink: 0;
	}

	.re-back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		padding: 0;
		margin-bottom: var(--space-3);
		background: none;
		border: none;
		font-family: inherit;
		font-size: var(--text-label-md);
		font-weight: 600;
		color: var(--color-primary);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}

	.re-back .material-symbols-outlined {
		font-size: 1.1rem;
	}

	.re-edit-head {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-bottom: var(--space-3);
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--color-outline-variant);
	}

	.re-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-8);
		color: var(--color-on-surface-variant);
		text-align: center;
	}

	.re-empty .material-symbols-outlined {
		font-size: 2rem;
	}

	.re-empty p {
		margin: 0;
		font-size: var(--text-body-md);
	}
</style>
