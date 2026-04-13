<script>
	import { page } from '$app/stores';
	import { onMount } from 'svelte';
	import BottomSheet from './BottomSheet.svelte';

	const pages = [
		{ href: '/',             label: 'Dashboard',    icon: 'dashboard'     },
		{ href: '/spielbetrieb', label: 'Spielbetrieb', icon: 'sports_score'  },
		{ href: '/kalender',     label: 'Kalender',     icon: 'calendar_today'},
	];

	const drawerLinks = [
		{ href: '/spielbetrieb', icon: 'sports_score',  label: 'Aufstellung',     desc: 'Mannschaftsaufstellungen' },
		{ href: '/kalender',     icon: 'calendar_today',label: 'Kalender',         desc: 'Trainings & Spiele'        },
		{ href: '/mehr',         icon: 'info',          label: 'Über den Verein',  desc: 'Infos & Kontakt'           },
	];

	let navEl      = $state(null);
	let indicatorLeft = $state(0);
	let pressed    = $state(null);
	let drawerOpen = $state(false);

	function activeIndex() {
		return pages.findIndex(i => $page.url.pathname === i.href);
	}

	function moveIndicator(index) {
		if (!navEl) return;
		const navRect = navEl.getBoundingClientRect();
		const itemEls = navEl.querySelectorAll('.nav-item');
		const itemEl  = itemEls[index];
		if (!itemEl) return;
		const itemRect = itemEl.getBoundingClientRect();
		const indW    = 60;
		const centerX = itemRect.left - navRect.left + itemRect.width / 2;
		indicatorLeft = centerX - indW / 2;
	}

	$effect(() => {
		const idx = activeIndex();
		requestAnimationFrame(() => moveIndicator(idx));
	});

	onMount(() => {
		const idx = activeIndex();
		requestAnimationFrame(() => moveIndicator(idx));
		window.addEventListener('resize', () => moveIndicator(activeIndex()));
	});
</script>

<nav class="bottom-nav" bind:this={navEl}>
	<span class="nav-indicator" style="left: {indicatorLeft}px" aria-hidden="true"></span>

	{#each pages as item, i}
		<a
			class="nav-item"
			class:active={$page.url.pathname === item.href}
			class:pressed={pressed === i}
			href={item.href}
			aria-label={item.label}
			onpointerdown={() => pressed = i}
			onpointerup={() => pressed = null}
			onpointercancel={() => pressed = null}
		>
			<span class="material-symbols-outlined nav-icon">{item.icon}</span>
			<span class="nav-label">{item.label}</span>
		</a>
	{/each}

	<!-- Mehr → öffnet Drawer -->
	<button
		class="nav-item nav-item--btn"
		class:pressed={pressed === 99}
		aria-label="Mehr"
		onclick={() => drawerOpen = true}
		onpointerdown={() => pressed = 99}
		onpointerup={() => pressed = null}
		onpointercancel={() => pressed = null}
	>
		<span class="material-symbols-outlined nav-icon">menu</span>
		<span class="nav-label">Mehr</span>
	</button>
</nav>

<!-- Bottom-Sheet Drawer -->
<BottomSheet bind:open={drawerOpen} title="Navigation">
	<nav class="drawer-nav">
		{#each drawerLinks as link}
			<a
				class="drawer-item"
				href={link.href}
				onclick={() => drawerOpen = false}
			>
				<span class="drawer-item-icon material-symbols-outlined">{link.icon}</span>
				<div class="drawer-item-text">
					<span class="drawer-item-label">{link.label}</span>
					<span class="drawer-item-desc">{link.desc}</span>
				</div>
				<span class="material-symbols-outlined drawer-item-chevron">chevron_right</span>
			</a>
		{/each}
	</nav>
</BottomSheet>
