<script>
	import UebersichtTab from '$lib/components/kalender/UebersichtTab.svelte';
	import WocheTab      from '$lib/components/kalender/WocheTab.svelte';
	import MonatTab      from '$lib/components/kalender/MonatTab.svelte';

	let view = $state('agenda'); // 'agenda' | 'woche' | 'monat'
</script>

<div class="page active">
	<div class="kv-switcher-wrap">
		<div class="kv-switcher" role="tablist" aria-label="Kalender-Ansicht">
			<button
				class="kv-switcher-btn"
				class:kv-switcher-btn--active={view === 'agenda'}
				role="tab"
				aria-selected={view === 'agenda'}
				onclick={() => view = 'agenda'}
			>
				<span class="material-symbols-outlined">dashboard</span>
				Agenda
			</button>
			<button
				class="kv-switcher-btn"
				class:kv-switcher-btn--active={view === 'woche'}
				role="tab"
				aria-selected={view === 'woche'}
				onclick={() => view = 'woche'}
			>
				<span class="material-symbols-outlined">view_week</span>
				Woche
			</button>
			<button
				class="kv-switcher-btn"
				class:kv-switcher-btn--active={view === 'monat'}
				role="tab"
				aria-selected={view === 'monat'}
				onclick={() => view = 'monat'}
			>
				<span class="material-symbols-outlined">calendar_month</span>
				Monat
			</button>
		</div>
	</div>

	{#if view === 'agenda'}
		<UebersichtTab />
	{:else if view === 'woche'}
		<WocheTab />
	{:else if view === 'monat'}
		<MonatTab />
	{/if}
</div>

<style>
	.kv-switcher-wrap {
		display: flex;
		justify-content: center;
		padding: var(--space-4) var(--space-5) 0;
	}
	.kv-switcher {
		display: inline-flex;
		padding: 3px;
		background: var(--color-surface-container);
		border: 1px solid var(--color-outline-variant);
		border-radius: 999px;
		gap: 2px;
	}
	.kv-switcher-btn {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 6px 14px;
		background: none;
		border: none;
		border-radius: 999px;
		font-family: inherit;
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 120ms ease, color 120ms ease;
	}
	.kv-switcher-btn .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.kv-switcher-btn--active {
		background: var(--color-primary);
		color: #fff;
	}
</style>
