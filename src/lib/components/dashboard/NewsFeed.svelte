<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import NewsCard from './NewsCard.svelte';
	import PollCard from './PollCard.svelte';

	let news  = $state([]);
	let polls = $state([]);

	async function load() {
		const [{ data: n }, { data: p }] = await Promise.all([
			sb.from('announcements').select('*').order('pinned', { ascending: false }).order('created_at', { ascending: false }).limit(10),
			sb.from('polls').select('*, poll_options(id, label, order_index)').order('created_at', { ascending: false }).limit(5),
		]);
		news  = n ?? [];
		polls = p ?? [];
	}

	onMount(load);

	const hasContent = $derived(news.length > 0 || polls.length > 0);
</script>

{#if hasContent}
	<section class="feed">
		<div class="feed-head">
			<div class="feed-head-left">
				<span class="feed-icon material-symbols-outlined">campaign</span>
				<h3 class="feed-title">News & Umfragen</h3>
			</div>
			<span class="feed-count">{news.length + polls.length}</span>
		</div>

		<div class="feed-scroll">
			{#each news as n, i}
				<div class="feed-item" style="--fi:{i}">
					<NewsCard news={n} onUpdated={load} />
				</div>
			{/each}
			{#each polls as p, i}
				<div class="feed-item" style="--fi:{news.length + i}">
					<PollCard poll={p} onVoted={load} />
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.feed {
		margin: var(--space-2) 0 var(--space-3);
	}

	/* Section header */
	.feed-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 var(--space-5);
		margin-bottom: var(--space-3);
	}
	.feed-head-left {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.feed-icon {
		font-size: 1.1rem;
		color: var(--color-primary, #CC0000);
	}
	.feed-title {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-text, #1a1a1a);
	}
	.feed-count {
		font-size: 0.72rem;
		font-weight: 700;
		background: var(--color-primary, #CC0000);
		color: #fff;
		border-radius: 999px;
		padding: 2px 8px;
		line-height: 1.4;
	}

	/* Horizontal scroll */
	.feed-scroll {
		display: flex;
		gap: var(--space-3);
		overflow-x: auto;
		scroll-snap-type: x mandatory;
		padding: 4px var(--space-5) 8px;
		scrollbar-width: none;
		-webkit-overflow-scrolling: touch;
	}
	.feed-scroll::-webkit-scrollbar { display: none; }

	/* Individual card wrapper */
	.feed-item {
		scroll-snap-align: start;
		flex: 0 0 82%;
		max-width: 340px;
		animation: feed-pop 440ms cubic-bezier(0.22, 1, 0.36, 1) both;
		animation-delay: calc(var(--fi) * 55ms + 80ms);
	}

	@keyframes feed-pop {
		from { opacity: 0; transform: translateY(12px) scale(0.97); }
		to   { opacity: 1; transform: translateY(0) scale(1); }
	}
</style>
