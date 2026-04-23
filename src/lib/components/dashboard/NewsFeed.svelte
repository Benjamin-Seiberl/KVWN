<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';
	import NewsCard from './NewsCard.svelte';
	import PollCard from './PollCard.svelte';

	let news  = $state([]);
	let polls = $state([]);

	async function load() {
		const [nRes, pRes] = await Promise.all([
			sb.from('announcements').select('*').order('pinned', { ascending: false }).order('created_at', { ascending: false }).limit(10),
			sb.from('polls').select('*, poll_options(id, label, order_index)').order('created_at', { ascending: false }).limit(5),
		]);
		if (nRes.error) { triggerToast('Fehler: ' + nRes.error.message); return; }
		if (pRes.error) { triggerToast('Fehler: ' + pRes.error.message); return; }
		news  = nRes.data ?? [];
		polls = pRes.data ?? [];
	}

	onMount(load);

	// Mixed feed: Pinned-Announcements first, dann News + Polls chronologisch gemischt.
	const feed = $derived.by(() => {
		const items = [];
		for (const n of news)  items.push({ kind: 'news',  id: n.id, createdAt: n.created_at, pinned: !!n.pinned, data: n });
		for (const p of polls) items.push({ kind: 'poll',  id: p.id, createdAt: p.created_at, pinned: false,        data: p });
		items.sort((a, b) => {
			if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
			return (b.createdAt ?? '').localeCompare(a.createdAt ?? '');
		});
		return items.slice(0, 6);
	});

	const hasContent = $derived(feed.length > 0);
</script>

{#if hasContent}
	<section class="feed">
		<div class="feed-head">
			<div class="feed-head-left">
				<span class="feed-icon material-symbols-outlined">campaign</span>
				<h3 class="feed-title">Neuigkeiten</h3>
			</div>
		</div>

		<div class="feed-list">
			{#each feed as item, i (item.kind + item.id)}
				<div class="feed-item" style="--fi:{i}">
					{#if item.kind === 'news'}
						<NewsCard news={item.data} onUpdated={load} />
					{:else}
						<PollCard poll={item.data} onVoted={load} />
					{/if}
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.feed {
		margin: var(--space-2) 0 var(--space-3);
		padding: 0 var(--space-5);
	}

	/* Section header */
	.feed-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.feed-head-left {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.feed-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.feed-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	/* Vertical list */
	.feed-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.feed-item {
		animation: feed-up 440ms cubic-bezier(0.22, 1, 0.36, 1) both;
		animation-delay: calc(var(--fi) * 55ms + 80ms);
	}
	@keyframes feed-up {
		from { opacity: 0; transform: translateY(10px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	@media (prefers-reduced-motion: reduce) {
		.feed-item { animation: none; }
	}
</style>
