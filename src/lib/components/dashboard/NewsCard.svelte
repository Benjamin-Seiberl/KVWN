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
		if ($playerRole === 'kapitaen') {
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
	<button class="ncard" class:ncard--hero={!!news.image_url} type="button" onclick={() => open = true}>

		{#if news.image_url}
			<!-- Hero style: full-bleed image with gradient overlay -->
			<div class="ncard-img-wrap">
				<img class="ncard-img" src={news.image_url} alt="" draggable="false" />
				<div class="ncard-img-gradient"></div>
				{#if news.pinned}
					<span class="ncard-pin-badge">
						<span class="material-symbols-outlined">keep</span>
					</span>
				{/if}
				<div class="ncard-img-content">
					<span class="ncard-meta-hero">{timeAgo(news.created_at)}</span>
					<h4 class="ncard-title-hero">{news.title}</h4>
				</div>
			</div>
		{:else}
			<!-- Editorial style: accent stripe + clean text -->
			<div class="ncard-editorial">
				<div class="ncard-accent-bar"></div>
				<div class="ncard-body">
					<div class="ncard-meta">
						{#if news.pinned}
							<span class="ncard-pin-icon material-symbols-outlined">keep</span>
						{/if}
						<span class="ncard-time">{timeAgo(news.created_at)}</span>
					</div>
					<h4 class="ncard-title">{news.title}</h4>
					<p class="ncard-preview">{news.body?.slice(0, 120)}{(news.body?.length ?? 0) > 120 ? '…' : ''}</p>
				</div>
			</div>
		{/if}

	</button>
</ContextMenu>

<BottomSheet bind:open title={news.title}>
	{#if news.image_url}<img class="n-full-img" src={news.image_url} alt="" />{/if}
	<p class="n-full-body">{news.body}</p>
</BottomSheet>

<style>
	/* ── Base card ── */
	.ncard {
		display: flex;
		flex-direction: column;
		border: none;
		padding: 0;
		background: none;
		text-align: left;
		cursor: pointer;
		overflow: hidden;
		width: 100%;
		border-radius: 18px;
		box-shadow: 0 2px 12px rgba(0,0,0,0.08), 0 0 0 1px rgba(0,0,0,0.04);
		transition: transform 160ms cubic-bezier(0.32, 0.72, 0, 1),
		            box-shadow 160ms ease;
	}
	.ncard:active {
		transform: scale(0.97);
		box-shadow: 0 1px 6px rgba(0,0,0,0.06);
	}

	/* ── Hero (image) style ── */
	.ncard-img-wrap {
		position: relative;
		width: 100%;
		aspect-ratio: 16/9;
		overflow: hidden;
		border-radius: 18px;
	}
	.ncard-img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
		transition: transform 400ms ease;
	}
	.ncard:active .ncard-img {
		transform: scale(1.03);
	}
	.ncard-img-gradient {
		position: absolute;
		inset: 0;
		background: linear-gradient(
			to bottom,
			transparent 30%,
			rgba(0,0,0,0.25) 60%,
			rgba(0,0,0,0.72) 100%
		);
	}
	.ncard-pin-badge {
		position: absolute;
		top: 10px;
		right: 10px;
		background: rgba(212,175,55,0.9);
		backdrop-filter: blur(8px);
		border-radius: 50%;
		width: 30px;
		height: 30px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.ncard-pin-badge .material-symbols-outlined {
		font-size: 1rem;
		color: #fff;
	}
	.ncard-img-content {
		position: absolute;
		bottom: 0;
		left: 0;
		right: 0;
		padding: 12px 14px;
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.ncard-meta-hero {
		font-size: 0.68rem;
		font-weight: 600;
		letter-spacing: 0.05em;
		color: rgba(255,255,255,0.75);
		text-transform: uppercase;
	}
	.ncard-title-hero {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-weight: 700;
		font-size: 1rem;
		color: #fff;
		line-height: 1.25;
		text-shadow: 0 1px 4px rgba(0,0,0,0.4);
	}

	/* ── Editorial (no image) style ── */
	.ncard-editorial {
		display: flex;
		background: var(--color-surface, #fff);
		border-radius: 18px;
		overflow: hidden;
		min-height: 100px;
	}
	.ncard-accent-bar {
		width: 4px;
		flex-shrink: 0;
		background: linear-gradient(to bottom, var(--color-primary, #CC0000), var(--color-secondary, #D4AF37));
		border-radius: 4px 0 0 4px;
	}
	.ncard-body {
		padding: 14px 14px 14px 12px;
		display: flex;
		flex-direction: column;
		gap: 5px;
		flex: 1;
	}
	.ncard-meta {
		display: flex;
		gap: 6px;
		align-items: center;
		font-size: 0.70rem;
		color: var(--color-text-soft, #888);
	}
	.ncard-pin-icon {
		font-size: 0.85rem;
		color: var(--color-secondary, #D4AF37);
	}
	.ncard-time { font-weight: 500; }
	.ncard-title {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-weight: 700;
		font-size: 0.95rem;
		color: var(--color-text, #1a1a1a);
		line-height: 1.3;
	}
	.ncard-preview {
		margin: 0;
		font-size: 0.80rem;
		color: var(--color-text-soft, #666);
		line-height: 1.5;
	}

	/* ── Bottom sheet content ── */
	.n-full-img {
		width: 100%;
		border-radius: 14px;
		margin-bottom: var(--space-3);
		object-fit: cover;
	}
	.n-full-body {
		white-space: pre-wrap;
		line-height: 1.7;
		color: var(--color-text, #1a1a1a);
		font-size: 0.95rem;
	}
</style>
