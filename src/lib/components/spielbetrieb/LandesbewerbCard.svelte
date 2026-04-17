<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { match, onReload = () => {} } = $props();

	let registrations = $state([]);
	let saving        = $state(false);
	let editOpen      = $state(false);
	let editDeadline  = $state('');
	let editDate      = $state('');
	let editTime      = $state('');

	const isAdmin  = $derived($playerRole === 'kapitaen');
	const deadline = $derived(match.registration_deadline ? new Date(match.registration_deadline) : null);
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
		const { data } = await sb.from('tournament_votes')
			.select('player_id, wants_to_play, players(id, name, photo)')
			.eq('tournament_id', match.id)
			.eq('wants_to_play', true)
			.order('created_at');
		registrations = data ?? [];
	}

	async function register() {
		if (!isOpen || !$playerId || saving) return;
		saving = true;
		const { error } = await sb.from('tournament_votes').upsert({
			tournament_id: match.id,
			player_id: $playerId,
			wants_to_play: true,
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
		const { error } = await sb.from('tournament_votes')
			.delete()
			.eq('tournament_id', match.id)
			.eq('player_id', $playerId);
		saving = false;
		if (error) { triggerToast('Fehler'); return; }
		triggerToast('Abgemeldet');
		await load();
		onReload();
	}

	function openEdit() {
		editDate     = match.date ?? '';
		editTime     = match.time ? String(match.time).slice(0, 5) : '';
		editDeadline = match.registration_deadline ? new Date(match.registration_deadline).toISOString().slice(0, 16) : '';
		editOpen     = true;
	}

	async function saveEdit() {
		saving = true;
		const payload = {
			date: editDate || null,
			time: editTime || null,
			registration_deadline: editDeadline ? new Date(editDeadline).toISOString() : null,
		};
		const { error } = await sb.from('matches').update(payload).eq('id', match.id);
		saving = false;
		if (error) { triggerToast('Fehler beim Speichern'); return; }
		Object.assign(match, payload);
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
			<h2 class="lbw-title">{match.tournament_title ?? 'Landesbewerb'}</h2>
			{#if match.tournament_location}
				<p class="lbw-loc">
					<span class="material-symbols-outlined" style="font-size:0.9rem;vertical-align:-2px">location_on</span>
					{match.tournament_location}
				</p>
			{/if}
			{#if match.date}
				<p class="lbw-date">
					<span class="material-symbols-outlined" style="font-size:0.9rem;vertical-align:-2px">event</span>
					{fmtDate(match.date)}{#if match.time} · {fmtTime(match.time)}{/if}
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
