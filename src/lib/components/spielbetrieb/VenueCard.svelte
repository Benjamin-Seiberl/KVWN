<script>
	import VenueProposeSheet from './VenueProposeSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import ContextMenu from '$lib/components/ContextMenu.svelte';
	import { imgPath, BLANK_IMG } from '$lib/utils/players.js';

	let { match, venues = [], votes = [], onChanged } = $props();
	let sheetOpen = $state(false);

	const myVote = $derived(votes.find(v => v.player_id === $playerId));

	function votersFor(venueId) {
		return votes.filter(v => v.venue_id === venueId);
	}

	async function vote(venue) {
		if (!$playerId) return;
		await sb
			.from('match_venue_votes')
			.upsert(
				{ match_id: match.id, player_id: $playerId, venue_id: venue.id },
				{ onConflict: 'match_id,player_id' }
			);
		triggerToast(`Abgestimmt: ${venue.name}`);
		await onChanged?.();
	}

	function venueActions(v) {
		const acts = [];
		if (v.url) {
			acts.push({
				label: 'Route öffnen',
				icon:  'directions',
				fn:    () => window.open(v.url, '_blank', 'noopener'),
			});
		}
		acts.push({
			label: 'Teilen',
			icon:  'share',
			fn:    async () => {
				const text = v.name + (v.url ? '\n' + v.url : '');
				if (navigator.share) {
					try { await navigator.share({ title: v.name, text }); } catch {}
				} else {
					await navigator.clipboard.writeText(text);
					triggerToast(`${v.name} kopiert`);
				}
			},
		});
		return acts;
	}
</script>

<section class="mw-card mw-card--venue">
	<div class="mw-card__head">
		<div>
			<h3 class="mw-card__title">
				<span class="material-symbols-outlined" style="color: var(--color-secondary);">celebration</span>
				Kulinarischer Ausklang
			</h3>
			<p class="mw-card__subtitle"><em>Wer isst nach dem Match mit?</em></p>
		</div>
	</div>

	{#if venues.length === 0}
		<p class="mw-empty">Noch kein Lokal vorgeschlagen.</p>
	{:else}
		<div class="mw-venue__list" style="margin-bottom: var(--space-3);">
			{#each venues as v}
				{@const voters = votersFor(v.id)}
				{@const isMine = myVote?.venue_id === v.id}
				{@const shown  = voters.slice(0, 3)}
				{@const more   = Math.max(0, voters.length - shown.length)}
				<ContextMenu actions={venueActions(v)}>
					<div class="mw-venue__item">
						<div class="mw-venue__body">
							<div class="mw-venue__name-row">
								<span class="mw-venue__name">{v.name}</span>
								{#if isMine}<span class="mw-venue__mine">Deine Stimme</span>{/if}
							</div>
							{#if voters.length > 0}
								<div class="mw-venue__avatars">
									{#each shown as voter}
										{@const p = voter.player}
										<img
											class="mw-venue__avatar"
											src={imgPath(p?.photo, p?.name)}
											alt={p?.name ?? ''}
											onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}
										/>
									{/each}
									{#if more > 0}
										<span class="mw-venue__more">+{more}</span>
									{/if}
								</div>
							{/if}
						</div>
						{#if isMine}
							<button class="mw-btn mw-btn--soft" disabled>Abgestimmt</button>
						{:else}
							<button class="mw-btn mw-btn--primary" onclick={() => vote(v)}>Abstimmen</button>
						{/if}
					</div>
				</ContextMenu>
			{/each}
		</div>
	{/if}

	<button class="mw-btn mw-btn--soft mw-btn--wide" onclick={() => sheetOpen = true}>
		<span class="material-symbols-outlined">add</span>
		Lokal vorschlagen
	</button>
</section>

<VenueProposeSheet bind:open={sheetOpen} {match} onSaved={() => { triggerToast('Lokal vorgeschlagen'); onChanged?.(); }} />
