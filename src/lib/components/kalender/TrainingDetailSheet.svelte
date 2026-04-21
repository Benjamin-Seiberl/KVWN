<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { imgPath, shortName } from '$lib/utils/players.js';
	import { toDateStr, MONTH_FULL } from '$lib/utils/dates.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { open = $bindable(false), date = null, onReload = null } = $props();

	const WEEKDAY_LONG = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];

	let templates = $state([]);
	let specials  = $state([]);
	let overrides = $state([]);
	let bookings  = $state([]);
	let waitlist  = $state([]);
	let keyDuty   = $state(null);
	let players   = $state([]);
	let loading   = $state(false);
	let saving    = $state(false);

	let selectedStart = $state(null);

	// ── Load when sheet opens on a date ─────────────────────────────────────
	$effect(() => {
		if (open && date) loadSheet();
		else if (!open) { selectedStart = null; }
	});

	async function loadSheet() {
		loading = true;
		try {
			const dow = new Date(date + 'T12:00:00').getDay();
			const [tpls, sps, ovs, bks, wl, kd, pls] = await Promise.all([
				sb.from('training_templates').select('*').eq('active', true).eq('day_of_week', dow),
				sb.from('training_specials').select('*').eq('date', date),
				sb.from('training_overrides').select('*').eq('date', date),
				sb.from('training_bookings').select('id, start_time, player_id').eq('date', date),
				sb.from('training_waitlist').select('id, start_time, player_id, position').eq('date', date).order('position'),
				sb.from('training_key_duties').select('start_time, player_id, players(name, photo)').eq('date', date).maybeSingle(),
				sb.from('players').select('id, name, photo'),
			]);
			if (tpls.error || sps.error || ovs.error || bks.error || wl.error || kd.error || pls.error) {
				triggerToast('Fehler: ' + (tpls.error ?? sps.error ?? ovs.error ?? bks.error ?? wl.error ?? kd.error ?? pls.error).message);
				return;
			}
			templates = tpls.data ?? [];
			specials  = sps.data ?? [];
			overrides = ovs.data ?? [];
			bookings  = bks.data ?? [];
			waitlist  = wl.data ?? [];
			keyDuty   = kd.data ?? null;
			players   = pls.data ?? [];
		} finally {
			loading = false;
		}
	}

	// ── Slot expansion ──────────────────────────────────────────────────────
	const slots = $derived.by(() => {
		const out = [];
		for (const t of templates) {
			const sh = Number(String(t.start_time).slice(0, 2));
			const eh = Number(String(t.end_time).slice(0, 2));
			for (let h = sh; h < eh; h++) {
				const startTime = `${String(h).padStart(2,'0')}:00:00`;
				const ov = overrides.find(o => String(o.start_time).slice(0,5) === startTime.slice(0,5));
				if (ov?.closed) continue;
				out.push({
					start_time: startTime,
					end_time:   `${String(h+1).padStart(2,'0')}:00:00`,
					capacity:   t.lane_count,
					note:       ov?.note ?? null,
					isSpecial:  false,
				});
			}
		}
		for (const s of specials) {
			const ov = overrides.find(o => String(o.start_time).slice(0,5) === String(s.start_time).slice(0,5));
			if (ov?.closed) continue;
			out.push({
				start_time: s.start_time,
				end_time:   s.end_time,
				capacity:   s.capacity,
				note:       s.note ?? ov?.note ?? null,
				isSpecial:  true,
			});
		}
		out.sort((a, b) => a.start_time.localeCompare(b.start_time));
		return out;
	});

	// Auto-select first slot on load
	$effect(() => {
		if (slots.length && !selectedStart) selectedStart = slots[0].start_time;
	});

	// ── Derived helpers ─────────────────────────────────────────────────────
	function bookingsForStart(start) {
		return bookings.filter(b => String(b.start_time).slice(0,5) === String(start).slice(0,5));
	}
	function waitlistForStart(start) {
		return waitlist.filter(w => String(w.start_time).slice(0,5) === String(start).slice(0,5));
	}
	function getPlayer(id) {
		return players.find(p => p.id === id);
	}
	function occRatio(start, capacity) {
		return capacity > 0 ? bookingsForStart(start).length / capacity : 0;
	}
	function pillColor(r) {
		if (r <= 0.6) return '#16a34a';
		if (r <  1.0) return '#ea580c';
		return '#dc2626';
	}

	const selectedSlot = $derived(slots.find(s => s.start_time === selectedStart) ?? null);
	const myBooking   = $derived(selectedSlot ? bookingsForStart(selectedStart).find(b => b.player_id === $playerId) ?? null : null);
	const myWait      = $derived(selectedSlot ? waitlistForStart(selectedStart).find(w => w.player_id === $playerId) ?? null : null);
	const slotRatio   = $derived(selectedSlot ? occRatio(selectedStart, selectedSlot.capacity) : 0);
	const isSameDayOrPast = $derived(!!date && date <= toDateStr(new Date()));

	const titleLabel = $derived(date ? 'Training am ' + WEEKDAY_LONG[new Date(date + 'T12:00:00').getDay()] : 'Training');
	const subtitle   = $derived.by(() => {
		if (!date) return '';
		const d = new Date(date + 'T12:00:00');
		return d.getDate() + '. ' + MONTH_FULL[d.getMonth()];
	});

	// ── Keyholder actions (one per day, stored on first slot's start_time) ─
	async function takeKey() {
		if (!$playerId || !slots.length) return;
		saving = true;
		const startKey = slots[0].start_time;
		const { error } = await sb.from('training_key_duties').upsert({ date, start_time: startKey, player_id: $playerId });
		if (error) triggerToast('Fehler: ' + error.message);
		else       triggerToast('Schlüssel-Dienst übernommen');
		await loadSheet();
		saving = false;
	}
	async function releaseKey() {
		if (!keyDuty) return;
		saving = true;
		const { error } = await sb.from('training_key_duties').delete().eq('date', date).eq('start_time', keyDuty.start_time).eq('player_id', $playerId);
		if (error) triggerToast('Fehler: ' + error.message);
		else       triggerToast('Schlüssel-Dienst freigegeben');
		await loadSheet();
		saving = false;
	}

	// ── Booking actions ─────────────────────────────────────────────────────
	async function book() {
		if (!selectedSlot || saving) return;
		saving = true;
		const { data, error } = await sb.rpc('book_training_slot', {
			p_date:  date,
			p_start: selectedSlot.start_time,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
		} else if (data?.status === 'booked') {
			triggerToast('Gebucht');
		} else if (data?.status === 'waitlisted') {
			triggerToast('Auf Warteliste (Position ' + data.position + ')');
		} else if (data?.status === 'already_booked') {
			triggerToast('Bereits gebucht');
		} else if (data?.status === 'already_waitlisted') {
			triggerToast('Bereits auf Warteliste');
		}
		await loadSheet();
		onReload?.();
		saving = false;
	}

	async function storno() {
		if (!myBooking || saving) return;
		saving = true;
		const { data, error } = await sb.rpc('cancel_training_booking', { p_booking_id: myBooking.id });
		if (error) {
			if (error.message.includes('same_day_storno_forbidden')) {
				triggerToast('Storno am selben Tag nicht mehr möglich');
			} else {
				triggerToast('Fehler: ' + error.message);
			}
		} else {
			triggerToast('Storniert');
			const promoted = data?.promoted_player_id;
			if (promoted) {
				try {
					await fetch('/api/push/notify', {
						method: 'POST',
						headers: { 'content-type': 'application/json' },
						body: JSON.stringify({
							player_ids: [promoted],
							title: 'Nachgerückt!',
							body: 'Du bist nachgerückt! Dein Training um ' + String(data.start_time).slice(0,5) + ' Uhr ist gesichert.',
							url: '/kalender',
						}),
					});
				} catch {}
			}
		}
		await loadSheet();
		onReload?.();
		saving = false;
	}

	async function leaveWaitlist() {
		if (!myWait || saving) return;
		saving = true;
		const { error } = await sb.from('training_waitlist').delete().eq('id', myWait.id);
		if (error) triggerToast('Fehler: ' + error.message);
		else       triggerToast('Von Warteliste abgemeldet');
		await loadSheet();
		onReload?.();
		saving = false;
	}

	function keyDutyPlayer() {
		if (!keyDuty) return null;
		return { name: keyDuty.players?.name, photo: keyDuty.players?.photo, id: keyDuty.player_id };
	}
</script>

<BottomSheet bind:open title={titleLabel}>
	{#if loading}
		<div class="tds-loading">
			<div class="shimmer-box tds-skel"></div>
			<div class="shimmer-box tds-skel tds-skel--short"></div>
			<div class="shimmer-box tds-skel"></div>
		</div>
	{:else if !slots.length}
		<div class="tds-empty">
			<span class="material-symbols-outlined">event_busy</span>
			<p>Kein Training an diesem Tag</p>
		</div>
	{:else}
		<p class="tds-subtitle">{subtitle}</p>

		<!-- ── Keyholder card ────────────────────────────────────────────── -->
		<div class="tds-key-card" class:tds-key-card--taken={!!keyDuty}>
			<span class="material-symbols-outlined tds-key-icon">key</span>
			{#if !keyDuty}
				<div class="tds-key-body">
					<span class="tds-key-label">Schlüssel-Dienst offen</span>
					<span class="tds-key-sub">Niemand hat den Schlüssel übernommen</span>
				</div>
				<button class="mw-btn mw-btn--soft" onclick={takeKey} disabled={saving || !$playerId}>
					Ich übernehme
				</button>
			{:else}
				{@const kp = keyDutyPlayer()}
				<img class="tds-key-avatar" src={imgPath(kp?.photo, kp?.name)} alt={kp?.name ?? ''} draggable="false" onerror={(e) => e.currentTarget.style.display='none'} />
				<div class="tds-key-body">
					<span class="tds-key-label">{shortName(kp?.name)}</span>
					<span class="tds-key-sub">sperrt auf</span>
				</div>
				{#if keyDuty.player_id === $playerId}
					<button class="tds-key-release" onclick={releaseKey} disabled={saving}>Freigeben</button>
				{/if}
			{/if}
		</div>

		<!-- ── Heatmap pills ─────────────────────────────────────────────── -->
		<p class="tds-section-title">Zeitslots</p>
		<div class="tds-pills">
			{#each slots as s}
				{@const r = occRatio(s.start_time, s.capacity)}
				{@const active = s.start_time === selectedStart}
				<button
					class="tds-pill"
					class:tds-pill--active={active}
					style="--pill-color:{pillColor(r)};"
					onclick={() => selectedStart = s.start_time}
				>
					<span class="tds-pill-time">{String(s.start_time).slice(0,5)}</span>
					<span class="tds-pill-load">{bookingsForStart(s.start_time).length}/{s.capacity}</span>
					{#if s.isSpecial}<span class="tds-pill-badge">Sonder</span>{/if}
				</button>
			{/each}
		</div>

		<!-- ── Selected slot body ────────────────────────────────────────── -->
		{#if selectedSlot}
			<div class="tds-slot-head">
				<span class="tds-slot-time">
					{String(selectedSlot.start_time).slice(0,5)} – {String(selectedSlot.end_time).slice(0,5)} Uhr
				</span>
				{#if selectedSlot.note}
					<span class="tds-slot-note">{selectedSlot.note}</span>
				{/if}
			</div>

			<!-- Bookings -->
			<p class="tds-section-title tds-section-title--sub">Gebucht ({bookingsForStart(selectedStart).length}/{selectedSlot.capacity})</p>
			{#if bookingsForStart(selectedStart).length === 0}
				<p class="tds-empty-sub">Noch niemand gebucht</p>
			{:else}
				<div class="tds-player-list">
					{#each bookingsForStart(selectedStart) as b}
						{@const pl = getPlayer(b.player_id)}
						<div class="tds-player-row" class:tds-player-row--me={b.player_id === $playerId}>
							<img src={imgPath(pl?.photo, pl?.name)} alt={pl?.name ?? ''} draggable="false" onerror={(e) => e.currentTarget.style.display='none'} />
							<span>{shortName(pl?.name)}</span>
							{#if b.player_id === $playerId}<span class="tds-me-chip">Du</span>{/if}
						</div>
					{/each}
				</div>
			{/if}

			<!-- Waitlist -->
			{#if waitlistForStart(selectedStart).length > 0}
				<p class="tds-section-title tds-section-title--sub">Warteliste</p>
				<div class="tds-player-list">
					{#each waitlistForStart(selectedStart) as w}
						{@const pl = getPlayer(w.player_id)}
						<div class="tds-player-row tds-player-row--wait" class:tds-player-row--me={w.player_id === $playerId}>
							<span class="tds-wait-pos">{w.position}.</span>
							<img src={imgPath(pl?.photo, pl?.name)} alt={pl?.name ?? ''} draggable="false" onerror={(e) => e.currentTarget.style.display='none'} />
							<span>{shortName(pl?.name)}</span>
							{#if w.player_id === $playerId}<span class="tds-me-chip">Du</span>{/if}
						</div>
					{/each}
				</div>
			{/if}

			<!-- ── Action button ─────────────────────────────────────────── -->
			<div class="tds-action-wrap">
				{#if myBooking}
					<button
						class="mw-btn mw-btn--wide tds-btn-storno"
						onclick={storno}
						disabled={saving || isSameDayOrPast}
					>
						Storno
					</button>
					{#if isSameDayOrPast}
						<p class="tds-hint">Storno am selben Tag nicht mehr möglich.</p>
					{/if}
				{:else if myWait}
					<button
						class="mw-btn mw-btn--wide mw-btn--ghost"
						onclick={leaveWaitlist}
						disabled={saving}
					>
						Von Warteliste abmelden
					</button>
					<p class="tds-hint">Du bist auf Position {myWait.position} der Warteliste.</p>
				{:else if slotRatio >= 1}
					<button
						class="mw-btn mw-btn--wide tds-btn-waitlist"
						onclick={book}
						disabled={saving || !$playerId}
					>
						Auf die Warteliste
					</button>
				{:else}
					<button
						class="mw-btn mw-btn--wide mw-btn--primary"
						onclick={book}
						disabled={saving || !$playerId}
					>
						Buchen
					</button>
				{/if}
			</div>
		{/if}
	{/if}
</BottomSheet>

<style>
	.tds-loading { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-4) 0; }
	.tds-skel { height: 56px; border-radius: var(--radius-lg); }
	.tds-skel--short { height: 32px; }

	.tds-empty { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.tds-empty .material-symbols-outlined { font-size: 2.5rem; opacity: 0.5; }
	.tds-empty p { font-size: var(--text-body-md); font-weight: 500; margin: 0; }
	.tds-empty-sub { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin: 0 0 var(--space-3); }

	.tds-subtitle { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin: 0 0 var(--space-4); }

	/* Keyholder card */
	.tds-key-card {
		display: flex; align-items: center; gap: var(--space-3);
		background: var(--color-surface-container);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		padding: var(--space-3) var(--space-4);
		margin-bottom: var(--space-5);
	}
	.tds-key-card--taken { background: rgba(212,175,55,0.08); border-color: rgba(212,175,55,0.4); }
	.tds-key-icon {
		font-size: 1.5rem; color: var(--color-secondary, #D4AF37);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tds-key-avatar {
		width: 36px; height: 36px; border-radius: 50%; object-fit: cover; object-position: top center;
		border: 2px solid var(--color-secondary, #D4AF37);
	}
	.tds-key-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.tds-key-label { font-family: var(--font-display); font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); }
	.tds-key-sub   { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); }
	.tds-key-release {
		background: transparent; border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md); padding: 4px 10px;
		font-size: var(--text-label-sm); font-weight: 700;
		color: var(--color-on-surface-variant); cursor: pointer;
	}
	.tds-key-release:active { transform: scale(0.95); }

	/* Section titles */
	.tds-section-title {
		font-family: var(--font-display);
		font-size: var(--text-label-sm); font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-2);
	}
	.tds-section-title--sub { margin-top: var(--space-4); }

	/* Heatmap pills */
	.tds-pills {
		display: flex; gap: var(--space-2);
		overflow-x: auto; scrollbar-width: none;
		padding: 2px 0 var(--space-3);
	}
	.tds-pills::-webkit-scrollbar { display: none; }

	.tds-pill {
		position: relative;
		flex-shrink: 0;
		display: flex; flex-direction: column; align-items: center; gap: 2px;
		min-width: 72px;
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-lg);
		border: 2px solid var(--pill-color, var(--color-outline-variant));
		background: color-mix(in srgb, var(--pill-color, var(--color-outline-variant)) 12%, transparent);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: transform 100ms ease, box-shadow 150ms ease;
		font: inherit;
	}
	.tds-pill:active { transform: scale(0.95); }
	.tds-pill--active {
		background: var(--pill-color, var(--color-primary));
		box-shadow: 0 4px 12px color-mix(in srgb, var(--pill-color, var(--color-primary)) 40%, transparent);
	}
	.tds-pill-time {
		font-family: var(--font-display);
		font-weight: 800; font-size: var(--text-label-md);
		color: var(--pill-color, var(--color-on-surface));
	}
	.tds-pill--active .tds-pill-time { color: #fff; }
	.tds-pill-load {
		font-size: 0.7rem; font-weight: 600;
		color: var(--color-on-surface-variant);
	}
	.tds-pill--active .tds-pill-load { color: rgba(255,255,255,0.85); }
	.tds-pill-badge {
		position: absolute; top: -6px; right: -4px;
		background: var(--color-primary); color: #fff;
		border-radius: 999px; padding: 1px 6px;
		font-size: 0.58rem; font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.05em;
	}

	/* Slot head */
	.tds-slot-head {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) 0;
		border-top: 1px solid var(--color-outline-variant);
	}
	.tds-slot-time {
		font-family: var(--font-display);
		font-size: var(--text-title-sm); font-weight: 800;
		color: var(--color-on-surface);
	}
	.tds-slot-note {
		font-size: var(--text-label-sm); font-weight: 600;
		background: rgba(204,0,0,0.08); color: var(--color-primary);
		border-radius: 999px; padding: 2px 8px;
	}

	/* Player list */
	.tds-player-list { display: flex; flex-direction: column; gap: var(--space-2); margin: 0 0 var(--space-3); }
	.tds-player-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		background: var(--color-surface-container);
	}
	.tds-player-row--me { background: rgba(204,0,0,0.06); border: 1px solid rgba(204,0,0,0.15); }
	.tds-player-row--wait { background: rgba(234,88,12,0.06); }
	.tds-player-row img {
		width: 32px; height: 32px; border-radius: 50%;
		object-fit: cover; object-position: top center;
	}
	.tds-player-row span { font-weight: 600; font-size: var(--text-label-md); }
	.tds-wait-pos {
		font-family: var(--font-display); font-weight: 800;
		color: #ea580c; min-width: 20px;
	}
	.tds-me-chip {
		margin-left: auto;
		background: var(--color-primary); color: #fff;
		border-radius: 999px; padding: 1px 8px;
		font-size: 0.68rem !important; font-weight: 700 !important;
		text-transform: uppercase; letter-spacing: 0.05em;
	}

	/* Action */
	.tds-action-wrap { margin-top: var(--space-5); display: flex; flex-direction: column; gap: var(--space-2); }
	.tds-btn-waitlist {
		background: #ea580c;
		color: #fff;
		border: none;
	}
	.tds-btn-storno {
		background: transparent;
		color: var(--color-primary);
		border: 2px solid var(--color-primary);
	}
	.tds-btn-storno:disabled {
		border-color: var(--color-outline-variant);
		color: var(--color-outline);
		opacity: 0.6;
		cursor: not-allowed;
	}
	.tds-hint {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		text-align: center;
		margin: 0;
	}
</style>
