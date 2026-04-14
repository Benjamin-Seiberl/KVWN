<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';

	let { match, supporters = [], onChanged } = $props();

	const iAmIn = $derived(supporters.some(s => s.player_id === $playerId));
	let busy = $state(false);

	async function toggle() {
		if (!$playerId || busy) return;
		busy = true;
		if (iAmIn) {
			await sb
				.from('match_supporters')
				.delete()
				.eq('match_id', match.id)
				.eq('player_id', $playerId);
		} else {
			await sb
				.from('match_supporters')
				.insert({ match_id: match.id, player_id: $playerId });
		}
		await onChanged?.();
		busy = false;
	}
</script>

<section class="mw-card" style="border: 2px solid var(--color-primary);">
	<div class="mw-card__head">
		<div>
			<h3 class="mw-card__title">
				<span class="material-symbols-outlined" style="color: var(--color-secondary);">groups</span>
				Zuschauer-Support
			</h3>
			<p class="mw-card__subtitle">Seid dabei und feuert uns an!</p>
		</div>
		<div style="display:flex; flex-direction:column; align-items:flex-end;">
			<span class="mw-supporters__count">{supporters.length}</span>
			<span class="mw-supporters__label">Zusagen</span>
		</div>
	</div>

	<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={toggle} disabled={busy || !$playerId}>
		<span class="material-symbols-outlined">{iAmIn ? 'heart_minus' : 'favorite'}</span>
		{iAmIn ? 'Doch nicht dabei' : 'Ich bin dabei!'}
	</button>
</section>
