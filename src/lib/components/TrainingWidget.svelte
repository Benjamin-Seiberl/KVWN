<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	let training = $state(null);
	let loading  = $state(true);

	onMount(async () => {
		const { data } = await sb
			.from('trainings')
			.select('datetime, lane_1, lane_2, lane_3, lane_4')
			.gte('datetime', new Date().toISOString())
			.order('datetime')
			.limit(1)
			.maybeSingle();
		training = data ?? null;
		loading  = false;
	});

	let dateStr = $derived(() => {
		if (!training) return '';
		const dt = new Date(training.datetime);
		return DAY_SHORT[dt.getDay()] + ' ' + dt.getDate() + '., ' +
			String(dt.getHours()).padStart(2, '0') + ':' +
			String(dt.getMinutes()).padStart(2, '0');
	});

	let lanesStr = $derived(() => {
		if (!training) return '';
		const lanes = [training.lane_1, training.lane_2, training.lane_3, training.lane_4]
			.map((l, i) => (l?.trim() ? 'Bahn ' + (i + 1) : null))
			.filter(Boolean);
		return lanes.length ? lanes.join(', ') : 'Bahnen 1–4';
	});
</script>

<div class="widget widget--card widget--half">
	<div class="widget-header">
		<span class="material-symbols-outlined widget-icon">fitness_center</span>
		<h3 class="widget-title">Training</h3>
	</div>
	<div class="training-info">
		{#if loading}
			<p class="training-name">Lade…</p>
		{:else if !training}
			<p class="training-name">Kein Training eingetragen</p>
		{:else}
			<p class="training-name">Training</p>
			<div class="training-meta">
				<span class="material-symbols-outlined">calendar_today</span>
				<span>{dateStr()}</span>
			</div>
			<div class="training-meta">
				<span class="material-symbols-outlined">sports_score</span>
				<span>{lanesStr()}</span>
			</div>
		{/if}
	</div>
</div>
