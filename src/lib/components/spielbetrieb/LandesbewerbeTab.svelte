<script>
	import { onMount }                    from 'svelte';
	import { sb }                         from '$lib/supabase';
	import { playerId, playerRole }       from '$lib/stores/auth';
	import { triggerToast }               from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { BEWERB_TYPEN, BEWERB_LABEL } from '$lib/constants/competitions.js';
	import LandesbewerbCard               from '$lib/components/spielbetrieb/LandesbewerbCard.svelte';
	import BottomSheet                    from '$lib/components/BottomSheet.svelte';

	// ── State ─────────────────────────────────────────────────────────────────
	let landesbewerbe     = $state([]);
	let activePlayerCount = $state(0);
	let loading           = $state(true);
	let showPast          = $state(false);

	let selectedLandes    = $state(null);
	let detailOpen        = $state(false);

	// Create-Sheet (Kapitän)
	let createOpen     = $state(false);
	let landesTitle    = $state('');
	let landesTyp      = $state('einzel_ak_herren');
	let landesDate     = $state('');
	let landesTime     = $state('');
	let landesLocation = $state('');
	let landesDeadline = $state('');
	let saving         = $state(false);

	const isAdmin = $derived($playerRole === 'kapitaen');
	const today   = toDateStr(new Date());

	// ── Load ──────────────────────────────────────────────────────────────────
	async function load() {
		loading = true;
		try {
			const [{ data: lData, error: lErr }, { count: pCount, error: pErr }] = await Promise.all([
				sb.from('landesbewerbe')
					.select(`
						id, title, typ, location, date, time, registration_deadline,
						landesbewerb_registrations!landesbewerb_id(player_id)
					`)
					.order('date', { ascending: true, nullsFirst: false }),
				sb.from('players').select('id', { count: 'exact', head: true }).eq('active', true),
			]);
			if (lErr) { triggerToast('Fehler: ' + lErr.message); return; }
			if (pErr) { triggerToast('Fehler: ' + pErr.message); return; }
			landesbewerbe     = lData ?? [];
			activePlayerCount = pCount ?? 0;
			if (selectedLandes) {
				selectedLandes = landesbewerbe.find(l => l.id === selectedLandes.id) ?? selectedLandes;
			}
		} finally {
			loading = false;
		}
	}

	onMount(load);

	// ── Helpers ───────────────────────────────────────────────────────────────
	/** Aktiv = Termin in Zukunft, ohne Termin → Frist in Zukunft. */
	function isPastLB(l) {
		if (l.date && l.date < today) return true;
		if (!l.date && l.registration_deadline) {
			return new Date(l.registration_deadline) < new Date();
		}
		return false;
	}

	function regCountOf(l)   { return (l.landesbewerb_registrations ?? []).length; }
	function deadlineDateOf(l){ return l.registration_deadline ? new Date(l.registration_deadline) : null; }
	function deadlineDayStr(l) {
		const d = deadlineDateOf(l);
		return d ? toDateStr(d) : null;
	}

	function myRegOf(l) {
		return (l.landesbewerb_registrations ?? []).some(r => r.player_id === $playerId);
	}

	function myStatusOf(l) {
		// Es gibt nur "angemeldet" oder "offen" — keine explizite Absage.
		return myRegOf(l) ? 'confirmed' : 'pending';
	}

	// ── Filter ────────────────────────────────────────────────────────────────
	const activeLandes = $derived(landesbewerbe.filter(l => !isPastLB(l)));
	const pastLandes   = $derived(landesbewerbe.filter(l =>  isPastLB(l)));

	// ── Aktionen ──────────────────────────────────────────────────────────────
	function openDetail(l, e) {
		e?.stopPropagation?.();
		selectedLandes = l;
		detailOpen = true;
	}

	function handleCardKey(e, l) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			openDetail(l);
		}
	}

	let wasDetailOpen = false;
	$effect(() => {
		if (wasDetailOpen && !detailOpen) load();
		wasDetailOpen = detailOpen;
	});

	async function createLandesbewerb() {
		if (!landesTitle || !landesDeadline) return;
		saving = true;
		const { data, error } = await sb.from('landesbewerbe').insert({
			title:                 landesTitle,
			typ:                   landesTyp,
			location:              landesLocation || null,
			date:                  landesDate || null,
			time:                  landesTime || null,
			registration_deadline: new Date(landesDeadline).toISOString(),
		}).select().single();
		saving = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		createOpen = false;
		landesTitle = ''; landesTyp = 'einzel_ak_herren';
		landesDate = '';  landesTime = '';
		landesLocation = ''; landesDeadline = '';
		await load();
		selectedLandes = landesbewerbe.find(l => l.id === data.id) ?? data;
		detailOpen = true;
	}
