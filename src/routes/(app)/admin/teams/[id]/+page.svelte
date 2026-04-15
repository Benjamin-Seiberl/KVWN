<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { sb } from '$lib/supabase';

	const teamId = $derived($page.params.id);

	let team = $state(null);
	let roster = $state([]);   // [{player_id, position, player}]
	let allPlayers = $state([]);
	let addOpen = $state(false);

	async function load() {
		const { data: t } = await sb
			.from('teams')
			.select('*, leagues(name, tier), seasons(name)')
			.eq('id', teamId)
			.maybeSingle();
		team = t;

		const { data: r } = await sb
			.from('team_rosters')
			.select('team_id, player_id, position, players(id, name, avatar_url)')
			.eq('team_id', teamId)
			.order('position');
		roster = r ?? [];

		const { data: p } = await sb.from('players').select('id, name, avatar_url, active').eq('active', true).order('name');
		allPlayers = p ?? [];
	}

	const availablePlayers = $derived(
		allPlayers.filter(p => !roster.find(r => r.player_id === p.id))
	);
	const nextPos = $derived(
		(roster.at(-1)?.position ?? 0) + 1
	);

	async function addPlayer(p) {
		await sb.from('team_rosters').insert({ team_id: teamId, player_id: p.id, position: nextPos });
		load();
	}
	async function removePlayer(r) {
		await sb.from('team_rosters').delete().eq('team_id', r.team_id).eq('player_id', r.player_id);
		load();
	}
	async function movePlayer(r, delta) {
		const idx = roster.findIndex(x => x.player_id === r.player_id);
		const other = roster[idx + delta];
		if (!other) return;
		// Swap positions
		await Promise.all([
			sb.from('team_rosters').update({ position: other.position }).eq('team_id', r.team_id).eq('player_id', r.player_id),
			sb.from('team_rosters').update({ position: r.position }).eq('team_id', other.team_id).eq('player_id', other.player_id),
		]);
		load();
	}

	onMount(load);
</script>

<div class="page">
	<header class="rhead">
		<a class="back" href="/admin/teams">
			<span class="material-symbols-outlined">arrow_back</span>
		</a>
		<div>
			<h2>{team?.name ?? '…'}</h2>
			<p class="sub">{team?.seasons?.name ?? ''} · Tier {team?.leagues?.tier ?? ''}</p>
		</div>
	</header>

	<ul class="rlist">
		{#each roster as r, i}
			<li class="r-item">
				<span class="r-pos">{r.position}</span>
				<div class="r-avatar">
					{#if r.players?.avatar_url}<img src={r.players.avatar_url} alt="" />{:else}<span>{(r.players?.name || '?').slice(0,1)}</span>{/if}
				</div>
				<span class="r-name">{r.players?.name}</span>
				<div class="r-actions">
					<button onclick={() => movePlayer(r, -1)} disabled={i === 0} aria-label="Hoch">
						<span class="material-symbols-outlined">arrow_upward</span>
					</button>
					<button onclick={() => movePlayer(r, 1)} disabled={i === roster.length - 1} aria-label="Runter">
						<span class="material-symbols-outlined">arrow_downward</span>
					</button>
					<button onclick={() => removePlayer(r)} aria-label="Entfernen">
						<span class="material-symbols-outlined">close</span>
					</button>
				</div>
			</li>
		{/each}
	</ul>

	{#if availablePlayers.length}
		<button class="add-more" onclick={() => addOpen = !addOpen}>
			<span class="material-symbols-outlined">{addOpen ? 'expand_less' : 'add'}</span>
			Spieler hinzufügen
		</button>
		{#if addOpen}
			<ul class="alist">
				{#each availablePlayers as p}
					<li><button onclick={() => addPlayer(p)}>
						<span class="material-symbols-outlined">add_circle</span> {p.name}
					</button></li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<style>
	.rhead { display: flex; gap: var(--space-3); align-items: flex-start; margin-bottom: var(--space-3); }
	.back { color: inherit; text-decoration: none; padding: 6px; background: var(--color-surface, #f5f5f5); border-radius: 999px; }
	h2 { margin: 0; font-family: 'Lexend'; font-weight: 600; font-size: 1.15rem; }
	.sub { margin: 0; color: var(--color-text-soft, #888); font-size: 0.85rem; }
	.rlist { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 6px; }
	.r-item { display: grid; grid-template-columns: 28px 36px 1fr auto; gap: 8px; align-items: center; padding: 8px 12px; background: var(--color-surface, #fff); border: 1px solid var(--color-border, #eee); border-radius: 10px; }
	.r-pos { font-weight: 700; color: var(--color-primary, #CC0000); text-align: center; }
	.r-avatar { width: 36px; height: 36px; border-radius: 50%; overflow: hidden; background: #eee; display: grid; place-items: center; font-weight: 600; color: #999; }
	.r-avatar img { width: 100%; height: 100%; object-fit: cover; }
	.r-name { font-weight: 500; }
	.r-actions { display: flex; gap: 2px; }
	.r-actions button { background: none; border: 0; padding: 4px; cursor: pointer; color: var(--color-text-soft, #888); }
	.r-actions button:disabled { opacity: 0.3; }
	.add-more { margin-top: var(--space-3); display: inline-flex; gap: 4px; padding: 8px 14px; border-radius: 999px; border: 1px dashed var(--color-primary, #CC0000); background: none; color: var(--color-primary, #CC0000); cursor: pointer; }
	.alist { list-style: none; padding: 0; margin: var(--space-2) 0 0; display: flex; flex-wrap: wrap; gap: 6px; }
	.alist button { display: inline-flex; gap: 4px; align-items: center; padding: 6px 10px; border: 1px solid var(--color-border, #eee); background: #fff; border-radius: 999px; font-size: 0.85rem; cursor: pointer; }
	.alist button :global(.material-symbols-outlined) { font-size: 1rem; color: var(--color-primary, #CC0000); }
</style>
