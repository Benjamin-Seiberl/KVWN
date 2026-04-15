<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import NewsCard from './NewsCard.svelte';
	import PollCard from './PollCard.svelte';

	let news = $state([]);
	let polls = $state([]);

	async function load() {
		const [{ data: n }, { data: p }] = await Promise.all([
			sb.from('announcements').select('*').order('pinned', { ascending: false }).order('created_at', { ascending: false }).limit(10),
			sb.from('polls').select('*, poll_options(id, label, order_index)').order('created_at', { ascending: false }).limit(5),
		]);
		news = n ?? [];
		polls = p ?? [];
	}

	onMount(load);

	const hasContent = $derived(news.length > 0 || polls.length > 0);
</script>

{#if hasContent}
	<section class="feed">
		<div class="feed-head">
			<span class="material-symbols-outlined">campaign</span>
			<h3>News & Umfragen</h3>
		</div>
		<div class="feed-scroll">
			{#each news as n}
				<NewsCard news={n} />
			{/each}
			{#each polls as p}
				<PollCard poll={p} onVoted={load} />
			{/each}
		</div>
	</section>
{/if}

<style>
	.feed {
		margin: var(--space-3) 0;
	}
	.feed-head {
		display: flex; gap: 6px; align-items: center;
		padding: 0 var(--space-5);
		margin-bottom: var(--space-2);
	}
	.feed-head h3 {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-weight: 600;
		font-size: 0.95rem;
	}
	.feed-head :global(.material-symbols-outlined) { color: var(--color-primary, #CC0000); }
	.feed-scroll {
		display: flex; gap: var(--space-3);
		overflow-x: auto;
		scroll-snap-type: x mandatory;
		padding: 0 var(--space-5) 4px;
		scrollbar-width: none;
	}
	.feed-scroll::-webkit-scrollbar { display: none; }
	.feed-scroll :global(> *) {
		scroll-snap-align: start;
		flex: 0 0 82%;
		max-width: 360px;
	}
</style>
