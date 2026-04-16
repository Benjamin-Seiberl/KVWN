<script>
	import { page } from '$app/stores';
	import { scrollY, scrollDirection } from '$lib/stores/scroll.js';

	const tabs = [
		{ href: '/',             label: 'Dashboard',    icon: 'house'          },
		{ href: '/kalender',     label: 'Kalender',     icon: 'calendar_month' },
		{ href: '/spielbetrieb', label: 'Spielbetrieb', icon: 'emoji_events'   },
		{ href: '/profil',       label: 'Profil',       icon: 'person'         },
	];

	let navVisible = $derived($scrollY <= 50 || $scrollDirection === 'up');

	function isActive(href) {
		if (href === '/') return $page.url.pathname === '/';
		return $page.url.pathname.startsWith(href);
	}
</script>

<div class="pill-nav-outer" class:nav-hidden={!navVisible} aria-label="Hauptnavigation">
	<nav class="pill-nav">
		{#each tabs as tab}
			{@const active = isActive(tab.href)}
			<a
				class="pill-tab"
				class:active
				href={tab.href}
				aria-label={tab.label}
				aria-current={active ? 'page' : undefined}
			>
				<span class="material-symbols-outlined pill-tab-icon">{tab.icon}</span>
				<div class="pill-tab-label-wrap">
					<div class="pill-tab-label-inner">
						<span class="pill-tab-label">{tab.label}</span>
					</div>
				</div>
			</a>
		{/each}
	</nav>
</div>
