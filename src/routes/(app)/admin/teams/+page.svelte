<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	let teams = $state([]);
	let seasons = $state([]);
	let leagues = $state([]);
	let currentSeason = $state(null);

	async function load() {
		const [{ data: t }, { data: s }, { data: l }] = await Promise.all([
			sb.from('teams').select('id, name, league_id, season_id, deleted_at, leagues(name, tier), seasons(name, is_current)').order('created_at'),
			sb.from('seasons').select('*').order('start_date', { ascending: false }),
			sb.from('leagues').select('*').order('tier'),
		]);
		teams   = t ?? [];
		seasons = s ?? [];
		leagues = l ?? [];
		currentSeason = seasons.find(x => x.is_current) ?? seasons[0] ?? null;
	}

	async function createTeam(league) {
		if (!currentSeason) return;
		const { error } = await sb.from('teams').insert({
			name: league.name,
			league_id: league.id,
			season_id: currentSeason.id,
		});
		if (!error) load();
	}

	async function softDelete(team) {
		if (!confirm(`Team „${team.name}" als inaktiv markieren?`)) return;
		await sb.from('teams').update({ deleted_at: new Date().toISOString() }).eq('id', team.id);
		load();
	}

	async function restore(team) {
		await sb.from('teams').update({ deleted_at: null }).eq('id', team.id);
		load();
	}

	const teamsForCurrent = $derived(
		teams.filter(t => t.season_id === currentSeason?.id)
	);
	const missingLeagues = $derived(
		leagues.filter(l => !teamsForCurrent.find(t => t.league_id === l.id && !t.deleted_at))
	);

	onMount(load);
</script>

<div class="page">
	<h2>Teams — {currentSeason?.name ?? '…'}</h2>

	<ul class="tlist">
		{#each teamsForCurrent as t}
			<li class="t-item" class:t-item--deleted={t.deleted_at}>
				<div class="t-info">
					<a class="t-name" href="/admin/teams/{t.id}">
						<span class="material-symbols-outlined">diversity_3</span>
						{t.name}
					</a>
					<span class="t-tier">Tier {t.leagues?.tier ?? '?'}</span>
				</div>
				{#if t.deleted_at}
					<button class="tbtn" onclick={() => restore(t)}>
						<span class="material-symbols-outlined">restore</span>
					</button>
				{:else}
					<button class="tbtn tbtn--danger" onclick={() => softDelete(t)}>
						<span class="material-symbols-outlined">delete</span>
					</button>
				{/if}
			</li>
		{/each}
	</ul>

	{#if missingLeagues.length}
		<div class="add-zone">
			<h3>Team hinzufügen</h3>
			<div class="add-btns">
				{#each missingLeagues as l}
					<button class="tbtn tbtn--add" onclick={() => createTeam(l)}>
						<span class="material-symbols-outlined">add</span>
						{l.name}
					</button>
				{/each}
			</div>
		</div>
	{/if}
</div>

<style>
	h2 { font-family: 'Lexend', sans-serif; font-weight: 600; font-size: 1.15rem; margin: 0 0 var(--space-3); }
	.tlist { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: var(--space-2); }
	.t-item { display: flex; align-items: center; gap: var(--space-2); padding: 12px; border: 1px solid var(--color-border, #eee); background: var(--color-surface, #fff); border-radius: 12px; }
	.t-item--deleted { opacity: 0.5; }
	.t-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
	.t-name { display: flex; align-items: center; gap: 6px; font-weight: 500; color: inherit; text-decoration: none; }
	.t-name :global(.material-symbols-outlined) { color: var(--color-primary, #CC0000); }
	.t-tier { font-size: 0.78rem; color: var(--color-text-soft, #888); }
	.tbtn { background: var(--color-surface, #f5f5f5); border: 1px solid var(--color-border, #eee); border-radius: 999px; padding: 6px 10px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; }
	.tbtn--danger { color: var(--color-primary, #CC0000); }
	.tbtn--add { border-color: var(--color-primary, #CC0000); color: var(--color-primary, #CC0000); }
	.add-zone { margin-top: var(--space-5); padding-top: var(--space-3); border-top: 1px dashed var(--color-border, #eee); }
	.add-zone h3 { font-family: 'Lexend'; font-size: 0.95rem; margin: 0 0 var(--space-2); }
	.add-btns { display: flex; flex-wrap: wrap; gap: var(--space-2); }
</style>
