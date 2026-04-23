<script>
	import { onMount }  from 'svelte';
	import { page }     from '$app/stores';
	import { sb }       from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { fmtDate, fmtTime, toDateStr } from '$lib/utils/dates.js';
	import { imgPath, shortName }          from '$lib/utils/players.js';
	import { matchEnded }                  from '$lib/utils/matchTiming.js';
	import AdminAufstellung   from '../admin/AdminAufstellung.svelte';
	import MatchResultEditor  from './MatchResultEditor.svelte';
	import BottomSheet        from '$lib/components/BottomSheet.svelte';

	let editOpen    = $state(false);
	let editMatchId = $state(null);
	let detailOpen  = $state(false);

	function openLineupEdit(id) {
		editMatchId = id;
		editOpen    = true;
	}

	let wasEditOpen = false;
	$effect(() => {
		if (wasEditOpen && !editOpen) {
			const id = editMatchId;
			editMatchId = null;
			if (selectedMatch?.id === id) selectMatch(selectedMatch);
		}
		wasEditOpen = editOpen;
	});

	let allMatches    = $state([]);
	let loading       = $state(true);
	let searchQuery   = $state('');
	let selectedMatch = $state(null);
	let selectedPlan  = $state(null);
	let loadingDetail = $state(false);

	function isPast(m) {
		return m.date < toDateStr(new Date());
	}

	function formTrend(avg5, overallAvg) {
		if (!avg5 || !overallAvg) return null;
		return +(avg5 - overallAvg).toFixed(1);
	}

	const filteredMatches = $derived.by(() => {
		const q = searchQuery.toLowerCase().trim();
		if (!q) return allMatches;
		return allMatches.filter(m =>
			m.opponent?.toLowerCase().includes(q) ||
			m.leagues?.name?.toLowerCase().includes(q) ||
			fmtDate(m.date).toLowerCase().includes(q)
		);
	});

	async function loadMatches() {
		const today = new Date();
		const from  = new Date(today); from.setDate(today.getDate() - 365);
		const to    = new Date(today); to.setDate(today.getDate() + 180);

		const { data } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, is_tournament, tournament_title, leagues(name)')
			.gte('date', toDateStr(from))
			.lte('date', toDateStr(to))
			.order('date', { ascending: false })
			.order('time', { ascending: true });

		allMatches = (data ?? []).filter(m => m.opponent?.toLowerCase() !== 'spielfrei');
		loading = false;
	}

	async function selectMatch(match) {
		detailOpen    = true;
		selectedMatch = match;
		selectedPlan  = null;
		loadingDetail = true;

		let players     = [];
		let playerStats = {};

		let gpRow = null;

		if (match.cal_week && match.league_id) {
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, result_mode, result_published_at, game_plan_players(id, position, player_id, player_name, score, played, result_state, players!game_plan_players_player_id_fkey(name, photo), game_plan_player_lanes(bahn, volle, abraeumen))')
				.eq('cal_week', match.cal_week)
				.eq('league_id', match.league_id)
				.maybeSingle();

			gpRow = gp ?? null;
			players = (gp?.game_plan_players ?? [])
				.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));

			const playerIds = players.filter(p => p.player_id).map(p => p.player_id);
			if (playerIds.length) {
				const { data: recent } = await sb
					.from('game_plan_players')
					.select('player_id, score, game_plans!inner(cal_week)')
					.in('player_id', playerIds)
					.eq('played', true)
					.not('score', 'is', null)
					.order('cal_week', { referencedTable: 'game_plans', ascending: false });

				const scoreMap = {};
				for (const g of recent ?? []) {
					if (!scoreMap[g.player_id]) scoreMap[g.player_id] = [];
					scoreMap[g.player_id].push(Number(g.score));
				}
				for (const p of players) {
					if (!p.player_id) continue;
					const scores = scoreMap[p.player_id] ?? [];
					const last5  = scores.slice(0, 5);
					playerStats[p.player_id] = {
						overallAvg: scores.length ? Math.round(scores.reduce((a,b)=>a+b,0) / scores.length) : null,
						avg5:       last5.length  ? Math.round(last5.reduce((a,b)=>a+b,0)  / last5.length)  : null,
					};
				}
			}
		}

		selectedPlan  = {
			id:                  gpRow?.id ?? null,
			result_mode:         gpRow?.result_mode ?? 'gesamt',
			result_published_at: gpRow?.result_published_at ?? null,
			players,
			playerStats,
		};
		loadingDetail = false;
	}

	const sheetTitle = $derived(selectedMatch ? ((selectedMatch.home_away === 'HEIM' ? 'vs. ' : 'bei ') + selectedMatch.opponent) : '');

	onMount(async () => {
		await loadMatches();
		const deep = $page.url.searchParams.get('match');
		if (deep && allMatches.length) {
			const found = allMatches.find(x => x.id === deep);
			if (found) selectMatch(found);
		}
	});
