<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false) } = $props();

	let matches       = $state([]);
	let loading       = $state(true);
	let selectedMatch = $state(null);
	let players       = $state([]);
	let loadingPlayers = $state(false);
	let gamePlanId     = $state(null);
	let savingId       = $state(null);

	// Letzte 4 Wochen an Matches laden
	async function loadMatches() {
		loading = true;
		const now = new Date();
		const fourWeeksAgo = new Date(now);
		fourWeeksAgo.setDate(now.getDate() - 28);
		const from = fmt(fourWeeksAgo);
		const to   = fmt(now);

		const { data } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', from)
			.lte('date', to)
			.order('date', { ascending: false })
			.order('time', { ascending: false });

		matches = data ?? [];
		loading = false;
	}

	function fmt(d) {
		return d.getFullYear() + '-' +
			String(d.getMonth() + 1).padStart(2, '0') + '-' +
			String(d.getDate()).padStart(2, '0');
	}

	const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	function matchLabel(m) {
		const d = new Date(m.date + 'T12:00');
		const day = DAY_SHORT[d.getDay()];
		const date = d.getDate() + '.' + (d.getMonth() + 1) + '.';
		return `${day} ${date} – ${m.opponent}`;
	}

	function matchSub(m) {
		return `${m.leagues?.name ?? ''} · ${m.home_away === 'HEIM' ? 'Heim' : 'Auswärts'}`;
	}

	// Aufstellung/Spieler für gewähltes Match laden
	async function selectMatch(m) {
		selectedMatch = m;
		loadingPlayers = true;

		const { data: gp } = await sb
			.from('game_plans')
			.select('id, game_plan_players(id, position, player_id, player_name, score, played, players(name, photo))')
			.eq('cal_week', m.cal_week)
			.eq('league_id', m.league_id)
			.maybeSingle();

		gamePlanId = gp?.id ?? null;
		players = (gp?.game_plan_players ?? [])
			.sort((a, b) => (a.position ?? 99) - (b.position ?? 99))
			.map(p => ({ ...p, draft: p.score ?? '' }));

		loadingPlayers = false;
	}

	async function saveScore(p) {
		if (p.draft === '' || p.draft === null) return;
		const n = Number(p.draft);
		if (!Number.isFinite(n)) return;

		savingId = p.id;
		const { error } = await sb
			.from('game_plan_players')
			.update({ score: n, played: true })
			.eq('id', p.id);

		if (!error) {
			p.score  = n;
			p.played = true;
		}
		savingId = null;
	}

	function allSaved() {
		return players.length > 0 && players.every(p => p.played);
	}

	function done() {
		const count = players.filter(p => p.played).length;
		open = false;
		setTimeout(() => triggerToast(`${count} Ergebnisse gespeichert`), 300);
	}

	function back() {
		selectedMatch = null;
		players = [];
	}

	$effect(() => {
		if (open) {
			loadMatches();
			selectedMatch = null;
			players = [];
		}
	});
</script>

