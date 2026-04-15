<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	const DAYS = ['Mo','Di','Mi','Do','Fr','Sa','So']; // ISO: 1=Mo..7=So; day_of_week 0=So..6=Sa
	const HOURS = Array.from({ length: 10 }, (_, i) => 14 + i); // 14..23

	let templates = $state([]);
	let lanes = $state(4);

	async function load() {
		const { data } = await sb.from('training_templates').select('*');
		templates = data ?? [];
	}

	function isActive(day, hour) {
		// day_of_week: 0=So..6=Sa. Unser Index: Mo=0..So=6
		const dow = day === 6 ? 0 : day + 1;
		return templates.some(t => t.active && t.day_of_week === dow && Number(String(t.start_time).slice(0,2)) === hour);
	}

	async function toggle(day, hour) {
		const dow = day === 6 ? 0 : day + 1;
		const startTime = `${String(hour).padStart(2, '0')}:00`;
		const existing = templates.find(t => t.day_of_week === dow && Number(String(t.start_time).slice(0,2)) === hour);
		if (existing) {
			await sb.from('training_templates').update({ active: !existing.active, lane_count: lanes }).eq('id', existing.id);
		} else {
			await sb.from('training_templates').insert({
				day_of_week: dow,
				start_time: startTime,
				end_time: `${String(hour + 1).padStart(2, '0')}:00`,
				lane_count: lanes,
				active: true,
			});
		}
		load();
	}

	onMount(load);
</script>

<div class="page">
	<h2>Trainings-Wochenplan</h2>
	<p class="hint">Klicke auf eine Zelle, um einen 1h-Block aktiv/inaktiv zu schalten.</p>
	<label class="lanes">
		<span>Bahnen pro Block:</span>
		<select bind:value={lanes}>
			<option value={4}>4</option>
			<option value={6}>6</option>
			<option value={8}>8</option>
		</select>
	</label>

	<div class="grid">
		<div class="cell cell--head"></div>
		{#each DAYS as d}<div class="cell cell--head">{d}</div>{/each}
		{#each HOURS as h}
			<div class="cell cell--time">{h}:00</div>
			{#each DAYS as _, dayIdx}
				<button
					class="cell cell--slot"
					class:active={isActive(dayIdx, h)}
					onclick={() => toggle(dayIdx, h)}
					aria-label="{DAYS[dayIdx]} {h}:00"
				></button>
			{/each}
		{/each}
	</div>
</div>

<style>
	h2 { font-family: 'Lexend'; font-weight: 600; font-size: 1.1rem; margin: 0 0 var(--space-2); }
	.hint { font-size: 0.82rem; color: var(--color-text-soft, #888); margin: 0 0 var(--space-3); }
	.lanes { display: inline-flex; gap: 8px; align-items: center; margin-bottom: var(--space-3); font-size: 0.9rem; }
	.lanes select { padding: 4px 8px; border: 1px solid var(--color-border, #ddd); border-radius: 8px; font-size: 16px; }
	.grid {
		display: grid;
		grid-template-columns: 48px repeat(7, 1fr);
		gap: 3px;
	}
	.cell { padding: 8px 2px; text-align: center; font-size: 0.75rem; }
	.cell--head { font-weight: 600; color: var(--color-text-soft, #666); }
	.cell--time { color: var(--color-text-soft, #888); }
	.cell--slot { background: var(--color-surface, #f5f5f5); border: 1px solid var(--color-border, #eee); border-radius: 6px; cursor: pointer; min-height: 32px; }
	.cell--slot.active { background: var(--color-primary, #CC0000); border-color: var(--color-primary, #CC0000); }
</style>