</script>

<div class="sb-page">

		<div class="mp-search-wrap">
			<div class="mp-input-wrap">
				<span class="material-symbols-outlined mp-search-icon">search</span>
				<input
					class="mp-input"
					type="search"
					placeholder="Match suchen…"
					autocomplete="off"
					bind:value={searchQuery}
				/>
				{#if searchQuery}
					<button class="mp-clear" onclick={() => searchQuery = ''} aria-label="Löschen">
						<span class="material-symbols-outlined">cancel</span>
					</button>
				{/if}
			</div>
		</div>

		{#if loading}
			<div class="sb-loading">
				<span class="material-symbols-outlined sb-loading-icon">sports_score</span>
				<p>Lade Spiele…</p>
			</div>

		{:else if filteredMatches.length === 0}
			<div class="sb-empty">
				<span class="material-symbols-outlined sb-loading-icon">event_busy</span>
				<p>{searchQuery ? 'Keine Treffer' : 'Keine Spiele gefunden'}</p>
			</div>

		{:else}
			<div class="mp-list">
				{#each filteredMatches as m}
					<button class="mp-card" class:mp-card--past={isPast(m)} onclick={() => selectMatch(m)}>
						<div class="mp-card-left">
							{#if m.home_away === 'HEIM'}
								<span class="chip chip--home">Heim</span>
							{:else}
								<span class="chip chip--away">Auswärts</span>
							{/if}
							<h3 class="mp-opponent">
								{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}
							</h3>
							<p class="mp-league">{m.leagues?.name ?? ''}{m.is_tournament ? ' · ' + (m.tournament_title ?? 'Turnier') : ''}</p>
						</div>
						<div class="mp-card-right">
							<span class="mp-date">{fmtDate(m.date)}</span>
							{#if fmtTime(m.time)}<span class="mp-time">{fmtTime(m.time)}</span>{/if}
							<span class="material-symbols-outlined mp-chevron">chevron_right</span>
						</div>
					</button>
				{/each}
			</div>
		{/if}

	</div>

<BottomSheet bind:open={detailOpen} title={sheetTitle}>
	{#if selectedMatch}
		{@const m = selectedMatch}

		<div class="sb-match-header">
			<p class="sb-league">{m.leagues?.name ?? ''}{m.is_tournament ? ' · ' + (m.tournament_title ?? 'Turnier') : ''}</p>
			<div class="sb-match-row">
				{#if m.home_away === 'HEIM'}
					<span class="chip chip--home">Heim</span>
				{:else}
					<span class="chip chip--away">Auswärts</span>
				{/if}
				<h2 class="sb-opponent">{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}</h2>
			</div>
			<p class="sb-date">{fmtDate(m.date)}{fmtTime(m.time) ? ' · ' + fmtTime(m.time) : ''}</p>
		</div>

		{#if loadingDetail}
			<div class="sb-loading">
				<span class="material-symbols-outlined sb-loading-icon">sports_score</span>
				<p>Lade Aufstellung…</p>
			</div>

		{:else}
			{@const players = selectedPlan?.players ?? []}
			{@const stats   = selectedPlan?.playerStats ?? {}}
			{@const played  = players.filter(p => p.played && p.score != null)}

			<div class="md-squad-section">
				<div class="md-squad-header">
					<div class="md-squad-header-rule"></div>
					<div class="md-squad-header-label">
						<span class="material-symbols-outlined md-squad-header-icon">shield</span>
						Aufstellung
					</div>
					<div class="md-squad-header-rule"></div>
				</div>

				{#if $playerRole === 'kapitaen'}
					<div class="md-squad-captain-actions">
						<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={() => openLineupEdit(m.id)}>
							<span class="material-symbols-outlined">edit</span>
							Aufstellung bearbeiten
						</button>
					</div>
				{/if}

				{#if players.length === 0}
					<div class="sb-empty md-squad-empty">
						<span class="material-symbols-outlined sb-loading-icon">group_off</span>
						<p>Noch keine Aufstellung</p>
					</div>
				{:else}
					<div class="md-squad-grid">
						{#each players as p, i}
							{@const name     = p.players?.name ?? p.player_name ?? '–'}
							{@const photo    = p.players?.photo ?? null}
							{@const isMe     = p.player_id === $playerId}
							{@const pStat    = stats[p.player_id] ?? null}
							{@const trend    = formTrend(pStat?.avg5, pStat?.overallAvg)}
							{@const hasScore = p.played && p.score != null && !!selectedPlan?.result_published_at}

							<div
								class="md-squad-card"
								class:md-squad-card--me={isMe}
								style="animation-delay:{i * 65}ms"
							>
								<img
									class="md-squad-photo"
									src={imgPath(photo, name)}
									alt={name}
									draggable="false"
									onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
								/>

								<div class="md-squad-vignette"></div>

								<div class="md-squad-pos">{p.position ?? '–'}</div>

								{#if isMe}
									<div class="md-squad-me-tag">DU</div>
								{/if}

								{#if hasScore}
									<div class="md-squad-score">{p.score}</div>
								{/if}

								<div class="md-squad-info">
									<div class="md-squad-name">{shortName(name)}</div>
									{#if pStat}
										<div class="md-squad-avg">
											<span class="md-squad-avg-val">{pStat.overallAvg}</span>
											<span class="md-squad-avg-unit"> Holz</span>
											{#if trend !== null}
												<span
													class="md-squad-trend"
													class:md-squad-trend--up={trend >= 0}
													class:md-squad-trend--down={trend < 0}
												>
													<span class="material-symbols-outlined">
														{trend >= 0 ? 'trending_up' : 'trending_down'}
													</span>
												</span>
											{/if}
										</div>
									{/if}
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>

			{#if $playerRole === 'kapitaen' && matchEnded(m) && selectedPlan?.id}
				<MatchResultEditor
					gamePlanId={selectedPlan.id}
					match={m}
					players={selectedPlan.players}
					initialMode={selectedPlan.result_mode}
					initialPublishedAt={selectedPlan.result_published_at}
					onPublished={() => selectMatch(m)}
				/>
			{/if}

			{#if selectedPlan?.result_published_at && played.length > 0}
				<div class="md-section">
					<div class="md-sec-head">
						<span class="material-symbols-outlined md-sec-icon">emoji_events</span>
						<h3 class="md-sec-title">Ergebnisse</h3>
					</div>

					<div class="md-results-card">
						{#each played as p}
							{@const name  = p.players?.name ?? p.player_name ?? '–'}
							{@const photo = p.players?.photo ?? null}
							{@const lanes = (p.game_plan_player_lanes ?? []).sort((a, b) => a.bahn - b.bahn)}
							{@const detail = selectedPlan?.result_mode === 'detailliert'}
							<div class="md-result-row">
								<span class="md-result-pos">{p.position ?? '–'}</span>
								<img
									class="md-result-avatar"
									src={imgPath(photo, name)}
									alt={name}
									draggable="false"
									onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
								/>
								<span class="md-result-name">{name}</span>
								<span class="md-result-score">{p.score}</span>
								<span class="md-result-unit">Holz</span>
							</div>
							{#if detail && lanes.length > 0}
								<div class="md-result-lanes">
									<table class="md-lane-table">
										<thead>
											<tr>
												<th>Bahn</th>
												<th>Volle</th>
												<th>Abräumen</th>
												<th>Summe</th>
											</tr>
										</thead>
										<tbody>
											{#each lanes as l}
												{@const lsum = (Number(l.volle) || 0) + (Number(l.abraeumen) || 0)}
												<tr>
													<td>{l.bahn}</td>
													<td>{l.volle ?? '–'}</td>
													<td>{l.abraeumen ?? '–'}</td>
													<td>{lsum || '–'}</td>
												</tr>
											{/each}
										</tbody>
									</table>
								</div>
							{/if}
						{/each}
						<div class="md-result-total">
							<span class="md-result-total-label">Gesamt</span>
							<span class="md-result-total-score">
								{played.reduce((s, p) => s + Number(p.score), 0)}
							</span>
							<span class="md-result-unit">Holz</span>
						</div>
					</div>
				</div>
			{/if}
		{/if}
	{/if}
</BottomSheet>

<AdminAufstellung bind:open={editOpen} preselectedMatchId={editMatchId} />

<style>
	.mp-search-wrap { position: relative; }
	.mp-input-wrap {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		background: var(--color-surface-container);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		padding: 0 var(--space-3);
		transition: border-color 200ms ease, box-shadow 200ms ease;
	}
	.mp-input-wrap:focus-within {
		border-color: rgba(204,0,0,0.5);
		box-shadow: 0 0 0 3px rgba(204,0,0,0.12);
	}
	.mp-search-icon {
		font-size: 1.15rem;
		color: var(--color-outline);
		font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.mp-input {
		flex: 1;
		height: 2.6rem;
		background: none;
		border: none;
		outline: none;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.mp-input::placeholder { color: var(--color-outline); }
	.mp-input::-webkit-search-cancel-button { display: none; }
	.mp-clear {
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
		color: var(--color-outline);
		display: flex;
		align-items: center;
	}
	.mp-clear .material-symbols-outlined { font-size: 1.1rem; }

	.md-squad-captain-actions {
		display: flex; gap: var(--space-2);
		padding: 0 var(--space-4) var(--space-3);
	}

	.mp-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.mp-card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
		cursor: pointer;
		text-align: left;
		font: inherit;
		transition: transform 120ms ease, box-shadow 120ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.mp-card:active { transform: scale(0.98); }
	.mp-card--past { opacity: 0.72; }
	.mp-card-left {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}
	.mp-opponent {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.mp-league {
		margin: 0;
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.mp-card-right {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		flex-shrink: 0;
	}
	.mp-date {
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-on-surface-variant);
		white-space: nowrap;
	}
	.mp-time {
		font-size: 0.65rem;
		color: var(--color-outline);
		white-space: nowrap;
	}
	.mp-chevron {
		font-size: 1rem;
		color: var(--color-outline);
		margin-top: 2px;
	}

	:global(.chip) {
		display: inline-flex;
		align-items: center;
		font-size: 0.62rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		border-radius: 999px;
		padding: 2px 8px;
	}
	:global(.chip--home)  { background: rgba(34,197,94,0.12);  color: #166534; }
	:global(.chip--away)  { background: rgba(204,0,0,0.1);     color: var(--color-primary); }

	.md-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.md-sec-head {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.md-sec-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.md-sec-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	.md-results-card {
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
		border: 1.5px solid rgba(212, 175, 55, 0.25);
		overflow: hidden;
	}
	.md-result-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		border-bottom: 1px solid var(--color-surface-container);
	}
	.md-result-pos {
		width: 1.4rem;
		text-align: center;
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 800;
		color: var(--color-primary);
	}
	.md-result-avatar {
		width: 32px;
		height: 32px;
		border-radius: 50%;
		object-fit: cover;
		object-position: top center;
		flex-shrink: 0;
		background: var(--color-surface-container);
	}
	.md-result-name {
		flex: 1;
		font-family: var(--font-display);
		font-size: var(--text-body-md);
		font-weight: 600;
		color: var(--color-on-surface);
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.md-result-score {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 800;
		color: var(--color-on-surface);
	}
	.md-result-unit {
		font-size: var(--text-label-sm);
		color: var(--color-outline);
		width: 2rem;
	}
	.md-result-total {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: rgba(212, 175, 55, 0.08);
	}
	.md-result-total-label {
		flex: 1;
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-on-surface-variant);
		padding-left: calc(1.4rem + var(--space-3) + 32px);
	}
	.md-result-total-score {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 800;
		color: var(--color-secondary, #D4AF37);
	}
	.md-result-lanes {
		padding: 0 var(--space-4) var(--space-3);
		background: color-mix(in srgb, var(--color-secondary) 5%, transparent);
		border-bottom: 1px solid var(--color-surface-container);
	}
	.md-lane-table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--text-label-sm);
	}
	.md-lane-table th {
		text-align: right;
		font-weight: 700;
		color: var(--color-on-surface-variant);
		padding: 4px 6px;
		border-bottom: 1px solid var(--color-outline-variant);
	}
	.md-lane-table th:first-child { text-align: left; }
	.md-lane-table td {
		text-align: right;
		padding: 4px 6px;
		color: var(--color-on-surface);
	}
	.md-lane-table td:first-child { text-align: left; font-weight: 600; }
</style>
