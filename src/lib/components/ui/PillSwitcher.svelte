<script>
	let { items = [], value, onSelect } = $props();
</script>

<div class="pill-switcher" role="tablist">
	{#each items as item (item.key)}
		<button
			type="button"
			role="tab"
			class="pill"
			class:active={value === item.key}
			aria-selected={value === item.key}
			onclick={() => onSelect?.(item.key)}
		>
			{#if item.icon}
				<span class="material-symbols-outlined" aria-hidden="true">{item.icon}</span>
			{/if}
			<span class="pill-label">{item.label}</span>
		</button>
	{/each}
</div>

<style>
	.pill-switcher {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: var(--space-1);
		width: 100%;
		padding: var(--space-1);
		background: var(--color-surface-container);
		border-radius: var(--radius-full);
		border-radius: 999px;
		overflow: hidden;
	}

	.pill {
		flex: 1 1 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-1);
		min-height: 40px;
		padding: var(--space-2) var(--space-3);
		border: none;
		background: transparent;
		color: var(--color-on-surface-variant);
		font-family: var(--font-body);
		font: var(--text-label-md);
		border-radius: var(--radius-full);
		border-radius: 999px;
		cursor: pointer;
		transition: background-color 150ms ease, color 150ms ease;
	}

	.pill.active {
		background: var(--color-primary);
		color: white;
	}

	.pill .material-symbols-outlined {
		font-size: 18px;
		line-height: 1;
	}

	.pill-label {
		white-space: nowrap;
	}
</style>
