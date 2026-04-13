<script>
	let { open = $bindable(false), title = '', children } = $props();

	let handleEl = $state(null);
	let startY = 0, dragY = $state(0), dragging = false;

	function onHandleDown(e) {
		startY   = e.clientY;
		dragY    = 0;
		dragging = true;
		handleEl.setPointerCapture(e.pointerId);
	}

	function onHandleMove(e) {
		if (!dragging) return;
		dragY = Math.max(0, e.clientY - startY);
	}

	function onHandleUp() {
		if (!dragging) return;
		dragging = false;
		if (dragY > 90) open = false;
		else dragY = 0;
	}

	function onKeydown(e) {
		if (e.key === 'Escape' && open) { open = false; }
	}
</script>

<svelte:window onkeydown={onKeydown} />

{#if open}
	<!-- Backdrop -->
	<div
		class="sheet-backdrop"
		onclick={() => open = false}
		aria-hidden="true"
	></div>

	<!-- Sheet -->
	<div
		class="sheet"
		role="dialog"
		aria-modal="true"
		style="transform: translateY({dragY}px)"
	>
		<!-- Drag-Handle -->
		<div
			class="sheet-handle-area"
			bind:this={handleEl}
			onpointerdown={onHandleDown}
			onpointermove={onHandleMove}
			onpointerup={onHandleUp}
			onpointercancel={onHandleUp}
		>
			<span class="sheet-handle"></span>
			{#if title}
				<p class="sheet-title">{title}</p>
			{/if}
		</div>

		<!-- Content -->
		<div class="sheet-body">
			{@render children?.()}
		</div>
	</div>
{/if}
