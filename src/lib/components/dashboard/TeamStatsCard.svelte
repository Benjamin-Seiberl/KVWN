<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	let totalGames   = $state(0);
	let avgTeamScore = $state(0);
	let activePlayers = $state(0);
	let loading = $state(true);

	onMount(async () => {
		const [{ count: games }, { data: scores }, { count: players }] = await Promise.all([
			sb.from('game_plan_players').select('*', { count: 'exact', head: true }).eq('played', true),
			sb.from('game_plan_players').select('score').eq('played', true).not('score', 'is', null).limit(200),
			sb.from('players').select('*', { count: 'exact', head: true }).eq('active', true),
		]);

		totalGames = games ?? 0;
		activePlayers = players ?? 0;
		if (scores?.length) {
			avgTeamScore = Math.round(scores.reduce((a, b) => a + b.score, 0) / scores.length);
		}
		loading = false;
	});
</script>

<div class="ts widget widget--card widget--half">
	<div class="widget-header">
		<span class="material-symbols-outlined widget-icon">groups</span>
		<h3 class="widget-title">Team</h3>
	</div>

	{#if loading}
		<div class="ts-loading">
			<div class="skel-bar shimmer-box" style="width:40px;height:24px;border-radius:6px"></div>
			<div class="skel-bar shimmer-box" style="width:60px;height:12px;border-radius:4px;margin-top:4px"></div>
		</div>
	{:else}
		<div class="ts-stats">
			<div class="ts-stat">
				<span class="ts-stat-value">{activePlayers}</span>
				<span class="ts-stat-label">Spieler</span>
			</div>
			<div class="ts-divider"></div>
			<div class="ts-stat">
				<span class="ts-stat-value">{avgTeamScore || '–'}</span>
				<span class="ts-stat-label">⌀ Holz</span>
			</div>
		</div>
	{/if}
</div>

<style>
	.ts {
		cursor: default;
	}
	.ts-loading {
		display: flex;
		flex-direction: column;
	}
	.ts-stats {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.ts-stat {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
	}
	.ts-stat-value {
		font-family: var(--font-display);
		font-size: 1.3rem;
		font-weight: 800;
		color: var(--color-on-surface);
		line-height: 1.1;
	}
	.ts-stat-label {
		font-size: 0.6rem;
		font-weight: 600;
		color: var(--color-outline);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.ts-divider {
		width: 1px;
		height: 28px;
		background: var(--color-outline-variant);
		flex-shrink: 0;
	}
</style>
