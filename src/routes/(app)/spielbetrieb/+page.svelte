<script>
  import { currentSubtab } from '$lib/stores/subtab.js';
  import { playerRole } from '$lib/stores/auth.js';
  import UebersichtTab           from '$lib/components/spielbetrieb/UebersichtTab.svelte';
  import AufstellungenTab        from '$lib/components/spielbetrieb/AufstellungenTab.svelte';
  import SpielbetriebTab         from '$lib/components/spielbetrieb/SpielbetriebTab.svelte';
  import StatsView               from '$lib/components/statistiken/StatsView.svelte';
  import AdminSpielbetriebTab    from '$lib/components/spielbetrieb/AdminSpielbetriebTab.svelte';
</script>

<div class="page active">
  {#if $currentSubtab === 'uebersicht' || !$currentSubtab}
    <UebersichtTab />
  {/if}
  {#if $currentSubtab === 'aufstellungen'}
    <AufstellungenTab />
  {/if}
  {#if $currentSubtab === 'spielbetrieb'}
    <SpielbetriebTab />
  {/if}
  {#if $currentSubtab === 'statistiken'}
    <StatsView />
  {/if}
  {#if $currentSubtab === 'admin' && $playerRole === 'kapitaen'}
    <AdminSpielbetriebTab />
  {/if}
</div>
