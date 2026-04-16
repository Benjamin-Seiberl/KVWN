<script>
	import { page } from '$app/stores';
	import { scrollY } from '$lib/stores/scroll.js';
	import { currentPageConfig, currentSubtab, setSubtab } from '$lib/stores/subtab.js';
	import { playerRole } from '$lib/stores/auth';
	import { spotlightOpen } from '$lib/stores/spotlight.js';

	// Transition only after 120px of scroll
	let isScrolled = $derived($scrollY > 120);

	// Filtered tabs (hide adminOnly tabs from non-admins)
	let visibleTabs = $derived.by(() => {
		const config = $currentPageConfig;
		if (!config) return [];
		return config.tabs.filter(t => !t.adminOnly || $playerRole === 'kapitaen');
	});

	function selectSubtabHeader(key) {
		const path = $page.url.pathname;
		if (key !== $currentSubtab) setSubtab(path, key);
	}
</script>

{#if $currentPageConfig}
<header class="page-header">

	<!-- Static header: title + sub-tab bar -->
	<div class="page-header-static" class:header-hidden={isScrolled}>
		<div class="ph-title-row">
			<h1 class="page-header-title">{$currentPageConfig.title}</h1>
			<button
				class="ph-search-btn"
				onclick={() => $spotlightOpen = true}
				aria-label="Suche öffnen"
			>
				<span class="material-symbols-outlined">search</span>
			</button>
		</div>

		<div class="page-header-tabs">
			{#each visibleTabs as tab (tab.key)}
				{@const active = tab.key === $currentSubtab}
				<button
					class="page-header-tab"
					class:active
					onclick={() => selectSubtabHeader(tab.key)}
				>
					<span class="material-symbols-outlined">{tab.icon}</span>
					{tab.label}
					{#if active}
						<div class="page-header-tab-indicator"></div>
					{/if}
				</button>
			{/each}
		</div>
	</div>

</header>
{/if}

<style>
.ph-title-row {
	display: flex;
	align-items: center;
	justify-content: space-between;
	margin-bottom: var(--space-5);
}

.ph-title-row :global(.page-header-title) {
	margin-bottom: 0;
	text-align: left;
}

.ph-search-btn {
	width: 36px;
	height: 36px;
	border-radius: var(--radius-full);
	background: rgba(120, 120, 128, 0.10);
	border: none;
	display: flex;
	align-items: center;
	justify-content: center;
	cursor: pointer;
	flex-shrink: 0;
	-webkit-tap-highlight-color: transparent;
	pointer-events: auto;
	transition: background 150ms ease, transform 150ms ease;
	color: var(--color-on-surface-variant);
}
.ph-search-btn:active {
	transform: scale(0.9);
	background: rgba(120, 120, 128, 0.20);
}
.ph-search-btn .material-symbols-outlined {
	font-size: 1.15rem;
	font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}
</style>
