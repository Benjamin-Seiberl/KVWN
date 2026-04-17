<script>
	import { onMount }           from 'svelte';
	import { sb }                from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { currentSubtab }    from '$lib/stores/subtab.js';
	import { triggerToast }      from '$lib/stores/toast.js';
	import StatsView             from '$lib/components/statistiken/StatsView.svelte';
	import TournamentMatchCard   from '$lib/components/spielbetrieb/TournamentMatchCard.svelte';
	import BottomSheet           from '$lib/components/BottomSheet.svelte';

	const DAY_NAMES   = ['So','Mo','Di','Mi','Do','Fr','Sa'];
	const MONTH_NAMES = ['Jän','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];

	// ── State ──────────────────────────────────────────────────────
	let allMatches    = $state([]);
	let loading       = $state(true);
	let searchQuery   = $state('');
	let selectedMatch = $state(null);
	let selectedPlan  = $state(null);   // { players[], playerStats{} }
	let loadingDetail = $state(false);

	// ── Helpers ────────────────────────────────────────────────────
	function fmt(d) {
		return d.getFullYear() + '-' +
			String(d.getMonth() + 1).padStart(2, '0') + '-' +
			String(d.getDate()).padStart(2, '0');
	}

	function chipDate(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES[d.getDay()] + ', ' + d.getDate() + '. ' + MONTH_NAMES[d.getMonth()];
	}

	function chipTime(m) {
		return m.time ? m.time.slice(0, 5) + ' Uhr' : '';
	}

	function isPast(m) {
		return m.date < fmt(new Date());
	}

	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function formTrend(avg5, overallAvg) {
		if (!avg5 || !overallAvg) return null;
		return +(avg5 - overallAvg).toFixed(1);
	}

	// ── Filtered matches ───────────────────────────────────────────
	const filteredMatches = $derived.by(() => {
		const q = searchQuery.toLowerCase().trim();
		if (!q) return allMatches;
		return allMatches.filter(m =>
			m.opponent?.toLowerCase().includes(q) ||
			m.leagues?.name?.toLowerCase().includes(q) ||
			chipDate(m).toLowerCase().includes(q)
		);
	});

	// ── Load all matches ───────────────────────────────────────────
	async function loadMatches() {
		const today = new Date();
		const from  = new Date(today); from.setDate(today.getDate() - 365);
		const to    = new Date(today); to.setDate(today.getDate() + 180);

		const { data } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, is_tournament, tournament_title, leagues(name)')
			.gte('date', fmt(from))
			.lte('date', fmt(to))
			.order('date', { ascending: false })
			.order('time', { ascending: true });

		allMatches = (data ?? []).filter(m => m.opponent?.toLowerCase() !== 'spielfrei');
		loading = false;
	}

	// ── Select a match → lazy-load game plan + stats ───────────────
	async function selectMatch(match) {
		selectedMatch = match;
		selectedPlan  = null;
		loadingDetail = true;

		let players     = [];
		let playerStats = {};
		let gamePlanId  = null;

		if (match.cal_week && match.league_id) {
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, game_plan_players(id, position, player_id, player_name, score, played, players(name, photo))')
				.eq('cal_week', match.cal_week)
				.eq('league_id', match.league_id)
				.maybeSingle();

			gamePlanId = gp?.id ?? null;
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

		selectedPlan  = { players, playerStats };
		loadingDetail = false;
	}

	function goBack() {
		selectedMatch = null;
		selectedPlan  = null;
	}

	// ── Tournament tab ─────────────────────────────────────────────
	const isAdmin = $derived($playerRole === 'kapitaen');

	let tournaments        = $state([]);
	let loadingTournaments = $state(false);
	let tourneySearch      = $state('');
	let selectedTourney    = $state(null);
	let createOpen         = $state(false);

	// New tournament form
	let newTitle    = $state('');
	let newDates    = $state(['']);   // bis zu 5 mögliche Tage
	let newLocation = $state('');
	let saving      = $state(false);

	function addDateField() {
		if (newDates.length < 5) newDates = [...newDates, ''];
	}
	function removeDateField(i) {
		newDates = newDates.filter((_, idx) => idx !== i);
	}

	const filteredTourneys = $derived.by(() => {
		const q = tourneySearch.toLowerCase().trim();
		if (!q) return tournaments;
		return tournaments.filter(t =>
			t.tournament_title?.toLowerCase().includes(q) ||
			t.tournament_location?.toLowerCase().includes(q)
		);
	});

	async function loadTournaments() {
		loadingTournaments = true;
		const { data } = await sb
			.from('matches')
			.select(`id, tournament_title, tournament_location, tournament_status,
			         tournament_date_options(id, date),
			         tournament_votes(player_id, wants_to_play)`)
			.eq('is_tournament', true)
			.eq('is_landesbewerb', false)
			.order('created_at', { ascending: false });
		tournaments = data ?? [];
		loadingTournaments = false;
	}

	async function createTournament() {
		const dates = newDates.filter(d => d);
		if (!newTitle || dates.length === 0) return;
		saving = true;
		const { data: match, error } = await sb.from('matches').insert({
			is_tournament:        true,
			tournament_title:     newTitle,
			tournament_location:  newLocation || null,
			tournament_status:    'voting',
			opponent:             newTitle,
			home_away:            'HEIM',
		}).select().single();
		if (error) { triggerToast('Fehler beim Erstellen'); saving = false; return; }
		await sb.from('tournament_date_options').insert(
			dates.map(d => ({ tournament_id: match.id, date: d }))
		);
		saving = false;
		createOpen = false;
		newTitle = ''; newDates = ['']; newLocation = '';
		await loadTournaments();
		selectedTourney = tournaments.find(t => t.id === match.id) ?? match;
	}

	$effect(() => {
		if ($currentSubtab === 'turnier' && !tournaments.length && !loadingTournaments) {
			loadTournaments();
		}
	});

	// ── Landesbewerb tab ───────────────────────────────────────────
	let landesbewerbe        = $state([]);
	let loadingLandes        = $state(false);
	let landesSearch         = $state('');
	let selectedLandes       = $state(null);
	let landesCreateOpen     = $state(false);

	let landesTitle    = $state('');
	let landesDate     = $state('');
	let landesTime     = $state('');
	let landesLocation = $state('');
	let landesSaving   = $state(false);

	const filteredLandes = $derived.by(() => {
		const q = landesSearch.toLowerCase().trim();
		if (!q) return landesbewerbe;
		return landesbewerbe.filter(t =>
			t.tournament_title?.toLowerCase().includes(q) ||
			t.tournament_location?.toLowerCase().includes(q) ||
			chipDate(t).toLowerCase().includes(q)
		);
	});

	async function loadLandesbewerbe() {
		loadingLandes = true;
		const today = new Date();
		const from  = new Date(today); from.setDate(today.getDate() - 365);
		const to    = new Date(today); to.setDate(today.getDate() + 365);
		const { data } = await sb
			.from('matches')
			.select('id, date, time, tournament_title, tournament_location, home_away, opponent')
			.eq('is_landesbewerb', true)
			.gte('date', fmt(from))
			.lte('date', fmt(to))
			.order('date', { ascending: false });
		landesbewerbe = data ?? [];
		loadingLandes = false;
	}

	async function createLandesbewerb() {
		if (!landesTitle || !landesDate) return;
		landesSaving = true;
		const { data, error } = await sb.from('matches').insert({
			is_landesbewerb:     true,
			is_tournament:       true,
			tournament_title:    landesTitle,
			tournament_location: landesLocation || null,
			date:                landesDate,
			time:                landesTime || null,
			opponent:            landesTitle,
			home_away:           'HEIM',
		}).select().single();
		landesSaving = false;
		if (error) { triggerToast('Fehler beim Erstellen'); return; }
		landesCreateOpen = false;
		landesTitle = ''; landesDate = ''; landesTime = ''; landesLocation = '';
		await loadLandesbewerbe();
		selectedLandes = data;
	}

	$effect(() => {
		if ($currentSubtab === 'landesbewerb' && !landesbewerbe.length && !loadingLandes) {
			loadLandesbewerbe();
		}
	});

	onMount(() => loadMatches());
</script>

<div class="page active">

{#if $currentSubtab === 'statistiken'}
	<StatsView />
{:else if $currentSubtab === 'turnier'}
<div class="sb-page">

	<!-- ── TURNIER PICKER ────────────────────────────────────────── -->
	{#if !selectedTourney}

		<div class="mp-search-wrap">
			<div class="tp-search-row">
				<div class="mp-input-wrap" style="flex:1">
					<span class="material-symbols-outlined mp-search-icon">search</span>
					<input
						class="mp-input"
						type="search"
						placeholder="Turnier suchen…"
						autocomplete="off"
						bind:value={tourneySearch}
					/>
					{#if tourneySearch}
						<button class="mp-clear" onclick={() => tourneySearch = ''} aria-label="Löschen">
							<span class="material-symbols-outlined">cancel</span>
						</button>
					{/if}
				</div>
				{#if isAdmin}
					<button class="tp-add-btn" onclick={() => createOpen = true} aria-label="Turnier erstellen">
						<span class="material-symbols-outlined">add</span>
					</button>
				{/if}
			</div>
		</div>

		{#if loadingTournaments}
			<div class="sb-loading">
				<span class="material-symbols-outlined sb-loading-icon">military_tech</span>
				<p>Lade Turniere…</p>
			</div>
		{:else if filteredTourneys.length === 0}
			<div class="sb-empty">
				<span class="material-symbols-outlined sb-loading-icon">military_tech</span>
				<p>{tourneySearch ? 'Keine Treffer' : 'Noch keine Turniere'}</p>
				{#if isAdmin && !tourneySearch}
					<button class="tp-create-cta" onclick={() => createOpen = true}>
						<span class="material-symbols-outlined">add_circle</span>
						Turnier erstellen
					</button>
				{/if}
			</div>
		{:else}
			<div class="mp-list">
				{#each filteredTourneys as t}
					{@const yesCount  = (t.tournament_votes ?? []).filter(v => v.wants_to_play).length}
					{@const statusMap = { voting: 'Abstimmung läuft', voting_closed: 'Geschlossen', scheduling: 'Spielplan', confirmed: 'Bestätigt' }}
					{@const statusKey = t.tournament_status ?? 'voting'}
					<button class="mp-card tp-card" onclick={() => selectedTourney = t}>
						<div class="mp-card-left">
							<div class="tp-trophy-badge">
								<span class="material-symbols-outlined">military_tech</span>
							</div>
							<h3 class="mp-opponent">{t.tournament_title ?? 'Turnier'}</h3>
							{#if t.tournament_location}
								<p class="mp-league">
									<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-2px">location_on</span>
									{t.tournament_location}
								</p>
							{/if}
							<div class="tp-card-meta">
								<span class="tp-status-badge tp-status-badge--{statusKey}">{statusMap[statusKey]}</span>
								{#if yesCount > 0}
									<span class="tp-yes-count">
										<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-1px">check_circle</span>
										{yesCount} Zusage{yesCount !== 1 ? 'n' : ''}
									</span>
								{/if}
							</div>
						</div>
						<div class="mp-card-right">
							<span class="material-symbols-outlined mp-chevron">chevron_right</span>
						</div>
					</button>
				{/each}
			</div>
		{/if}

	<!-- ── TURNIER DETAIL ─────────────────────────────────────────── -->
	{:else}
		<button class="md-back" onclick={() => { selectedTourney = null; }}>
			<span class="material-symbols-outlined">arrow_back_ios</span>
			Alle Turniere
		</button>

		<TournamentMatchCard match={selectedTourney} onReload={loadTournaments} />
	{/if}

	<!-- Create tournament sheet -->
	<BottomSheet bind:open={createOpen} title="Turnier erstellen">
		<div class="tp-form">
			<label class="tp-field">
				<span class="tp-label">Turniername *</span>
				<input class="tp-input" type="text" placeholder="z.B. NÖ-Cup 2026" bind:value={newTitle} />
			</label>

			<div class="tp-field">
				<span class="tp-label">Mögliche Tage *</span>
				{#each newDates as d, i}
					<div class="tp-date-row">
						<input class="tp-input tp-date-input" type="date" bind:value={newDates[i]} />
						{#if newDates.length > 1}
							<button class="tp-date-remove" onclick={() => removeDateField(i)} aria-label="Datum entfernen">
								<span class="material-symbols-outlined">close</span>
							</button>
						{/if}
					</div>
				{/each}
				{#if newDates.length < 5}
					<button class="tp-add-date-btn" onclick={addDateField}>
						<span class="material-symbols-outlined">add</span>
						Datum hinzufügen
					</button>
				{/if}
			</div>

			<label class="tp-field">
				<span class="tp-label">Ort</span>
				<input class="tp-input" type="text" placeholder="z.B. Sportanlage Wiener Neustadt" bind:value={newLocation} />
			</label>
			<button
				class="tp-save-btn"
				onclick={createTournament}
				disabled={!newTitle || !newDates.some(d => d) || saving}
			>
				{saving ? 'Speichern…' : 'Turnier anlegen'}
			</button>
		</div>
	</BottomSheet>

</div>
{:else if $currentSubtab === 'landesbewerb'}
<div class="sb-page">

	<!-- ── LANDESBEWERB PICKER ───────────────────────────────────── -->
	{#if !selectedLandes}

		<div class="mp-search-wrap">
			<div class="tp-search-row">
				<div class="mp-input-wrap" style="flex:1">
					<span class="material-symbols-outlined mp-search-icon">search</span>
					<input
						class="mp-input"
						type="search"
						placeholder="Landesbewerb suchen…"
						autocomplete="off"
						bind:value={landesSearch}
					/>
					{#if landesSearch}
						<button class="mp-clear" onclick={() => landesSearch = ''} aria-label="Löschen">
							<span class="material-symbols-outlined">cancel</span>
						</button>
					{/if}
				</div>
				{#if isAdmin}
					<button class="tp-add-btn" onclick={() => landesCreateOpen = true} aria-label="Landesbewerb erstellen">
						<span class="material-symbols-outlined">add</span>
					</button>
				{/if}
			</div>
		</div>

		{#if loadingLandes}
			<div class="sb-loading">
				<span class="material-symbols-outlined sb-loading-icon">workspace_premium</span>
				<p>Lade Landesbewerbe…</p>
			</div>
		{:else if filteredLandes.length === 0}
			<div class="sb-empty">
				<span class="material-symbols-outlined sb-loading-icon">workspace_premium</span>
				<p>{landesSearch ? 'Keine Treffer' : 'Noch keine Landesbewerbe'}</p>
				{#if isAdmin && !landesSearch}
					<button class="tp-create-cta" onclick={() => landesCreateOpen = true}>
						<span class="material-symbols-outlined">add_circle</span>
						Landesbewerb erstellen
					</button>
				{/if}
			</div>
		{:else}
			<div class="mp-list">
				{#each filteredLandes as t}
					<button class="mp-card" class:mp-card--past={isPast(t)} onclick={() => selectedLandes = t}>
						<div class="mp-card-left">
							<div class="tp-trophy-badge tp-trophy-badge--landes">
								<span class="material-symbols-outlined">workspace_premium</span>
							</div>
							<h3 class="mp-opponent">{t.tournament_title ?? 'Landesbewerb'}</h3>
							{#if t.tournament_location}
								<p class="mp-league">
									<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-2px">location_on</span>
									{t.tournament_location}
								</p>
							{/if}
						</div>
						<div class="mp-card-right">
							<span class="mp-date">{chipDate(t)}</span>
							{#if chipTime(t)}<span class="mp-time">{chipTime(t)}</span>{/if}
							<span class="material-symbols-outlined mp-chevron">chevron_right</span>
						</div>
					</button>
				{/each}
			</div>
		{/if}

	<!-- ── LANDESBEWERB DETAIL ────────────────────────────────────── -->
	{:else}
		<button class="md-back" onclick={() => { selectedLandes = null; }}>
			<span class="material-symbols-outlined">arrow_back_ios</span>
			Alle Landesbewerbe
		</button>

		<TournamentMatchCard match={selectedLandes} />
	{/if}

	<BottomSheet bind:open={landesCreateOpen} title="Landesbewerb erstellen">
		<div class="tp-form">
			<label class="tp-field">
				<span class="tp-label">Titel *</span>
				<input class="tp-input" type="text" placeholder="z.B. NÖ Landesmeisterschaft 2025" bind:value={landesTitle} />
			</label>
			<label class="tp-field">
				<span class="tp-label">Datum *</span>
				<input class="tp-input" type="date" bind:value={landesDate} />
			</label>
			<label class="tp-field">
				<span class="tp-label">Uhrzeit</span>
				<input class="tp-input" type="time" bind:value={landesTime} />
			</label>
			<label class="tp-field">
				<span class="tp-label">Ort</span>
				<input class="tp-input" type="text" placeholder="z.B. Sportzentrum Wiener Neustadt" bind:value={landesLocation} />
			</label>
			<button
				class="tp-save-btn"
				onclick={createLandesbewerb}
				disabled={!landesTitle || !landesDate || landesSaving}
			>
				{landesSaving ? 'Speichern…' : 'Landesbewerb anlegen'}
			</button>
		</div>
	</BottomSheet>

</div>
{:else}
<div class="sb-page">

	<!-- ── MATCH PICKER ──────────────────────────────────────────── -->
	{#if !selectedMatch}

		<!-- Search -->
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
							<span class="mp-date">{chipDate(m)}</span>
							{#if chipTime(m)}<span class="mp-time">{chipTime(m)}</span>{/if}
							<span class="material-symbols-outlined mp-chevron">chevron_right</span>
						</div>
					</button>
				{/each}
			</div>
		{/if}

	<!-- ── MATCH DETAIL ──────────────────────────────────────────── -->
	{:else}
		{@const m = selectedMatch}

		<!-- Back -->
		<button class="md-back" onclick={goBack}>
			<span class="material-symbols-outlined">arrow_back_ios</span>
			Alle Spiele
		</button>

		<!-- Match header -->
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
			<p class="sb-date">{chipDate(m)}{chipTime(m) ? ' · ' + chipTime(m) : ''}</p>
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

			<!-- Aufstellung -->
			<div class="md-section">
				<div class="md-sec-head">
					<span class="material-symbols-outlined md-sec-icon">group</span>
					<h3 class="md-sec-title">Aufstellung</h3>
				</div>

				{#if players.length === 0}
					<div class="sb-empty">
						<span class="material-symbols-outlined sb-loading-icon">group_off</span>
						<p>Noch keine Aufstellung</p>
					</div>
				{:else}
					<div class="sb-lineup-list">
						{#each players as p}
							{@const name  = p.players?.name ?? p.player_name ?? '–'}
							{@const photo = p.players?.photo ?? null}
							{@const isMe  = p.player_id === $playerId}
							{@const pStat = stats[p.player_id] ?? null}
							{@const trend = formTrend(pStat?.avg5, pStat?.overallAvg)}

							<div class="picker-scout-card" class:picker-scout-card--me={isMe}>
								<div class="picker-scout-photo-wrap">
									<img
										class="picker-scout-photo"
										src={imgPath(photo, name)}
										alt={name}
										draggable="false"
										onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
									/>
								</div>
								<div class="picker-scout-info">
									<div class="picker-scout-header">
										<span class="picker-scout-name">{name}</span>
										<div class="sb-pos-badge">{p.position ?? '–'}</div>
									</div>
									<div class="picker-scout-stats">
										<div class="picker-scout-stat">
											<span class="picker-scout-stat-label">Schnitt</span>
											<span class="picker-scout-stat-value">
												{pStat?.overallAvg ?? '–'}&thinsp;<span class="picker-scout-stat-unit">Holz</span>
											</span>
										</div>
										<div class="picker-scout-stat">
											<span class="picker-scout-stat-label">Form (5)</span>
											<div class="picker-scout-form-row">
												<span class="picker-scout-form-value">{pStat?.avg5 ?? '–'}</span>
												{#if trend !== null}
													<span
														class="picker-scout-trend"
														class:picker-scout-trend--up={trend >= 0}
														class:picker-scout-trend--down={trend < 0}
													>
														<span class="material-symbols-outlined">
															{trend >= 0 ? 'trending_up' : 'trending_down'}
														</span>
														{trend >= 0 ? '+' : ''}{trend}
													</span>
												{/if}
											</div>
										</div>
									</div>
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>

			<!-- Ergebnisse (nur wenn Scores vorhanden) -->
			{#if played.length > 0}
				<div class="md-section">
					<div class="md-sec-head">
						<span class="material-symbols-outlined md-sec-icon">emoji_events</span>
						<h3 class="md-sec-title">Ergebnisse</h3>
					</div>

					<div class="md-results-card">
						{#each played as p}
							{@const name = p.players?.name ?? p.player_name ?? '–'}
							{@const photo = p.players?.photo ?? null}
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

</div>
{/if}

</div>

<style>
	/* ── Tournament tab ── */
	.tp-search-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.tp-add-btn {
		width: 2.6rem;
		height: 2.6rem;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary);
		color: #fff;
		border: none;
		border-radius: var(--radius-lg);
		cursor: pointer;
		transition: transform 120ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.tp-add-btn:active { transform: scale(0.92); }
	.tp-add-btn .material-symbols-outlined { font-size: 1.3rem; }

	.tp-trophy-badge {
		width: 2rem;
		height: 2rem;
		display: flex;
		align-items: center;
		justify-content: center;
		background: rgba(212,175,55,0.12);
		border-radius: var(--radius-md);
		margin-bottom: 2px;
	}
	.tp-trophy-badge .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-secondary, #D4AF37);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tp-trophy-badge--landes {
		background: rgba(99, 102, 241, 0.1);
	}
	.tp-trophy-badge--landes .material-symbols-outlined {
		color: #6366f1;
	}

	.tp-create-cta {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-2) var(--space-4);
		background: var(--color-primary);
		color: #fff;
		border: none;
		border-radius: var(--radius-lg);
		font: inherit;
		font-size: var(--text-label-md);
		font-weight: 700;
		cursor: pointer;
		margin-top: var(--space-2);
	}
	.tp-create-cta .material-symbols-outlined { font-size: 1.1rem; }

	/* Create form inside BottomSheet */
	.tp-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5) var(--space-6);
	}
	.tp-field {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.tp-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.tp-input {
		width: 100%;
		padding: var(--space-3) var(--space-3);
		background: var(--color-surface-container);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		font: inherit;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		box-sizing: border-box;
		transition: border-color 150ms ease, box-shadow 150ms ease;
	}
	.tp-input:focus {
		outline: none;
		border-color: rgba(204,0,0,0.5);
		box-shadow: 0 0 0 3px rgba(204,0,0,0.1);
	}
	.tp-save-btn {
		width: 100%;
		padding: var(--space-3);
		background: var(--color-primary);
		color: #fff;
		border: none;
		border-radius: var(--radius-lg);
		font: inherit;
		font-size: var(--text-body-md);
		font-weight: 700;
		cursor: pointer;
		transition: opacity 150ms ease;
		margin-top: var(--space-2);
	}
	.tp-save-btn:disabled { opacity: 0.5; cursor: not-allowed; }

	.sb-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5) calc(var(--nav-height, 72px) + var(--space-6));
	}

	/* ── Loading / empty ── */
	.sb-loading, .sb-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-3);
		padding: var(--space-10) var(--space-4);
		color: var(--color-outline);
	}
	.sb-loading-icon { font-size: 2.5rem; opacity: 0.5; }
	.sb-loading p, .sb-empty p { font-size: var(--text-body-md); font-weight: 500; }

	/* ── Search bar ── */
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

	/* ── Match picker list ── */
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

	/* chips */
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

	/* ── Detail view ── */
	.md-back {
		display: flex;
		align-items: center;
		gap: 2px;
		background: none;
		border: none;
		cursor: pointer;
		font: inherit;
		font-size: var(--text-label-md);
		font-weight: 700;
		color: var(--color-primary);
		padding: 0;
		-webkit-tap-highlight-color: transparent;
	}
	.md-back .material-symbols-outlined { font-size: 1rem; }

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

	/* ── Results card ── */
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
</style>
