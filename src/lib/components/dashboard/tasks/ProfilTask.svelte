<script>
	import { goto } from '$app/navigation';
	import { setSubtab } from '$lib/stores/subtab.js';

	let { missingFields } = $props();

	const MAX_CHIPS = 5;

	let visible = $derived(missingFields.slice(0, MAX_CHIPS));
	let rest    = $derived(Math.max(0, missingFields.length - MAX_CHIPS));
	let count   = $derived(missingFields.length);

	function openProfil() {
		setSubtab('/profil', 'uebersicht');
		goto('/profil');
	}
</script>

{#if count > 0}
	<div class="pt">
		<div class="pt-head">
			<span class="pt-icon material-symbols-outlined">account_circle</span>
			<div class="pt-head-text">
				<span class="pt-title">Profil vervollständigen</span>
				<span class="pt-sub">
					{count === 1 ? '1 fehlendes Feld' : `${count} fehlende Felder`}
				</span>
			</div>
		</div>

		<div class="pt-chips">
			{#each visible as f (f.key)}
				<span class="pt-chip">{f.label}</span>
			{/each}
			{#if rest > 0}
				<span class="pt-chip pt-chip--more">+{rest} mehr</span>
			{/if}
		</div>

		<div class="pt-actions">
			<button
				class="mw-btn mw-btn--primary mw-btn--wide"
				onclick={openProfil}
				aria-label="Profil vervollständigen"
			>
				<span class="material-symbols-outlined">edit</span>
				Vervollständigen
			</button>
		</div>
	</div>
{/if}

<style>
	.pt {
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-left: 4px solid var(--color-primary);
		border-radius: var(--radius-lg);
		padding: var(--space-3) var(--space-4);
		box-shadow: var(--shadow-card);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.pt-head {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.pt-icon {
		font-size: 1.2rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
		flex-shrink: 0;
	}
	.pt-head-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.pt-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.pt-sub {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}

	.pt-chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-1);
		margin-top: var(--space-1);
	}
	.pt-chip {
		display: inline-flex;
		align-items: center;
		padding: 3px 10px;
		border-radius: var(--radius-full);
		background: var(--color-surface-container);
		color: var(--color-on-surface-variant);
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 500;
		border: 1px solid var(--color-outline-variant);
	}
	.pt-chip--more {
		background: transparent;
		border-style: dashed;
	}

	.pt-actions {
		display: flex;
		margin-top: var(--space-1);
	}
	.pt-actions :global(.mw-btn) {
		flex: 1;
	}
</style>
