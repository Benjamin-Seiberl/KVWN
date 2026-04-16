<script>
	import { goto } from '$app/navigation';
	import AbsenceSheet from './AbsenceSheet.svelte';

	let absenceOpen = $state(false);

	const actions = [
		{ icon: 'event_busy', label: 'Abwesenheit',   color: '#CC0000', action: () => { absenceOpen = true; } },
		{ icon: 'sports',     label: 'Spielbetrieb',   color: '#1A56DB', action: () => goto('/spielbetrieb') },
		{ icon: 'today',      label: 'Kalender',       color: '#276749', action: () => goto('/kalender') },
		{ icon: 'person',     label: 'Profil',         color: '#553C9A', action: () => goto('/profil') },
	];
</script>

<div class="qa">
	<div class="qa-header">
		<span class="material-symbols-outlined qa-icon">bolt</span>
		<h3 class="qa-title">Schnellzugriff</h3>
	</div>
	<div class="qa-grid">
		{#each actions as a}
			<button class="qa-btn" onclick={a.action} aria-label={a.label}>
				<div class="qa-btn-icon" style="background: {a.color}10; color: {a.color}">
					<span class="material-symbols-outlined">{a.icon}</span>
				</div>
				<span class="qa-btn-label">{a.label}</span>
			</button>
		{/each}
	</div>
</div>

<AbsenceSheet bind:open={absenceOpen} />

<style>
	.qa {
		padding: 0 var(--space-5);
		margin: var(--space-2) 0;
	}
	.qa-header {
		display: flex;
		align-items: center;
		gap: 7px;
		margin-bottom: var(--space-3);
	}
	.qa-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.qa-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	.qa-grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-2);
	}

	.qa-btn {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		padding: var(--space-3) var(--space-1);
		border: none;
		border-radius: var(--radius-lg);
		background: var(--color-surface-container-lowest);
		box-shadow: 0 1px 4px rgba(0,0,0,0.04);
		cursor: pointer;
		font: inherit;
		transition: transform 0.1s ease;
	}
	.qa-btn:active {
		transform: scale(0.93);
	}

	.qa-btn-icon {
		width: 40px;
		height: 40px;
		border-radius: var(--radius-md);
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.qa-btn-icon .material-symbols-outlined {
		font-size: 1.2rem;
	}

	.qa-btn-label {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-on-surface-variant);
		white-space: nowrap;
	}
</style>
