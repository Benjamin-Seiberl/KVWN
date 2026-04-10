<script>
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	const items = [
		{ href: '/',            label: 'Dashboard',   icon: 'dashboard'    },
		{ href: '/spielbetrieb', label: 'Spielbetrieb', icon: 'sports_score' },
		{ href: '/kalender',    label: 'Kalender',    icon: 'calendar_today'},
		{ href: '/mehr',        label: 'Mehr',        icon: 'menu'          },
	];

	let navEl = $state(null);
	let indicatorLeft = $state(0);
	let pressed = $state(null);

	function activeIndex() {
		return items.findIndex(i => $page.url.pathname === i.href);
	}

	function moveIndicator(index) {
		if (!navEl) return;
		const navRect  = navEl.getBoundingClientRect();
		const itemEls  = navEl.querySelectorAll('.nav-item');
		const itemEl   = itemEls[index];
		if (!itemEl) return;
		const itemRect = itemEl.getBoundingClientRect();
		const indW     = 60;
		const centerX  = itemRect.left - navRect.left + itemRect.width / 2;
		indicatorLeft  = centerX - indW / 2;
	}

	$effect(() => {
		// Reagiert auf Route-Wechsel
		const idx = activeIndex();
		// requestAnimationFrame damit DOM schon gerendert ist
		requestAnimationFrame(() => moveIndicator(idx));
	});

	onMount(() => {
		const idx = activeIndex();
		// Beim ersten Mount ohne Transition
		requestAnimationFrame(() => moveIndicator(idx));
		window.addEventListener('resize', () => moveIndicator(activeIndex()));
	});
</script>

<nav class="bottom-nav" bind:this={navEl}>
	<span class="nav-indicator" style="left: {indicatorLeft}px" aria-hidden="true"></span>

	{#each items as item, i}
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
</nav>
