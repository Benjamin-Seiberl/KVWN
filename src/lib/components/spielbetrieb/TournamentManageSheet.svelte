<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import TurniereTab from '$lib/components/spielbetrieb/TurniereTab.svelte';

	let { open = $bindable(false) } = $props();
</script>

<BottomSheet bind:open title="Turniere verwalten">
	<TurniereTab />
</BottomSheet>
