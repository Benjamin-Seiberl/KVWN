<script>
	import { isMember } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { page, navigating } from '$app/stores';
	import { onMount } from 'svelte';
	import { initScrollListener } from '$lib/stores/scroll.js';
	import BottomNav       from '$lib/components/BottomNav.svelte';
	import PagePill        from '$lib/components/PagePill.svelte';
	import SpotlightSearch from '$lib/components/SpotlightSearch.svelte';
	import { spotlightOpen } from '$lib/stores/spotlight.js';

	let { children } = $props();

	// ── iOS Overscroll / Pull-to-Refresh physics ─────────────────────────────

	/** Resistance-adjusted pull distance (px). + = top pull, − = bottom push. */
	let pullDistance     = $state(0);
	let isGlobalDragging = $state(false);
	/** 'top' | 'bottom' | null – set once at touchstart */
	let dragOrigin       = $state(null);

	let startY = 0;
	let startX = 0;

	/** Resistance-adjusted pull threshold that fires the Spotlight overlay */
	const SPOTLIGHT_THRESHOLD = 58;

	/** Transition applied to all transformed elements */
	const snapTransition = $derived(
		isGlobalDragging
			? 'none'
			: 'transform 500ms cubic-bezier(0.34, 1.56, 0.64, 1)',
	);

	/** Pull indicator opacity (fades in as user pulls down) */
	const ptrOpacity = $derived(
		Math.min(Math.max(pullDistance - 8, 0) / (SPOTLIGHT_THRESHOLD * 0.65), 1),
	);

	// ── Scroll position helpers ───────────────────────────────────────────────

	function atTop() {
		return window.scrollY <= 0;
	}
	function atBottom() {
		return (
			window.scrollY + window.innerHeight >=
			document.documentElement.scrollHeight - 2
		);
	}

	// ── Touch handlers ────────────────────────────────────────────────────────

	function onTouchStart(e) {
		// Don't intercept when Spotlight or a BottomSheet is open
		if ($spotlightOpen) return;
		if (document.body.classList.contains('sheet-open')) return;

		startY = e.touches[0].clientY;
		startX = e.touches[0].clientX;

		if (atTop()) {
			dragOrigin       = 'top';
			isGlobalDragging = true;
		} else if (atBottom()) {
			dragOrigin       = 'bottom';
			isGlobalDragging = true;
		}
		// else: mid-scroll → ignore
	}

	function onTouchMove(e) {
		if (!isGlobalDragging || !dragOrigin) return;

		const touch    = e.touches[0];
		const rawDist  = touch.clientY - startY;
		const rawDistX = touch.clientX - startX;

		// If horizontal movement dominates early → abort (let carousel take it)
		if (Math.abs(rawDistX) > Math.abs(rawDist) + 4 && Math.abs(rawDistX) > 12) {
			isGlobalDragging = false;
			pullDistance     = 0;
			dragOrigin       = null;
			return;
		}

		if (dragOrigin === 'top' && rawDist > 0) {
			// ── Top pull: rubber-band resistance ─────────────────────────────
			e.preventDefault();
			pullDistance = Math.pow(rawDist, 0.75) * 1.2;
		} else if (dragOrigin === 'bottom' && rawDist < 0) {
			// ── Bottom push: inverted rubber-band resistance ──────────────────
			e.preventDefault();
			pullDistance = -(Math.pow(Math.abs(rawDist), 0.75) * 1.2);
		} else {
			// Wrong direction – abort the gesture
			isGlobalDragging = false;
			pullDistance     = 0;
			dragOrigin       = null;
		}
	}

	function onTouchEnd() {
		if (!isGlobalDragging) return;

		const origin = dragOrigin;
		const dist   = pullDistance;
		isGlobalDragging = false;
		dragOrigin       = null;

		if (origin === 'top' && dist >= SPOTLIGHT_THRESHOLD) {
			// Open Spotlight search — snap content back immediately
			pullDistance = 0;
			$spotlightOpen = true;
		} else {
			// Bouncy snap-back (transition handles the spring)
			pullDistance = 0;
		}
	}

	// ── Auth guard ────────────────────────────────────────────────────────────

	$effect(() => {
		if (browser && $isMember === false) goto('/login');
	});

	onMount(() => {
		// Touch listeners on document so they fire regardless of target element,
		// but we only intercept when genuinely at top/bottom of the scroll.
		document.addEventListener('touchstart',  onTouchStart, { passive: true });
		document.addEventListener('touchmove',   onTouchMove,  { passive: false });
		document.addEventListener('touchend',    onTouchEnd);
		document.addEventListener('touchcancel', onTouchEnd);

		return initScrollListener();
	});
</script>

{#if $isMember === true}
<div class="app-shell">

	<!-- Dynamic Island Pill -->
	<PagePill />

	<!-- ── Spotlight pull indicator: fades in as user pulls down ── -->
	<div
		class="ptr-container"
		style="opacity: {ptrOpacity}; pointer-events: none;"
	>
		<div class="ptr-ring" class:ptr-ring--ready={pullDistance >= SPOTLIGHT_THRESHOLD}>
			<span class="material-symbols-outlined ptr-icon">search</span>
		</div>
	</div>

	<main class="page-content">

		<!-- ── Feed: full pull distance (top + bottom bounce) ── -->
		<div
			class="layout-feed-wrap"
			style="
				transform: translateY({pullDistance}px);
				transition: {snapTransition};
			"
		>
			{#if $navigating}
				<div class="page-skeleton animate-fade-float">
					<div class="skeleton-card skeleton-card--short shimmer-box"></div>
					<div class="skeleton-card skeleton-card--tall shimmer-box"></div>
					<div class="skeleton-card shimmer-box"></div>
					<div class="skeleton-card skeleton-card--short shimmer-box"></div>
				</div>
			{:else}
				{#key $page.url.pathname}
					<div class="animate-fade-float">
						{@render children()}
					</div>
				{/key}
			{/if}
		</div>

	</main>

	<BottomNav />

	<!-- Spotlight Search Overlay (portal'd to body) -->
	<SpotlightSearch bind:open={$spotlightOpen} />

</div>
{/if}

<style>
	/* ── PTR indicator ────────────────────────────────────────────────────────── */
	.ptr-container {
		position: fixed;
		top: calc(env(safe-area-inset-top, 0px) + 10px);
		left: 50%;
		transform: translateX(-50%);
		z-index: 89; /* below PagePill (91) but above content */
		pointer-events: none;
		transition: opacity 200ms ease;
	}

	.ptr-ring {
		width: 38px;
		height: 38px;
		border-radius: 50%;
		background: var(--color-surface-container-lowest, #fff);
		box-shadow: 0 2px 14px rgba(0,0,0,0.14), 0 0 0 1px rgba(0,0,0,0.04);
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 250ms ease, box-shadow 250ms ease;
	}

	.ptr-ring--ready {
		background: var(--color-primary, #CC0000);
		box-shadow: 0 4px 20px rgba(204,0,0,0.35);
	}

	.ptr-icon {
		font-size: 1.1rem;
		color: var(--color-on-surface-variant, #666);
		transition: color 250ms ease;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.ptr-ring--ready .ptr-icon {
		color: #fff;
	}

	/* ── Layout wrappers ──────────────────────────────────────────────────────── */
	.layout-feed-wrap {
		will-change: transform;
	}
</style>
