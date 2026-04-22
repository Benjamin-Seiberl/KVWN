<script>
	import { onMount }       from 'svelte';
	import BottomSheet       from '$lib/components/BottomSheet.svelte';
	import { sb }            from '$lib/supabase.js';
	import { triggerToast }  from '$lib/stores/toast.js';
	import { fmtDate }       from '$lib/utils/dates.js';
	import { shortTime }     from '$lib/utils/league.js';
	import { seasonStart }   from '$lib/utils/season.js';

	let { open = $bindable(false) } = $props();

	let matches  = $state([]);
	let loading  = $state(false);
	let showPast = $state(false);

	$effect(() => {
		if (open && matches.length === 0) load();
	});

	async function load() {
		loading = true;
		const { data, error } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name), game_plans(result_published_at)')
			.not('league_id', 'is', null)
			.eq('is_tournament', false)
			.eq('is_landesbewerb', false)
			.eq('is_friendly', false)
			.gte('date', seasonStart())
			.order('date', { ascending: true })
			.order('time', { ascending: true });
		if (error) { triggerToast('Fehler: ' + error.message); loading = false; return; }
		matches = (data ?? []).filter(m => m.opponent && m.opponent.toLowerCase() !== 'spielfrei');
		loading = false;
	}

	const isPublished = (m) => (m.game_plans ?? []).some(gp => gp.result_published_at);

	const openMatches = $derived(matches.filter(m => !isPublished(m)));
	const pastMatches = $derived(matches.filter(m => isPublished(m)).slice().reverse());
</script>

<BottomSheet bind:open title="Offene Spiele">
	{#if loading}
		<div class="om-empty"><span class="material-symbols-outlined">hourglass_top</span><p>Lädt…</p></div>
	{:else}
		<div class="om-toolbar">
			<label class="om-toggle">
				<input type="checkbox" bind:checked={showPast} />
				Vergangene Spiele zeigen
			</label>
		</div>

		<h3 class="om-section-title">Offen ({openMatches.length})</h3>
		{#if openMatches.length === 0}
			<div class="om-empty"><span class="material-symbols-outlined">event_available</span><p>Keine offenen Spiele</p></div>
		{:else}
			<ul class="om-list">
				{#each openMatches as m}
					{@const isAway = m.home_away !== 'HEIM'}
					<li class="om-item om-item--league">
						<span class="om-item-icon material-symbols-outlined">sports</span>
						<div class="om-item-body">
							<span class="om-item-title">{(isAway ? 'bei ' : 'vs. ') + m.opponent}</span>
							<span class="om-item-sub">
								{fmtDate(m.date)}{m.time ? ' · ' + shortTime(m.time) + ' Uhr' : ''}
								<span class="om-chip om-chip--ha" class:om-chip--away={isAway}>{isAway ? 'Auswärts' : 'Heim'}</span>
								{#if m.leagues?.name}<span class="om-chip om-chip--neutral">{m.leagues.name}</span>{/if}
							</span>
						</div>
					</li>
				{/each}
			</ul>
		{/if}

		{#if showPast}
			<h3 class="om-section-title">Vergangen ({pastMatches.length})</h3>
			{#if pastMatches.length === 0}
				<div class="om-empty"><span class="material-symbols-outlined">history</span><p>Keine vergangenen Spiele</p></div>
			{:else}
				<ul class="om-list">
					{#each pastMatches as m}
						{@const isAway = m.home_away !== 'HEIM'}
						<li class="om-item om-item--past">
							<span class="om-item-icon material-symbols-outlined">scoreboard</span>
							<div class="om-item-body">
								<span class="om-item-title">{(isAway ? 'bei ' : 'vs. ') + m.opponent}</span>
								<span class="om-item-sub">
									{fmtDate(m.date)}
									<span class="om-chip om-chip--ha" class:om-chip--away={isAway}>{isAway ? 'Auswärts' : 'Heim'}</span>
									{#if m.leagues?.name}<span class="om-chip om-chip--neutral">{m.leagues.name}</span>{/if}
								</span>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		{/if}
	{/if}
</BottomSheet>

<style>
	.om-toolbar {
		padding-bottom: var(--space-3);
	}
	.om-toggle {
		display: inline-flex;
		flex-direction: row;
		align-items: center;
		gap: var(--space-2);
		font: var(--text-label-md);
		font-family: var(--font-body);
		color: var(--color-on-surface-variant);
		cursor: pointer;
	}
	.om-toggle input[type='checkbox'] {
		accent-color: var(--color-primary);
		cursor: pointer;
	}

	.om-section-title {
		font: var(--text-title-sm);
		font-family: var(--font-display);
		color: var(--color-on-surface);
		margin: var(--space-4) 0 var(--space-2);
	}

	.om-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.om-item {
		display: flex;
		flex-direction: row;
		align-items: flex-start;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-md);
	}
	.om-item--past { opacity: 0.75; }

	.om-item-icon {
		font-size: 22px;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.om-item--league .om-item-icon {
		color: var(--color-on-surface);
	}

	.om-item-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		flex: 1;
		min-width: 0;
	}
	.om-item-title {
		font: var(--text-title-sm);
		font-family: var(--font-display);
		color: var(--color-on-surface);
	}
	.om-item-sub {
		font: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-2);
	}

	.om-chip {
		display: inline-flex;
		padding: var(--space-1) var(--space-2);
		border-radius: var(--radius-full);
		font: var(--text-label-sm);
	}
	.om-chip--ha {
		background: var(--color-surface-container);
		color: var(--color-on-surface);
	}
	.om-chip--ha.om-chip--away {
		background: var(--color-surface-container-highest, var(--color-surface-container));
	}
	.om-chip--neutral {
		background: var(--color-surface-container);
		color: var(--color-on-surface-variant);
	}

	.om-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-6);
		color: var(--color-on-surface-variant);
		text-align: center;
	}
	.om-empty p { margin: 0; }
</style>
