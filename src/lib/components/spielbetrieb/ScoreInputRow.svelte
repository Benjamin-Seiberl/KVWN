<script>
	import { sb } from '$lib/supabase';

	let { player, onSaved } = $props();
	let draft = $state(player.score ?? '');
	let saving = $state(false);

	async function save() {
		if (draft === '' || draft === null) return;
		const n = Number(draft);
		if (!Number.isFinite(n)) return;
		saving = true;
		const { error } = await sb
			.from('game_plan_players')
			.update({ score: n, played: true })
			.eq('id', player.id);
		saving = false;
		if (!error) onSaved?.();
	}

	const name = $derived(player.players?.name ?? player.player_name ?? '–');
</script>

<div class="srow" class:srow--saved={player.played}>
	<span class="srow-pos">{player.position ?? '–'}</span>
	<span class="srow-name">{name}</span>
	<input
		class="srow-input"
		type="number"
		inputmode="numeric"
		min="0"
		max="999"
		placeholder="Holz"
		bind:value={draft}
		onblur={save}
	/>
	{#if saving}<span class="material-symbols-outlined spin">autorenew</span>
	{:else if player.played}<span class="material-symbols-outlined ok">check_circle</span>
	{/if}
</div>

<style>
	.srow {
		display: grid;
		grid-template-columns: 28px 1fr 90px 24px;
		gap: 8px;
		align-items: center;
		padding: 8px 10px;
		background: #fff;
		border: 1px solid var(--color-border, #eee);
		border-radius: 8px;
	}
	.srow--saved { background: #f3fbf4; border-color: rgba(42,157,87,0.3); }
	.srow-pos { font-weight: 700; color: var(--color-primary, #CC0000); text-align: center; }
	.srow-name { font-weight: 500; }
	.srow-input {
		padding: 6px 10px;
		border: 1px solid var(--color-border, #ddd);
		border-radius: 6px;
		font-size: 16px;
		text-align: right;
		font-weight: 600;
	}
	.ok { color: var(--color-success, #2a9d57); font-size: 1.2rem; }
	.spin { animation: sp 1s linear infinite; color: var(--color-text-soft, #999); font-size: 1.1rem; }
	@keyframes sp { to { transform: rotate(360deg); } }
</style>
