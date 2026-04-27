<script>
	import { onMount }              from 'svelte';
	import { sb }                   from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast }         from '$lib/stores/toast.js';
	import { fmtDate, toDateStr }   from '$lib/utils/dates.js';
	import { imgPath, BLANK_IMG }   from '$lib/utils/players.js';
	import TournamentMatchCard      from '$lib/components/spielbetrieb/TournamentMatchCard.svelte';
	import BottomSheet              from '$lib/components/BottomSheet.svelte';

	// ── State ─────────────────────────────────────────────────────────────────
	let tournaments       = $state([]);
	let activePlayerCount = $state(0);
	let loading           = $state(true);
	let showPast          = $state(false);

	let selectedTourney   = $state(null);
	let detailOpen        = $state(false);

	// Create-Sheet (Kapitän)
	let createOpen = $state(false);
	let newTitle    = $state('');
	let newDates    = $state(['']);
	let newLocation = $state('');
	let newDeadline = $state('');
	let saving      = $state(false);

	const isAdmin = $derived($playerRole === 'kapitaen');
	const today   = toDateStr(new Date());

	// ── Load ──────────────────────────────────────────────────────────────────
	async function load() {
		loading = true;
		try {
			const [{ data: tData, error: tErr }, { count: pCount, error: pErr }] = await Promise.all([
				sb.from('tournaments')
					.select(`
						id, title, location, status, voting_deadline, confirmed_date, created_at,
						tournament_date_options!tournament_id(id, date),
						tournament_votes!tournament_id(player_id, wants_to_play, players(id, name, photo))
					`)
					.order('created_at', { ascending: false }),
				sb.from('players').select('id', { count: 'exact', head: true }).eq('active', true),
			]);
			if (tErr) { triggerToast('Fehler: ' + tErr.message); return; }
			if (pErr) { triggerToast('Fehler: ' + pErr.message); return; }
			tournaments       = tData ?? [];
			activePlayerCount = pCount ?? 0;
			// Wenn Detail-Sheet offen ist: aktualisieren.
			if (selectedTourney) {
				selectedTourney = tournaments.find(t => t.id === selectedTourney.id) ?? selectedTourney;
			}
		} finally {
			loading = false;
		}
	}

	onMount(load);

	// ── Helpers ───────────────────────────────────────────────────────────────
	/** Frühestes anstehendes oder das bestätigte Datum eines Turniers. */
	function tourneyAnchorDate(t) {
		if (t.confirmed_date) return t.confirmed_date;
		const opts = (t.tournament_date_options ?? [])
			.map(o => o.date)
			.filter(Boolean)
			.sort();
		const future = opts.find(d => d >= today);
		return future ?? opts.at(-1) ?? null;
	}

	/** „Aktiv": noch nicht beendet (kein confirmed_date in der Vergangenheit
	 *   und Status nicht 'confirmed' mit ausschließlich vergangenen Terminen). */
	function isPastTourney(t) {
		const anchor = tourneyAnchorDate(t);
		if (anchor && anchor < today) return true;
		// status 'confirmed' aber kein confirmed_date → behalten als aktiv,
		// damit Kapitän es noch sieht. Spielplan/voting_closed bleibt aktiv.
		return false;
	}

	function tourneyDateLabel(t) {
		if (t.confirmed_date) return fmtDate(t.confirmed_date);
		const opts = (t.tournament_date_options ?? [])
			.map(o => o.date)
			.filter(Boolean)
			.sort();
		const future = opts.filter(d => d >= today);
		const list   = future.length ? future : opts;
		if (list.length === 0) return 'Termin offen';
		if (list.length === 1) return fmtDate(list[0]);
		if (list.length === 2) return fmtDate(list[0]) + ' / ' + fmtDate(list[1]);
		return fmtDate(list[0]) + ' +' + (list.length - 1);
	}

	function statusKeyOf(t)   { return t.status ?? 'voting'; }
	function statusLabelOf(t) {
		return ({
			voting:        'Abstimmung läuft',
			voting_closed: 'Abstimmung beendet',
			scheduling:    'Spielplan',
			confirmed:     'Bestätigt',
		})[statusKeyOf(t)] ?? 'Status';
	}

	function yesPlayersOf(t) {
		return (t.tournament_votes ?? [])
			.filter(v => v.wants_to_play && v.players)
			.map(v => v.players);
	}

	function myVoteOf(t) {
		return (t.tournament_votes ?? []).find(v => v.player_id === $playerId) ?? null;
	}

	function votingOpenOf(t) {
		const key = statusKeyOf(t);
		if (key !== 'voting') return false;
		if (t.voting_deadline && new Date(t.voting_deadline) < new Date()) return false;
		return true;
	}

	// ── Filter ────────────────────────────────────────────────────────────────
	const activeTourneys = $derived(tournaments.filter(t => !isPastTourney(t)));
	const pastTourneys   = $derived(tournaments.filter(t =>  isPastTourney(t)));

	// ── Aktionen ──────────────────────────────────────────────────────────────
	function openDetail(t, e) {
		e?.stopPropagation?.();
		selectedTourney = t;
		detailOpen = true;
	}

	function handleCardKey(e, t) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			openDetail(t);
		}
	}

	let wasDetailOpen = false;
	$effect(() => {
		if (wasDetailOpen && !detailOpen) load();
		wasDetailOpen = detailOpen;
	});

	function addDateField()    { if (newDates.length < 5) newDates = [...newDates, '']; }
	function removeDateField(i){ newDates = newDates.filter((_, idx) => idx !== i); }

	async function createTournament() {
		const dates = newDates.filter(d => d);
		if (!newTitle || dates.length === 0) return;
		saving = true;
		try {
			const { data: t, error } = await sb.from('tournaments').insert({
				title:           newTitle,
				location:        newLocation || null,
				status:          'voting',
				voting_deadline: newDeadline ? new Date(newDeadline).toISOString() : null,
			}).select().single();
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			const { error: dErr } = await sb.from('tournament_date_options').insert(
				dates.map(d => ({ tournament_id: t.id, date: d }))
			);
			if (dErr) { triggerToast('Fehler: ' + dErr.message); return; }
			createOpen = false;
			newTitle = ''; newDates = ['']; newLocation = ''; newDeadline = '';
			await load();
			selectedTourney = tournaments.find(x => x.id === t.id) ?? t;
			detailOpen = true;
		} finally {
			saving = false;
		}
	}
