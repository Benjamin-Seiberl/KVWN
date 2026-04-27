<!--
  iOS-style Custom Slider
  Usage:
    <IOSSlider bind:value min={0} max={100} step={1} />
    <IOSSlider bind:value min={0} max={10} label="Intensität" unit="/ 10" />
-->
<script>
	let {
		value   = $bindable(50),
		min     = 0,
		max     = 100,
		step    = 1,
		label   = '',
		unit    = '',
		color   = 'var(--color-primary, #CC0000)',
		disabled = false,
	} = $props();

	const pct = $derived(((value - min) / (max - min)) * 100);
</script>

<div class="ios-slider-wrap" class:ios-slider-wrap--disabled={disabled}>
	{#if label || unit}
		<div class="ios-slider-row">
			{#if label}<span class="ios-slider-label">{label}</span>{/if}
			{#if unit}<span class="ios-slider-val">{value}{unit}</span>{/if}
		</div>
	{/if}

	<div class="ios-slider-track-wrap">
		<input
			class="ios-slider"
			type="range"
			{min}
			{max}
			{step}
			{disabled}
			bind:value
			style="--pct:{pct}%; --color:{color};"
		/>
	</div>
</div>

<style>
	.ios-slider-wrap {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.ios-slider-wrap--disabled {
		opacity: 0.45;
		pointer-events: none;
	}

	.ios-slider-row {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
	}
	.ios-slider-label {
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text, #1a1a1a);
	}
	.ios-slider-val {
		font-size: 0.82rem;
		font-weight: 600;
		color: var(--color-text-soft, #888);
		font-variant-numeric: tabular-nums;
	}

	/* Track wrapper gives height for the thumb to overflow */
	.ios-slider-track-wrap {
		position: relative;
		height: 28px;
		display: flex;
		align-items: center;
	}

	.ios-slider {
		-webkit-appearance: none;
		appearance: none;
		width: 100%;
		height: 4px;
		border-radius: 99px;
		outline: none;
		cursor: pointer;
		/* Two-tone track: filled left = accent, empty right = gray */
		background: linear-gradient(
			to right,
			var(--color) 0%,
			var(--color) var(--pct),
			rgba(120,120,128,0.2) var(--pct),
			rgba(120,120,128,0.2) 100%
		);
		transition: background 0ms; /* JS updates continuously */
	}

	/* Webkit thumb */
	.ios-slider::-webkit-slider-thumb {
		-webkit-appearance: none;
		width: 28px;
		height: 28px;
		border-radius: 50%;
		background: #fff;
		border: none;
		box-shadow: var(--shadow-card);
		cursor: pointer;
		transition: transform 120ms cubic-bezier(0.34, 1.3, 0.64, 1),
		            box-shadow 120ms ease;
	}
	.ios-slider::-webkit-slider-thumb:active {
		transform: scale(1.12);
		box-shadow: var(--shadow-float);
	}

	/* Firefox thumb */
	.ios-slider::-moz-range-thumb {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		background: #fff;
		border: none;
		box-shadow: var(--shadow-card);
		cursor: pointer;
	}
	/* Firefox track */
	.ios-slider::-moz-range-track {
		height: 4px;
		border-radius: 99px;
		background: rgba(120,120,128,0.2);
	}
	.ios-slider::-moz-range-progress {
		height: 4px;
		border-radius: 99px;
		background: var(--color);
	}
</style>
