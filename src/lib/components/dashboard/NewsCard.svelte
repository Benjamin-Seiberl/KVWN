<script>
	import { sb } from '$lib/supabase';
	import { playerRole } from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import ContextMenu from '$lib/components/ContextMenu.svelte';

	let { news, onUpdated } = $props();
	let open = $state(false);

	function timeAgo(iso) {
		if (!iso) return '';
		const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
		if (s < 60) return 'gerade eben';
		if (s < 3600) return `vor ${Math.floor(s/60)} Min.`;
		if (s < 86400) return `vor ${Math.floor(s/3600)} Std.`;
		return `vor ${Math.floor(s/86400)} Tg.`;
	}

	// ── Context menu actions ───────────────────────────────────────────────────
	async function togglePin() {
		const { error } = await sb
			.from('announcements')
			.update({ pinned: !news.pinned })
			.eq('id', news.id);
		if (!error) {
			triggerToast(news.pinned ? 'Beitrag losgelöst' : 'Beitrag angeheftet');
			onUpdated?.();
		}
	}

	async function shareNews() {
		const text = `${news.title}\n\n${news.body?.slice(0, 200)}`;
		if (navigator.share) {
			try { await navigator.share({ title: news.title, text }); } catch {}
		} else {
			await navigator.clipboard.writeText(text);
			triggerToast('In Zwischenablage kopiert');
		}
	}

	async function deleteNews() {
		const { error } = await sb
			.from('announcements')
			.delete()
			.eq('id', news.id);
		if (!error) {
			triggerToast('Beitrag gelöscht');
			onUpdated?.();
		}
	}

	let contextActions = $derived.by(() => {
		const base = [
			{
				label: news.pinned ? 'Loslösen' : 'Anheften',
				icon:  news.pinned ? 'keep_off' : 'keep',
				fn:    togglePin,
			},
			{
				label: 'Teilen',
				icon:  'share',
				fn:    shareNews,
			},
		];
		if ($playerRole === 'admin') {
			base.push({
				label:       'Löschen',
				icon:        'delete',
				fn:          deleteNews,
				destructive: true,
			});
		}
		return base;
	});
</script>

<ContextMenu actions={contextActions}>
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
</ContextMenu>

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
		width: 100%;
		transition: transform 150ms cubic-bezier(0.32, 0.72, 0, 1);
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