<BottomSheet bind:open title={selectedMatch ? 'Ergebnisse' : 'Match wählen'}>

	{#if loading}
		<div class="ae-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
		</div>

	{:else if !selectedMatch}
		<!-- Match-Auswahl -->
		{#if matches.length === 0}
			<p class="ae-empty">Keine Matches in den letzten 4 Wochen.</p>
		{:else}
			<p class="ae-hint">Wähle ein Match, um Ergebnisse einzutragen.</p>
			<div class="ae-match-list">
				{#each matches as m (m.id)}
					<button class="ae-match-row" onclick={() => selectMatch(m)}>
						<div class="ae-match-info">
							<span class="ae-match-label">{matchLabel(m)}</span>
							<span class="ae-match-sub">{matchSub(m)}</span>
						</div>
						<span class="material-symbols-outlined ae-chevron">chevron_right</span>
					</button>
				{/each}
			</div>
		{/if}

	{:else}
		<!-- Zurück-Button + Match-Info -->
		<button class="ae-back" onclick={back}>
			<span class="material-symbols-outlined">arrow_back</span>
			Zurück
		</button>

		<div class="ae-match-hero">
			<span class="ae-match-hero-label">{matchLabel(selectedMatch)}</span>
			<span class="ae-match-hero-sub">{matchSub(selectedMatch)}</span>
		</div>

		{#if loadingPlayers}
			<div class="ae-loading">
				<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			</div>
		{:else if players.length === 0}
			<p class="ae-empty">Keine Aufstellung für dieses Match gefunden.</p>
		{:else}
			<!-- Score-Eingabe pro Spieler -->
			<div class="ae-players">
				{#each players as p (p.id)}
					{@const name = p.players?.name ?? p.player_name ?? '–'}
					<div class="ae-player" class:ae-player--saved={p.played}>
						<span class="ae-pos">{p.position ?? '–'}</span>
						<span class="ae-name">{name}</span>
						<input
							class="ae-score"
							type="number"
							inputmode="numeric"
							min="0"
							max="999"
							placeholder="Holz"
							bind:value={p.draft}
							onblur={() => saveScore(p)}
						/>
						{#if savingId === p.id}
							<span class="material-symbols-outlined ae-spin">autorenew</span>
						{:else if p.played}
							<span class="material-symbols-outlined ae-ok">check_circle</span>
						{:else}
							<span class="ae-icon-placeholder"></span>
						{/if}
					</div>
				{/each}
			</div>

			<!-- Fertig-Button -->
			<button class="mw-btn mw-btn--primary mw-btn--wide ae-done" onclick={done}>
				<span class="material-symbols-outlined">check</span>
				{allSaved() ? 'Alle gespeichert' : 'Fertig'}
			</button>
		{/if}
	{/if}

</BottomSheet>

<style>
	/* Loading / Empty */
	.ae-loading { display: flex; flex-direction: column; gap: var(--space-2); }
	.ae-empty { color: var(--color-on-surface-variant); font-size: var(--text-body-md); }
	.ae-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-3);
	}

	/* Match list */
	.ae-match-list { display: flex; flex-direction: column; gap: var(--space-2); }
	.ae-match-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: none;
		cursor: pointer;
		text-align: left;
		width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.ae-match-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
	.ae-match-label { font-weight: 600; font-size: var(--text-body-md); color: var(--color-on-surface); }
	.ae-match-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
	.ae-chevron { font-size: 1.2rem; color: var(--color-outline); }

	/* Back button */
	.ae-back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		border: none;
		background: none;
		font-size: var(--text-body-sm);
		font-weight: 600;
		color: var(--color-primary);
		cursor: pointer;
		padding: 0;
		margin-bottom: var(--space-3);
		-webkit-tap-highlight-color: transparent;
	}
	.ae-back .material-symbols-outlined { font-size: 1.1rem; }

	/* Match hero */
	.ae-match-hero {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-bottom: var(--space-4);
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--color-outline-variant);
	}
	.ae-match-hero-label {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
	}
	.ae-match-hero-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }

	/* Player score rows */
	.ae-players { display: flex; flex-direction: column; gap: var(--space-2); margin-bottom: var(--space-4); }
	.ae-player {
		display: grid;
		grid-template-columns: 28px 1fr 80px 24px;
		gap: var(--space-2);
		align-items: center;
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: 1.5px solid transparent;
		transition: border-color 0.15s;
	}
	.ae-player--saved { border-color: rgba(42, 157, 87, 0.3); background: rgba(42, 157, 87, 0.04); }

	.ae-pos {
		font-weight: 700;
		color: var(--color-primary);
		text-align: center;
		font-size: var(--text-body-sm);
	}
	.ae-name {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.ae-score {
		padding: 6px 8px;
		border: 1px solid var(--color-outline-variant);
		border-radius: 6px;
		font-size: 16px;
		text-align: right;
		font-weight: 600;
		background: var(--color-surface-container-lowest);
		color: var(--color-on-surface);
		font-family: var(--font-body);
	}
	.ae-score:focus { border-color: var(--color-primary); outline: none; }

	.ae-ok { color: #2a9d57; font-size: 1.2rem; font-variation-settings: 'FILL' 1; }
	.ae-spin { animation: ae-sp 1s linear infinite; color: var(--color-outline); font-size: 1.1rem; }
	@keyframes ae-sp { to { transform: rotate(360deg); } }
	.ae-icon-placeholder { width: 24px; }

	/* Done */
	.ae-done { margin-top: var(--space-2); }
</style>
