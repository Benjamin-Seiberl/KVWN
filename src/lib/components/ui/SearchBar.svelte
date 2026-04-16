<!--
  iOS-style Search Bar
  Usage:
    <SearchBar bind:value placeholder="Spieler suchen…" />
    <SearchBar bind:value onSearch={(v) => filter(v)} />
-->
<script>
	let {
		value    = $bindable(''),
		placeholder = 'Suchen…',
		onSearch = undefined,
		autofocus = false,
	} = $props();

	let inputEl = $state(null);
	let focused = $state(false);

	function clear() {
		value = '';
		inputEl?.focus();
		onSearch?.('');
	}

	function handleInput(e) {
		value = e.target.value;
		onSearch?.(value);
	}

	function handleKeydown(e) {
		if (e.key === 'Enter') {
			inputEl?.blur();
			onSearch?.(value);
		}
		if (e.key === 'Escape') {
			clear();
			inputEl?.blur();
		}
	}
</script>

<div class="sb" class:sb--focused={focused}>
	<span class="sb-icon material-symbols-outlined" aria-hidden="true">search</span>
	<input
		bind:this={inputEl}
		class="sb-input"
		type="search"
		autocomplete="off"
		autocorrect="off"
		spellcheck="false"
		{placeholder}
		{autofocus}
		value={value}
		oninput={handleInput}
		onkeydown={handleKeydown}
		onfocus={() => focused = true}
		onblur={() => focused = false}
	/>
	{#if value}
		<button class="sb-clear" type="button" onclick={clear} aria-label="Suche leeren" tabindex="-1">
			<span class="material-symbols-outlined" aria-hidden="true">cancel</span>
		</button>
	{/if}
</div>

<style>
	.sb {
		display: flex;
		align-items: center;
		gap: 6px;
		background: rgba(120, 120, 128, 0.12);
		border-radius: 12px;
		padding: 0 10px;
		height: 40px;
		transition: background 200ms ease, box-shadow 200ms ease;
	}
	.sb--focused {
		background: #fff;
		box-shadow: 0 0 0 1.5px var(--color-primary, #CC0000),
		            0 2px 12px rgba(204,0,0,0.08);
	}

	.sb-icon {
		font-size: 1.05rem;
		color: rgba(60, 60, 67, 0.45);
		flex-shrink: 0;
		transition: color 200ms ease;
		pointer-events: none;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.sb--focused .sb-icon {
		color: var(--color-primary, #CC0000);
	}

	.sb-input {
		flex: 1;
		background: none;
		border: none;
		outline: none;
		font-family: inherit;
		font-size: 1rem;
		color: var(--color-text, #1a1a1a);
		caret-color: var(--color-primary, #CC0000);
		min-width: 0;
		/* Remove default search input styling */
		-webkit-appearance: none;
	}
	.sb-input::placeholder {
		color: rgba(60, 60, 67, 0.45);
	}
	/* Hide native clear button in webkit */
	.sb-input::-webkit-search-cancel-button { display: none; }
	.sb-input::-webkit-search-decoration   { display: none; }

	.sb-clear {
		display: flex;
		align-items: center;
		justify-content: center;
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
		color: rgba(60, 60, 67, 0.45);
		flex-shrink: 0;
		transition: color 150ms ease, transform 150ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.sb-clear:active {
		transform: scale(0.85);
	}
	.sb-clear .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
</style>