</script>

<div class="tt-page">
	{#if loading}
		<!-- Skeleton ─────────────────────────────────────────────────────────── -->
		<div class="tt-loading">
			<div class="shimmer-box tt-skel tt-skel--head"></div>
			<div class="shimmer-box tt-skel tt-skel--card"></div>
			<div class="shimmer-box tt-skel tt-skel--card"></div>
		</div>
	{:else}

		<!-- ── Header (Kapitän: Plus-Button) ─────────────────────────────────── -->
		<header class="tt-page-head">
			<div class="tt-head-left">
				<span class="material-symbols-outlined tt-head-icon">emoji_events</span>
				<h2 class="tt-head-title">Aktive Turniere</h2>
			</div>
			{#if isAdmin}
				<button
					class="tt-add-btn"
					type="button"
					aria-label="Turnier erstellen"
					onclick={() => createOpen = true}
				>
					<span class="material-symbols-outlined">add</span>
				</button>
			{/if}
		</header>

		{#if activeTourneys.length === 0}
			<!-- Empty-State ─────────────────────────────────────────────────── -->
			<div class="mw-card tt-empty">
				<span class="material-symbols-outlined tt-empty-icon">military_tech</span>
				<p class="tt-empty-text">Keine aktiven Turniere</p>
				{#if isAdmin}
					<button class="mw-btn mw-btn--primary" type="button" onclick={() => createOpen = true}>
						<span class="material-symbols-outlined">add_circle</span>
						Turnier erstellen
					</button>
				{/if}
			</div>
		{:else}
			<!-- Aktive Turnier-Cards ────────────────────────────────────────── -->
			<div class="tt-cards">
				{#each activeTourneys as t (t.id)}
					{@const yes        = yesPlayersOf(t)}
					{@const yesCount   = yes.length}
					{@const total      = activePlayerCount}
					{@const my         = myVoteOf(t)}
					{@const myStatus   = my == null ? 'pending' : my.wants_to_play ? 'confirmed' : 'declined'}
					{@const myLabel    = myStatus === 'pending'
						? 'Noch offen'
						: myStatus === 'confirmed'
							? 'Zugesagt'
							: 'Abgelehnt'}
					{@const votingOpen = votingOpenOf(t)}
					{@const lineupSet  = statusKeyOf(t) === 'confirmed'}
					{@const showVoteAction = votingOpen && myStatus === 'pending'}
					{@const showLineupHint = !lineupSet && (statusKeyOf(t) === 'voting_closed' || statusKeyOf(t) === 'scheduling')}

					<article
						class="mw-card tt-card animate-fade-float"
						role="button"
						tabindex="0"
						aria-label={`Turnier ${t.title ?? ''} am ${tourneyDateLabel(t)}. ${statusLabelOf(t)}. ${yesCount} von ${total} angemeldet. Mein Status: ${myLabel}.`}
						onclick={() => openDetail(t)}
						onkeydown={(e) => handleCardKey(e, t)}
					>
						<!-- Header: Trophy + Titel + Status -->
						<div class="tt-card-head">
							<div class="tt-trophy">
								<span class="material-symbols-outlined">military_tech</span>
							</div>
							<div class="tt-head-info">
								<h3 class="tt-card-title">{t.title ?? 'Turnier'}</h3>
								<p class="tt-card-meta">
									<span class="tt-card-when">{tourneyDateLabel(t)}</span>
									{#if t.location}
										<span class="tt-card-sep">·</span>
										<span class="tt-card-loc">
											<span class="material-symbols-outlined tt-loc-icon">location_on</span>
											{t.location}
										</span>
									{/if}
								</p>
							</div>
							<span class="mw-badge tt-status-badge tt-status-badge--{statusKeyOf(t)}">
								{statusLabelOf(t)}
							</span>
						</div>

						<div class="tt-divider"></div>

						<!-- Counter + Roster-Mini -->
						<div class="tt-roster">
							<div class="tt-counter">
								<span class="material-symbols-outlined tt-counter-icon">groups</span>
								<span class="tt-counter-num">{yesCount}<span class="tt-counter-total">/{total}</span></span>
								<span class="tt-counter-label">angemeldet</span>
							</div>
							{#if yes.length > 0}
								<div class="tt-avatars" aria-hidden="true">
									{#each yes.slice(0, 3) as pl (pl.id)}
										<img
											class="tt-avatar"
											src={imgPath(pl.photo, pl.name)}
											alt=""
											draggable="false"
											onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}
										/>
									{/each}
									{#if yes.length > 3}
										<span class="tt-avatar tt-avatar--more">+{yes.length - 3}</span>
									{/if}
								</div>
							{/if}
						</div>

						<!-- Mein Status (Outer-Card-Klick öffnet Detail-Sheet) -->
						<div
							class="tt-mine tt-mine--{myStatus}"
							class:tt-mine--locked={!votingOpen}
						>
							<span class="material-symbols-outlined tt-mine-icon">
								{#if myStatus === 'confirmed'}check_circle
								{:else if myStatus === 'declined'}cancel
								{:else}radio_button_unchecked{/if}
							</span>
							<span class="tt-mine-label">{myLabel}</span>
							{#if votingOpen}
								<span class="material-symbols-outlined tt-mine-chevron">chevron_right</span>
							{:else}
								<span class="material-symbols-outlined tt-mine-chevron">lock</span>
							{/if}
						</div>

						<!-- Offene-Aktionen-Strip (Spieler) -->
						{#if showVoteAction || showLineupHint}
							<div class="tt-actions" aria-live="polite">
								{#if showVoteAction}
									<span class="material-symbols-outlined tt-actions-icon">how_to_vote</span>
									<span class="tt-actions-text">Du musst noch abstimmen</span>
								{:else if showLineupHint}
									<span class="material-symbols-outlined tt-actions-icon">schedule</span>
									<span class="tt-actions-text">Aufstellung steht noch nicht</span>
								{/if}
							</div>
						{/if}

						<!-- Kapitän: Verwalten -->
						{#if isAdmin}
							<div class="tt-admin-row">
								<button
									type="button"
									class="mw-btn mw-btn--soft tt-admin-btn"
									aria-label={`Turnier verwalten: ${t.title ?? ''}`}
									onclick={(e) => openDetail(t, e)}
								>
									<span class="material-symbols-outlined">settings</span>
									Verwalten
								</button>
							</div>
						{/if}
					</article>
				{/each}
			</div>
		{/if}

		<!-- ── Frühere anzeigen ─────────────────────────────────────────────── -->
		{#if pastTourneys.length > 0}
			<div class="tt-past-toggle-wrap">
				<button
					class="tt-past-toggle"
					type="button"
					aria-expanded={showPast}
					onclick={() => showPast = !showPast}
				>
					<span class="material-symbols-outlined">{showPast ? 'expand_less' : 'expand_more'}</span>
					{showPast ? 'Frühere ausblenden' : `Frühere anzeigen (${pastTourneys.length})`}
				</button>
			</div>

			{#if showPast}
				<div class="tt-cards tt-cards--past">
					{#each pastTourneys as t (t.id)}
						{@const yesCount = yesPlayersOf(t).length}
						<article
							class="mw-card tt-card tt-card--past"
							role="button"
							tabindex="0"
							aria-label={`Vergangenes Turnier ${t.title ?? ''} am ${tourneyDateLabel(t)}.`}
							onclick={() => openDetail(t)}
							onkeydown={(e) => handleCardKey(e, t)}
						>
							<div class="tt-card-head">
								<div class="tt-trophy tt-trophy--past">
									<span class="material-symbols-outlined">military_tech</span>
								</div>
								<div class="tt-head-info">
									<h3 class="tt-card-title">{t.title ?? 'Turnier'}</h3>
									<p class="tt-card-meta">
										<span class="tt-card-when">{tourneyDateLabel(t)}</span>
										{#if yesCount > 0}
											<span class="tt-card-sep">·</span>
											<span>{yesCount} Teilnehmer</span>
										{/if}
									</p>
								</div>
								<span class="material-symbols-outlined tt-chevron">chevron_right</span>
							</div>
						</article>
					{/each}
				</div>
			{/if}
		{/if}

	{/if}
</div>

<!-- ── Detail-Sheet (Voten/Verwalten) ───────────────────────────────────── -->
<BottomSheet bind:open={detailOpen} title={selectedTourney?.title ?? 'Turnier'}>
	{#if selectedTourney}
		<TournamentMatchCard tournament={selectedTourney} onReload={load} />
	{/if}
</BottomSheet>

<!-- ── Create-Sheet (Kapitän) ───────────────────────────────────────────── -->
<BottomSheet bind:open={createOpen} title="Turnier erstellen">
	<div class="tt-form">
		<label class="tt-field">
			<span class="tt-label">Turniername *</span>
			<input class="tt-input" type="text" placeholder="z.B. NÖ-Cup 2026" bind:value={newTitle} />
		</label>

		<div class="tt-field">
			<span class="tt-label">Mögliche Tage *</span>
			{#each newDates as d, i}
				<div class="tt-date-row">
					<input class="tt-input tt-date-input" type="date" bind:value={newDates[i]} />
					{#if newDates.length > 1}
						<button
							class="tt-date-remove"
							type="button"
							aria-label="Datum entfernen"
							onclick={() => removeDateField(i)}
						>
							<span class="material-symbols-outlined">close</span>
						</button>
					{/if}
				</div>
			{/each}
			{#if newDates.length < 5}
				<button class="tt-add-date-btn" type="button" onclick={addDateField}>
					<span class="material-symbols-outlined">add</span>
					Datum hinzufügen
				</button>
			{/if}
		</div>

		<label class="tt-field">
			<span class="tt-label">Abstimmungs-Frist</span>
			<input class="tt-input" type="datetime-local" bind:value={newDeadline} />
		</label>

		<label class="tt-field">
			<span class="tt-label">Ort</span>
			<input class="tt-input" type="text" placeholder="z.B. Sportanlage Wiener Neustadt" bind:value={newLocation} />
		</label>

		<button
			class="mw-btn mw-btn--primary mw-btn--wide"
			type="button"
			onclick={createTournament}
			disabled={!newTitle || !newDates.some(d => d) || saving}
		>
			{saving ? 'Speichern…' : 'Turnier anlegen'}
		</button>
	</div>
</BottomSheet>

<style>
	/* ── Page-Frame ───────────────────────────────────────────────────────── */
	.tt-page {
		padding: var(--space-4) 0 calc(var(--nav-height) + var(--space-5));
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.tt-loading {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding: 0 var(--space-4);
	}
	.tt-skel { border-radius: var(--radius-lg); }
	.tt-skel--head { height: 32px; width: 60%; }
	.tt-skel--card { height: 200px; }

	/* ── Page-Header ──────────────────────────────────────────────────────── */
	.tt-page-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: 0 var(--space-5);
	}
	.tt-head-left {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.tt-head-icon {
		font-size: 1.2rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tt-head-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-md);
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.tt-add-btn {
		width: 44px;
		height: 44px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary);
		color: var(--color-on-primary);
		border: none;
		border-radius: var(--radius-full);
		cursor: pointer;
		transition: transform 120ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.tt-add-btn:active { transform: scale(0.92); }
	.tt-add-btn:focus-visible { outline: 2px solid var(--color-primary); outline-offset: 2px; }
	.tt-add-btn .material-symbols-outlined {
		font-size: 1.3rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	/* ── Card-Liste ───────────────────────────────────────────────────────── */
	.tt-cards {
		display: flex;
		flex-direction: column;
	}
	.tt-cards :global(.mw-card) {
		margin: 0 var(--space-4) var(--space-3);
	}

	/* ── Empty-State ──────────────────────────────────────────────────────── */
	.tt-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-6) var(--space-4);
		text-align: center;
	}
	.tt-empty-icon {
		font-size: 1.6rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tt-empty-text {
		margin: 0;
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
	}

	/* ── Card ─────────────────────────────────────────────────────────────── */
	.tt-card {
		display: flex;
		flex-direction: column;
		cursor: pointer;
		text-align: left;
		font: inherit;
		-webkit-tap-highlight-color: transparent;
		transition: transform 120ms ease, box-shadow 120ms ease;
	}
	.tt-card:active  { transform: scale(0.985); }
	.tt-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.tt-card--past { opacity: 0.78; }

	.tt-card-head {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.tt-trophy {
		width: 40px;
		height: 40px;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-full);
		background: linear-gradient(135deg, var(--color-secondary), color-mix(in srgb, var(--color-secondary) 35%, white));
	}
	.tt-trophy .material-symbols-outlined {
		font-size: 1.25rem;
		color: color-mix(in srgb, var(--color-secondary) 70%, black);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tt-trophy--past {
		background: var(--color-surface-container);
	}
	.tt-trophy--past .material-symbols-outlined {
		color: var(--color-on-surface-variant);
	}

	.tt-head-info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.tt-card-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.tt-card-meta {
		margin: 0;
		display: flex;
		align-items: center;
		gap: var(--space-2);
		flex-wrap: wrap;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.tt-card-when { font-weight: 700; }
	.tt-card-sep  { color: var(--color-outline); }
	.tt-card-loc {
		display: inline-flex;
		align-items: center;
		gap: 2px;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.tt-loc-icon {
		font-size: 0.85rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.tt-status-badge {
		flex-shrink: 0;
		font-size: 0.62rem;
	}
	.tt-status-badge--voting {
		background: color-mix(in srgb, var(--color-primary) 12%, white);
		color: var(--color-primary);
	}
	.tt-status-badge--voting_closed {
		background: var(--color-surface-container);
		color: var(--color-on-surface-variant);
	}
	.tt-status-badge--scheduling {
		background: color-mix(in srgb, var(--color-secondary) 16%, white);
		color: color-mix(in srgb, var(--color-secondary) 80%, black);
	}
	.tt-status-badge--confirmed {
		background: color-mix(in srgb, var(--color-success) 12%, white);
		color: var(--color-success);
	}

	.tt-chevron {
		font-size: 1.1rem;
		color: var(--color-outline);
		flex-shrink: 0;
	}

	.tt-divider {
		border-top: 1px solid var(--color-outline-variant);
		margin: var(--space-3) 0;
	}

	/* ── Counter + Roster-Mini ────────────────────────────────────────────── */
	.tt-roster {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.tt-counter {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-width: 0;
	}
	.tt-counter-icon {
		font-size: 1.05rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.tt-counter-num {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		color: var(--color-on-surface);
	}
	.tt-counter-total {
		font-weight: 700;
		color: var(--color-on-surface-variant);
	}
	.tt-counter-label {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.04em;
		color: var(--color-on-surface-variant);
	}

	.tt-avatars {
		display: flex;
		align-items: center;
		flex-shrink: 0;
	}
	.tt-avatar {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-full);
		object-fit: cover;
		object-position: top center;
		border: 2px solid var(--color-surface-container-lowest);
		background: var(--color-surface-container);
		margin-left: -8px;
		flex-shrink: 0;
	}
	.tt-avatar:first-child { margin-left: 0; }
	.tt-avatar--more {
		display: flex;
		align-items: center;
		justify-content: center;
		font-family: var(--font-display);
		font-size: 0.7rem;
		font-weight: 800;
		color: var(--color-on-surface-variant);
		background: var(--color-surface-container);
	}

	/* ── Mein-Status-Bar ──────────────────────────────────────────────────── */
	.tt-mine {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-height: 44px;
		margin-top: var(--space-3);
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		cursor: pointer;
		font-family: var(--font-body);
		font-size: var(--text-label-md);
		font-weight: 700;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease, transform 80ms ease;
	}
	.tt-mine:active { transform: scale(0.98); }
	.tt-mine:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.tt-mine-icon {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.tt-mine-label {
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.tt-mine-chevron {
		font-size: 1rem;
		opacity: 0.7;
		flex-shrink: 0;
	}
	.tt-mine--pending {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		color: var(--color-primary);
		box-shadow: inset 3px 0 0 var(--color-primary);
	}
	.tt-mine--confirmed {
		background: color-mix(in srgb, var(--color-success) 10%, transparent);
		color: var(--color-success);
		box-shadow: inset 3px 0 0 var(--color-success);
	}
	.tt-mine--declined {
		background: var(--color-surface-container);
		color: var(--color-on-surface-variant);
		box-shadow: inset 3px 0 0 var(--color-outline-variant);
	}
	.tt-mine--locked {
		cursor: pointer; /* öffnet trotzdem Detail */
		opacity: 0.85;
	}

	/* ── Offene-Aktionen-Strip ────────────────────────────────────────────── */
	.tt-actions {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-height: 36px;
		margin-top: var(--space-2);
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--color-secondary) 14%, white);
		color: color-mix(in srgb, var(--color-secondary) 80%, black);
		border-left: 3px solid var(--color-secondary);
		border-radius: var(--radius-md);
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
	}
	.tt-actions-icon {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.tt-actions-text {
		flex: 1;
		min-width: 0;
	}

	/* ── Kapitän: Verwalten-Button ────────────────────────────────────────── */
	.tt-admin-row {
		display: flex;
		justify-content: flex-end;
		margin-top: var(--space-3);
	}
	.tt-admin-btn {
		min-height: 36px;
		padding: var(--space-2) var(--space-3);
		font-size: var(--text-label-sm);
		-webkit-tap-highlight-color: transparent;
	}
	.tt-admin-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	/* ── Frühere anzeigen ─────────────────────────────────────────────────── */
	.tt-past-toggle-wrap {
		padding: 0 var(--space-4);
		margin-top: var(--space-2);
	}
	.tt-past-toggle {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-height: 44px;
		padding: var(--space-2) var(--space-3);
		background: transparent;
		color: var(--color-on-surface-variant);
		border: none;
		border-radius: var(--radius-md);
		cursor: pointer;
		font-family: var(--font-body);
		font-size: var(--text-label-md);
		font-weight: 700;
		-webkit-tap-highlight-color: transparent;
	}
	.tt-past-toggle:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.tt-past-toggle .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	/* ── Create-Form ──────────────────────────────────────────────────────── */
	.tt-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5) var(--space-6);
	}
	.tt-field {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.tt-label {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.tt-input {
		width: 100%;
		padding: var(--space-3);
		background: var(--color-surface-container);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		font: inherit;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		box-sizing: border-box;
		transition: border-color 150ms ease, box-shadow 150ms ease;
	}
	.tt-input:focus {
		outline: none;
		border-color: color-mix(in srgb, var(--color-primary) 50%, transparent);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 12%, transparent);
	}
	.tt-date-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin-bottom: 6px;
	}
	.tt-date-input { flex: 1; }
	.tt-date-remove {
		width: 36px;
		height: 36px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-surface-container);
		border: none;
		border-radius: var(--radius-md);
		color: var(--color-on-surface-variant);
		cursor: pointer;
		flex-shrink: 0;
	}
	.tt-date-remove:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.tt-add-date-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		min-height: 36px;
		padding: 0 var(--space-3);
		background: transparent;
		border: 1.5px dashed var(--color-outline-variant);
		border-radius: var(--radius-md);
		color: var(--color-on-surface-variant);
		cursor: pointer;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
	}
	.tt-add-date-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.tt-add-date-btn .material-symbols-outlined { font-size: 1rem; }
</style>
