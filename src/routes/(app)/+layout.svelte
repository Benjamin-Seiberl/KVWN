<script>
	import { isMember } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import BottomNav from '$lib/components/BottomNav.svelte';

	let { children } = $props();

	// Auth-Guard: nicht eingeloggt oder kein Mitglied → Login
	$effect(() => {
		if (browser && $isMember === false) goto('/login');
	});
</script>

{#if $isMember === true}
<div class="app-shell">

	<main class="page-content">
		{@render children()}
	</main>

	<BottomNav />

</div>
{/if}
