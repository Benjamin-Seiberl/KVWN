<script>
	/**
	 * Generic section card. Props:
	 *   section: string — identifier passed back via onEdit (e.g. 'daten', 'kontakt').
	 *   title:   string — card header.
	 *   icon:    string — material symbol name.
	 *   rows:    Array<{ key, label, value, icon, readonly?, valueClass? }>.
	 *   onEdit:  (section, focus) => void.
	 */
	let { section, title, icon, rows = [], onEdit } = $props();
</script>

<section class="data-card">
	<div class="data-card-head">
		<h3 class="section-title">
			<span class="material-symbols-outlined">{icon}</span>
			{title}
		</h3>
		<button class="data-card-edit" onclick={() => onEdit?.(section, '')}>
			<span class="material-symbols-outlined">edit</span>
			Bearbeiten
		</button>
	</div>
	<div class="data-rows">
		{#each rows as row (row.key)}
			<button
				class="data-row"
				class:data-row--readonly={row.readonly}
				onclick={() => !row.readonly && onEdit?.(section, row.key)}
				disabled={row.readonly}
			>
				<span class="material-symbols-outlined data-row-icon">{row.icon}</span>
				<div class="data-row-text">
					<span class="data-row-label">{row.label}</span>
					{#if row.value}
						<span class="data-row-value {row.valueClass ?? ''}">{row.value}</span>
					{:else}
						<span class="data-row-value data-row-value--empty">Nicht angegeben</span>
					{/if}
				</div>
				{#if !row.readonly}
					<span class="material-symbols-outlined data-row-arrow">chevron_right</span>
				{/if}
			</button>
		{/each}
	</div>
</section>

<style>
	.data-card {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.data-card-head { display: flex; justify-content: space-between; align-items: center; }

	.data-card-edit {
		display: inline-flex; align-items: center; gap: 4px;
		background: transparent; border: 1px solid var(--color-outline-variant);
		border-radius: 999px; padding: 4px 10px; font-size: 0.72rem; font-weight: 700;
		color: var(--color-on-surface-variant); cursor: pointer; font-family: inherit;
	}
	.data-card-edit .material-symbols-outlined { font-size: 0.88rem; }
	.data-card-edit:active { background: var(--color-surface-container-low); }

	.data-rows { display: flex; flex-direction: column; }
	.data-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) 0; border: none; background: none;
		border-top: 1px solid var(--color-surface-container);
		text-align: left; font-family: inherit; cursor: pointer; width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.data-row:first-child { border-top: none; }
	.data-row:active:not(.data-row--readonly) { background: var(--color-surface-container-low); }
	.data-row--readonly { cursor: default; }
	.data-row-icon {
		font-size: 1.1rem; color: var(--color-primary); flex-shrink: 0;
		width: 24px; text-align: center;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.data-row-text { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
	.data-row-label { font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-on-surface-variant); }
	.data-row-value { font-size: 0.92rem; font-weight: 600; color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.data-row-value--empty { color: var(--color-outline); font-weight: 500; font-style: italic; }
	.data-row-value:global(.val-expired) { color: var(--color-primary); font-weight: 800; }
	.data-row-value:global(.val-soon) { color: #b45309; font-weight: 700; }
	.data-row-arrow { color: var(--color-on-surface-variant); font-size: 1rem; flex-shrink: 0; }
</style>
