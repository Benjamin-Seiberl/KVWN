<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import ContextMenu from '$lib/components/ContextMenu.svelte';

	let { poll, onVoted } = $props();
	let votes = $state([]);
	let myVotes = $derived(votes.filter(v => v.player_id === $playerId).map(v => v.option_id));

	const options = $derived((poll.poll_options ?? []).slice().sort((a, b) => a.order_index - b.order_index));
	const totalVoters = $derived(new Set(votes.map(v => v.player_id)).size);
	const closed = $derived(poll.deadline && new Date(poll.deadline) < new Date());

	async function loadVotes() {
		const { data } = await sb.from('poll_votes').select('player_id, option_id').eq('poll_id', poll.id);
		votes = data ?? [];
	}

	function countsFor(optId) {
		return votes.filter(v => v.option_id === optId).length;
	}
	function pctFor(optId) {
		if (!totalVoters) return 0;
		return Math.round((countsFor(optId) / totalVoters) * 100);
	}

	async function vote(opt) {
		if (closed || !$playerId) return;
		if (myVotes.includes(opt.id)) {
			await sb.from('poll_votes').delete()
				.eq('poll_id', poll.id).eq('option_id', opt.id).eq('player_id', $playerId);
			triggerToast('Stimme zurückgezogen');
		} else {
			if (!poll.multi_select) {
				await sb.from('poll_votes').delete().eq('poll_id', poll.id).eq('player_id', $playerId);
			}
			await sb.from('poll_votes').insert({
				poll_id: poll.id, option_id: opt.id, player_id: $playerId,
			});
			triggerToast(`Abgestimmt: ${opt.label}`);
		}
		await loadVotes();
		onVoted?.();
	}

	async function shareResults() {
		const lines = options.map(o => `${o.label}: ${pctFor(o.id)}%`).join('\n');
		const text = `${poll.question}\n\n${lines}\n(${totalVoters} Stimmen)`;
		if (navigator.share) {
			try { await navigator.share({ title: poll.question, text }); } catch {}
		} else {
			await navigator.clipboard.writeText(text);
			triggerToast('Ergebnis kopiert');
		}
	}

	const contextActions = [
		{ label: 'Ergebnisse teilen', icon: 'share', fn: shareResults },
	];

	onMount(loadVotes);
</script>

<ContextMenu actions={contextActions}>
	<div class="pcard">

		<!-- Header -->
		<div class="pcard-head">
			<div class="pcard-badge">
				<span class="material-symbols-outlined">ballot</span>
				<span>Umfrage{poll.multi_select ? ' · Multi' : ''}</span>
			</div>
			{#if closed}
				<span class="pcard-closed-tag">beendet</span>
			{/if}
		</div>

		<h4 class="pcard-q">{poll.question}</h4>

		<!-- Options -->
		<ul class="popts">
			{#each options as o}
				{@const pct = pctFor(o.id)}
				{@const mine = myVotes.includes(o.id)}
				<li>
					<button
						class="popt"
						class:popt--mine={mine}
						class:popt--leading={pct === Math.max(...options.map(x => pctFor(x.id))) && pct > 0}
						disabled={closed}
						onclick={() => vote(o)}
					>
						<span
							class="popt-bar"
							style="width: {pct}%; transition: width 600ms cubic-bezier(0.34, 1.1, 0.64, 1);"
						></span>
						<span class="popt-left">
							{#if mine}
								<span class="popt-check material-symbols-outlined">check_circle</span>
							{/if}
							<span class="popt-label">{o.label}</span>
						</span>
						<span class="popt-pct">{pct}%</span>
					</button>
				</li>
			{/each}
		</ul>

		<!-- Footer -->
		<div class="pcard-foot">
			<span class="material-symbols-outlined">group</span>
			<span>{totalVoters} Stimme{totalVoters === 1 ? '' : 'n'}</span>
			{#if poll.deadline}
				<span class="pcard-sep">·</span>
				<span>bis {new Date(poll.deadline).toLocaleString('de-AT', { dateStyle: 'short', timeStyle: 'short' })}</span>
			{/if}
		</div>

	</div>
</ContextMenu>

<style>
	.pcard {
		background: var(--color-surface, #fff);
		border-radius: 18px;
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: 10px;
		box-shadow: 0 2px 12px rgba(0,0,0,0.07), 0 0 0 1px rgba(0,0,0,0.04);
		width: 100%;
	}

	/* Header row */
	.pcard-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.pcard-badge {
		display: flex;
		gap: 5px;
		align-items: center;
		font-size: 0.70rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: var(--color-secondary, #D4AF37);
		text-transform: uppercase;
	}
	.pcard-badge .material-symbols-outlined { font-size: 0.95rem; }
	.pcard-closed-tag {
		font-size: 0.66rem;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--color-text-soft, #888);
		background: rgba(0,0,0,0.06);
		padding: 2px 8px;
		border-radius: 999px;
	}

	/* Question */
	.pcard-q {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-text, #1a1a1a);
		line-height: 1.3;
	}

	/* Options list */
	.popts {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	/* Option button */
	.popt {
		position: relative;
		display: flex;
		justify-content: space-between;
		align-items: center;
		width: 100%;
		padding: 10px 12px;
		border: 1.5px solid var(--color-border, #eee);
		background: #fafafa;
		border-radius: 10px;
		cursor: pointer;
		text-align: left;
		overflow: hidden;
		font-size: 0.87rem;
		transition: border-color 200ms ease, background 200ms ease;
	}
	.popt:disabled { cursor: default; }
	.popt:not(:disabled):active { transform: scale(0.98); }

	.popt-bar {
		position: absolute;
		left: 0; top: 0; bottom: 0;
		background: rgba(204,0,0,0.08);
		border-radius: 8px 0 0 8px;
		z-index: 0;
	}
	.popt--mine .popt-bar { background: rgba(212,175,55,0.18); }
	.popt--leading:not(.popt--mine) .popt-bar { background: rgba(204,0,0,0.13); }

	.popt--mine {
		border-color: var(--color-secondary, #D4AF37);
		background: rgba(212,175,55,0.04);
	}

	.popt-left {
		position: relative;
		z-index: 1;
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.popt-check {
		font-size: 1rem;
		color: var(--color-secondary, #D4AF37);
	}
	.popt-label {
		font-weight: 500;
		color: var(--color-text, #1a1a1a);
	}
	.popt-pct {
		position: relative;
		z-index: 1;
		font-size: 0.80rem;
		font-weight: 700;
		color: var(--color-text-soft, #666);
		min-width: 32px;
		text-align: right;
	}
	.popt--mine .popt-pct { color: var(--color-secondary, #D4AF37); }

	/* Footer */
	.pcard-foot {
		display: flex;
		align-items: center;
		gap: 5px;
		font-size: 0.72rem;
		color: var(--color-text-soft, #999);
	}
	.pcard-foot .material-symbols-outlined { font-size: 0.90rem; }
	.pcard-sep { opacity: 0.5; }
</style>
