<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import LandesbewerbeTab from '$lib/components/spielbetrieb/LandesbewerbeTab.svelte';

	let { open = $bindable(false) } = $props();
</script>

<BottomSheet bind:open title="Landesbewerbe verwalten">
	<LandesbewerbeTab />
</BottomSheet>
