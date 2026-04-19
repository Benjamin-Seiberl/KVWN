<script>
	import { page } from '$app/stores';
	import { fly } from 'svelte/transition';
	import { scrollY, scrollDirection } from '$lib/stores/scroll.js';
	import { currentPageConfig, currentSubtab, setSubtab } from '$lib/stores/subtab.js';
	import { playerRole } from '$lib/stores/auth.js';

	const tabs = [
		{ href: '/',             label: 'Dashboard',    icon: 'house'          },
		{ href: '/kalender',     label: 'Kalender',     icon: 'calendar_month' },
		{ href: '/spielbetrieb', label: 'Spielbetrieb', icon: 'emoji_events'   },
		{ href: '/profil',       label: 'Profil',       icon: 'person'         },
	];

	let subtabMenuOpen = $state(false);
	let navVisible     = $derived($scrollY <= 50 || $scrollDirection === 'up');

	// Position of the active tab element — used to anchor the subtab strip
	let stripLeft  = $state(0);
	let stripWidth = $state(0);
	let tabEls     = [];

	$effect(() => {
		$page.url.pathname;
		subtabMenuOpen = false;
	});

	const visibleSubtabs = $derived(
		($currentPageConfig?.tabs ?? []).filter(t => !t.adminOnly || $playerRole === 'kapitaen')
	);
	const hasSubtabs = $derived(visibleSubtabs.length > 1);

	function isActive(href) {
		if (href === '/') return $page.url.pathname === '/';
		return $page.url.pathname.startsWith(href);
	}

	function handleTabClick(tab, e, idx) {
		if (isActive(tab.href)) {
			if (hasSubtabs) {
				e.preventDefault();
				if (!subtabMenuOpen) {
					const el = tabEls[idx];
					if (el) {
						const rect = el.getBoundingClientRect();
						stripLeft  = rect.left;
						stripWidth = rect.width;
					}
				}
				subtabMenuOpen = !subtabMenuOpen;
			}
		} else {
			subtabMenuOpen = false;
		}
	}

	function selectSubtab(key) {
		setSubtab($page.url.pathname, key);
		subtabMenuOpen = false;
	}
</script>

<!-- Backdrop -->
{#if subtabMenuOpen}
	<button
		class="pill-subtab-backdrop"
		onclick={() => subtabMenuOpen = false}
		aria-label="Schließen"
		transition:fly={{ duration: 150, opacity: 0 }}
	></button>
{/if}

<!-- Subtab Strip — anchored to active tab -->
{#if subtabMenuOpen && navVisible}
	<div
		class="pill-subtab-strip"
		style="left: {stripLeft}px; width: {stripWidth}px;"
		transition:fly={{ y: 10, duration: 200, opacity: 0 }}
	>
		{#each visibleSubtabs as st}
			<button
				class="pill-subtab-opt"
				class:active={$currentSubtab === st.key}
				onclick={() => selectSubtab(st.key)}
			>
				<span class="material-symbols-outlined">{st.icon}</span>
				<span>{st.label}</span>
			</button>
		{/each}
	</div>
{/if}

<!-- Bottom Nav -->
<div class="pill-nav-outer" class:nav-hidden={!navVisible} aria-label="Hauptnavigation">
	<nav class="pill-nav">
		{#each tabs as tab, i}
			{@const active = isActive(tab.href)}
			<a
				class="pill-tab"
				class:active
				href={tab.href}
				aria-label={tab.label}
				aria-current={active ? 'page' : undefined}
				onclick={(e) => handleTabClick(tab, e, i)}
				bind:this={tabEls[i]}
			>
				<span class="material-symbols-outlined pill-tab-icon">{tab.icon}</span>
				<div class="pill-tab-label-wrap">
					<div class="pill-tab-label-inner">
						<span class="pill-tab-label">{tab.label}</span>
					</div>
				</div>
				{#if active && hasSubtabs}
					<span class="pill-tab-chevron" class:pill-tab-chevron--open={subtabMenuOpen}>
						<span class="material-symbols-outlined">expand_less</span>
					</span>
				{/if}
			</a>
		{/each}
	</nav>
</div>
