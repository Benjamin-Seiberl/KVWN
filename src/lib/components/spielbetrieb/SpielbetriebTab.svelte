<script>
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { get } from 'svelte/store';
	import PillSwitcher from '$lib/components/ui/PillSwitcher.svelte';
	import SpielbetriebeTab from '$lib/components/spielbetrieb/SpielbetriebeTab.svelte';
	import TurniereTab from '$lib/components/spielbetrieb/TurniereTab.svelte';
	import LandesbewerbeTab from '$lib/components/spielbetrieb/LandesbewerbeTab.svelte';

	const VALID = ['spiele', 'turnier', 'landesbewerb'];
	const initialPill = get(page).url.searchParams.get('pill');
	let active = $state(VALID.includes(initialPill) ? initialPill : 'spiele');

	$effect(() => {
		const url = new URL($page.url);
		if (url.searchParams.get('pill') !== active) {
			url.searchParams.set('pill', active);
			goto(url.pathname + url.search, { replaceState: true, keepFocus: true, noScroll: true });
		}
	});
</script>

<div class="spielbetrieb-container">
	<div class="pill-bar">
		<PillSwitcher
			items={[
				{ key: 'spiele', label: 'Spiele', icon: 'sports' },
				{ key: 'turnier', label: 'Turnier', icon: 'military_tech' },
				{ key: 'landesbewerb', label: 'Landesbewerb', icon: 'workspace_premium' }
			]}
			value={active}
			onSelect={(k) => (active = k)}
		/>
	</div>

	{#if active === 'spiele'}<SpielbetriebeTab />{/if}
	{#if active === 'turnier'}<TurniereTab />{/if}
	{#if active === 'landesbewerb'}<LandesbewerbeTab />{/if}
</div>

<style>
	.spielbetrieb-container {
		display: flex;
		flex-direction: column;
	}

	.pill-bar {
		position: sticky;
		top: 0;
		z-index: 5;
		background: var(--color-surface-container-lowest);
		padding: var(--space-2) var(--space-3);
	}
</style>
