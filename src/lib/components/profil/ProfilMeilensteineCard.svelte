<script>
	/** @typedef {{ icon: string, label: string, sub: string }} Milestone */
	let { milestones = [] } = $props();
</script>

{#if milestones.length}
	<section class="milestones">
		<h3 class="section-title">
			<span class="material-symbols-outlined">workspace_premium</span>
			Karriere-Meilensteine
		</h3>
		<div class="milestones-scroll">
			{#each milestones as m, i (m.label + i)}
				<div class="milestone-card">
					<span class="milestone-icon material-symbols-outlined">{m.icon}</span>
					<p class="milestone-label">{m.label}</p>
					<p class="milestone-sub">{m.sub}</p>
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.milestones { display: flex; flex-direction: column; gap: var(--space-3); }

	.milestones-scroll {
		display: flex; gap: var(--space-3);
		overflow-x: auto; scrollbar-width: none;
		padding-bottom: 4px;
	}
	.milestones-scroll::-webkit-scrollbar { display: none; }

	.milestone-card {
		flex-shrink: 0; width: 120px;
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 14px;
		padding: var(--space-4) var(--space-3);
		display: flex; flex-direction: column; align-items: center;
		gap: var(--space-2); text-align: center;
	}
	.milestone-icon {
		font-size: 2rem; color: var(--color-secondary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.milestone-label {
		font-family: var(--font-display); font-weight: 800; font-size: 0.85rem;
		color: var(--color-on-surface); margin: 0; line-height: 1.2;
	}
	.milestone-sub { font-size: 0.72rem; color: var(--color-on-surface-variant); margin: 0; }
</style>
