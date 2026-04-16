<script>
	import { isMember } from '$lib/stores/auth';
	import { goto, invalidateAll } from '$app/navigation';
	import { browser } from '$app/environment';
	import { page, navigating } from '$app/stores';
	import { onMount } from 'svelte';
	import { initScrollListener } from '$lib/stores/scroll.js';
	import BottomNav from '$lib/components/BottomNav.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';
	import PagePill   from '$lib/components/PagePill.svelte';

	let { children } = $props();

	// ── iOS Overscroll / Pull-to-Refresh physics ─────────────────────────────

	/** Resistance-adjusted pull distance (px). + = top pull, − = bottom push. */
	let pullDistance    = $state(0);
	let isGlobalDragging = $state(false);
	/** 'top' | 'bottom' | null – set once at touchstart */
	let dragOrigin      = $state(null);
	let isRefreshing    = $state(false);

	let startY = 0;
	let startX = 0;

	/** Threshold (resistance-adjusted px) that triggers a refresh */
	const REFRESH_THRESHOLD = 72;
	/** Pull distance held open while refresh loads */
	const HOLD_DISTANCE = Math.round(REFRESH_THRESHOLD * 0.55);

	/** Transition applied to all transformed elements */
	const snapTransition = $derived(
		isGlobalDragging
			? 'none'
			: 'transform 500ms cubic-bezier(0.34, 1.56, 0.64, 1)',
	);

	/** PTR indicator opacity (0 → invisible, 1 → fully visible) */
	const ptrOpacity = $derived(
		isRefreshing
			? 1
			: Math.min(Math.max(pullDistance - 8, 0) / (REFRESH_THRESHOLD * 0.65), 1),
	);

	/** Arrow rotation: 0° at rest → 180° at threshold (ready to release) */
	const ptrRotation = $derived(
		isRefreshing ? 0 : Math.min(pullDistance / REFRESH_THRESHOLD, 1) * 180,
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
		if (isRefreshing) return;
		// Don't intercept when a BottomSheet is open
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

		const shouldRefresh = dragOrigin === 'top' && pullDistance >= REFRESH_THRESHOLD;
		isGlobalDragging    = false;
		dragOrigin          = null;

		if (shouldRefresh && !isRefreshing) {
			// Hold the pull indicator open while data reloads
			isRefreshing = true;
			pullDistance = HOLD_DISTANCE;

			invalidateAll().finally(() => {
				isRefreshing = false;
				pullDistance = 0;
			});
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

	<!-- ── PTR indicator: sits fixed at top, revealed as content slides down ── -->
	<div
		class="ptr-container"
		style="opacity: {ptrOpacity}; pointer-events: none;"
	>
		<div class="ptr-ring" class:ptr-ring--ready={pullDistance >= REFRESH_THRESHOLD || isRefreshing}>
			<span
				class="material-symbols-outlined ptr-icon"
				class:ptr-icon--spin={isRefreshing}
				style="transform: rotate({ptrRotation}deg)"
			>
				{isRefreshing ? 'refresh' : 'arrow_downward'}
			</span>
		</div>
	</div>

	<main class="page-content">

		<!-- ── PageHeader: parallax at 40% speed, zooms slightly ── -->
		<div
			class="layout-header-wrap"
			style="
				transform: translateY({Math.max(pullDistance, 0) * 0.4}px)
				           scale({1 + Math.max(pullDistance, 0) * 0.002});
				transform-origin: top center;
				transition: {snapTransition};
			"
		>
			<PageHeader />
		</div>

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
		transition: transform 200ms ease, color 250ms ease;
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.ptr-ring--ready .ptr-icon {
		color: #fff;
	}

	@keyframes ptr-spin {
		to { transform: rotate(360deg) !important; }
	}

	.ptr-icon--spin {
		animation: ptr-spin 0.75s linear infinite;
	}

	/* ── Layout wrappers ──────────────────────────────────────────────────────── */
	.layout-header-wrap {
		/* will-change keeps compositor layer, avoids layout thrash during drag */
		will-change: transform;
	}

	.layout-feed-wrap {
		will-change: transform;
	}
</style>
