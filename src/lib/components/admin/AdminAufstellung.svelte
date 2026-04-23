<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';
	import { toDateStr, fmtDate, daysUntil } from '$lib/utils/dates.js';
	import { imgPath } from '$lib/utils/players.js';
	import { classifyPlayer } from '$lib/utils/eligibility.js';

	const REASON_LABELS = {
		availability: 'Verfügbarkeit/Krankheit',
		tactical:     'Taktisch',
		form:         'Form',
		other:        'Sonstiges',
	};

	let { open = $bindable(false), preselectedMatchId = null } = $props();

	let matches        = $state([]);
	let loading        = $state(true);
	let selectedMatch  = $state(null);
	let loadingLineup  = $state(false);
	let gamePlan       = $state(null);   // full row incl. lineup_published_at
	let lineup         = $state([]);     // [{id, position, player_id, player_name, players}]
	let allPlayers     = $state([]);
	let rosters        = $state([]);     // [{player_id, position, team_id, league_tier, league_name}]
	let lineupsByRound = $state({});     // { [round_code]: [{team_id, league_tier, league_name, player_ids}] }
	let saving         = $state(false);
	let publishing     = $state(false);
	let starterCount   = $state(4);
	let absences       = $state([]);         // for current match date
	let playerStats    = $state({});         // player_id → { seasonAvg, form5 }

	// Swap sheet
	let swapOpen       = $state(false);
	let swapSlotIdx    = $state(null);       // index in lineup[]
	let swapSortMode   = $state('form5');    // 'form5' | 'seasonAvg'
	let swapReasonCode = $state(null);
	let swapReasonText = $state('');
	let swapSaving     = $state(false);

	const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	async function loadMatches() {
		loading = true;
		const now = new Date();
		const until = new Date(now);
		until.setDate(now.getDate() + 21);

		const { data, error } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, round_code, league_id, leagues(name, tier)')
			.gte('date', toDateStr(now))
			.lte('date', toDateStr(until))
			.order('date')
			.order('time');

		if (error) triggerToast('Fehler: ' + error.message);
		matches = data ?? [];
		loading = false;
	}

	function matchLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return `${DAY_SHORT[d.getDay()]} ${d.getDate()}.${d.getMonth() + 1}. – ${m.opponent}`;
	}

	function matchSub(m) {
		return `${m.leagues?.name ?? ''} · ${m.home_away === 'HEIM' ? 'Heim' : 'Auswärts'}`;
	}

	async function selectMatch(m) {
		selectedMatch = m;
		loadingLineup = true;
		starterCount = /bundesliga|landesliga/i.test(m.leagues?.name ?? '') ? 6 : 4;

		// Alle aktiven Spieler laden
		const { data: pl } = await sb
			.from('players')
			.select('id, name, photo')
			.eq('active', true)
			.order('name');
		allPlayers = pl ?? [];

		// Abwesenheiten am Match-Tag laden
		const { data: absenceRows } = await sb
			.from('absences')
			.select('player_id, from_date, to_date, reason')
			.lte('from_date', m.date)
			.gte('to_date',   m.date);
		absences = absenceRows ?? [];

		// Scores laden (Form-Trend + Saison-Schnitt für Swap-Pool)
		const { data: scoreRows } = await sb
			.from('game_plan_players')
			.select('player_id, score, game_plans!inner(matches!inner(date))')
			.eq('played', true)
			.not('score', 'is', null);
		const byPlayer = {};
		for (const row of scoreRows ?? []) {
			if (!row.player_id || row.score == null) continue;
			const date = row.game_plans?.matches?.date;
			if (!date) continue;
			(byPlayer[row.player_id] ??= []).push({ score: Number(row.score), date });
		}
		const stats = {};
		for (const [pid, arr] of Object.entries(byPlayer)) {
			const sorted = arr.sort((a, b) => b.date.localeCompare(a.date));
			const all   = sorted.map(x => x.score);
			const last5 = all.slice(0, 5);
			stats[pid] = {
				seasonAvg: all.length   ? Math.round(all.reduce((a,b)=>a+b,0)   / all.length)   : null,
				form5:     last5.length ? Math.round(last5.reduce((a,b)=>a+b,0) / last5.length) : null,
			};
		}
		playerStats = stats;

		// Nennlisten laden (für Positions-Sperrung)
		const { data: rData } = await sb
			.from('team_rosters')
			.select('player_id, position, league_id, leagues(name, tier)');
		rosters = (rData ?? []).map(r => ({
			player_id:   r.player_id,
			position:    r.position,
			team_id:     r.league_id,
			league_tier: r.leagues?.tier ?? 99,
			league_name: r.leagues?.name ?? '',
		}));

		// Rundencode-Konflikte laden (alle Aufstellungen derselben Runde, rundenbasiert!)
		lineupsByRound = {};
		if (m.round_code) {
			const { data: rdData } = await sb
				.from('game_plans')
				.select('league_id, round_code, leagues(name, tier), game_plan_players(player_id)')
				.eq('round_code', m.round_code);

			const byTeam = {};
			for (const gp of rdData ?? []) {
				const tid = gp.league_id;
				if (!byTeam[tid]) {
					byTeam[tid] = {
						team_id:     tid,
						league_tier: gp.leagues?.tier ?? 99,
						league_name: gp.leagues?.name ?? '',
						player_ids:  [],
					};
				}
				for (const gpp of gp.game_plan_players ?? []) {
					byTeam[tid].player_ids.push(gpp.player_id);
				}
			}
			lineupsByRound[m.round_code] = Object.values(byTeam);
		}

		// Bestehende Aufstellung laden
		const { data: gp } = await sb
			.from('game_plans')
			.select('id, cal_week, league_id, round_code, lineup_published_at, confirmation_deadline, game_plan_players(id, position, player_id, player_name, players!game_plan_players_player_id_fkey(name, photo))')
			.eq('cal_week', m.cal_week)
			.eq('league_id', m.league_id)
			.maybeSingle();

		gamePlan = gp ?? null;
		lineup = (gp?.game_plan_players ?? []).sort((a, b) => (a.position ?? 99) - (b.position ?? 99));
		loadingLineup = false;
	}

	// Pool-Spieler mit Eligibility-Klassifikation
	let classifiedPool = $derived.by(() => {
		if (!selectedMatch) return [];
		const usedIds = new Set(lineup.map(l => l.player_id));
		const matchCtx = {
			team_id:     selectedMatch.league_id,
			league_tier: selectedMatch.leagues?.tier ?? 99,
			round_code:  selectedMatch.round_code ?? null,
			date:        selectedMatch.date,
		};
		return allPlayers
			.filter(p => !usedIds.has(p.id))
			.map(p => ({ player: p, ...classifyPlayer({ player: p, match: matchCtx, rosters, lineupsByRound, absences }) }));
	});

	let eligiblePool   = $derived(classifiedPool.filter(c => c.eligible));
	let ineligiblePool = $derived(classifiedPool.filter(c => !c.eligible));

	async function addPlayer(player) {
		if (lineup.length >= starterCount || saving) return;
		saving = true;

		if (!gamePlan) {
			const { data: newGp, error } = await sb
				.from('game_plans')
				.insert({
					cal_week:   selectedMatch.cal_week,
					league_id:  selectedMatch.league_id,
					round_code: selectedMatch.round_code ?? null,
				})
				.select('id, cal_week, league_id, round_code, lineup_published_at, confirmation_deadline')
				.single();
			if (error) { triggerToast('Fehler: ' + error.message); saving = false; return; }
			gamePlan = { ...newGp, game_plan_players: [] };
		}

		const pos = lineup.length + 1;
		const { data: row, error } = await sb
			.from('game_plan_players')
			.insert({ game_plan_id: gamePlan.id, position: pos, player_id: player.id, player_name: player.name })
			.select('id, position, player_id, player_name')
			.single();

		if (error) { triggerToast('Fehler: ' + error.message); saving = false; return; }
		lineup = [...lineup, { ...row, players: player }];
		saving = false;
	}

	async function removePlayer(entry) {
		if (saving) return;
		saving = true;
		const { error } = await sb.from('game_plan_players').delete().eq('id', entry.id);
		if (error) { triggerToast('Fehler: ' + error.message); saving = false; return; }
		lineup = lineup.filter(l => l.id !== entry.id);
		for (let i = 0; i < lineup.length; i++) {
			if (lineup[i].position !== i + 1) {
				lineup[i] = { ...lineup[i], position: i + 1 };
				await sb.from('game_plan_players').update({ position: i + 1 }).eq('id', lineup[i].id);
			}
		}
		saving = false;
	}

	function nextSundayDate() {
		const d = new Date();
		const daysToSun = (7 - d.getDay()) % 7 || 7;
		d.setDate(d.getDate() + daysToSun);
		return toDateStr(d);
	}

	async function publishLineup() {
		if (!gamePlan || lineup.length < starterCount || publishing) return;
		publishing = true;

		const deadline = nextSundayDate();
		const publishedAt = new Date().toISOString();
		const { error } = await sb
			.from('game_plans')
			.update({ lineup_published_at: publishedAt, confirmation_deadline: deadline })
			.eq('id', gamePlan.id);

		if (error) { triggerToast('Fehler: ' + error.message); publishing = false; return; }
		gamePlan = { ...gamePlan, lineup_published_at: publishedAt, confirmation_deadline: deadline };

		const m = selectedMatch;
		const playerIds = lineup.map(l => l.player_id);
		try {
			const res = await fetch('/api/push/notify', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					player_ids: playerIds,
					title: 'Aufstellung veröffentlicht',
					body: `${m.leagues?.name} vs. ${m.opponent} – bitte bestätigen`,
					url: '/spielbetrieb',
				}),
			});
			const { sent = 0 } = await res.json();
			triggerToast(`Aufstellung veröffentlicht – ${sent} Spieler benachrichtigt`);
		} catch {
			triggerToast('Aufstellung veröffentlicht');
		}
		publishing = false;
	}

	let isPublished = $derived(!!gamePlan?.lineup_published_at);
	let canPublish  = $derived(!isPublished && lineup.length >= starterCount && !!gamePlan);
	let daysToMatch = $derived(selectedMatch?.date ? daysUntil(selectedMatch.date) : null);

	// ─── Swap sheet ────────────────────────────────────────────────────────
	function openSwapSheet(idx) {
		swapSlotIdx    = idx;
		swapSortMode   = 'form5';
		swapReasonCode = null;
		swapReasonText = '';
		swapOpen       = true;
	}

	let sortedSwapPool = $derived.by(() => {
		const key = swapSortMode;
		return [...classifiedPool].filter(c => c.eligible).sort((a, b) => {
			const va = playerStats[a.player.id]?.[key];
			const vb = playerStats[b.player.id]?.[key];
			if (va == null && vb == null) return 0;
			if (va == null) return 1;
			if (vb == null) return -1;
			return vb - va;
		});
	});

	async function doSwap(newPlayer) {
		if (swapSaving || swapSlotIdx == null || !swapReasonCode) return;
		if (swapReasonCode === 'other' && !swapReasonText.trim()) { triggerToast('Bitte Grund angeben'); return; }
		swapSaving = true;

		const old = lineup[swapSlotIdx];
		if (!old) { swapSaving = false; return; }

		const { error: delErr } = await sb.from('game_plan_players').delete().eq('id', old.id);
		if (delErr) { triggerToast('Fehler: ' + delErr.message); swapSaving = false; return; }

		const { data: newRow, error: insErr } = await sb
			.from('game_plan_players')
			.insert({
				game_plan_id:        gamePlan.id,
				position:            old.position,
				player_id:           newPlayer.id,
				player_name:         newPlayer.name,
				replaced_from_id:    old.player_id,
				replaced_at:         new Date().toISOString(),
				replaced_reason_code: swapReasonCode,
				replaced_reason_text: swapReasonText.trim() || null,
			})
			.select('id, position, player_id, player_name')
			.single();
		if (insErr) { triggerToast('Fehler: ' + insErr.message); swapSaving = false; return; }

		lineup = lineup.map((l, i) => i === swapSlotIdx ? { ...newRow, players: newPlayer } : l);

		const reasonLabel = swapReasonCode === 'other' ? (swapReasonText.trim() || 'Sonstiges') : REASON_LABELS[swapReasonCode];
		const m = selectedMatch;

		try {
			await Promise.all([
				fetch('/api/push/notify', { method:'POST', headers:{'Content-Type':'application/json'},
					body: JSON.stringify({
						player_ids: [newPlayer.id],
						title: 'Du wurdest aufgestellt',
						body:  `${m.leagues?.name ?? ''} vs. ${m.opponent} – bitte bestätigen`,
						url:   '/#action-hub-lineup',
						pref_key: 'lineup',
					}),
				}),
				fetch('/api/push/notify', { method:'POST', headers:{'Content-Type':'application/json'},
					body: JSON.stringify({
						player_ids: [old.player_id],
						title: 'Aufstellungs-Änderung',
						body:  `Du wurdest aus Aufstellung gegen ${m.opponent} genommen — Grund: ${reasonLabel}`,
						url:   '/spielbetrieb',
						pref_key: 'lineup',
					}),
				}),
			]);
		} catch {}

		triggerToast('Spieler getauscht');
		swapOpen   = false;
		swapSaving = false;
	}

	function back() {
		selectedMatch  = null;
		lineup         = [];
		gamePlan       = null;
		lineupsByRound = {};
		rosters        = [];
	}

	$effect(() => {
		if (open) {
			loadMatches();
			back();
		}
	});

	$effect(() => {
		if (open && preselectedMatchId && !selectedMatch && matches.length > 0) {
			const m = matches.find(x => x.id === preselectedMatchId);
			if (m) selectMatch(m);
		}
	});
