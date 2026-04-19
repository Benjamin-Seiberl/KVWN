<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { goto } from '$app/navigation';

	import { fmtDate } from '$lib/utils/dates.js';

	let events  = $state([]);
	let loading = $state(true);

	onMount(async () => {
		const todayStr = new Date().toISOString().split('T')[0];
		const { data } = await sb
			.from('events')
			.select('id, title, date, time, location')
			.gte('date', todayStr)
			.order('date')
			.order('time')
			.limit(3);
		events = data ?? [];
		loading = false;
	});

	function fmtTime(t) { return t ? t.substring(0, 5) : ''; }
</script>

{#if loading || events.length > 0}
<div class="ue">
	<div class="ue-header">
		<div class="ue-header-left">
			<span class="material-symbols-outlined ue-icon">celebration</span>
			<h3 class="ue-title">Events</h3>
		</div>
		{#if events.length > 0}
			<button class="ue-more" onclick={() => goto('/kalender')}>
				Alle <span class="material-symbols-outlined" style="font-size:0.9rem">chevron_right</span>
			</button>
		{/if}
	</div>

	{#if loading}
		<div class="ue-list">
			{#each [0,1] as _}
				<div class="ue-item ue-item--skel">
					<div class="ue-item-date-col">
						<div class="skel-bar shimmer-box" style="width:24px;height:10px;border-radius:3px"></div>
						<div class="skel-bar shimmer-box" style="width:18px;height:18px;border-radius:4px;margin-top:2px"></div>
					</div>
					<div class="ue-item-body">
						<div class="skel-bar shimmer-box" style="width:70%;height:13px;border-radius:5px"></div>
						<div class="skel-bar shimmer-box" style="width:50%;height:10px;border-radius:4px;margin-top:4px"></div>
					</div>
				</div>
			{/each}
		</div>
	{:else}
		<div class="ue-list">
			{#each events as ev}
				{@const d = new Date(ev.date + 'T12:00')}
				<div class="ue-item">
					<div class="ue-item-date-col">
						<span class="ue-day">{DAY_SHORT[d.getDay()]}</span>
						<span class="ue-num">{d.getDate()}</span>
						<span class="ue-mon">{MONTHS[d.getMonth()]}</span>
					</div>
					<div class="ue-item-body">
						<span class="ue-item-title">{ev.title}</span>
						<span class="ue-item-meta">
							{#if ev.time}{fmtTime(ev.time)} Uhr{/if}
							{#if ev.location} · {ev.location}{/if}
						</span>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>
{/if}

<style>
	.ue {
		padding: 0 var(--space-5);
		margin: var(--space-2) 0;
	}
	.ue-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.ue-header-left {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.ue-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.ue-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}
	.ue-more {
		display: flex;
		align-items: center;
		gap: 2px;
		border: none;
		background: none;
		font: inherit;
		font-size: var(--text-body-sm);
		font-weight: 600;
		color: var(--color-primary);
		cursor: pointer;
		padding: 4px 6px;
		border-radius: var(--radius-md);
	}
	.ue-more:active { opacity: 0.7; }

	.ue-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.ue-item {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-lg);
		box-shadow: 0 1px 4px rgba(0,0,0,0.04);
	}
	.ue-item--skel {
		pointer-events: none;
	}

	.ue-item-date-col {
		width: 40px;
		display: flex;
		flex-direction: column;
		align-items: center;
		flex-shrink: 0;
	}
	.ue-day {
		font-size: 0.6rem;
		font-weight: 700;
		text-transform: uppercase;
		color: var(--color-primary);
		letter-spacing: 0.03em;
	}
	.ue-num {
		font-family: var(--font-display);
		font-size: 1.15rem;
		font-weight: 800;
		color: var(--color-on-surface);
		line-height: 1.1;
	}
	.ue-mon {
		font-size: 0.55rem;
		font-weight: 600;
		color: var(--color-outline);
		text-transform: uppercase;
	}

	.ue-item-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.ue-item-title {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.ue-item-meta {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
	}
</style>
