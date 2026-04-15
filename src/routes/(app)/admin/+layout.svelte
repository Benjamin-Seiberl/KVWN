<script>
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { playerRole } from '$lib/stores/auth';

	let { children } = $props();

	const tabs = [
		{ href: '/admin',           label: 'Übersicht', icon: 'dashboard' },
		{ href: '/admin/spieler',   label: 'Spieler',   icon: 'group' },
		{ href: '/admin/teams',     label: 'Teams',     icon: 'diversity_3' },
		{ href: '/admin/saison',    label: 'Saison',    icon: 'event_note' },
		{ href: '/admin/training',  label: 'Training',  icon: 'fitness_center' },
		{ href: '/admin/news',      label: 'News',      icon: 'campaign' },
	];

	$effect(() => {
		if (browser && $playerRole && $playerRole !== 'admin') goto('/');
	});
</script>

{#if $playerRole === 'admin'}
	<!-- playerRole ist definitiv 'admin' → rendern -->
	<header class="admin-hdr">
		<h1 class="admin-hdr__title">
			<span class="material-symbols-outlined">shield_person</span>
			Admin-Panel
		</h1>
		<nav class="admin-tabs">
			{#each tabs as t}
				<a
					class="admin-tab"
					class:admin-tab--active={$page.url.pathname === t.href || (t.href !== '/admin' && $page.url.pathname.startsWith(t.href))}
					href={t.href}
				>
					<span class="material-symbols-outlined">{t.icon}</span>
					<span>{t.label}</span>
				</a>
			{/each}
		</nav>
	</header>
	<section class="admin-body">
		{@render children()}
	</section>
{:else if $playerRole && $playerRole !== 'admin'}
	<!-- Definitiv kein Admin → Zugriff verweigert -->
	<p class="admin-guard">Zugriff nur für Admins.</p>
{/if}
<!-- Wenn playerRole noch null/initialisiert → nichts rendern (kein Flackern) -->

<style>
	.admin-hdr {
		position: sticky; top: 0; z-index: 10;
		background: var(--color-bg, #fff);
		padding: var(--space-4) var(--space-5) 0;
		border-bottom: 1px solid var(--color-border, #eee);
	}
	.admin-hdr__title {
		display: flex; gap: var(--space-2); align-items: center;
		font-family: 'Lexend', sans-serif; font-weight: 600; font-size: 1.3rem;
		margin: 0 0 var(--space-3);
		color: var(--color-primary, #CC0000);
	}
	.admin-tabs {
		display: flex; gap: var(--space-1); overflow-x: auto;
		scrollbar-width: none;
		margin: 0 calc(-1 * var(--space-5));
		padding: 0 var(--space-5) var(--space-2);
	}
	.admin-tabs::-webkit-scrollbar { display: none; }
	.admin-tab {
		display: inline-flex; gap: 4px; align-items: center;
		padding: 6px 12px;
		border-radius: 999px;
		font-size: 0.85rem;
		white-space: nowrap;
		color: var(--color-text-soft, #666);
		background: var(--color-surface, #f5f5f5);
		text-decoration: none;
		border: 1px solid transparent;
	}
	.admin-tab :global(.material-symbols-outlined) { font-size: 1rem; }
	.admin-tab--active {
		color: #fff;
		background: var(--color-primary, #CC0000);
		box-shadow: 0 2px 6px rgba(204,0,0,0.3);
	}
	.admin-body {
		padding: var(--space-4) var(--space-5);
	}
	.admin-guard {
		padding: var(--space-6);
		text-align: center;
		color: var(--color-text-soft, #666);
	}
</style>