</script>

<div class="lt-page">
	{#if loading}
		<!-- Skeleton ─────────────────────────────────────────────────────────── -->
		<div class="lt-loading">
			<div class="shimmer-box lt-skel lt-skel--head"></div>
			<div class="shimmer-box lt-skel lt-skel--card"></div>
			<div class="shimmer-box lt-skel lt-skel--card"></div>
		</div>
	{:else}

		<!-- ── Header ────────────────────────────────────────────────────────── -->
		<header class="lt-page-head">
			<div class="lt-head-left">
				<span class="material-symbols-outlined lt-head-icon">workspace_premium</span>
				<h2 class="lt-head-title">Aktive Landesbewerbe</h2>
			</div>
			{#if isAdmin}
				<button
					class="lt-add-btn"
					type="button"
					aria-label="Landesbewerb erstellen"
					onclick={() => createOpen = true}
				>
					<span class="material-symbols-outlined">add</span>
				</button>
			{/if}
		</header>

		{#if activeLandes.length === 0}
			<!-- Empty-State ─────────────────────────────────────────────────── -->
			<div class="mw-card lt-empty">
				<span class="material-symbols-outlined lt-empty-icon">workspace_premium</span>
				<p class="lt-empty-text">Keine aktiven Landesbewerbe</p>
				{#if isAdmin}
					<button class="mw-btn mw-btn--primary" type="button" onclick={() => createOpen = true}>
						<span class="material-symbols-outlined">add_circle</span>
						Landesbewerb erstellen
					</button>
				{/if}
			</div>
		{:else}
			<!-- Aktive Landesbewerb-Cards ───────────────────────────────────── -->
			<div class="lt-cards">
				{#each activeLandes as l (l.id)}
					{@const reg          = regCountOf(l)}
					{@const total        = activePlayerCount}
					{@const myStatus     = myStatusOf(l)}
					{@const myLabel      = myStatus === 'confirmed' ? 'Angemeldet' : 'Noch offen'}
					{@const dlStr        = deadlineDayStr(l)}
					{@const dlDays       = dlStr ? daysUntil(dlStr) : null}
					{@const dlOpen       = deadlineDateOf(l) ? deadlineDateOf(l) > new Date() : true}
					{@const dlUrgent     = dlOpen && dlDays != null && dlDays <= 2}
					{@const showVoteHint = dlOpen && myStatus === 'pending'}
					{@const typLabel     = BEWERB_LABEL[l.typ] ?? l.typ ?? '—'}

					<article
						class="mw-card lt-card animate-fade-float"
						role="button"
						tabindex="0"
						aria-label={`Landesbewerb ${l.title ?? ''}, ${typLabel}${l.date ? `, am ${fmtDate(l.date)}` : ''}. ${reg} von ${total} angemeldet. Mein Status: ${myLabel}.`}
						onclick={() => openDetail(l)}
						onkeydown={(e) => handleCardKey(e, l)}
					>
						<!-- Header: Trophy + Titel + Disziplin + Termin -->
						<div class="lt-card-head">
							<div class="lt-trophy">
								<span class="material-symbols-outlined">workspace_premium</span>
							</div>
							<div class="lt-head-info">
								<h3 class="lt-card-title">{l.title ?? 'Landesbewerb'}</h3>
								<p class="lt-card-meta">
									<span class="lt-typ-badge">{typLabel}</span>
									{#if l.date}
										<span class="lt-card-sep">·</span>
										<span class="lt-card-when">
											{fmtDate(l.date)}{l.time ? ' · ' + fmtTime(l.time) : ''}
										</span>
									{/if}
								</p>
								{#if l.location}
									<p class="lt-card-loc">
										<span class="material-symbols-outlined lt-loc-icon">location_on</span>
										{l.location}
									</p>
								{/if}
							</div>
						</div>

						<div class="lt-divider"></div>

						<!-- Counter + Frist-Countdown -->
						<div class="lt-stats">
							<div class="lt-counter">
								<span class="material-symbols-outlined lt-counter-icon">how_to_reg</span>
								<span class="lt-counter-num">{reg}<span class="lt-counter-total">/{total}</span></span>
								<span class="lt-counter-label">angemeldet</span>
							</div>
							{#if dlStr}
								<div class="lt-frist" class:lt-frist--urgent={dlUrgent} class:lt-frist--past={!dlOpen}>
									<span class="material-symbols-outlined lt-frist-icon">alarm</span>
									{#if !dlOpen}
										<span>Frist abgelaufen</span>
									{:else if dlDays === 0}
										<span>Frist heute</span>
									{:else if dlDays === 1}
										<span>Frist morgen</span>
									{:else}
										<span>Frist in {dlDays} Tagen</span>
									{/if}
								</div>
							{/if}
						</div>

						<!-- Mein Status (Outer-Card-Klick öffnet Detail-Sheet) -->
						<div
							class="lt-mine lt-mine--{myStatus}"
						>
							<span class="material-symbols-outlined lt-mine-icon">
								{#if myStatus === 'confirmed'}check_circle
								{:else}radio_button_unchecked{/if}
							</span>
							<span class="lt-mine-label">{myLabel}</span>
							{#if dlOpen}
								<span class="material-symbols-outlined lt-mine-chevron">chevron_right</span>
							{:else}
								<span class="material-symbols-outlined lt-mine-chevron">lock</span>
							{/if}
						</div>

						<!-- Offene-Aktionen-Strip -->
						{#if showVoteHint}
							<div class="lt-actions" aria-live="polite">
								<span class="material-symbols-outlined lt-actions-icon">how_to_reg</span>
								<span class="lt-actions-text">
									{dlUrgent ? 'Frist endet bald — bitte anmelden' : 'Du musst dich noch anmelden'}
								</span>
							</div>
						{/if}

						<!-- Kapitän: Verwalten -->
						{#if isAdmin}
							<div class="lt-admin-row">
								<button
									type="button"
									class="mw-btn mw-btn--soft lt-admin-btn"
									aria-label={`Landesbewerb verwalten: ${l.title ?? ''}`}
									onclick={(e) => openDetail(l, e)}
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
		{#if pastLandes.length > 0}
			<div class="lt-past-toggle-wrap">
				<button
					class="lt-past-toggle"
					type="button"
					aria-expanded={showPast}
					onclick={() => showPast = !showPast}
				>
					<span class="material-symbols-outlined">{showPast ? 'expand_less' : 'expand_more'}</span>
					{showPast ? 'Frühere ausblenden' : `Frühere anzeigen (${pastLandes.length})`}
				</button>
			</div>

			{#if showPast}
				<div class="lt-cards lt-cards--past">
					{#each pastLandes as l (l.id)}
						{@const reg = regCountOf(l)}
						{@const typLabel = BEWERB_LABEL[l.typ] ?? l.typ ?? '—'}
						<article
							class="mw-card lt-card lt-card--past"
							role="button"
							tabindex="0"
							aria-label={`Vergangener Landesbewerb ${l.title ?? ''}.`}
							onclick={() => openDetail(l)}
							onkeydown={(e) => handleCardKey(e, l)}
						>
							<div class="lt-card-head">
								<div class="lt-trophy lt-trophy--past">
									<span class="material-symbols-outlined">workspace_premium</span>
								</div>
								<div class="lt-head-info">
									<h3 class="lt-card-title">{l.title ?? 'Landesbewerb'}</h3>
									<p class="lt-card-meta">
										<span class="lt-typ-badge">{typLabel}</span>
										{#if l.date}
											<span class="lt-card-sep">·</span>
											<span class="lt-card-when">{fmtDate(l.date)}</span>
										{/if}
										{#if reg > 0}
											<span class="lt-card-sep">·</span>
											<span>{reg} angemeldet</span>
										{/if}
									</p>
								</div>
								<span class="material-symbols-outlined lt-chevron">chevron_right</span>
							</div>
						</article>
					{/each}
				</div>
			{/if}
		{/if}

	{/if}
</div>

<!-- ── Detail-Sheet (An-/Abmelden / Verwalten) ──────────────────────────── -->
<BottomSheet bind:open={detailOpen} title={selectedLandes?.title ?? 'Landesbewerb'}>
	{#if selectedLandes}
		<LandesbewerbCard lb={selectedLandes} onReload={load} />
	{/if}
</BottomSheet>

<!-- ── Create-Sheet (Kapitän) ───────────────────────────────────────────── -->
<BottomSheet bind:open={createOpen} title="Landesbewerb erstellen">
	<div class="lt-form">
		<label class="lt-field">
			<span class="lt-label">Titel *</span>
			<input class="lt-input" type="text" placeholder="z.B. NÖ Landesmeisterschaft 2026" bind:value={landesTitle} />
		</label>
		<label class="lt-field">
			<span class="lt-label">Bewerbstyp *</span>
			<select class="lt-input" bind:value={landesTyp}>
				{#each BEWERB_TYPEN as bt (bt.key)}
					<option value={bt.key}>{bt.label}</option>
				{/each}
			</select>
		</label>
		<label class="lt-field">
			<span class="lt-label">Anmelde-Frist *</span>
			<input class="lt-input" type="datetime-local" bind:value={landesDeadline} />
		</label>
		<label class="lt-field">
			<span class="lt-label">Datum</span>
			<input class="lt-input" type="date" bind:value={landesDate} />
		</label>
		<label class="lt-field">
			<span class="lt-label">Uhrzeit</span>
			<input class="lt-input" type="time" bind:value={landesTime} />
		</label>
		<label class="lt-field">
			<span class="lt-label">Ort</span>
			<input class="lt-input" type="text" placeholder="z.B. Sportzentrum Wiener Neustadt" bind:value={landesLocation} />
		</label>
		<button
			class="mw-btn mw-btn--primary mw-btn--wide"
			type="button"
			onclick={createLandesbewerb}
			disabled={!landesTitle || !landesDeadline || saving}
		>
			{saving ? 'Speichern…' : 'Landesbewerb anlegen'}
		</button>
	</div>
</BottomSheet>

<style>
	/* ── Page-Frame ───────────────────────────────────────────────────────── */
	.lt-page {
		padding: var(--space-4) 0 calc(var(--nav-height) + var(--space-5));
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.lt-loading {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding: 0 var(--space-4);
	}
	.lt-skel { border-radius: var(--radius-lg); }
	.lt-skel--head { height: 32px; width: 70%; }
	.lt-skel--card { height: 220px; }

	/* ── Page-Header ──────────────────────────────────────────────────────── */
	.lt-page-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: 0 var(--space-5);
	}
	.lt-head-left {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.lt-head-icon {
		font-size: 1.2rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lt-head-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-md);
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.lt-add-btn {
		width: 44px;
		height: 44px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary);
		color: #fff;
		border: none;
		border-radius: var(--radius-full);
		cursor: pointer;
		transition: transform 120ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.lt-add-btn:active { transform: scale(0.92); }
	.lt-add-btn:focus-visible { outline: 2px solid var(--color-primary); outline-offset: 2px; }
	.lt-add-btn .material-symbols-outlined {
		font-size: 1.3rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	/* ── Card-Liste ───────────────────────────────────────────────────────── */
	.lt-cards {
		display: flex;
		flex-direction: column;
	}
	.lt-cards :global(.mw-card) {
		margin: 0 var(--space-4) var(--space-3);
	}

	/* ── Empty-State ──────────────────────────────────────────────────────── */
	.lt-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-6) var(--space-4);
		text-align: center;
	}
	.lt-empty-icon {
		font-size: 1.6rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lt-empty-text {
		margin: 0;
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
	}

	/* ── Card ─────────────────────────────────────────────────────────────── */
	.lt-card {
		display: flex;
		flex-direction: column;
		cursor: pointer;
		text-align: left;
		font: inherit;
		-webkit-tap-highlight-color: transparent;
		transition: transform 120ms ease, box-shadow 120ms ease;
	}
	.lt-card:active { transform: scale(0.985); }
	.lt-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lt-card--past { opacity: 0.78; }

	.lt-card-head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
	}
	.lt-trophy {
		width: 40px;
		height: 40px;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-full);
		background: linear-gradient(135deg, var(--color-secondary), color-mix(in srgb, var(--color-secondary) 35%, white));
	}
	.lt-trophy .material-symbols-outlined {
		font-size: 1.25rem;
		color: color-mix(in srgb, var(--color-secondary) 70%, black);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lt-trophy--past {
		background: var(--color-surface-container);
	}
	.lt-trophy--past .material-symbols-outlined {
		color: var(--color-on-surface-variant);
	}

	.lt-head-info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.lt-card-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.lt-card-meta {
		margin: 0;
		display: flex;
		align-items: center;
		gap: var(--space-2);
		flex-wrap: wrap;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.lt-card-when { font-weight: 700; }
	.lt-card-sep  { color: var(--color-outline); }
	.lt-typ-badge {
		display: inline-block;
		font-family: var(--font-display);
		font-size: 0.62rem;
		font-weight: 800;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		background: color-mix(in srgb, var(--color-primary) 10%, white);
		color: var(--color-primary);
		border-radius: var(--radius-full);
		padding: 2px 8px;
	}
	.lt-card-loc {
		margin: 2px 0 0;
		display: flex;
		align-items: center;
		gap: 2px;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.lt-loc-icon {
		font-size: 0.85rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.lt-chevron {
		font-size: 1.1rem;
		color: var(--color-outline);
		flex-shrink: 0;
	}

	.lt-divider {
		border-top: 1px solid var(--color-outline-variant);
		margin: var(--space-3) 0;
	}

	/* ── Counter + Frist ──────────────────────────────────────────────────── */
	.lt-stats {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.lt-counter {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-width: 0;
	}
	.lt-counter-icon {
		font-size: 1.05rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.lt-counter-num {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		color: var(--color-on-surface);
	}
	.lt-counter-total {
		font-weight: 700;
		color: var(--color-on-surface-variant);
	}
	.lt-counter-label {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.04em;
		color: var(--color-on-surface-variant);
	}

	.lt-frist {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
	}
	.lt-frist-icon {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.lt-frist--urgent {
		color: var(--color-primary);
		font-weight: 800;
	}
	.lt-frist--past {
		color: var(--color-outline);
	}

	/* ── Mein-Status-Bar ──────────────────────────────────────────────────── */
	.lt-mine {
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
	.lt-mine:active { transform: scale(0.98); }
	.lt-mine:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lt-mine-icon {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.lt-mine-label {
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.lt-mine-chevron {
		font-size: 1rem;
		opacity: 0.7;
		flex-shrink: 0;
	}
	.lt-mine--pending {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		color: var(--color-primary);
		box-shadow: inset 3px 0 0 var(--color-primary);
	}
	.lt-mine--confirmed {
		background: color-mix(in srgb, var(--color-success) 10%, transparent);
		color: var(--color-success);
		box-shadow: inset 3px 0 0 var(--color-success);
	}

	/* ── Offene-Aktionen-Strip ────────────────────────────────────────────── */
	.lt-actions {
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
	.lt-actions-icon {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.lt-actions-text {
		flex: 1;
		min-width: 0;
	}

	/* ── Kapitän: Verwalten ───────────────────────────────────────────────── */
	.lt-admin-row {
		display: flex;
		justify-content: flex-end;
		margin-top: var(--space-3);
	}
	.lt-admin-btn {
		min-height: 36px;
		padding: var(--space-2) var(--space-3);
		font-size: var(--text-label-sm);
		-webkit-tap-highlight-color: transparent;
	}
	.lt-admin-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	/* ── Frühere anzeigen ─────────────────────────────────────────────────── */
	.lt-past-toggle-wrap {
		padding: 0 var(--space-4);
		margin-top: var(--space-2);
	}
	.lt-past-toggle {
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
	.lt-past-toggle:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lt-past-toggle .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	/* ── Create-Form ──────────────────────────────────────────────────────── */
	.lt-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5) var(--space-6);
	}
	.lt-field {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.lt-label {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.lt-input {
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
	.lt-input:focus {
		outline: none;
		border-color: color-mix(in srgb, var(--color-primary) 50%, transparent);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 12%, transparent);
	}
</style>
