<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { news } = $props();
	let open = $state(false);

	function timeAgo(iso) {
		if (!iso) return '';
		const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
		if (s < 60) return 'gerade eben';
		if (s < 3600) return `vor ${Math.floor(s/60)} Min.`;
		if (s < 86400) return `vor ${Math.floor(s/3600)} Std.`;
		return `vor ${Math.floor(s/86400)} Tg.`;
	}
</script>

<button class="ncard" type="button" onclick={() => open = true}>
	{#if news.image_url}
		<img class="ncard-img" src={news.image_url} alt="" />
	{/if}
	<div class="ncard-body">
		<div class="ncard-meta">
			{#if news.pinned}<span class="ncard-pin">📌</span>{/if}
			<span>{timeAgo(news.created_at)}</span>
		</div>
		<h4 class="ncard-title">{news.title}</h4>
		<p class="ncard-preview">{news.body?.slice(0, 110)}{news.body?.length > 110 ? '…' : ''}</p>
	</div>
</button>

<BottomSheet bind:open title={news.title}>
	{#if news.image_url}<img class="n-full-img" src={news.image_url} alt="" />{/if}
	<p class="n-full-body">{news.body}</p>
</BottomSheet>

<style>
	.ncard {
		border: 1px solid var(--color-border, #eee);
		background: var(--color-surface, #fff);
		border-radius: 14px;
		padding: 0;
		text-align: left;
		cursor: pointer;
		overflow: hidden;
		display: flex; flex-direction: column;
		box-shadow: 0 1px 4px rgba(0,0,0,0.04);
	}
	.ncard-img { width: 100%; aspect-ratio: 16/9; object-fit: cover; }
	.ncard-body { padding: var(--space-3); display: flex; flex-direction: column; gap: 4px; }
	.ncard-meta { display: flex; gap: 6px; font-size: 0.72rem; color: var(--color-text-soft, #888); }
	.ncard-title { margin: 0; font-family: 'Lexend'; font-weight: 600; font-size: 0.95rem; }
	.ncard-preview { margin: 0; font-size: 0.82rem; color: var(--color-text-soft, #666); }
	.ncard-pin { color: var(--color-secondary, #D4AF37); }
	.n-full-img { width: 100%; border-radius: 12px; margin-bottom: var(--space-3); }
	.n-full-body { white-space: pre-wrap; line-height: 1.6; }
</style>
