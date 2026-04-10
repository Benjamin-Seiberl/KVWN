<script>
	import { isMember, user, signOut } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { page } from '$app/stores';
	import { afterNavigate } from '$app/navigation';
	import BottomNav from '$lib/components/BottomNav.svelte';

	let { children } = $props();

	// Auth-Guard: nicht eingeloggt oder kein Mitglied → Login
	$effect(() => {
		if (browser && $isMember === false) goto('/login');
	});

	// Avatar-Initial aus User-Name
	let initial = $derived(
		$user?.user_metadata?.full_name?.charAt(0)?.toUpperCase() ?? 'M'
	);
</script>

{#if $isMember === true}
<div class="app-shell">

	<header class="app-header">
		<div class="header-greeting">
			<p class="header-subtitle">Willkommen zurück</p>
			<h1 class="header-title">KV Wiener Neustadt</h1>
		</div>
		<div class="header-actions">
			<button class="icon-btn" aria-label="Benachrichtigungen">
				<span class="material-symbols-outlined">notifications</span>
			</button>
			<button class="avatar" onclick={signOut} title="Abmelden" aria-label="Abmelden" style="cursor:pointer;border:none;background:none;padding:0">{initial}</button>
		</div>
	</header>

	<main class="page-content">
		{@render children()}
	</main>

	<BottomNav />

</div>
{/if}
