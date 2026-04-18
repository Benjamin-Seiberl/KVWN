<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { lb, onReload = () => {} } = $props();

	const BEWERB_TYPEN = {
		einzel_ak_herren:        'Einzel AK Herren',
		einzel_ak_damen:         'Einzel AK Damen',
		nachwuchs_u10_maennlich: 'Nachwuchs U10 männlich',
		nachwuchs_u10_weiblich:  'Nachwuchs U10 weiblich',
		nachwuchs_u15_maennlich: 'Nachwuchs U15 männlich',
		nachwuchs_u15_weiblich:  'Nachwuchs U15 weiblich',
		nachwuchs_u19_maennlich: 'Nachwuchs U19 männlich',
		nachwuchs_u19_weiblich:  'Nachwuchs U19 weiblich',
		nachwuchs_u23_maennlich: 'Nachwuchs U23 männlich',
		nachwuchs_u23_weiblich:  'Nachwuchs U23 weiblich',
		ue50_herren:             'Ü50 Herren',
		ue50_damen:              'Ü50 Damen',
		ue60_herren:             'Ü60 Herren',
		ue60_damen:              'Ü60 Damen',
		lm_sprint_herren:        'LM Sprint Herren',
		lm_sprint_damen:         'LM Sprint Damen',
		tandem_mixed:            'Tandem Mixed',
	};

	let registrations = $state([]);
	let saving        = $state(false);
	let editOpen      = $state(false);
	let editDeadline  = $state('');
	let editDate      = $state('');
	let editTime      = $state('');

	const isAdmin  = $derived($playerRole === 'kapitaen');
	const deadline = $derived(lb.registration_deadline ? new Date(lb.registration_deadline) : null);
	const isOpen   = $derived(!deadline || deadline > new Date());
	const myReg    = $derived(registrations.find(r => r.player_id === $playerId));
	const msLeft   = $derived(deadline ? deadline.getTime() - Date.now() : Infinity);
	const isUrgent = $derived(isOpen && deadline && msLeft < 24 * 60 * 60 * 1000 && !myReg);

	const DAY_SHORT = ['So','Mo','Di','Mi','Do','Fr','Sa'];
	const MONTHS    = ['Jän','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];

	function fmtDate(dateStr) {
		if (!dateStr) return '';
		const d = new Date(dateStr + 'T12:00');
		return DAY_SHORT[d.getDay()] + ', ' + d.getDate() + '. ' + MONTHS[d.getMonth()];
	}
	function fmtTime(t) { return t ? String(t).slice(0, 5) + ' Uhr' : ''; }
	function fmtDeadline(d) {
		if (!d) return '';
		return d.toLocaleString('de-AT', { dateStyle: 'medium', timeStyle: 'short' });
	}
	function fmtHoursLeft(ms) {
		if (ms <= 0) return '';
		const h = Math.floor(ms / 3_600_000);
		if (h < 1) return 'unter 1 Stunde';
		if (h === 1) return '1 Stunde';
		return h + ' Stunden';
	}
	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	async function load() {
		const { data } = await sb.from('landesbewerb_registrations')
			.select('player_id, players(id, name, photo)')
			.eq('landesbewerb_id', lb.id)
			.order('created_at');
		registrations = data ?? [];
	}

	async function register() {
		if (!isOpen || !$playerId || saving) return;
		saving = true;
		const { error } = await sb.from('landesbewerb_registrations').upsert({
			landesbewerb_id: lb.id,
			player_id: $playerId,
		});
		saving = false;
		if (error) { triggerToast('Fehler'); return; }
		triggerToast('Angemeldet');
		await load();
		onReload();
	}

	async function unregister() {
		if (!isOpen || !$playerId || saving) return;
		saving = true;
		const { error } = await sb.from('landesbewerb_registrations')
			.delete()
			.eq('landesbewerb_id', lb.id)
			.eq('player_id', $playerId);
		saving = false;
		if (error) { triggerToast('Fehler'); return; }
		triggerToast('Abgemeldet');
		await load();
		onReload();
	}

	function openEdit() {
		editDate     = lb.date ?? '';
		editTime     = lb.time ? String(lb.time).slice(0, 5) : '';
		editDeadline = lb.registration_deadline ? new Date(lb.registration_deadline).toISOString().slice(0, 16) : '';
		editOpen     = true;
	}

	async function saveEdit() {
		saving = true;
		const payload = {
			date: editDate || null,
			time: editTime || null,
			registration_deadline: editDeadline ? new Date(editDeadline).toISOString() : null,
		};
		const { error } = await sb.from('landesbewerbe').update(payload).eq('id', lb.id);
		saving = false;
		if (error) { triggerToast('Fehler beim Speichern'); return; }
		lb = { ...lb, ...payload };
		editOpen = false;
		triggerToast('Aktualisiert');
		onReload();
	}

	onMount(load);
</script>

<div class="lbw">

	<!-- Header -->
	<div class="lbw-hero">
		<div class="lbw-hero-trophy">
			<span class="material-symbols-outlined">workspace_premium</span>
		</div>
		<div class="lbw-hero-info">
			<span class="lbw-typ-badge">{BEWERB_TYPEN[lb.typ] ?? lb.typ}</span>
			<h2 class="lbw-title">{lb.title}</h2>
			{#if lb.location}
				<p class="lbw-loc">
					<span class="material-symbols-outlined" style="font-size:0.9rem;vertical-align:-2px">location_on</span>
					{lb.location}
				</p>
			{/if}
			{#if lb.date}
				<p class="lbw-date">
					<span class="material-symbols-outlined" style="font-size:0.9rem;vertical-align:-2px">event</span>
					{fmtDate(lb.date)}{#if lb.time} · {fmtTime(lb.time)}{/if}
				</p>
			{/if}
		</div>
	</div>

	<!-- Deadline-Banner (urgent) -->
	{#if isUrgent}
		<div class="lbw-deadline-banner lbw-deadline-banner--urgent">
			<span class="material-symbols-outlined">alarm</span>
			<span>Anmeldeschluss in {fmtHoursLeft(msLeft)} — nicht vergessen!</span>
		</div>
	{/if}

	<!-- Anmeldung -->
	<div class="lbw-section">
		<div class="lbw-sec-head">
			<span class="material-symbols-outlined">how_to_reg</span>
			<h3>Anmeldung</h3>
			{#if isOpen}
				<span class="lbw-badge lbw-badge--open">offen</span>
			{:else}
				<span class="lbw-badge lbw-badge--closed">geschlossen</span>
			{/if}
		</div>

		{#if deadline}
			<p class="lbw-deadline-text">
				{#if isOpen}bis{:else}war bis{/if} {fmtDeadline(deadline)}
			</p>
		{/if}

		{#if isOpen}
			{#if myReg}
				<button class="lbw-register-btn lbw-register-btn--active" onclick={unregister} disabled={saving}>
					<span class="material-symbols-outlined">check_circle</span>
					Angemeldet · zum Abmelden tippen
				</button>
			{:else}
				<button class="lbw-register-btn" onclick={register} disabled={saving || !$playerId}>
					<span class="material-symbols-outlined">event_available</span>
					Ich melde mich an
				</button>
			{/if}
		{:else if myReg}
			<div class="lbw-register-btn lbw-register-btn--locked">
				<span class="material-symbols-outlined">check_circle</span>
				Du bist angemeldet
			</div>
		{/if}
	</div>

	<!-- Teilnehmerliste -->
	<div class="lbw-section">
		<div class="lbw-sec-head">
			<span class="material-symbols-outlined">groups</span>
			<h3>Angemeldet ({registrations.length})</h3>
		</div>
		{#if registrations.length === 0}
			<p class="lbw-empty">Noch niemand angemeldet.</p>
		{:else}
			<div class="lbw-players-grid">
				{#each registrations as r}
					{@const pl = r.players}
					{#if pl}
						<div class="lbw-player-chip" class:lbw-player-chip--me={r.player_id === $playerId}>
							{#if imgPath(pl.photo, pl.name)}
								<img src={imgPath(pl.photo, pl.name)} alt="" class="lbw-player-photo" onerror={(e) => e.currentTarget.style.display = 'none'} />
							{:else}
								<div class="lbw-player-photo lbw-player-photo--fallback">
									{(pl.name ?? '?')[0]}
								</div>
							{/if}
							<span class="lbw-player-name">{pl.name}</span>
						</div>
					{/if}
				{/each}
			</div>
		{/if}
	</div>

	<!-- Admin-Aktionen -->
	{#if isAdmin}
		<div class="lbw-admin">
			<button class="lbw-admin-btn" onclick={openEdit}>
				<span class="material-symbols-outlined">edit_calendar</span>
				Termin &amp; Deadline bearbeiten
			</button>
		</div>
	{/if}
</div>

<!-- Admin Edit Sheet -->
<BottomSheet bind:open={editOpen} title="Landesbewerb bearbeiten">
	<div class="lbw-edit-form">
		<label class="tp-field">
			<span class="tp-label">Termin-Datum</span>
			<input class="tp-input" type="date" bind:value={editDate} />
		</label>
		<label class="tp-field">
			<span class="tp-label">Uhrzeit</span>
			<input class="tp-input" type="time" bind:value={editTime} />
		</label>
		<label class="tp-field">
			<span class="tp-label">Anmelde-Deadline</span>
			<input class="tp-input" type="datetime-local" bind:value={editDeadline} />
		</label>
		<button class="tp-save-btn" onclick={saveEdit} disabled={saving}>
			{saving ? 'Speichern…' : 'Speichern'}
		</button>
	</div>
</BottomSheet>

<style>
	.lbw { padding: var(--space-3) var(--space-3) var(--space-8); display: flex; flex-direction: column; gap: var(--space-3); }

	.lbw-hero { background: var(--color-surface-container-lowest); border: 1px solid var(--color-outline-variant); border-radius: var(--radius-xl); padding: var(--space-4); display: flex; gap: var(--space-3); align-items: flex-start; }
	.lbw-hero-trophy { width: 48px; height: 48px; border-radius: var(--radius-full); background: linear-gradient(135deg, #4a90d9, #a8d4f5); display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
	.lbw-hero-trophy .material-symbols-outlined { font-size: 1.5rem; color: #1a3a5c; font-variation-settings: 'FILL' 1; }
	.lbw-hero-info { flex: 1; min-width: 0; }
	.lbw-typ-badge { display: inline-block; font-family: var(--font-display); font-size: 0.6rem; font-weight: 800; letter-spacing: 0.06em; text-transform: uppercase; background: rgba(25, 118, 210, 0.1); color: #1565c0; border-radius: var(--radius-full); padding: 2px 8px; margin-bottom: 4px; }
	.lbw-title { font-family: var(--font-display); font-size: var(--text-title-md); font-weight: 800; color: var(--color-on-surface); margin: 0 0 3px; }
	.lbw-loc, .lbw-date { display: flex; align-items: center; gap: 3px; font-size: var(--text-body-sm); color: var(--color-on-surface-variant); margin: 2px 0 0; }

	.lbw-deadline-banner { display: flex; align-items: center; gap: 8px; padding: 10px 14px; border-radius: 12px; font-size: 0.85rem; font-weight: 600; background: rgba(212, 175, 55, 0.12); color: #7a5a00; border: 1px solid rgba(212, 175, 55, 0.3); }
	.lbw-deadline-banner--urgent { background: rgba(204, 0, 0, 0.08); color: var(--color-primary); border-color: rgba(204, 0, 0, 0.25); animation: pulse-border 1.5s ease-in-out infinite; }
	.lbw-deadline-banner .material-symbols-outlined { font-size: 1.1rem; font-variation-settings: 'FILL' 1; flex-shrink: 0; }
	@keyframes pulse-border { 0%, 100% { box-shadow: 0 0 0 0 rgba(204,0,0,0.15); } 50% { box-shadow: 0 0 0 4px rgba(204,0,0,0.08); } }

	.lbw-section { background: var(--color-surface-container-lowest); border: 1px solid var(--color-outline-variant); border-radius: var(--radius-xl); padding: var(--space-4); }
	.lbw-sec-head { display: flex; align-items: center; gap: var(--space-2); margin-bottom: var(--space-3); }
	.lbw-sec-head .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); font-variation-settings: 'FILL' 1; }
	.lbw-sec-head h3 { font-family: var(--font-display); font-size: var(--text-label-lg); font-weight: 800; color: var(--color-on-surface); margin: 0; flex: 1; }
	.lbw-badge { font-family: var(--font-display); font-size: 0.6rem; font-weight: 800; letter-spacing: 0.05em; text-transform: uppercase; padding: 2px 8px; border-radius: var(--radius-full); }
	.lbw-badge--open   { background: rgba(46, 125, 50, 0.12); color: #2e7d32; }
	.lbw-badge--closed { background: rgba(0,0,0,0.07); color: var(--color-on-surface-variant); }

	.lbw-deadline-text { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); margin: 0 0 var(--space-3); }
	.lbw-empty { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); margin: 0; }

	.lbw-register-btn { width: 100%; display: flex; align-items: center; justify-content: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); border-radius: var(--radius-full); border: 2px solid var(--color-primary); background: var(--color-primary); color: #fff; font-family: var(--font-display); font-size: var(--text-label-lg); font-weight: 800; cursor: pointer; transition: opacity 150ms; -webkit-tap-highlight-color: transparent; }
	.lbw-register-btn:disabled { opacity: 0.5; cursor: default; }
	.lbw-register-btn .material-symbols-outlined { font-size: 1.1rem; font-variation-settings: 'FILL' 1; }
	.lbw-register-btn--active { background: rgba(46,125,50,0.1); color: #2e7d32; border-color: #2e7d32; }
	.lbw-register-btn--locked { background: rgba(0,0,0,0.05); color: var(--color-on-surface-variant); border-color: var(--color-outline-variant); cursor: default; }

	.lbw-players-grid { display: flex; flex-wrap: wrap; gap: var(--space-2); }
	.lbw-player-chip { display: flex; align-items: center; gap: var(--space-2); padding: 4px 10px 4px 4px; background: var(--color-surface-container); border-radius: var(--radius-full); border: 1.5px solid var(--color-outline-variant); }
	.lbw-player-chip--me { border-color: var(--color-primary); background: rgba(204,0,0,0.05); }
	.lbw-player-photo { width: 28px; height: 28px; border-radius: var(--radius-full); object-fit: cover; object-position: top center; background: var(--color-surface-container-high); flex-shrink: 0; }
	.lbw-player-photo--fallback { display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-weight: 800; font-size: 0.8rem; color: var(--color-on-surface-variant); background: var(--color-surface-container-high); }
	.lbw-player-name { font-family: var(--font-display); font-size: var(--text-body-sm); font-weight: 700; color: var(--color-on-surface); }

	.lbw-admin { display: flex; flex-direction: column; gap: var(--space-2); }
	.lbw-admin-btn { display: flex; align-items: center; justify-content: center; gap: var(--space-2); padding: var(--space-3); border-radius: var(--radius-full); border: 1.5px solid rgba(204,0,0,0.2); background: rgba(204,0,0,0.04); color: var(--color-primary); font-family: var(--font-display); font-size: var(--text-label-lg); font-weight: 700; cursor: pointer; -webkit-tap-highlight-color: transparent; }
	.lbw-admin-btn .material-symbols-outlined { font-size: 1rem; font-variation-settings: 'FILL' 1; }

	.lbw-edit-form { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-2) 0 var(--space-4); }
</style>
