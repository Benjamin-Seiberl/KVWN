<script>
	import { browser } from '$app/environment';
	import { onMount } from 'svelte';

	let { open = $bindable(false), title = '', zIndex = null, children } = $props();

	// ── Portal: rendert direkt in <body> ─────────────────────
	// Verhindert dass overflow-y:auto / transform-Ancestors den
	// position:fixed-Kontext zerstören (iOS Safari).
	function portal(node) {
		document.body.appendChild(node);
		return { destroy() { node.remove(); } };
	}

	// ── 3D-Stage-Effekt: body-Klasse steuert CSS-Transforms ──
	$effect(() => {
		if (!browser) return;
		if (open) {
			document.body.classList.add('sheet-open');
			document.body.style.overflow = 'hidden';
		} else {
			document.body.classList.remove('sheet-open');
			document.body.style.overflow = '';
		}
	});

	// ── Drag-State ───────────────────────────────────────────
	let dragOffsetY = $state(0);
	let isDragging  = $state(false);
	let dragStartY  = 0;
	let velocity    = 0;
	let lastY       = 0;
	let lastT       = 0;

	// Offset zurücksetzen wenn Sheet geöffnet wird
	$effect(() => { if (open) dragOffsetY = 0; });

	function onPointerDown(e) {
		isDragging = true;
		dragStartY = e.clientY;
		velocity   = 0;
		lastY      = e.clientY;
		lastT      = Date.now();
		e.currentTarget.setPointerCapture(e.pointerId);
	}

	function onPointerMove(e) {
		if (!isDragging) return;
		// Nur nach unten ziehbar (kein Überdehnen nach oben)
		dragOffsetY = Math.max(0, e.clientY - dragStartY);
		const now = Date.now();
		const dt  = now - lastT;
		if (dt > 0) velocity = (e.clientY - lastY) / dt;
		lastY = e.clientY;
		lastT = now;
	}

	function onPointerUp() {
		if (!isDragging) return;
		isDragging = false;
		// Schließen: > 35% Bildschirmhöhe oder schnelles Wischen (v > 0.8 px/ms)
		if (dragOffsetY > window.innerHeight * 0.35 || velocity > 0.8) {
			close();
		} else {
			dragOffsetY = 0;
		}
	}

	function close() {
		dragOffsetY = 0;
		open = false;
	}

	function onKeydown(e) {
		if (e.key === 'Escape' && open) close();
	}

	// Inline-Style nur während des Ziehens (überschreibt CSS-Transition)
	let sheetStyle = $derived.by(() => {
		if (!isDragging || dragOffsetY === 0) return '';
		return `transform: translateX(-50%) translateY(${dragOffsetY}px); transition: none;`;
	});

	let mounted = $state(false);
	onMount(() => { mounted = true; });
</script>

<svelte:window onkeydown={onKeydown} />

{#if mounted}
<div use:portal>
	<!-- Backdrop: Tap = schließen, Fade-In wenn open -->
	<div
		class="bs-backdrop"
		class:bs-backdrop--visible={open}
		onclick={close}
		role="presentation"
		style={zIndex ? `z-index:${zIndex - 1}` : ''}
	></div>

	<!-- Sheet -->
	<div
		class="bs-sheet"
		class:bs-sheet--open={open}
		style="{sheetStyle}{zIndex ? ` z-index:${zIndex};` : ''}"
		role="dialog"
		aria-modal="true"
		aria-label={title || 'Menü'}
	>
		<!-- Drag-Header: gesamter Kopfbereich ist die Ziehlinie -->
		<div
			class="bs-drag-header"
			role="presentation"
			onpointerdown={onPointerDown}
			onpointermove={onPointerMove}
			onpointerup={onPointerUp}
			onpointercancel={onPointerUp}
		>
			<div class="bs-drag-bar"></div>
			{#if title}
				<h3 class="bs-title">{title}</h3>
			{/if}
		</div>

		<!-- Scrollbarer Inhalt -->
		<div class="bs-content">
			{@render children?.()}
		</div>
	</div>
</div>
{/if}
