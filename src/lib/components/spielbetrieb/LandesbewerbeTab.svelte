<script>
	import { onMount }      from 'svelte';
	import { sb }           from '$lib/supabase';
	import { playerRole }   from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr } from '$lib/utils/dates.js';
	import { BEWERB_TYPEN } from '$lib/constants/competitions.js';
	import LandesbewerbCard from '$lib/components/spielbetrieb/LandesbewerbCard.svelte';
	import BottomSheet      from '$lib/components/BottomSheet.svelte';

	const isAdmin = $derived($playerRole === 'kapitaen');

	let landesbewerbe    = $state([]);
	let loadingLandes    = $state(false);
	let landesSearch     = $state('');
	let selectedLandes   = $state(null);
	let landesCreateOpen = $state(false);
	let detailOpen       = $state(false);

	let landesTitle    = $state('');
	let landesTyp      = $state('einzel_ak_herren');
	let landesDate     = $state('');
	let landesTime     = $state('');
	let landesLocation = $state('');
	let landesDeadline = $state('');
	let landesSaving   = $state(false);

	const filteredLandes = $derived.by(() => {
		const q = landesSearch.toLowerCase().trim();
		if (!q) return landesbewerbe;
		return landesbewerbe.filter(t =>
			t.title?.toLowerCase().includes(q) ||
			t.location?.toLowerCase().includes(q) ||
			(t.date && t.date.includes(q))
		);
	});

	async function loadLandesbewerbe() {
		loadingLandes = true;
		const { data, error } = await sb
			.from('landesbewerbe')
			.select('id, title, typ, location, date, time, registration_deadline, landesbewerb_registrations!landesbewerb_id(player_id)')
			.order('date', { ascending: false });
		if (error) triggerToast('Ladefehler: ' + (error.message ?? error.code ?? 'Unbekannt'));
		landesbewerbe = data ?? [];
		if (selectedLandes) {
			selectedLandes = landesbewerbe.find(l => l.id === selectedLandes.id) ?? selectedLandes;
		}
		loadingLandes = false;
	}

	async function createLandesbewerb() {
		if (!landesTitle || !landesDeadline) return;
		landesSaving = true;
		const { data, error } = await sb.from('landesbewerbe').insert({
			title:                 landesTitle,
			typ:                   landesTyp,
			location:              landesLocation || null,
			date:                  landesDate || null,
			time:                  landesTime || null,
			registration_deadline: new Date(landesDeadline).toISOString(),
		}).select().single();
		landesSaving = false;
		if (error) { triggerToast('Fehler: ' + (error.message ?? 'Unbekannt')); return; }
		landesCreateOpen = false;
		landesTitle = ''; landesTyp = 'einzel_ak_herren'; landesDate = ''; landesTime = ''; landesLocation = ''; landesDeadline = '';
		await loadLandesbewerbe();
		selectedLandes = landesbewerbe.find(l => l.id === data.id) ?? data;
		detailOpen = true;
	}

	onMount(() => loadLandesbewerbe());
</script>

<div class="sb-page">

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
					{@const regCount = (t.landesbewerb_registrations ?? []).length}
					{@const dl = t.registration_deadline ? new Date(t.registration_deadline) : null}
					{@const regOpen = dl && dl > new Date()}
					<button class="mp-card" class:mp-card--past={t.date && t.date < toDateStr(new Date())} onclick={() => { selectedLandes = t; detailOpen = true; }}>
						<div class="mp-card-left">
							<div class="tp-trophy-badge tp-trophy-badge--landes">
								<span class="material-symbols-outlined">workspace_premium</span>
							</div>
							<h3 class="mp-opponent">{t.title ?? 'Landesbewerb'}</h3>
							{#if t.location}
								<p class="mp-league">
									<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-2px">location_on</span>
									{t.location}
								</p>
							{/if}
							{#if dl}
								<div class="tp-card-meta">
									{#if regOpen}
										<span class="tp-status-badge tp-status-badge--voting">Anmeldung offen</span>
									{:else}
										<span class="tp-status-badge tp-status-badge--voting_closed">Geschlossen</span>
									{/if}
									{#if regCount > 0}
										<span class="tp-yes-count">
											<span class="material-symbols-outlined" style="font-size:0.75rem;vertical-align:-1px">how_to_reg</span>
											{regCount} Anmeldung{regCount !== 1 ? 'en' : ''}
										</span>
									{/if}
								</div>
							{/if}
						</div>
						<div class="mp-card-right">
							{#if t.date}<span class="mp-date">{fmtDate(t.date)}</span>{/if}
							{#if t.time}<span class="mp-time">{fmtTime(t.time)}</span>{/if}
							<span class="material-symbols-outlined mp-chevron">chevron_right</span>
						</div>
					</button>
				{/each}
			</div>
		{/if}

	<BottomSheet bind:open={landesCreateOpen} title="Landesbewerb erstellen">
		<div class="tp-form">
			<label class="tp-field">
				<span class="tp-label">Titel *</span>
				<input class="tp-input" type="text" placeholder="z.B. NÖ Landesmeisterschaft 2026" bind:value={landesTitle} />
			</label>
			<label class="tp-field">
				<span class="tp-label">Bewerbstyp *</span>
				<select class="tp-input" bind:value={landesTyp}>
					{#each BEWERB_TYPEN as bt}
						<option value={bt.key}>{bt.label}</option>
					{/each}
				</select>
			</label>
			<label class="tp-field">
				<span class="tp-label">Anmelde-Deadline *</span>
				<input class="tp-input" type="datetime-local" bind:value={landesDeadline} />
			</label>
			<label class="tp-field">
				<span class="tp-label">Datum</span>
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
				disabled={!landesTitle || !landesDeadline || landesSaving}
			>
				{landesSaving ? 'Speichern…' : 'Landesbewerb anlegen'}
			</button>
		</div>
	</BottomSheet>

	<BottomSheet bind:open={detailOpen} title={selectedLandes?.title ?? 'Landesbewerb'}>
		{#if selectedLandes}
			<LandesbewerbCard lb={selectedLandes} onReload={loadLandesbewerbe} />
		{/if}
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

</style>
