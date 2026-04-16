<script>
	import { page } from '$app/stores';
	import { scrollY, scrollDirection } from '$lib/stores/scroll.js';
	import { currentPageConfig, currentSubtab, activeSubtabs, setSubtab } from '$lib/stores/subtab.js';

	// Transition only after 80px of scroll (was 15 – too eager)
	let isScrolled = $derived($scrollY > 120);

	// --- Dynamic Island state ---
	let pillExpanded = $state(false);
	let isDragging   = $state(false);
	let dragDeltaY   = $state(0);
	let dragStartY   = 0;

	// Auto-close pill when scrolling further down
	$effect(() => {
		if ($scrollDirection === 'down' && pillExpanded) {
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

	// --- Pill height with drag physics ---
	const PILL_COLLAPSED = 48;
	const PILL_EXPANDED  = 130;   // tall enough for content + padding

	let pillHeight = $derived.by(() => {
		const base = pillExpanded ? PILL_EXPANDED : PILL_COLLAPSED;
		if (!isDragging) return base;

		const offset = pillExpanded
			// Expanded: can shrink fully, overshoot open by max 30px
			? Math.min(Math.max(dragDeltaY, -(PILL_EXPANDED - PILL_COLLAPSED)), 30)
			// Collapsed: can only grow (drag down)
			: Math.min(Math.max(dragDeltaY, 0), PILL_EXPANDED - PILL_COLLAPSED);

		return Math.max(PILL_COLLAPSED, base + offset);
	});

	// --- Pointer handlers ---
	function onPointerDown(e) {
		isDragging  = true;
		dragStartY  = e.clientY;
		dragDeltaY  = 0;
		e.currentTarget.setPointerCapture(e.pointerId);
	}

	function onPointerMove(e) {
		if (!isDragging) return;
		dragDeltaY = e.clientY - dragStartY;

		// Snap open mid-drag – stays open even if finger pauses
		if (!pillExpanded && dragDeltaY > 50) {
			pillExpanded = true;
			dragStartY   = e.clientY;   // reset so continued drag doesn't over-stretch
			dragDeltaY   = 0;
		}
		// Snap closed mid-drag when pulling up past threshold
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
		// otherwise spring back to current state

		dragDeltaY = 0;
	}

	function selectSubtab(key) {
		const path = $page.url.pathname;
		if (key !== $currentSubtab) setSubtab(path, key);
		pillExpanded = false;
	}

	function selectSubtabHeader(key) {
		const path = $page.url.pathname;
		if (key !== $currentSubtab) setSubtab(path, key);
	}
</script>

{#if $currentPageConfig}
<header class="page-header">

	<!-- Static header: title + sub-tab bar -->
	<div class="page-header-static" class:header-hidden={isScrolled}>
		<h1 class="page-header-title">{$currentPageConfig.title}</h1>

		<div class="page-header-tabs">
			{#each $currentPageConfig.tabs as tab (tab.key)}
				{@const active = tab.key === $currentSubtab}
				<button
					class="page-header-tab"
					class:active
					onclick={() => selectSubtabHeader(tab.key)}
				>
					<span class="material-symbols-outlined">{tab.icon}</span>
					{tab.label}
					{#if active}
						<div class="page-header-tab-indicator"></div>
					{/if}
				</button>
			{/each}
		</div>
	</div>

	<!-- Dynamic Island Pill -->
	<div
		class="di-pill"
		class:di-pill--hidden={!isScrolled}
		class:di-pill--expanded={pillExpanded}
		class:di-pill--dragging={isDragging}
		style="height: {pillHeight}px; {isDragging ? 'transition: none;' : ''}"
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
		onpointercancel={onPointerUp}
	>
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
			{#each $currentPageConfig.tabs as tab (tab.key)}
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

</header>
{/if}
