<script>
	import { page } from '$app/stores';
	import { scrollY, scrollDirection } from '$lib/stores/scroll.js';
	import { currentPageConfig, currentSubtab, setSubtab } from '$lib/stores/subtab.js';
	import { playerRole } from '$lib/stores/auth';
	import { toastMessage, isToastActive } from '$lib/stores/toast.js';

	// ── Portal-Action: rendert die Pille direkt in <body> ─────
	// Verhindert dass overflow-y:auto / position:relative-Ancestors
	// den Touch-Hit-Test auf iOS Safari blockieren.
	function portal(node) {
		document.body.appendChild(node);
		return {
			destroy() { node.remove(); }
		};
	}

	// ── Visibility ────────────────────────────────────────────
	let isScrolled = $derived($scrollY > 120);

	// ── Pill state ────────────────────────────────────────────
	let pillExpanded = $state(false);
	let isDragging   = $state(false);
	let dragDeltaY   = $state(0);
	let dragStartY   = 0;

	// Auto-close when scrolling further down
	$effect(() => {
		if ($scrollDirection === 'down' && pillExpanded) {
			pillExpanded = false;
		}
	});

	// Wenn Toast aktiv → Pill-Menü schließen
	$effect(() => {
		if ($isToastActive && pillExpanded) {
			pillExpanded = false;
		}
	});

	// Current subtab label shown in pill head
	let currentLabel = $derived.by(() => {
		const config = $currentPageConfig;
		const sub    = $currentSubtab;
		if (!config || !sub) return '';
		return config.tabs.find(t => t.key === sub)?.label ?? '';
	});

	// Filtered tabs (hide adminOnly tabs from non-admins)
	let visibleTabs = $derived.by(() => {
		const config = $currentPageConfig;
		if (!config) return [];
		return config.tabs.filter(t => !t.adminOnly || $playerRole === 'kapitaen');
	});

	// ── Pill height with drag physics ─────────────────────────
	const PILL_COLLAPSED = 48;
	const PILL_EXPANDED  = 130;

	let pillHeight = $derived.by(() => {
		// Toast-Modus: feste Höhe
		if ($isToastActive) return PILL_COLLAPSED;

		const base = pillExpanded ? PILL_EXPANDED : PILL_COLLAPSED;
		if (!isDragging) return base;

		const offset = pillExpanded
			// Expanded: can shrink fully, overshoot open by max 30px
			? Math.min(Math.max(dragDeltaY, -(PILL_EXPANDED - PILL_COLLAPSED)), 30)
			// Collapsed: can only grow (drag down)
			: Math.min(Math.max(dragDeltaY, 0), PILL_EXPANDED - PILL_COLLAPSED);

		return Math.max(PILL_COLLAPSED, base + offset);
	});

	// ── Pointer handlers ──────────────────────────────────────
	function onPointerDown(e) {
		if ($isToastActive) return;
		if (e.target.closest('.di-pill-option')) return; // Button-Click nativ durchlassen
		isDragging  = true;
		dragStartY  = e.clientY;
		dragDeltaY  = 0;
		e.currentTarget.setPointerCapture(e.pointerId);
	}

	function onPointerMove(e) {
		if (!isDragging) return;
		dragDeltaY = e.clientY - dragStartY;

		// Snap open mid-drag
		if (!pillExpanded && dragDeltaY > 50) {
			pillExpanded = true;
			dragStartY   = e.clientY;
			dragDeltaY   = 0;
		}
		// Snap closed mid-drag when pulling up
		if (pillExpanded && dragDeltaY < -50) {
			pillExpanded = false;
			dragStartY   = e.clientY;
			dragDeltaY   = 0;
		}
	}

	function onPointerUp(e) {
		if (!isDragging) return;
		isDragging = false;

		// Tap (barely moved) → toggle open/closed
		if (Math.abs(dragDeltaY) < 15) {
			pillExpanded = !pillExpanded;
		} else if (!pillExpanded && dragDeltaY > 50) {
			pillExpanded = true;
		} else if (pillExpanded && dragDeltaY < -50) {
			pillExpanded = false;
		}
		dragDeltaY = 0;
	}

	function selectSubtab(key) {
		const path = $page.url.pathname;
		if (key !== $currentSubtab) setSubtab(path, key);
		pillExpanded = false;
	}
</script>

<!-- Rendered at the app-shell level so position:fixed is always
     relative to the actual viewport, regardless of overflow ancestors -->
<div
	use:portal
	class="di-pill"
	class:di-pill--hidden={!isScrolled && !$isToastActive}
	class:di-pill--expanded={pillExpanded && !$isToastActive}
	class:di-pill--dragging={isDragging}
	class:di-pill--toast={$isToastActive}
	style="height: {pillHeight}px; {isDragging ? 'transition: none;' : ''}"
	onpointerdown={onPointerDown}
	onpointermove={onPointerMove}
	onpointerup={onPointerUp}
	onpointercancel={onPointerUp}
>
	<!-- ═══ TOAST LAYER (absolute, fadet ein) ═══ -->
	<div class="di-pill-toast-layer" class:di-pill-toast-layer--active={$isToastActive}>
		<span class="material-symbols-outlined di-pill-toast-icon">check_circle</span>
		<span class="di-pill-toast-text">{$toastMessage}</span>
	</div>

	<!-- ═══ NORMAL LAYER (weicht unscharf nach hinten) ═══ -->
	<div class="di-pill-normal-layer" class:di-pill-normal-layer--hidden={$isToastActive}>
		<!-- Pill head: current subtab label -->
		<div class="di-pill-head">
			<span class="di-pill-label">{currentLabel}</span>
			<div class="di-pill-drag-bar"></div>
		</div>

		<!-- Pill body: subtab options (fades in as pill expands) -->
		<div
			class="di-pill-body"
			class:di-pill-body--hidden={!pillExpanded && dragDeltaY < 30}
		>
			{#each visibleTabs as tab (tab.key)}
				{@const active = tab.key === $currentSubtab}
				<button
					class="di-pill-option"
					class:active
					onclick={(e) => { e.stopPropagation(); selectSubtab(tab.key); }}
				>
					<span class="material-symbols-outlined">{tab.icon}</span>
					<span class="di-pill-option-label">{tab.label}</span>
				</button>
			{/each}
		</div>
	</div>
</div>
