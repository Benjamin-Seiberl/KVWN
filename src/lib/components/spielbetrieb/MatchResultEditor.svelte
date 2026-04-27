<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate } from '$lib/utils/dates.js';
	import ScoreInputRow from '$lib/components/spielbetrieb/ScoreInputRow.svelte';

	let { gamePlanId, match, initialMode = 'gesamt', initialPublishedAt = null, players = [], onPublished } = $props();

	let mode         = $state(initialMode || 'gesamt');
	let publishedAt  = $state(initialPublishedAt);
	let publishing   = $state(false);
	let feedbackSending = $state(false);

	// Client-side caches keyed by game_plan_player_id
	let scores         = $state({});  // playerId → number | null
	let lanesByPlayer  = $state({});  // playerId → [{ bahn, volle, abraeumen }]
	let playedById     = $state({});  // playerId → boolean (false = DNF / nicht gespielt)
	let loaded         = $state(false);

	async function loadLanes() {
		const ids = players.map(p => p.id);
		const initialScores = {};
		const initialPlayed = {};
		for (const p of players) {
			initialScores[p.id] = p.score ?? null;
			// played === false → DNF aktiv. null/true → spielt (Default true).
			initialPlayed[p.id] = p.played === false ? false : true;
		}
		scores     = initialScores;
		playedById = initialPlayed;

		if (!ids.length) { loaded = true; return; }
		const { data, error } = await sb
			.from('game_plan_player_lanes')
			.select('game_plan_player_id, bahn, volle, abraeumen')
			.in('game_plan_player_id', ids);
		if (error) {
			triggerToast('Fehler: ' + error.message);
			loaded = true;
			return;
		}
		const map = {};
		for (const row of data ?? []) {
			(map[row.game_plan_player_id] ??= []).push({
				bahn: row.bahn, volle: row.volle, abraeumen: row.abraeumen,
			});
		}
		lanesByPlayer = map;
		loaded = true;
	}

	onMount(loadLanes);

	async function setMode(newMode) {
		if (newMode === mode) return;
		mode = newMode;
		const { error } = await sb
			.from('game_plans')
			.update({ result_mode: newMode })
			.eq('id', gamePlanId);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
	}

	// ── Per-row debounced commit (vom ScoreInputRow nach 500ms Inaktivität) ──
	async function handleRowChange(playerId, snap) {
		if (playedById[playerId] === false) return; // DNF — keine Score-Edits

		if (snap.mode === 'gesamt') {
			const score = snap.score;
			scores = { ...scores, [playerId]: score };
			const { error } = await sb.from('game_plan_players').update({
				score,
				result_state: publishedAt ? 'published' : (score != null ? 'draft' : 'empty'),
				played: score != null,
			}).eq('id', playerId);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			return;
		}

		// detailliert: alle 4 Bahnen upserten + score sum aktualisieren
		const lanes = snap.lanes ?? [];
		// Cache aktualisieren
		lanesByPlayer = { ...lanesByPlayer, [playerId]: lanes };

		// Pro Bahn upsert
		for (const l of lanes) {
			const { error: laneErr } = await sb.from('game_plan_player_lanes').upsert(
				{
					game_plan_player_id: playerId,
					bahn:                l.bahn,
					volle:               l.volle ?? null,
					abraeumen:           l.abraeumen ?? null,
				},
				{ onConflict: 'game_plan_player_id,bahn' },
			);
			if (laneErr) { triggerToast('Fehler: ' + laneErr.message); return; }
		}

		// Sum berechnen
		let sum = 0;
		let any = false;
		for (const l of lanes) {
			if (Number.isFinite(Number(l.volle)))     { sum += Number(l.volle);     any = true; }
			if (Number.isFinite(Number(l.abraeumen))) { sum += Number(l.abraeumen); any = true; }
		}
		const newScore = any ? sum : null;
		scores = { ...scores, [playerId]: newScore };

		const { error: gppErr } = await sb.from('game_plan_players').update({
			score: newScore,
			result_state: publishedAt ? 'published' : (newScore != null ? 'draft' : 'empty'),
			played: newScore != null,
		}).eq('id', playerId);
		if (gppErr) { triggerToast('Fehler: ' + gppErr.message); return; }
	}

	// ── DNF-Toggle ────────────────────────────────────────────────────────────
	async function handlePlayedChange(playerId, played) {
		playedById = { ...playedById, [playerId]: played };
		if (played === false) {
			// DNF: score=0, played=false. Lane-Rows bleiben in DB, sind aber irrelevant.
			scores = { ...scores, [playerId]: 0 };
			const { error } = await sb.from('game_plan_players').update({
				score: 0,
				played: false,
				result_state: publishedAt ? 'published' : 'draft',
			}).eq('id', playerId);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
		} else {
			// Re-aktivieren: score=null, played=true zurücksetzen, Eingabe wieder offen.
			// (Existierende Code-Pfade nutzen `played: score != null` als Boolean — null vermeiden.)
			scores = { ...scores, [playerId]: null };
			const { error } = await sb.from('game_plan_players').update({
				score: null,
				played: true,
				result_state: publishedAt ? 'published' : 'empty',
			}).eq('id', playerId);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
		}
	}

	// "ready for publish": entweder score gesetzt ODER DNF aktiv
	const allHaveScore = $derived(
		players.length > 0 && players.every(p => playedById[p.id] === false || scores[p.id] != null)
	);

	async function publish() {
		if (publishing) return;
		publishing = true;
		try {
			const now = new Date().toISOString();
			for (const p of players) {
				const isDnf = playedById[p.id] === false;
				if (isDnf) {
					const { error } = await sb.from('game_plan_players').update({
						result_state: 'published',
						published_at: now,
						played: false,
						score:  0,
					}).eq('id', p.id);
					if (error) { triggerToast('Fehler: ' + error.message); return; }
				} else if (scores[p.id] != null) {
					const { error } = await sb.from('game_plan_players').update({
						result_state: 'published',
						published_at: now,
						played: true,
					}).eq('id', p.id);
					if (error) { triggerToast('Fehler: ' + error.message); return; }
				}
			}
			const { error: gpErr } = await sb.from('game_plans').update({
				result_published_at: now,
				result_mode: mode,
			}).eq('id', gamePlanId);
			if (gpErr) { triggerToast('Fehler: ' + gpErr.message); return; }
			publishedAt = now;
			triggerToast('Ergebnis veröffentlicht');
			onPublished?.();
		} finally {
			publishing = false;
		}
	}

	async function requestFeedback() {
		if (feedbackSending) return;
		feedbackSending = true;
		try {
			const { data: entries, error } = await sb
				.from('game_plan_players')
				.select('player_id')
				.eq('game_plan_id', gamePlanId)
				.eq('played', true);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			const player_ids = (entries ?? []).map(e => e.player_id).filter(Boolean);
			if (!player_ids.length) { triggerToast('Keine Empfänger gefunden'); return; }
			const feedbackUrl = match?.id ? `/spielbetrieb?feedback=${match.id}` : '/spielbetrieb';
			await fetch('/api/push/notify', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					player_ids,
					title: 'Kurzes Feedback',
					body: `${match?.opponent ?? 'Spiel'} – eine Frage zum Spiel`,
					url: feedbackUrl,
					pref_key: 'feedback',
				}),
			});
			triggerToast('Feedback-Anfrage gesendet');
		} finally {
			feedbackSending = false;
		}
	}
