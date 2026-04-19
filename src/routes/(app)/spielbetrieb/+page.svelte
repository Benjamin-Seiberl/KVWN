<script>
	import { currentSubtab } from '$lib/stores/subtab.js';
	import UebersichtTab     from '$lib/components/spielbetrieb/UebersichtTab.svelte';
	import StatsView         from '$lib/components/statistiken/StatsView.svelte';
	import SpielbetriebeTab  from '$lib/components/spielbetrieb/SpielbetriebeTab.svelte';
	import TurniereTab       from '$lib/components/spielbetrieb/TurniereTab.svelte';
	import LandesbewerbeTab  from '$lib/components/spielbetrieb/LandesbewerbeTab.svelte';
</script>

<div class="page active">
	{#if $currentSubtab === 'uebersicht' || !$currentSubtab}
		<UebersichtTab />
	{:else if $currentSubtab === 'statistiken'}
		<StatsView />
	{:else if $currentSubtab === 'turnier'}
		<TurniereTab />
	{:else if $currentSubtab === 'landesbewerb'}
		<LandesbewerbeTab />
	{:else}
		<SpielbetriebeTab />
	{/if}
</div>
