<!--
  iOS-style Expandable Accordion Row
  Usage:
    <AccordionRow label="Einstellungen" icon="settings">
      <p>Content here</p>
    </AccordionRow>
    <AccordionRow label="Info" open>
      ...
    </AccordionRow>
-->
<script>
	let {
		label     = '',
		icon      = '',
		open      = $bindable(false),
		disabled  = false,
		children,
	} = $props();

	function toggle() {
		if (!disabled) open = !open;
	}
</script>

<div class="acc" class:acc--open={open} class:acc--disabled={disabled}>
	<button
		class="acc-header"
		type="button"
		onclick={toggle}
		aria-expanded={open}
		{disabled}
	>
		{#if icon}
			<span class="acc-icon material-symbols-outlined" aria-hidden="true">{icon}</span>
		{/if}
		<span class="acc-label">{label}</span>
		<span class="acc-chevron material-symbols-outlined" aria-hidden="true">chevron_right</span>
	</button>

	<div class="acc-body" aria-hidden={!open}>
		<div class="acc-body-inner">
			{@render children?.()}
		</div>
	</div>
</div>

<style>
	.acc {
		background: var(--color-surface, #fff);
		border-radius: 12px;
		overflow: hidden;
		border: 1px solid var(--color-border, rgba(0,0,0,0.08));
	}

	/* Header row */
	.acc-header {
		width: 100%;
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 13px 16px;
		background: none;
		border: none;
		cursor: pointer;
		text-align: left;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease;
	}
	.acc-header:active {
		background: rgba(0,0,0,0.04);
	}
	.acc--disabled .acc-header {
		cursor: not-allowed;
		opacity: 0.45;
	}

	.acc-icon {
		font-size: 1.1rem;
		color: var(--color-primary, #CC0000);
		flex-shrink: 0;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.acc-label {
		flex: 1;
		font-size: 0.95rem;
		font-weight: 500;
		color: var(--color-text, #1a1a1a);
	}

	.acc-chevron {
		font-size: 1.2rem;
		color: var(--color-text-soft, #999);
		flex-shrink: 0;
		transform: rotate(0deg);
		transition: transform 300ms cubic-bezier(0.34, 1.3, 0.64, 1);
		font-variation-settings: 'FILL' 0, 'wght' 300, 'GRAD' 0, 'opsz' 24;
	}
	.acc--open .acc-chevron {
		transform: rotate(90deg);
	}

	/* Collapsible body */
	.acc-body {
		display: grid;
		grid-template-rows: 0fr;
		transition: grid-template-rows 320ms cubic-bezier(0.22, 1, 0.36, 1);
	}
	.acc--open .acc-body {
		grid-template-rows: 1fr;
	}

	.acc-body-inner {
		overflow: hidden;
		border-top: 0 solid var(--color-border, rgba(0,0,0,0.08));
		transition: border-top-width 0ms 320ms, padding 320ms cubic-bezier(0.22, 1, 0.36, 1);
		padding: 0 16px;
	}
	.acc--open .acc-body-inner {
		border-top-width: 1px;
		padding: 12px 16px 14px;
		transition: border-top-width 0ms 0ms, padding 320ms cubic-bezier(0.22, 1, 0.36, 1);
	}
</style>
