<script>
	import { page } from '$app/stores';
	import { scrollY } from '$lib/stores/scroll.js';
	import { currentPageConfig, currentSubtab, setSubtab } from '$lib/stores/subtab.js';
	import { playerRole } from '$lib/stores/auth';

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
		<h1 class="page-header-title">{$currentPageConfig.title}</h1>

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
