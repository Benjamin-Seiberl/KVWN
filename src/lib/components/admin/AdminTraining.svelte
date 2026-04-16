<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false) } = $props();

	const DAYS  = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
	const HOURS = Array.from({ length: 10 }, (_, i) => 14 + i); // 14..23

	let templates = $state([]);
	let loading   = $state(true);
	let lanes     = $state(4);

	async function load() {
		loading = true;
		const { data } = await sb.from('training_templates').select('*');
		templates = data ?? [];
		loading = false;
	}

	// day_of_week mapping: grid index Mo=0..So=6 → DB: 0=So, 1=Mo..6=Sa
	function toDow(dayIdx) {
		return dayIdx === 6 ? 0 : dayIdx + 1;
	}

	function isActive(dayIdx, hour) {
		const dow = toDow(dayIdx);
		return templates.some(t =>
			t.active && t.day_of_week === dow &&
			Number(String(t.start_time).slice(0, 2)) === hour
		);
	}

	function activeCount() {
		return templates.filter(t => t.active).length;
	}

	async function toggle(dayIdx, hour) {
		const dow = toDow(dayIdx);
		const startTime = `${String(hour).padStart(2, '0')}:00`;
		const existing = templates.find(t =>
			t.day_of_week === dow &&
			Number(String(t.start_time).slice(0, 2)) === hour
		);

		if (existing) {
			await sb.from('training_templates')
				.update({ active: !existing.active, lane_count: lanes })
				.eq('id', existing.id);
		} else {
			await sb.from('training_templates').insert({
				day_of_week: dow,
				start_time: startTime,
				end_time: `${String(hour + 1).padStart(2, '0')}:00`,
				lane_count: lanes,
				active: true,
			});
		}
		await load();
	}

	function save() {
		open = false;
		setTimeout(() => triggerToast(`${activeCount()} Trainings-Slots aktiv`), 300);
	}

	// Load when sheet opens
	$effect(() => {
		if (open) load();
	});
</script>

<BottomSheet bind:open title="Training verwalten">
	{#if loading}
		<div class="at-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
		</div>
	{:else}
		<!-- Bahnen-Auswahl -->
		<div class="at-lanes">
			<span class="at-lanes-label">Bahnen pro Block</span>
			<div class="at-lanes-options">
				{#each [4, 6, 8] as n}
					<button
						class="at-lane-btn"
						class:at-lane-btn--active={lanes === n}
						onclick={() => { lanes = n; }}
					>{n}</button>
				{/each}
			</div>
		</div>

		<!-- Wochenplan-Grid -->
		<p class="at-hint">Tippe auf eine Zelle um 1h-Blöcke zu aktivieren.</p>
		<div class="at-grid" style="grid-template-columns: 48px repeat(7, 1fr)">
			<!-- Header -->
			<div class="at-cell at-cell--head"></div>
			{#each DAYS as d}
				<div class="at-cell at-cell--head">{d}</div>
			{/each}

			<!-- Stunden-Zeilen -->
			{#each HOURS as h}
				<div class="at-cell at-cell--time">{h}:00</div>
				{#each DAYS as _, dayIdx}
					{@const active = isActive(dayIdx, h)}
					<button
						class="at-cell at-cell--slot"
						class:at-cell--active={active}
						onclick={() => toggle(dayIdx, h)}
						aria-label="{DAYS[dayIdx]} {h}:00 {active ? 'aktiv' : 'inaktiv'}"
					>
						{#if active}
							<span class="material-symbols-outlined at-check">check</span>
						{/if}
					</button>
				{/each}
			{/each}
		</div>

		<!-- Fertig-Button -->
		<button class="mw-btn mw-btn--primary mw-btn--wide at-done" onclick={save}>
			<span class="material-symbols-outlined">check</span>
			Fertig
		</button>
	{/if}
</BottomSheet>

<style>
	/* Bahnen-Auswahl */
	.at-lanes {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.at-lanes-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-outline);
	}
	.at-lanes-options {
		display: flex;
		gap: var(--space-1);
	}
	.at-lane-btn {
		width: 36px; height: 36px;
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-low);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.at-lane-btn--active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: #fff;
	}

	/* Hinweis */
	.at-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-3);
	}

	/* Grid */
	.at-grid {
		display: grid;
		gap: 3px;
		margin-bottom: var(--space-4);
	}
	.at-cell {
		text-align: center;
		font-size: 0.72rem;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.at-cell--head {
		font-weight: 700;
		color: var(--color-outline);
		padding: 4px 0;
		font-size: var(--text-label-sm);
	}
	.at-cell--time {
		color: var(--color-on-surface-variant);
		font-size: 0.7rem;
		padding: 2px 0;
	}
	.at-cell--slot {
		min-height: 28px;
		background: var(--color-surface-container-low);
		border: 1px solid var(--color-outline-variant);
		border-radius: 6px;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 0.15s, border-color 0.15s;
		padding: 0;
	}
	.at-cell--active {
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.at-check {
		font-size: 0.85rem;
		color: #fff;
		font-variation-settings: 'FILL' 1, 'wght' 600;
	}

	/* Fertig */
	.at-done {
		margin-top: var(--space-2);
	}

	/* Loading */
	.at-loading {
		padding: var(--space-4) 0;
	}
</style>
