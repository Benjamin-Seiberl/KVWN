<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import BottomSheet from './BottomSheet.svelte';

	const DAY_LONG  = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
	const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
	const MONTHS    = ['Jänner', 'Februar', 'März', 'April', 'Mai', 'Juni',
	                   'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

	let trainings = $state([]);
	let loading   = $state(true);
	let sheetOpen = $state(false);

	onMount(async () => {
		const { data } = await sb
			.from('trainings')
			.select('datetime, lane_1, lane_2, lane_3, lane_4')
			.gte('datetime', new Date().toISOString())
			.order('datetime')
			.limit(5);
		trainings = data ?? [];
		loading   = false;
	});

	// Nächstes Training
	let next = $derived.by(() => trainings[0] ?? null);

	// Weitere Trainings (ohne das erste)
	let upcoming = $derived.by(() => trainings.slice(1));

	function formatDateLong(dt) {
		const d = new Date(dt);
		return DAY_LONG[d.getDay()] + ', ' + d.getDate() + '. ' + MONTHS[d.getMonth()];
	}

	function formatDateShort(dt) {
		const d = new Date(dt);
		return DAY_SHORT[d.getDay()] + ', ' + d.getDate() + '. ' + MONTHS[d.getMonth()];
	}

	function formatTime(dt) {
		const d = new Date(dt);
		return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
	}

	// Widget-Vorschau: kurzes Datum
	let previewDate = $derived.by(() => {
		if (!next) return '';
		const d = new Date(next.datetime);
		return DAY_SHORT[d.getDay()] + ' ' + d.getDate() + '., ' + formatTime(next.datetime) + ' Uhr';
	});

	// Bahnen aufbereiten
	function getLanes(t) {
		return [
			{ nr: 1, player: t.lane_1?.trim() || null },
			{ nr: 2, player: t.lane_2?.trim() || null },
			{ nr: 3, player: t.lane_3?.trim() || null },
			{ nr: 4, player: t.lane_4?.trim() || null },
		];
	}
</script>

<!-- Widget-Karte: Tap öffnet Bottom Sheet -->
<button
	class="widget widget--card widget--half training-widget-btn"
	onclick={() => sheetOpen = true}
	aria-label="Training-Details öffnen"
>
	<div class="widget-header">
		<span class="material-symbols-outlined widget-icon">fitness_center</span>
		<h3 class="widget-title">Training</h3>
		<span class="material-symbols-outlined training-chevron">chevron_right</span>
	</div>
	<div class="training-info">
		{#if loading}
			<p class="training-name">Lade…</p>
		{:else if !next}
			<p class="training-name">Kein Training eingetragen</p>
		{:else}
			<div class="training-meta">
				<span class="material-symbols-outlined">calendar_today</span>
				<span>{previewDate}</span>
			</div>
		{/if}
	</div>
</button>

<!-- Bottom Sheet: Trainingsdetails -->
<BottomSheet bind:open={sheetOpen} title="Training">
	{#if !next}
		<p style="color: var(--color-on-surface-variant); margin: 0;">
			Kein Training eingetragen.
		</p>
	{:else}
		<!-- Nächstes Training: Hero-Karte -->
		<div class="bs-training-next">
			<p class="bs-training-next-label">Nächstes Training</p>
			<p class="bs-training-next-date">{formatDateLong(next.datetime)}</p>
			<p class="bs-training-next-time">{formatTime(next.datetime)} Uhr</p>
		</div>

		<!-- Bahnen-Belegung -->
		<p class="bs-section-title">Bahnen</p>
		<div class="bs-lanes">
			{#each getLanes(next) as lane}
				<div class="bs-lane" class:bs-lane--free={!lane.player}>
					<span class="bs-lane-nr">Bahn {lane.nr}</span>
					<span class="bs-lane-player">{lane.player ?? 'Frei'}</span>
				</div>
			{/each}
		</div>

		<!-- Feste Trainingszeiten -->
		<p class="bs-section-title">Trainingszeiten</p>
		<div class="bs-info-row">
			<span class="material-symbols-outlined">schedule</span>
			<span class="bs-info-row-text">Donnerstag, 15:00 – 21:00 Uhr</span>
		</div>
		<div class="bs-info-row">
			<span class="material-symbols-outlined">location_on</span>
			<span class="bs-info-row-text">Kegelzentrum Wiener Neustadt</span>
		</div>

		<!-- Weitere Trainings -->
		{#if upcoming.length > 0}
			<p class="bs-section-title" style="margin-top: var(--space-5);">Weitere Trainings</p>
			<div class="bs-training-list">
				{#each upcoming as t}
					<div class="bs-training-row">
						<span class="bs-training-row-date">{formatDateShort(t.datetime)}</span>
						<span class="bs-training-row-time">{formatTime(t.datetime)} Uhr</span>
					</div>
				{/each}
			</div>
		{/if}
	{/if}
</BottomSheet>
