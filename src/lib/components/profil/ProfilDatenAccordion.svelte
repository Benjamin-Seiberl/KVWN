<script>
	/**
	 * Akkordeon-Card für die fünf Profil-Datensektionen.
	 * Genau eine Sektion auf einmal offen. Initial alle zu.
	 *
	 * Props:
	 *   sections: Array<{
	 *     key: string,
	 *     title: string,
	 *     icon: string,
	 *     rows: Array<{ key, label, value, icon, readonly?, valueClass? }>
	 *   }>
	 *   onEdit: (sectionKey: string, focus: string) => void
	 */
	let { sections = [], onEdit } = $props();

	let openKey = $state(null);

	function toggle(key) {
		openKey = openKey === key ? null : key;
	}

	function missingCount(rows) {
		return rows.filter(r => !r.value && !r.readonly).length;
	}
</script>

<section class="acc-card">
	<div class="acc-head">
		<div class="acc-eyebrow">MEINE DATEN</div>
		<div class="acc-hairline"></div>
	</div>

	<div class="acc-list">
		{#each sections as section, idx (section.key)}
			{@const isOpen  = openKey === section.key}
			{@const missing = missingCount(section.rows)}
			{@const bodyId  = `acc-body-${section.key}`}

			<div class="acc-item" class:acc-item--first={idx === 0}>
				<button
					type="button"
					class="acc-trigger"
					class:acc-trigger--open={isOpen}
					aria-expanded={isOpen}
					aria-controls={bodyId}
					onclick={() => toggle(section.key)}
				>
					<span class="material-symbols-outlined acc-trigger-icon">{section.icon}</span>
					<span class="acc-trigger-title">{section.title}</span>
					{#if missing > 0}
						<span class="acc-dot-marker" aria-label="{missing} fehlend">
							<span class="acc-dot" aria-hidden="true"></span>
							<span class="acc-dot-count">{missing}</span>
						</span>
					{/if}
					<span class="material-symbols-outlined acc-chevron" aria-hidden="true">chevron_right</span>
				</button>

				<div
					class="acc-body-wrap"
					class:acc-body-wrap--open={isOpen}
					id={bodyId}
					role="region"
					aria-hidden={!isOpen}
				>
					<div class="acc-body-inner">
						<div class="acc-rows">
							{#each section.rows as row (row.key)}
								{#if row.readonly}
									<div class="acc-row acc-row--readonly">
										<span class="material-symbols-outlined acc-row-icon">{row.icon}</span>
										<div class="acc-row-text">
											<span class="acc-row-label">{row.label}</span>
											{#if row.value}
												<span class="acc-row-value {row.valueClass ?? ''}">{row.value}</span>
											{:else}
												<span class="acc-row-value acc-row-value--empty">Nicht angegeben</span>
											{/if}
										</div>
									</div>
								{:else}
									<button
										type="button"
										class="acc-row"
										onclick={() => onEdit?.(section.key, row.key)}
									>
										<span class="material-symbols-outlined acc-row-icon">{row.icon}</span>
										<div class="acc-row-text">
											<span class="acc-row-label">{row.label}</span>
											{#if row.value}
												<span class="acc-row-value {row.valueClass ?? ''}">{row.value}</span>
											{:else}
												<span class="acc-row-value acc-row-value--empty">Nicht angegeben</span>
											{/if}
										</div>
										<span class="material-symbols-outlined acc-row-arrow" aria-hidden="true">chevron_right</span>
									</button>
								{/if}
							{/each}
						</div>

						<button
							type="button"
							class="acc-section-edit"
							onclick={() => onEdit?.(section.key, '')}
						>
							BEARBEITEN
						</button>
					</div>
				</div>
			</div>
		{/each}
	</div>
</section>

<style>
	.acc-card {
		--acc-gold:     var(--color-secondary);
		--acc-hairline: linear-gradient(90deg, transparent, var(--acc-gold) 20%, var(--acc-gold) 80%, transparent);

		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-card);
		padding: 0;
		overflow: hidden;
	}

	/* ── Header ────────────────────────────────────────────────────────── */
	.acc-head {
		padding: var(--space-4) var(--space-4) var(--space-3);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.acc-eyebrow {
		font-size: 0.65rem;
		font-weight: 700;
		letter-spacing: 0.2em;
		text-transform: uppercase;
		color: var(--acc-gold);
		text-align: center;
	}
	.acc-hairline {
		height: 1px;
		width: 100%;
		background: var(--acc-hairline);
		opacity: 0.85;
	}

	/* ── Liste ─────────────────────────────────────────────────────────── */
	.acc-list { display: flex; flex-direction: column; }

	.acc-item { display: flex; flex-direction: column; }

	/* ── Trigger ───────────────────────────────────────────────────────── */
	.acc-trigger {
		width: 100%;
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: transparent;
		border: none;
		border-top: 1px solid var(--color-surface-container);
		text-align: left;
		font-family: inherit;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.acc-item--first .acc-trigger { border-top: none; }
	.acc-trigger:hover,
	.acc-trigger:active,
	.acc-trigger--open { background: var(--color-surface-container-low); }

	.acc-trigger-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		flex-shrink: 0;
		width: 24px;
		text-align: center;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.acc-trigger-title {
		flex: 1;
		font-weight: 700;
		font-size: 0.95rem;
		color: var(--color-on-surface);
	}

	/* ── Missing-Marker ────────────────────────────────────────────────── */
	.acc-dot-marker {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		flex-shrink: 0;
	}
	.acc-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--acc-gold);
		box-shadow: 0 0 0 2px rgba(212, 175, 55, 0.18);
	}
	.acc-dot-count {
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-on-surface-variant);
	}

	/* ── Chevron ───────────────────────────────────────────────────────── */
	.acc-chevron {
		font-size: 1.1rem;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
		transition: transform 200ms ease;
	}
	.acc-trigger--open .acc-chevron { transform: rotate(90deg); }

	/* ── Collapsible-Body (grid 0fr → 1fr Trick) ───────────────────────── */
	.acc-body-wrap {
		display: grid;
		grid-template-rows: 0fr;
		transition: grid-template-rows 250ms ease;
	}
	.acc-body-wrap--open { grid-template-rows: 1fr; }

	.acc-body-inner {
		overflow: hidden;
		min-height: 0;
	}
	.acc-body-wrap--open .acc-body-inner {
		padding: var(--space-2) var(--space-4) var(--space-4);
	}

	/* ── Rows ──────────────────────────────────────────────────────────── */
	.acc-rows { display: flex; flex-direction: column; }
	.acc-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) 0;
		border: none;
		background: none;
		border-top: 1px solid var(--color-surface-container);
		text-align: left;
		font-family: inherit;
		cursor: pointer;
		width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.acc-row:first-child { border-top: none; }
	.acc-row:active:not(.acc-row--readonly) { background: var(--color-surface-container-low); }
	.acc-row--readonly { cursor: default; }

	.acc-row-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		flex-shrink: 0;
		width: 24px;
		text-align: center;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.acc-row-text {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}
	.acc-row-label {
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
	}
	.acc-row-value {
		font-size: 0.92rem;
		font-weight: 600;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.acc-row-value--empty {
		color: var(--color-outline);
		font-weight: 500;
		font-style: italic;
	}
	.acc-row-value:global(.val-expired) {
		color: var(--color-primary);
		font-weight: 800;
	}
	.acc-row-value:global(.val-soon) {
		color: #b45309;
		font-weight: 700;
	}
	.acc-row-arrow {
		color: var(--color-on-surface-variant);
		font-size: 1rem;
		flex-shrink: 0;
	}

	/* ── Section-Edit-Button ───────────────────────────────────────────── */
	.acc-section-edit {
		margin-top: var(--space-3);
		align-self: flex-end;
		background: transparent;
		border: none;
		padding: var(--space-2) var(--space-1);
		font-family: var(--font-display);
		font-size: 0.72rem;
		font-weight: 700;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--acc-gold);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.acc-section-edit:hover,
	.acc-section-edit:active { opacity: 0.75; }

	/* Body-inner needs to be a flex column so section-edit aligns right. */
	.acc-body-wrap--open .acc-body-inner {
		display: flex;
		flex-direction: column;
	}

	/* ── Reduced Motion ────────────────────────────────────────────────── */
	@media (prefers-reduced-motion: reduce) {
		.acc-chevron,
		.acc-body-wrap {
			transition: none !important;
		}
	}
</style>
