<script>
	import { onMount }           from 'svelte';
	import { sb }                from '$lib/supabase';
	import { playerRole }        from '$lib/stores/auth';
	import { triggerToast }      from '$lib/stores/toast.js';
	import TournamentMatchCard   from '$lib/components/spielbetrieb/TournamentMatchCard.svelte';
	import BottomSheet           from '$lib/components/BottomSheet.svelte';

	const isAdmin = $derived($playerRole === 'kapitaen');

	let tournaments        = $state([]);
	let loadingTournaments = $state(false);
	let tourneySearch      = $state('');
	let selectedTourney    = $state(null);
	let createOpen         = $state(false);

	let newTitle    = $state('');
	let newDates    = $state(['']);
	let newLocation = $state('');
	let newDeadline = $state('');
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
			t.title?.toLowerCase().includes(q) ||
			t.location?.toLowerCase().includes(q)
		);
	});

	async function loadTournaments() {
		loadingTournaments = true;
		const { data, error } = await sb
			.from('tournaments')
			.select(`id, title, location, status, voting_deadline,
			         tournament_date_options!tournament_id(id, date),
			         tournament_votes!tournament_id(player_id, wants_to_play)`)
			.order('created_at', { ascending: false });
		if (error) triggerToast('Ladefehler: ' + (error.message ?? error.code ?? 'Unbekannt'));
		tournaments = data ?? [];
		loadingTournaments = false;
	}

	async function createTournament() {
		const dates = newDates.filter(d => d);
		if (!newTitle || dates.length === 0) return;
		saving = true;
		const { data: t, error } = await sb.from('tournaments').insert({
			title:           newTitle,
			location:        newLocation || null,
			status:          'voting',
			voting_deadline: newDeadline ? new Date(newDeadline).toISOString() : null,
		}).select().single();
		if (error) { triggerToast('Fehler: ' + (error.message ?? 'Unbekannt')); saving = false; return; }
		await sb.from('tournament_date_options').insert(
			dates.map(d => ({ tournament_id: t.id, date: d }))
		);
		saving = false;
		createOpen = false;
		newTitle = ''; newDates = ['']; newLocation = ''; newDeadline = '';
		await loadTournaments();
		selectedTourney = tournaments.find(x => x.id === t.id) ?? t;
	}

	onMount(() => loadTournaments());
</script>

<div class="sb-page">

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
					{@const statusKey = t.status ?? 'voting'}
					<button class="mp-card tp-card" onclick={() => selectedTourney = t}>
						<div class="mp-card-left">
							<div class="tp-trophy-badge">
								<span class="material-symbols-outlined">military_tech</span>
							</div>
							<h3 class="mp-opponent">{t.title ?? 'Turnier'}</h3>
							{#if t.location}
								<p class="mp-league">
									<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-2px">location_on</span>
									{t.location}
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

	{:else}
		<button class="md-back" onclick={() => { selectedTourney = null; }}>
			<span class="material-symbols-outlined">arrow_back_ios</span>
			Alle Turniere
		</button>

		<TournamentMatchCard tournament={selectedTourney} onReload={loadTournaments} />
	{/if}

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
				<span class="tp-label">Abstimmungs-Deadline</span>
				<input class="tp-input" type="datetime-local" bind:value={newDeadline} />
			</label>

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

<style>
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
	.mp-chevron {
		font-size: 1rem;
		color: var(--color-outline);
		margin-top: 2px;
	}

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
</style>
