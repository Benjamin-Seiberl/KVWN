<script>
	import { isMember } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { page, navigating } from '$app/stores';
	import { onMount } from 'svelte';
	import { initScrollListener } from '$lib/stores/scroll.js';
	import BottomNav from '$lib/components/BottomNav.svelte';
	import PageHeader from '$lib/components/PageHeader.svelte';

	let { children } = $props();

	// Auth-Guard: nicht eingeloggt oder kein Mitglied → Login
	$effect(() => {
		if (browser && $isMember === false) goto('/login');
	});

	onMount(() => {
		return initScrollListener();
	});
</script>

{#if $isMember === true}
<div class="app-shell">

	<main class="page-content">
		<!-- Header scrollt mit dem Inhalt; Pill bleibt via position:fixed oben -->
		<PageHeader />

		{#if $navigating}
			<!-- Skeleton während Navigation -->
			<div class="page-skeleton animate-fade-float">
				<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
				<div class="skeleton-card skeleton-card--tall animate-pulse-skeleton" style="animation-delay:80ms"></div>
				<div class="skeleton-card animate-pulse-skeleton" style="animation-delay:160ms"></div>
				<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:240ms"></div>
			</div>
		{:else}
			<!-- Page Content mit fadeFloat-Transition -->
			{#key $page.url.pathname}
				<div class="animate-fade-float">
					{@render children()}
				</div>
			{/key}
		{/if}
	</main>

	<BottomNav />

</div>
{/if}
