<script>
	import { toastMessage, isToastActive } from '$lib/stores/toast.js';

	function portal(node) {
		document.body.appendChild(node);
		return { destroy() { node.remove(); } };
	}
</script>

<div use:portal class="toast-pill" class:toast-pill--visible={$isToastActive}>
	<span class="material-symbols-outlined toast-pill-icon">check_circle</span>
	<span class="toast-pill-text">{$toastMessage}</span>
</div>
