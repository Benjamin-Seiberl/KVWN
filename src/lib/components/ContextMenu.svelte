<script>
	/**
	 * ContextMenu — iOS-style haptic touch context menu
	 *
	 * Props:
	 *   actions  — array of { label, icon, fn, destructive? }
	 *   children — the trigger element (rendered as-is + cloned into overlay)
	 */
	let { actions = [], children } = $props();

	// ── State ──────────────────────────────────────────────────────────────────
	let active    = $state(false);
	let openUp    = $state(false);
	let squishing = $state(false);
	let cloneRect = $state(null);
	let menuY     = $state(0);
	let menuX     = $state(0);

	let triggerEl = $state(null);

	// ── Portal Svelte action ───────────────────────────────────────────────────
	function portal(node) {
		document.body.appendChild(node);
		return {
			destroy() {
				if (node.parentNode === document.body) {
					document.body.removeChild(node);
				}
			}
		};
	}

	// ── Long-press detection ───────────────────────────────────────────────────
	let pressTimer = null;
	let startX = 0;
	let startY = 0;
	const THRESHOLD   = 8;
	const PRESS_DELAY = 500;

	function onPointerDown(e) {
		if (e.button !== undefined && e.button !== 0) return;
		startX = e.clientX;
		startY = e.clientY;
		squishing = true;

		pressTimer = setTimeout(() => {
			pressTimer = null;
			openMenu();
		}, PRESS_DELAY);
	}

	function onPointerMove(e) {
		if (!pressTimer) return;
		const dx = Math.abs(e.clientX - startX);
		const dy = Math.abs(e.clientY - startY);
		if (dx > THRESHOLD || dy > THRESHOLD) cancelPress();
	}

	function onPointerUp() {
		cancelPress();
	}

	function cancelPress() {
		if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
		squishing = false;
	}

	// ── Open overlay ───────────────────────────────────────────────────────────
	function openMenu() {
		if (!triggerEl) return;

		const rect = triggerEl.getBoundingClientRect();
		const vw   = window.innerWidth;
		const vh   = window.innerHeight;

		cloneRect = {
			top:    rect.top,
			left:   rect.left,
			width:  rect.width,
			height: rect.height,
		};

		const menuHeight = actions.length * 52 + 16;
		const spaceBelow = vh - rect.bottom;
		openUp = spaceBelow < 160;

		const menuWidth = 220;
		let mx = rect.left;
		if (mx + menuWidth > vw - 12) mx = vw - menuWidth - 12;
		if (mx < 12) mx = 12;
		menuX = mx;
		menuY = openUp
			? rect.top - menuHeight - 8
			: rect.bottom + 8;

		squishing = false;
		active = true;

		if (navigator.vibrate) navigator.vibrate(8);
	}

	// ── Close ─────────────────────────────────────────────────────────────────
	function close() {
		active = false;
		cloneRect = null;
	}

	// ── Action handler ────────────────────────────────────────────────────────
	function handleAction(action) {
		close();
		setTimeout(() => action.fn?.(), 200);
	}
</script>

<!-- Trigger wrapper -->
<div
	bind:this={triggerEl}
	class="cm-trigger"
	class:cm-trigger--squish={squishing}
	onpointerdown={onPointerDown}
	onpointermove={onPointerMove}
	onpointerup={onPointerUp}
	onpointercancel={cancelPress}
	role="presentation"
>
	{@render children?.()}
</div>

<!-- Portal overlay -->
{#if active}
	<div class="cm-overlay" use:portal>
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div class="cm-backdrop" onpointerdown={close}></div>

		<!-- Magic clone at exact position -->
		{#if cloneRect}
			<div
				class="cm-clone animate-bounce-pop"
				style:top="{cloneRect.top}px"
				style:left="{cloneRect.left}px"
				style:width="{cloneRect.width}px"
			>
				{@render children?.()}
			</div>
		{/if}

		<!-- Floating menu -->
		<div
			class="cm-menu animate-menu-pop"
			class:cm-menu--up={openUp}
			style:top="{menuY}px"
			style:left="{menuX}px"
		>
			{#each actions as action, i}
				<button
					class="cm-item"
					class:cm-item--destructive={action.destructive}
					onclick={() => handleAction(action)}
					type="button"
				>
					{#if action.icon}
						<span class="material-symbols-outlined cm-item-icon">{action.icon}</span>
					{/if}
					<span class="cm-item-label">{action.label}</span>
				</button>
				{#if i < actions.length - 1}
					<div class="cm-divider"></div>
				{/if}
			{/each}
		</div>
	</div>
{/if}

<style>
	/* Trigger */
	.cm-trigger {
		display: contents;
	}
	.cm-trigger--squish :global(> *) {
		transform: scale(0.95);
		transition: transform 150ms cubic-bezier(0.32, 0.72, 0, 1);
	}

	/* Overlay */
	.cm-overlay {
		position: fixed;
		inset: 0;
		z-index: 200;
		overscroll-behavior: contain;
		touch-action: none;
	}

	/* Backdrop */
	.cm-backdrop {
		position: absolute;
		inset: 0;
		background: rgba(0, 0, 0, 0.35);
		backdrop-filter: blur(16px) saturate(0.8);
		-webkit-backdrop-filter: blur(16px) saturate(0.8);
		animation: cm-fade-in 200ms ease forwards;
	}
	@keyframes cm-fade-in {
		from { opacity: 0; }
		to   { opacity: 1; }
	}

	/* Clone */
	.cm-clone {
		position: absolute;
		z-index: 2;
		pointer-events: none;
		border-radius: 14px;
		overflow: hidden;
		box-shadow: 0 16px 48px rgba(0, 0, 0, 0.35);
		display: flex;
		flex-direction: column;
	}
	.cm-clone :global(button) {
		width: 100%;
		pointer-events: none;
	}

	/* Menu */
	.cm-menu {
		position: absolute;
		z-index: 3;
		width: 220px;
		border-radius: 14px;
		overflow: hidden;
		background: rgba(255, 255, 255, 0.72);
		backdrop-filter: blur(24px) saturate(1.6);
		-webkit-backdrop-filter: blur(24px) saturate(1.6);
		box-shadow:
			0 8px 32px rgba(204, 0, 0, 0.18),
			0 2px 8px rgba(0, 0, 0, 0.12),
			inset 0 0 0 0.5px rgba(255, 255, 255, 0.5);
	}

	/* Items */
	.cm-item {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		padding: 14px 16px;
		border: none;
		background: transparent;
		cursor: pointer;
		text-align: left;
		font-size: 0.95rem;
		font-weight: 500;
		color: #1a1a1a;
		-webkit-tap-highlight-color: transparent;
		transition: background 120ms;
	}
	.cm-item:active { background: rgba(0, 0, 0, 0.06); }
	.cm-item--destructive { color: #d00; }
	.cm-item--destructive .cm-item-icon { color: #d00; }

	.cm-item-icon {
		font-size: 1.15rem;
		color: #555;
		font-variation-settings: 'FILL' 0, 'wght' 300;
		flex-shrink: 0;
	}
	.cm-item-label { flex: 1; }

	.cm-divider {
		height: 0.5px;
		background: rgba(0, 0, 0, 0.1);
		margin: 0 14px;
	}
</style>
