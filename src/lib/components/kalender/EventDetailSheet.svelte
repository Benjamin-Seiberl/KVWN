<script>
	import { fmtDate } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { open = $bindable(false), event = null } = $props();
</script>

<BottomSheet bind:open title="Termin">
	{#if event}
		<div class="ed">
			<h2 class="ed-title">{event.title}</h2>

			<div class="ed-meta">
				<div class="ed-meta-row">
					<span class="material-symbols-outlined">calendar_today</span>
					<span>{fmtDate(event.date)}</span>
				</div>
				{#if event.time}
					<div class="ed-meta-row">
						<span class="material-symbols-outlined">schedule</span>
						<span>{shortTime(event.time)} Uhr</span>
					</div>
				{/if}
				{#if event.location}
					<div class="ed-meta-row">
						<span class="material-symbols-outlined">location_on</span>
						<span>{event.location}</span>
					</div>
				{/if}
			</div>

			{#if event.description}
				<p class="ed-desc">{event.description}</p>
			{/if}
		</div>
	{/if}
</BottomSheet>

<style>
	.ed { display: flex; flex-direction: column; gap: var(--space-4); padding-bottom: var(--space-4); }

	.ed-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-headline-sm);
		font-weight: 800;
		line-height: 1.2;
		color: var(--color-on-surface);
	}

	.ed-meta { display: flex; flex-direction: column; gap: var(--space-2); }
	.ed-meta-row {
		display: flex; align-items: center; gap: var(--space-2);
		font-size: var(--text-body-md); color: var(--color-on-surface);
	}
	.ed-meta-row .material-symbols-outlined {
		font-size: 1rem; color: #2a78b4;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.ed-desc {
		margin: 0;
		padding: var(--space-4);
		background: var(--color-surface-container);
		border-radius: var(--radius-md);
		font-size: var(--text-body-md);
		line-height: 1.5;
		color: var(--color-on-surface);
		white-space: pre-wrap;
	}
</style>
