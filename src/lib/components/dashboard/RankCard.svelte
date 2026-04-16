<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';

	let rank     = $state(null);
	let total    = $state(0);
	let avgScore = $state(null);
	let loading  = $state(true);

	async function load() {
		const pid = $playerId;
		if (!pid) { loading = false; return; }

		// Fetch all players with their average scores to compute rank
		const { data: allScores } = await sb
			.from('game_plan_players')
			.select('player_id, score')
			.eq('played', true)
			.not('score', 'is', null);

		if (!allScores?.length) { loading = false; return; }

		// Group by player, calc average
		const byPlayer = {};
		for (const s of allScores) {
			if (!byPlayer[s.player_id]) byPlayer[s.player_id] = [];
			byPlayer[s.player_id].push(s.score);
		}

		const ranked = Object.entries(byPlayer)
			.map(([id, scores]) => ({
				id,
				avg: scores.reduce((a, b) => a + b, 0) / scores.length,
				games: scores.length,
			}))
			.filter(p => p.games >= 3) // Min 3 games to rank
			.sort((a, b) => b.avg - a.avg);

		total = ranked.length;
		const myIdx = ranked.findIndex(p => p.id === pid);
		if (myIdx >= 0) {
			rank = myIdx + 1;
			avgScore = Math.round(ranked[myIdx].avg);
		}
		loading = false;
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			load();
		}
	});

	let badge = $derived.by(() => {
		if (!rank || !total) return null;
		const pct = rank / total;
		if (pct <= 0.1)  return { label: 'Elite', color: '#CC0000', bg: 'rgba(204,0,0,0.08)' };
		if (pct <= 0.25) return { label: 'Gold', color: '#8a6f1e', bg: 'rgba(212,175,55,0.12)' };
		if (pct <= 0.5)  return { label: 'Silber', color: '#5a5a5a', bg: 'rgba(120,120,120,0.1)' };
		return { label: 'Bronze', color: '#8B5E3C', bg: 'rgba(139,94,60,0.1)' };
	});
</script>

<div class="rc widget widget--card widget--half" class:widget--gold-member={badge?.label === 'Gold' || badge?.label === 'Elite'}>
	<div class="widget-header">
		<span class="material-symbols-outlined widget-icon">leaderboard</span>
		<h3 class="widget-title">Rang</h3>
	</div>

	{#if loading}
		<div class="rc-loading">
			<div class="skel-bar shimmer-box" style="width:48px;height:28px;border-radius:8px"></div>
			<div class="skel-bar shimmer-box" style="width:36px;height:14px;border-radius:6px;margin-top:6px"></div>
		</div>
	{:else if rank}
		<div class="rank-display rank-display--stacked">
			<div class="rank-number">
				<span class="rank-value">#{rank}</span>
			</div>
			{#if badge}
				<span class="rc-badge" style="color:{badge.color};background:{badge.bg}">{badge.label}</span>
			{/if}
		</div>
		{#if avgScore}
			<span class="rc-avg">⌀ {avgScore} Holz</span>
		{/if}
		<span class="rc-total">von {total} Spielern</span>
	{:else}
		<p class="rc-no-data">Noch nicht genug Spiele</p>
	{/if}
</div>

<style>
	.rc {
		cursor: default;
	}
	.rc-loading {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
	}
	.rc-badge {
		font-size: 0.65rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 2px 8px;
		border-radius: var(--radius-full);
	}
	.rc-avg {
		font-size: var(--text-body-sm);
		font-weight: 600;
		color: var(--color-on-surface);
		margin-top: var(--space-1);
	}
	.rc-total {
		font-size: 0.65rem;
		color: var(--color-outline);
	}
	.rc-no-data {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0;
	}
</style>
