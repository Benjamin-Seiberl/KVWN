<script>
  import { currentSubtab } from '$lib/stores/subtab.js';
  import SpieleTab        from '$lib/components/spielbetrieb/SpieleTab.svelte';
  import TurniereTab      from '$lib/components/spielbetrieb/TurniereTab.svelte';
  import LandesbewerbeTab from '$lib/components/spielbetrieb/LandesbewerbeTab.svelte';
  import StatsView        from '$lib/components/statistiken/StatsView.svelte';
</script>

<div class="page active">
  {#if $currentSubtab === 'spiele' || !$currentSubtab}
    <SpieleTab />
  {/if}
  {#if $currentSubtab === 'turniere'}
    <TurniereTab />
  {/if}
  {#if $currentSubtab === 'landesbewerbe'}
    <LandesbewerbeTab />
  {/if}
  {#if $currentSubtab === 'statistiken'}
    <StatsView />
  {/if}
</div>
