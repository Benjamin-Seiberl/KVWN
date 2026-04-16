<!--
  Soft Destructive Button (iOS Style)
  Usage:
    <DestructiveButton onclick={deleteAccount}>Konto löschen</DestructiveButton>
    <DestructiveButton loading={deleting} icon="delete" onclick={deleteItem}>
      Eintrag löschen
    </DestructiveButton>
-->
<script>
	let {
		onclick   = undefined,
		disabled  = false,
		loading   = false,
		icon      = 'delete',
		type      = 'button',
		children,
	} = $props();
</script>

<button
	class="dbt"
	{type}
	disabled={disabled || loading}
	onclick={onclick}
>
	{#if loading}
		<span class="dbt-spinner" aria-hidden="true"></span>
	{:else if icon}
		<span class="material-symbols-outlined dbt-icon" aria-hidden="true">{icon}</span>
	{/if}
	<span class="dbt-label">
		{@render children?.()}
	</span>
</button>

<style>
	.dbt {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 7px;
		width: 100%;
		padding: 13px 20px;
		border-radius: 12px;
		border: none;
		background: #fff1f1;
		color: #CC0000;
		cursor: pointer;
		font-family: inherit;
		font-size: 0.95rem;
		font-weight: 600;
		letter-spacing: 0.01em;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease,
		            transform 120ms cubic-bezier(0.32, 0.72, 0, 1),
		            box-shadow 150ms ease;
	}
	.dbt:hover {
		background: #ffe3e3;
	}
	.dbt:active {
		transform: scale(0.98);
		background: #ffd5d5;
		box-shadow: none;
	}
	.dbt:disabled {
		opacity: 0.45;
		cursor: not-allowed;
		transform: none;
	}

	.dbt-icon {
		font-size: 1.05rem;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.dbt-label {
		line-height: 1;
	}

	/* Spinner */
	.dbt-spinner {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		border: 2px solid rgba(204,0,0,0.25);
		border-top-color: #CC0000;
		animation: dbt-spin 0.7s linear infinite;
		flex-shrink: 0;
	}
	@keyframes dbt-spin {
		to { transform: rotate(360deg); }
	}
</style>
