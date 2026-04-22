<!--
  iOS-style Toggle Switch
  Usage:
    <ToggleSwitch bind:checked={value} />
    <ToggleSwitch checked={me?.flag} onchange={(e) => save(e.target.checked)} />
-->
<script>
	let {
		checked  = $bindable(false),
		disabled = false,
		onchange,
		ariaLabel = '',
	} = $props();
</script>

<input
	class="toggle-switch"
	type="checkbox"
	bind:checked
	{disabled}
	{onchange}
	aria-label={ariaLabel || undefined}
/>

<style>
	.toggle-switch {
		-webkit-appearance: none;
		appearance: none;
		width: 44px;
		height: 26px;
		border-radius: 999px;
		background: var(--color-surface-container);
		border: 1px solid var(--color-outline-variant);
		position: relative;
		cursor: pointer;
		flex-shrink: 0;
		transition: background 150ms ease, border-color 150ms ease;
		margin: 0;
	}
	.toggle-switch::after {
		content: '';
		position: absolute;
		top: 2px;
		left: 2px;
		width: 20px;
		height: 20px;
		border-radius: 50%;
		background: var(--color-surface-container-lowest);
		box-shadow: var(--shadow-card);
		transition: transform 150ms ease;
	}
	.toggle-switch:checked {
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.toggle-switch:checked::after { transform: translateX(18px); }
	.toggle-switch:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
</style>