</script>

<BottomSheet bind:open title={selectedMatch ? 'Aufstellung bearbeiten' : 'Match wählen'}>

	{#if loading}
		<div class="aa-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
		</div>

	{:else if !selectedMatch}
		<!-- Match-Auswahl -->
		{#if matches.length === 0}
			<p class="aa-empty">Keine anstehenden Matches.</p>
		{:else}
			<p class="aa-hint">Wähle ein Match für die Aufstellung.</p>
			<div class="aa-match-list">
				{#each matches as m (m.id)}
					<button class="aa-match-row" onclick={() => selectMatch(m)}>
						<div class="aa-match-info">
							<span class="aa-match-label">{matchLabel(m)}</span>
							<span class="aa-match-sub">{matchSub(m)}</span>
						</div>
						{#if !m.round_code}
							<span class="aa-no-round" title="Rundencode fehlt">!</span>
						{/if}
						<span class="material-symbols-outlined aa-chevron">chevron_right</span>
					</button>
				{/each}
			</div>
		{/if}

	{:else}
		<!-- Zurück -->
		<button class="aa-back" onclick={back}>
			<span class="material-symbols-outlined">arrow_back</span>
			Zurück
		</button>

		<!-- Match-Info -->
		<div class="aa-match-hero">
			<span class="aa-match-hero-label">{matchLabel(selectedMatch)}</span>
			<span class="aa-match-hero-sub">
				{matchSub(selectedMatch)} · {starterCount} Starter
				{#if selectedMatch.round_code}
					· <span class="aa-round-pill">{selectedMatch.round_code}</span>
				{/if}
			</span>
		</div>

		{#if loadingLineup}
			<div class="aa-loading">
				<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			</div>
		{:else}
			<!-- Aufstellung -->
			<p class="aa-section-title">Aufstellung ({lineup.length}/{starterCount})</p>
			<div class="aa-lineup">
				{#each Array(starterCount) as _, i}
					{@const entry = lineup[i]}
					{#if entry}
						{@const name  = entry.players?.name ?? entry.player_name ?? '–'}
						{@const photo = entry.players?.photo ?? null}
						<button
							class="aa-slot aa-slot--filled"
							onclick={() => isPublished ? openSwapSheet(i) : removePlayer(entry)}
							disabled={saving}
						>
							<span class="aa-slot-pos">{i + 1}</span>
							<div class="aa-slot-avatar">
								<img src={imgPath(photo, name)} alt={name} onerror={(e) => { e.currentTarget.style.display = 'none'; }} />
								<span class="aa-slot-initial">{name.slice(0, 1)}</span>
							</div>
							<span class="aa-slot-name">{name}</span>
							<span class="material-symbols-outlined aa-slot-remove">
								{isPublished ? 'swap_horiz' : 'close'}
							</span>
						</button>
					{:else}
						<div class="aa-slot aa-slot--empty">
							<span class="aa-slot-pos">{i + 1}</span>
							<div class="aa-slot-avatar aa-slot-avatar--empty">
								<span class="material-symbols-outlined">person_add</span>
							</div>
							<span class="aa-slot-name aa-slot-name--empty">Offen</span>
						</div>
					{/if}
				{/each}
			</div>

			<!-- Publish-Status / Button -->
			{#if isPublished}
				<div class="aa-published-badge">
					<span class="material-symbols-outlined">check_circle</span>
					Veröffentlicht · Frist: {fmtDate(gamePlan.confirmation_deadline)}
				</div>
			{:else if gamePlan}
				{#if daysToMatch !== null && daysToMatch < 3 && daysToMatch >= 0}
					<div class="aa-publish-warn">
						<span class="material-symbols-outlined">warning</span>
						<div>
							<strong>Frist sehr kurz ({daysToMatch} {daysToMatch === 1 ? 'Tag' : 'Tage'})</strong>
							<span>Spieler haben wenig Zeit zu antworten.</span>
						</div>
					</div>
				{/if}
				<button
					class="mw-btn mw-btn--primary mw-btn--wide aa-publish-btn"
					onclick={publishLineup}
					disabled={!canPublish || publishing}
				>
					{#if publishing}
						<span class="material-symbols-outlined aa-spin">sync</span>
						Wird veröffentlicht…
					{:else}
						<span class="material-symbols-outlined">send</span>
						{lineup.length < starterCount ? `Noch ${starterCount - lineup.length} Slot(s) offen` : 'Aufstellung veröffentlichen'}
					{/if}
				</button>
			{/if}

			<!-- Verfügbare Spieler -->
			{#if !isPublished}
				<p class="aa-section-title" style="margin-top: var(--space-5);">
					Verfügbare Spieler ({eligiblePool.length})
				</p>
				<div class="aa-pool">
					{#each eligiblePool as { player } (player.id)}
						<button
							class="aa-pool-player"
							onclick={() => addPlayer(player)}
							disabled={saving || lineup.length >= starterCount}
						>
							<div class="aa-pool-avatar">
								<img src={imgPath(player.photo, player.name)} alt={player.name} onerror={(e) => { e.currentTarget.style.display = 'none'; }} />
								<span class="aa-pool-initial">{(player.name || '?').slice(0, 1)}</span>
							</div>
							<span class="aa-pool-name">{player.name}</span>
						</button>
					{/each}
				</div>

				{#if ineligiblePool.length > 0}
					<details class="aa-ineligible-section">
						<summary class="aa-section-title aa-section-title--warn">
							Nicht aufstellbar ({ineligiblePool.length})
						</summary>
						<div class="aa-pool aa-pool--ineligible">
							{#each ineligiblePool as { player, reason } (player.id)}
								<div class="aa-pool-player aa-pool-player--blocked" title={reason}>
									<div class="aa-pool-avatar">
										<img src={imgPath(player.photo, player.name)} alt={player.name} onerror={(e) => { e.currentTarget.style.display = 'none'; }} />
										<span class="aa-pool-initial">{(player.name || '?').slice(0, 1)}</span>
									</div>
									<div class="aa-pool-name-wrap">
										<span class="aa-pool-name">{player.name}</span>
										<span class="aa-pool-reason">{reason}</span>
									</div>
									<span class="material-symbols-outlined aa-blocked-icon">block</span>
								</div>
							{/each}
						</div>
					</details>
				{/if}
			{/if}
		{/if}
	{/if}

</BottomSheet>

<!-- Swap-Sheet: Spieler ersetzen (Post-Publish) -->
<BottomSheet bind:open={swapOpen} title="Spieler ersetzen">
	{#if swapSlotIdx !== null && lineup[swapSlotIdx]}
		{@const old = lineup[swapSlotIdx]}
		{@const oldName = old.players?.name ?? old.player_name ?? '–'}
		<p class="aa-swap-hint">
			<strong>Position {old.position}:</strong> {oldName} durch neuen Spieler ersetzen.
		</p>

		<!-- Grund (Pflicht) -->
		<p class="aa-section-title">Grund</p>
		<div class="aa-reason-chips">
			{#each [['availability','Verfügbarkeit'], ['tactical','Taktisch'], ['form','Form'], ['other','Sonstiges']] as [code, label]}
				<button
					type="button"
					class="aa-chip"
					class:aa-chip--active={swapReasonCode === code}
					onclick={() => swapReasonCode = code}
				>{label}</button>
			{/each}
		</div>
		{#if swapReasonCode === 'other'}
			<input
				class="aa-reason-input"
				type="text"
				bind:value={swapReasonText}
				placeholder="Grund angeben…"
				maxlength="120"
			/>
		{/if}

		<!-- Sortierung -->
		<div class="aa-swap-sort">
			<span class="aa-swap-sort-label">Sortierung</span>
			<div class="aa-swap-sort-toggle">
				<button
					type="button"
					class="aa-sort-btn"
					class:aa-sort-btn--active={swapSortMode === 'form5'}
					onclick={() => swapSortMode = 'form5'}
				>Form (letzte 5)</button>
				<button
					type="button"
					class="aa-sort-btn"
					class:aa-sort-btn--active={swapSortMode === 'seasonAvg'}
					onclick={() => swapSortMode = 'seasonAvg'}
				>Saison-∅</button>
			</div>
		</div>

		<!-- Pool -->
		<p class="aa-section-title">Verfügbar ({sortedSwapPool.length})</p>
		<div class="aa-swap-pool">
			{#each sortedSwapPool as { player } (player.id)}
				{@const st = playerStats[player.id] ?? {}}
				<button
					class="aa-swap-player"
					onclick={() => doSwap(player)}
					disabled={swapSaving || !swapReasonCode}
				>
					<div class="aa-pool-avatar">
						<img src={imgPath(player.photo, player.name)} alt={player.name} onerror={(e) => { e.currentTarget.style.display = 'none'; }} />
						<span class="aa-pool-initial">{(player.name || '?').slice(0, 1)}</span>
					</div>
					<div class="aa-swap-info">
						<span class="aa-swap-name">{player.name}</span>
						<span class="aa-swap-stats">
							∅ {st.seasonAvg ?? '–'} · F5 {st.form5 ?? '–'}
						</span>
					</div>
					<span class="material-symbols-outlined aa-swap-arrow">swap_horiz</span>
				</button>
			{/each}
			{#if sortedSwapPool.length === 0}
				<p class="aa-empty">Keine verfügbaren Spieler.</p>
			{/if}
		</div>
	{/if}
</BottomSheet>

<style>
	.aa-loading { display: flex; flex-direction: column; gap: var(--space-2); }
	.aa-empty, .aa-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-3);
	}

	/* Match list */
	.aa-match-list { display: flex; flex-direction: column; gap: var(--space-2); }
	.aa-match-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: none; cursor: pointer; text-align: left; width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-match-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
	.aa-match-label { font-weight: 600; font-size: var(--text-body-md); color: var(--color-on-surface); }
	.aa-match-sub   { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
	.aa-chevron     { font-size: 1.2rem; color: var(--color-outline); }
	.aa-no-round {
		width: 1.25rem; height: 1.25rem;
		background: #b45309; color: #fff;
		border-radius: 50%;
		font-size: 0.65rem; font-weight: 800;
		display: flex; align-items: center; justify-content: center;
		flex-shrink: 0;
	}

	/* Back */
	.aa-back {
		display: inline-flex; align-items: center; gap: var(--space-1);
		border: none; background: none;
		font-size: var(--text-body-sm); font-weight: 600;
		color: var(--color-primary); cursor: pointer; padding: 0;
		margin-bottom: var(--space-3);
		-webkit-tap-highlight-color: transparent;
	}
	.aa-back .material-symbols-outlined { font-size: 1.1rem; }

	/* Match hero */
	.aa-match-hero {
		display: flex; flex-direction: column; gap: 2px;
		margin-bottom: var(--space-4);
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--color-outline-variant);
	}
	.aa-match-hero-label {
		font-family: var(--font-display); font-weight: 700;
		font-size: var(--text-title-sm); color: var(--color-on-surface);
	}
	.aa-match-hero-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
	.aa-round-pill {
		display: inline-block;
		background: var(--color-primary-container, rgba(158,0,0,.12));
		color: var(--color-primary);
		border-radius: var(--radius-full);
		padding: 0 6px;
		font-size: 0.7rem; font-weight: 800; letter-spacing: 0.05em;
	}

	/* Section title */
	.aa-section-title {
		font-size: var(--text-label-sm); font-weight: 700;
		letter-spacing: 0.07em; text-transform: uppercase;
		color: var(--color-outline); margin: 0 0 var(--space-2);
		cursor: default;
	}
	.aa-section-title--warn { color: #b45309; cursor: pointer; }

	/* Lineup slots */
	.aa-lineup { display: flex; flex-direction: column; gap: var(--space-2); margin-bottom: var(--space-4); }
	.aa-slot {
		display: grid;
		grid-template-columns: 28px 36px 1fr 24px;
		gap: var(--space-2); align-items: center;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		border: 1.5px solid transparent;
	}
	.aa-slot--filled {
		background: var(--color-surface-container-low);
		border-color: var(--color-outline-variant);
		cursor: pointer; width: 100%; text-align: left;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-slot--filled:disabled { cursor: default; }
	.aa-slot--empty {
		background: var(--color-surface-container-low);
		border: 1.5px dashed var(--color-outline-variant);
		opacity: 0.55;
	}
	.aa-slot-pos { font-weight: 800; color: var(--color-primary); text-align: center; font-size: var(--text-body-sm); }
	.aa-slot-avatar {
		width: 36px; height: 36px; border-radius: 50%;
		overflow: hidden; background: var(--color-surface-container-highest);
		display: grid; place-items: center; position: relative;
	}
	.aa-slot-avatar img { width: 100%; height: 100%; object-fit: cover; position: absolute; inset: 0; }
	.aa-slot-initial { font-weight: 700; font-size: var(--text-body-sm); color: var(--color-outline); }
	.aa-slot-avatar--empty { background: none; }
	.aa-slot-avatar--empty .material-symbols-outlined { font-size: 1.3rem; color: var(--color-outline); }
	.aa-slot-name { font-weight: 600; font-size: var(--text-body-md); color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.aa-slot-name--empty { color: var(--color-outline); font-weight: 500; }
	.aa-slot-remove { font-size: 1rem; color: var(--color-outline); transition: color 0.15s; }
	.aa-slot--filled:active .aa-slot-remove { color: var(--color-primary); }

	/* Publish */
	.aa-publish-btn { margin-bottom: var(--space-4); }
	.aa-spin { animation: aa-spin 1s linear infinite; }
	@keyframes aa-spin { to { transform: rotate(360deg); } }

	.aa-published-badge {
		display: flex; align-items: center; gap: var(--space-2);
		padding: var(--space-3) var(--space-4);
		background: rgba(45, 122, 58, 0.12);
		border: 1px solid rgba(45, 122, 58, 0.3);
		border-radius: var(--radius-md);
		color: #2D7A3A;
		font-size: var(--text-body-sm); font-weight: 600;
		margin-bottom: var(--space-4);
	}
	.aa-published-badge .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	/* Player pool */
	.aa-pool {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
		gap: var(--space-2);
		margin-bottom: var(--space-4);
	}
	.aa-pool--ineligible { opacity: 0.75; margin-top: var(--space-2); }
	.aa-pool-player {
		display: flex; align-items: center; gap: var(--space-2);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-outline-variant);
		cursor: pointer; text-align: left;
		-webkit-tap-highlight-color: transparent;
		transition: background 0.15s;
	}
	.aa-pool-player:active { background: var(--color-surface-container); }
	.aa-pool-player:disabled { opacity: 0.4; pointer-events: none; }
	.aa-pool-player--blocked {
		cursor: default; pointer-events: none;
		border-color: rgba(180, 83, 9, 0.3);
		background: rgba(180, 83, 9, 0.06);
		grid-template-columns: 28px 1fr 20px;
		display: grid;
	}
	.aa-pool-avatar {
		width: 28px; height: 28px; border-radius: 50%;
		overflow: hidden; background: var(--color-surface-container-highest);
		display: grid; place-items: center; flex-shrink: 0; position: relative;
	}
	.aa-pool-avatar img { width: 100%; height: 100%; object-fit: cover; position: absolute; inset: 0; }
	.aa-pool-initial { font-weight: 700; font-size: 0.7rem; color: var(--color-outline); }
	.aa-pool-name-wrap { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
	.aa-pool-name { font-size: var(--text-body-sm); font-weight: 600; color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.aa-pool-reason { font-size: 0.65rem; color: #b45309; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.aa-blocked-icon { font-size: 0.9rem; color: #b45309; align-self: center; }

	.aa-ineligible-section { margin-bottom: var(--space-2); }
	.aa-ineligible-section summary { margin-bottom: var(--space-2); }

	/* Publish-Warnung */
	.aa-publish-warn {
		display: flex; align-items: center; gap: var(--space-2);
		padding: var(--space-3);
		background: rgba(180, 83, 9, 0.1);
		border: 1px solid rgba(180, 83, 9, 0.35);
		border-radius: var(--radius-md);
		color: #b45309;
		margin-bottom: var(--space-3);
	}
	.aa-publish-warn .material-symbols-outlined {
		font-size: 1.2rem;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
		flex-shrink: 0;
	}
	.aa-publish-warn div { display: flex; flex-direction: column; gap: 2px; }
	.aa-publish-warn strong { font-size: var(--text-body-sm); font-weight: 700; }
	.aa-publish-warn span { font-size: var(--text-label-sm); }

	/* Swap-Sheet */
	.aa-swap-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface);
		margin: 0 0 var(--space-3);
	}
	.aa-swap-hint strong { color: var(--color-primary); }

	.aa-reason-chips {
		display: flex; flex-wrap: wrap; gap: var(--space-2);
		margin: 0 0 var(--space-3);
	}
	.aa-chip {
		padding: 6px 12px;
		border-radius: var(--radius-full);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-low);
		color: var(--color-on-surface);
		font-size: var(--text-body-sm);
		font-weight: 600;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: border-color 0.15s, background 0.15s;
	}
	.aa-chip--active {
		border-color: var(--color-primary);
		background: var(--color-primary);
		color: #fff;
	}
	.aa-reason-input {
		width: 100%;
		padding: 10px 12px;
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		font-size: var(--text-body-md);
		font-family: inherit;
		color: var(--color-on-surface);
		background: var(--color-surface-container-low);
		box-sizing: border-box;
		margin-bottom: var(--space-3);
	}
	.aa-reason-input:focus { outline: none; border-color: var(--color-primary); }

	.aa-swap-sort {
		display: flex; align-items: center; justify-content: space-between;
		gap: var(--space-3);
		margin: 0 0 var(--space-3);
	}
	.aa-swap-sort-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-on-surface-variant);
	}
	.aa-swap-sort-toggle {
		display: flex;
		border-radius: var(--radius-full);
		background: var(--color-surface-container-low);
		padding: 3px;
		gap: 2px;
	}
	.aa-sort-btn {
		padding: 6px 10px;
		border: none;
		background: transparent;
		border-radius: var(--radius-full);
		font-size: var(--text-label-sm);
		font-weight: 600;
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-sort-btn--active {
		background: var(--color-primary);
		color: #fff;
	}

	.aa-swap-pool {
		display: flex; flex-direction: column;
		gap: var(--space-2);
	}
	.aa-swap-player {
		display: grid;
		grid-template-columns: 32px 1fr 24px;
		gap: var(--space-3);
		align-items: center;
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: left;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-swap-player:active { background: var(--color-surface-container); }
	.aa-swap-player:disabled { opacity: 0.45; pointer-events: none; }
	.aa-swap-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.aa-swap-name { font-weight: 600; font-size: var(--text-body-sm); color: var(--color-on-surface); }
	.aa-swap-stats { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); font-variant-numeric: tabular-nums; }
	.aa-swap-arrow { color: var(--color-primary); font-size: 1.1rem; }
</style>
