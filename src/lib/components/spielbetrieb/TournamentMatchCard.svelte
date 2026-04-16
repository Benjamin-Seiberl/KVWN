<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerRole } from '$lib/stores/auth';

	let { match } = $props();

	let rounds = $state([]);       // tournament_rounds
	let assignments = $state([]);  // tournament_round_players
	let players = $state([]);
	const isAdmin = $derived($playerRole === 'kapitaen');

	// Neuer Durchgang Form
	let newTime = $state('');
	let newLanes = $state(4);

	async function load() {
		const [{ data: r }, { data: p }] = await Promise.all([
			sb.from('tournament_rounds').select('*').eq('match_id', match.id).order('round_number'),
			sb.from('players').select('id, name, avatar_url, photo').eq('active', true).order('name'),
		]);
		rounds = r ?? [];
		players = p ?? [];
		if (rounds.length) {
			const { data: a } = await sb
				.from('tournament_round_players')
				.select('*')
				.in('round_id', rounds.map(x => x.id));
			assignments = a ?? [];
		}
	}

	async function addRound() {
		if (!newTime) return;
		const nextNum = (rounds.at(-1)?.round_number ?? 0) + 1;
		await sb.from('tournament_rounds').insert({
			match_id: match.id,
			round_number: nextNum,
			start_time: newTime,
			lane_count: newLanes,
		});
		newTime = '';
		load();
	}

	async function removeRound(r) {
		if (!confirm(`Durchgang ${r.round_number} löschen?`)) return;
		await sb.from('tournament_rounds').delete().eq('id', r.id);
		load();
	}

	function assignmentFor(roundId, lane) {
		return assignments.find(a => a.round_id === roundId && a.lane_number === lane);
	}

	async function setLane(round, lane, playerId) {
		const existing = assignmentFor(round.id, lane);
		if (existing && playerId === existing.player_id) return;
		if (playerId === null) {
			await sb.from('tournament_round_players').delete()
				.eq('round_id', round.id).eq('lane_number', lane);
		} else if (existing) {
			await sb.from('tournament_round_players').update({ player_id: playerId })
				.eq('round_id', round.id).eq('lane_number', lane);
		} else {
			await sb.from('tournament_round_players').insert({
				round_id: round.id, lane_number: lane, player_id: playerId,
			});
		}
		load();
	}

	async function updateScore(assign, score) {
		const n = Number(score);
		if (!Number.isFinite(n)) return;
		await sb.from('tournament_round_players').update({ score: n })
			.eq('round_id', assign.round_id).eq('lane_number', assign.lane_number);
		load();
	}

	function getPlayer(id) { return players.find(p => p.id === id); }

	onMount(load);
</script>

<section class="tcard">
	<header class="tcard-head">
		<h3>
			<span class="material-symbols-outlined">emoji_events</span>
			{match.tournament_title || 'Turnier'}
		</h3>
		{#if match.tournament_location}<p class="tcard-loc">{match.tournament_location}</p>{/if}
	</header>

	{#each rounds as r}
		<div class="round">
			<div class="round-head">
				<strong>Durchgang {r.round_number}</strong>
				<span class="round-time">{String(r.start_time).slice(0,5)} · {r.lane_count} Bahnen</span>
				{#if isAdmin}
					<button class="mini-del" onclick={() => removeRound(r)} aria-label="Durchgang entfernen">
						<span class="material-symbols-outlined">close</span>
					</button>
				{/if}
			</div>
			<div class="lanes">
				{#each Array(r.lane_count) as _, i}
					{@const lane = i + 1}
					{@const a = assignmentFor(r.id, lane)}
					{@const pl = a ? getPlayer(a.player_id) : null}
					<div class="lane-slot">
						<span class="lane-label">Bahn {lane}</span>
						<select
							class="lane-sel"
							disabled={!isAdmin}
							value={a?.player_id ?? ''}
							onchange={(e) => setLane(r, lane, e.target.value || null)}
						>
							<option value="">—</option>
							{#each players as p}
								<option value={p.id}>{p.name}</option>
							{/each}
						</select>
						{#if a}
							<input
								class="lane-score"
								type="number"
								min="0"
								max="999"
								inputmode="numeric"
								placeholder="Holz"
								value={a.score ?? ''}
								onblur={(e) => updateScore(a, e.target.value)}
							/>
						{/if}
					</div>
				{/each}
			</div>
		</div>
	{/each}

	{#if isAdmin}
		<div class="add-round">
			<strong>Durchgang hinzufügen</strong>
			<div class="row">
				<input type="time" bind:value={newTime} />
				<select bind:value={newLanes}>
					<option value={4}>4 Bahnen</option>
					<option value={6}>6 Bahnen</option>
					<option value={8}>8 Bahnen</option>
				</select>
				<button class="btn" onclick={addRound} disabled={!newTime}>
					<span class="material-symbols-outlined">add</span>
				</button>
			</div>
		</div>
	{/if}
</section>

<style>
	.tcard { background: linear-gradient(145deg, #fffaf0, #fff); border: 1px solid rgba(212,175,55,0.4); border-radius: 16px; padding: var(--space-4); margin-top: var(--space-3); box-shadow: 0 4px 16px rgba(212,175,55,0.12); }
	.tcard-head h3 { display: flex; gap: 6px; align-items: center; margin: 0; font-family: 'Lexend'; font-weight: 700; font-size: 1.05rem; color: var(--color-secondary, #D4AF37); }
	.tcard-loc { margin: 2px 0 var(--space-3); color: var(--color-text-soft, #888); font-size: 0.85rem; }
	.round { padding: var(--space-3) 0; border-top: 1px dashed rgba(212,175,55,0.3); }
	.round:first-of-type { border-top: 0; }
	.round-head { display: flex; align-items: center; gap: 8px; margin-bottom: var(--space-2); }
	.round-time { color: var(--color-text-soft, #888); font-size: 0.85rem; }
	.mini-del { margin-left: auto; background: none; border: 0; color: var(--color-primary, #CC0000); cursor: pointer; }
	.lanes { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 6px; }
	.lane-slot { display: flex; flex-direction: column; gap: 2px; padding: 8px; background: #fff; border: 1px solid var(--color-border, #eee); border-radius: 10px; }
	.lane-label { font-size: 0.72rem; text-transform: uppercase; color: var(--color-text-soft, #888); font-weight: 600; }
	.lane-sel { padding: 4px 6px; font-size: 14px; border: 1px solid var(--color-border, #ddd); border-radius: 6px; }
	.lane-score { padding: 4px 6px; font-size: 16px; border: 1px solid var(--color-border, #ddd); border-radius: 6px; text-align: right; }
	.add-round { margin-top: var(--space-3); padding-top: var(--space-3); border-top: 1px dashed rgba(212,175,55,0.3); }
	.add-round .row { display: flex; gap: 6px; margin-top: 6px; }
	.row input, .row select { flex: 1; padding: 8px; border: 1px solid var(--color-border, #ddd); border-radius: 8px; font-size: 16px; }
	.btn { padding: 8px 12px; background: var(--color-secondary, #D4AF37); color: #fff; border: 0; border-radius: 999px; cursor: pointer; }
</style>