</script>

<section class="mre">
	<header class="mre-head">
		<div class="mre-title-row">
			<span class="material-symbols-outlined mre-icon">sports_score</span>
			<h3 class="mre-title">Ergebnis erfassen</h3>
		</div>

		{#if publishedAt}
			<span class="mre-chip mre-chip--pub">
				<span class="material-symbols-outlined">check_circle</span>
				Veröffentlicht am {fmtDate(publishedAt.slice(0, 10))}
			</span>
		{:else}
			<span class="mre-chip mre-chip--draft">
				<span class="material-symbols-outlined">edit_note</span>
				Entwurf
			</span>
		{/if}
	</header>

	<!-- Mode toggle -->
	<div class="mre-toggle" role="tablist" aria-label="Erfassungs-Modus">
		<button
			class="mre-toggle-btn"
			class:mre-toggle-btn--active={mode === 'gesamt'}
			onclick={() => setMode('gesamt')}
			role="tab"
			aria-selected={mode === 'gesamt'}
		>
			Gesamt
		</button>
		<button
			class="mre-toggle-btn"
			class:mre-toggle-btn--active={mode === 'detailliert'}
			onclick={() => setMode('detailliert')}
			role="tab"
			aria-selected={mode === 'detailliert'}
		>
			Pro Bahn
		</button>
	</div>

	{#if !loaded}
		<div class="mre-loading shimmer-box"></div>
	{:else if players.length === 0}
		<p class="mre-empty">Keine Aufstellung vorhanden.</p>
	{:else}
		<div class="mre-rows">
			{#each players as p}
				<ScoreInputRow
					player={p}
					mode={mode}
					lanes={lanesByPlayer[p.id] ?? []}
					score={scores[p.id] ?? null}
					played={playedById[p.id] !== false}
					published={!!publishedAt}
					onRowChange={handleRowChange}
					onPlayedChange={handlePlayedChange}
				/>
			{/each}
		</div>

		<div class="mre-actions">
			{#if !publishedAt}
				<button
					class="mw-btn mw-btn--primary mw-btn--wide"
					onclick={publish}
					disabled={!allHaveScore || publishing}
				>
					<span class="material-symbols-outlined">publish</span>
					{publishing ? 'Wird veröffentlicht…' : 'Ergebnis veröffentlichen'}
				</button>
				{#if !allHaveScore}
					<p class="mre-hint">Alle Holz-Werte eintragen oder „Nicht gespielt" markieren, um zu veröffentlichen.</p>
				{/if}
			{:else}
				<button
					class="mw-btn mw-btn--ghost mw-btn--wide"
					onclick={requestFeedback}
					disabled={feedbackSending}
				>
					<span class="material-symbols-outlined">rate_review</span>
					{feedbackSending ? 'Wird gesendet…' : 'Feedback-Anfrage senden'}
				</button>
				<p class="mre-hint">Änderungen werden automatisch gespeichert.</p>
			{/if}
		</div>
	{/if}
</section>

<style>
	.mre {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding: var(--space-4);
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
	}
	.mre-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-2);
		flex-wrap: wrap;
	}
	.mre-title-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.mre-icon {
		color: var(--color-primary);
		font-size: 1.2rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.mre-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
	}
	.mre-chip {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-size: var(--text-label-sm);
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
	}
	.mre-chip .material-symbols-outlined {
		font-size: 0.9rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.mre-chip--draft {
		background: color-mix(in srgb, var(--color-outline-variant) 60%, transparent);
		color: var(--color-on-surface-variant);
	}
	.mre-chip--pub {
		background: color-mix(in srgb, var(--color-secondary) 18%, transparent);
		color: color-mix(in srgb, var(--color-secondary) 65%, var(--color-on-surface));
	}

	.mre-toggle {
		display: inline-flex;
		align-self: flex-start;
		padding: 3px;
		background: var(--color-surface-container);
		border: 1px solid var(--color-outline-variant);
		border-radius: 999px;
	}
	.mre-toggle-btn {
		padding: 6px 14px;
		background: none;
		border: none;
		border-radius: 999px;
		font-family: inherit;
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 120ms ease, color 120ms ease;
	}
	.mre-toggle-btn--active {
		background: var(--color-primary);
		color: #fff;
	}

	.mre-rows {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.mre-loading {
		height: 120px;
		border-radius: var(--radius-md);
	}
	.mre-empty {
		font-size: var(--text-label-md);
		color: var(--color-on-surface-variant);
		text-align: center;
		padding: var(--space-4);
		margin: 0;
	}

	.mre-actions {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.mre-hint {
		margin: 0;
		font-size: var(--text-label-sm);
		color: var(--color-outline);
		text-align: center;
	}
</style>
