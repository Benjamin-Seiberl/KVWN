<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { DAY_SHORT, daysUntil } from '$lib/utils/dates.js';

	let match    = $state(null);
	let position = $state(null);
	let loading  = $state(true);

	function formatTime(t) { return t ? t.substring(0, 5) : ''; }

	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_SHORT[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '.';
	}

	async function load() {
		const pid = $playerId;
		if (!pid) { loading = false; return; }

		const todayStr = new Date().toISOString().split('T')[0];

		// Find all game_plan_players entries for this player in future matches
		const { data: entries } = await sb
			.from('game_plan_players')
			.select('position, game_plans!inner(cal_week, league_id)')
			.eq('player_id', pid);

		if (!entries?.length) { loading = false; return; }

		// Get future matches
		const { data: futureMatches } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', todayStr)
			.order('date')
			.order('time');

		if (!futureMatches?.length) { loading = false; return; }

		// Find the earliest match where the player is on the lineup
		for (const m of futureMatches) {
			const entry = entries.find(e =>
				e.game_plans.cal_week === m.cal_week &&
				e.game_plans.league_id === m.league_id
			);
			if (entry) {
				match = m;
				position = entry.position;
				break;
			}
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
</script>

{#if loading}
	<div class="nmc-wrap">
		<div class="nmc nmc--skeleton">
			<div class="nmc-icon-wrap shimmer-box"></div>
			<div class="nmc-body">
				<div class="skel-bar shimmer-box" style="width:50%;height:10px;border-radius:4px"></div>
				<div class="skel-bar shimmer-box" style="width:80%;height:16px;border-radius:6px;margin-top:6px"></div>
				<div class="skel-bar shimmer-box" style="width:60%;height:10px;border-radius:4px;margin-top:6px"></div>
			</div>
		</div>
	</div>
{:else if match}
	{@const days = daysUntil(match.date)}
	<div class="nmc-wrap">
		<div class="sec-head">
			<span class="material-symbols-outlined sec-icon">emoji_events</span>
			<h3 class="sec-title">Mein nächstes Spiel</h3>
		</div>
		<button class="nmc" onclick={() => goto('/spielbetrieb')} aria-label="Mein nächstes Match">
			<div class="nmc-icon-wrap">
				<span class="nmc-days">{days}</span>
				<span class="nmc-days-label">{days === 1 ? 'Tag' : 'Tage'}</span>
			</div>
			<div class="nmc-body">
				<span class="nmc-label">Dein nächster Einsatz</span>
				<span class="nmc-opponent">vs. {match.opponent}</span>
				<span class="nmc-meta">
					{dateLabel(match)} · {formatTime(match.time)} Uhr
					{#if position} · Pos. {position}{/if}
				</span>
				<span class="nmc-league">{match.leagues?.name ?? ''}</span>
			</div>
			<span class="material-symbols-outlined nmc-chevron">chevron_right</span>
		</button>
	</div>
{/if}

<style>
	.nmc-wrap {
		padding: 0 var(--space-5);
	}

	/* Section-head — local copy of the page-level pattern (Svelte scoped CSS). */
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

	.nmc {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-card);
		padding: var(--space-4);
		border: none;
		width: 100%;
		text-align: left;
		cursor: pointer;
		font: inherit;
		border-left: 4px solid var(--color-primary);
		transition: transform 0.15s ease, box-shadow 0.15s ease;
	}
	.nmc:active {
		transform: scale(0.97);
	}
	.nmc--skeleton {
		pointer-events: none;
		border-left-color: var(--color-outline-variant);
	}

	.nmc-icon-wrap {
		width: 52px;
		height: 52px;
		border-radius: var(--radius-lg);
		background: linear-gradient(135deg, var(--color-primary), #7A0000);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		color: #fff;
	}
	.nmc-days {
		font-family: var(--font-display);
		font-size: 1.4rem;
		font-weight: 800;
		line-height: 1;
	}
	.nmc-days-label {
		font-size: 0.55rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		opacity: 0.85;
		line-height: 1;
	}

	.nmc-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.nmc-label {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-primary);
	}
	.nmc-opponent {
		font-family: var(--font-display);
		font-size: 1.05rem;
		font-weight: 700;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.nmc-meta {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
	}
	.nmc-league {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-outline);
		margin-top: 2px;
	}
	.nmc-chevron {
		color: var(--color-outline);
		font-size: 1.2rem;
		flex-shrink: 0;
	}
</style>
