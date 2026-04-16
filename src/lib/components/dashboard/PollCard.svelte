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
		<div class="pcard-meta">
			<span class="material-symbols-outlined">ballot</span>
			<span>Umfrage{poll.multi_select ? ' · Multi' : ''}{closed ? ' · beendet' : ''}</span>
		</div>
		<h4 class="pcard-q">{poll.question}</h4>
		<ul class="popts">
			{#each options as o}
				{@const pct = pctFor(o.id)}
				{@const mine = myVotes.includes(o.id)}
				<li>
					<button
						class="popt"
						class:popt--mine={mine}
						disabled={closed}
						onclick={() => vote(o)}
					>
						<span class="popt-bar" style="width: {pct}%"></span>
						<span class="popt-label">
							{#if mine}<span class="material-symbols-outlined popt-check">check_circle</span>{/if}
							{o.label}
						</span>
						<span class="popt-pct">{pct}%</span>
					</button>
				</li>
			{/each}
		</ul>
		<p class="pcard-foot">{totalVoters} Stimme{totalVoters === 1 ? '' : 'n'}{poll.deadline ? ' · bis ' + new Date(poll.deadline).toLocaleString('de-AT', { dateStyle: 'short', timeStyle: 'short' }) : ''}</p>
	</div>
</ContextMenu>

<style>
	.pcard {
		border: 1px solid var(--color-border, #eee);
		background: linear-gradient(135deg, #fff, #fffaf0);
		border-radius: 14px;
		padding: var(--space-3);
		display: flex; flex-direction: column; gap: 6px;
		box-shadow: 0 1px 4px rgba(0,0,0,0.04);
		width: 100%;
	}
	.pcard-meta { display: flex; gap: 4px; align-items: center; font-size: 0.72rem; color: var(--color-secondary, #D4AF37); font-weight: 600; }
	.pcard-meta :global(.material-symbols-outlined) { font-size: 0.95rem; }
	.pcard-q { margin: 0; font-family: 'Lexend'; font-weight: 600; font-size: 0.95rem; }
	.popts { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 4px; }
	.popt {
		position: relative;
		display: flex; justify-content: space-between; align-items: center;
		width: 100%; padding: 8px 12px;
		border: 1px solid var(--color-border, #eee);
		background: #fff;
		border-radius: 8px;
		cursor: pointer;
		text-align: left;
		overflow: hidden;
		font-size: 0.85rem;
	}
	.popt:disabled { cursor: default; }
	.popt-bar {
		position: absolute; left: 0; top: 0; bottom: 0;
		background: rgba(204,0,0,0.1);
		transition: width 0.3s;
		z-index: 0;
	}
	.popt--mine .popt-bar { background: rgba(212,175,55,0.2); }
	.popt-label, .popt-pct { position: relative; z-index: 1; }
	.popt-label { display: inline-flex; gap: 4px; align-items: center; }
	.popt-check { font-size: 1rem; color: var(--color-secondary, #D4AF37); }
	.popt-pct { font-weight: 600; color: var(--color-text-soft, #666); }
	.popt--mine { border-color: var(--color-secondary, #D4AF37); }
	.pcard-foot { font-size: 0.72rem; color: var(--color-text-soft, #888); margin: 0; }
</style>
