<script>
	let { onclick } = $props();
</script>

<button class="back-btn" {onclick} aria-label="Zurück">
	<span class="material-symbols-outlined">arrow_back_ios_new</span>
</button>

<style>
	.back-btn {
		position: fixed;
		top: calc(env(safe-area-inset-top, 0px) + 12px);
		left: 16px;
		width: 44px;
		height: 44px;
		border-radius: 50%;
		border: 1px solid rgba(255, 255, 255, 0.35);
		background: rgba(255, 255, 255, 0.22);
		backdrop-filter: blur(24px) saturate(180%);
		-webkit-backdrop-filter: blur(24px) saturate(180%);
		box-shadow: 0 2px 12px rgba(0, 0, 0, 0.12), inset 0 1px 0 rgba(255, 255, 255, 0.4);
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		z-index: 90;
		color: var(--color-on-surface);
		-webkit-tap-highlight-color: transparent;
		transition: transform 0.1s, opacity 0.1s;
	}

	.back-btn:active {
		transform: scale(0.93);
		opacity: 0.8;
	}

	.back-btn .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
</style>
