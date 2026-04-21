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

	// ── Load when sheet opens on a date ─────────────────────────────────────
	$effect(() => {
		if (open && date) loadSheet();
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

	// ── Derived helpers ─────────────────────────────────────────────────────
	function bookingsForStart(start) {
		return bookings.filter(b => String(b.start_time).slice(0,5) === String(start).slice(0,5));
	}
	function waitlistForStart(start) {
		return waitlist.filter(w => String(w.start_time).slice(0,5) === String(start).slice(0,5));
	}
	function myBookingFor(start) {
		return bookingsForStart(start).find(b => b.player_id === $playerId) ?? null;
	}
	function myWaitFor(start) {
		return waitlistForStart(start).find(w => w.player_id === $playerId) ?? null;
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

	const isSameDayOrPast = $derived(!!date && date <= toDateStr(new Date()));
	const myAnyBooking = $derived(bookings.find(b => b.player_id === $playerId) ?? null);
	const myAnyWait    = $derived(waitlist.find(w => w.player_id === $playerId) ?? null);

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
	async function book(startTime) {
		if (!startTime || saving) return;
		saving = true;
		const { data, error } = await sb.rpc('book_training_slot', {
			p_date:  date,
			p_start: startTime,
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

	async function storno(bookingId) {
		if (!bookingId || saving) return;
		saving = true;
		const { data, error } = await sb.rpc('cancel_training_booking', { p_booking_id: bookingId });
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

	async function leaveWaitlist(waitId) {
		if (!waitId || saving) return;
		saving = true;
		const { error } = await sb.from('training_waitlist').delete().eq('id', waitId);
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

		<!-- ── Slot cards (stacked vertically) ──────────────────────────── -->
		<div class="tds-slot-stack">
			{#each slots as s (s.start_time)}
				{@const slotBookings = bookingsForStart(s.start_time)}
				{@const slotWait     = waitlistForStart(s.start_time)}
				{@const freeSpots    = Math.max(0, s.capacity - slotBookings.length)}
				{@const myB          = myBookingFor(s.start_time)}
				{@const myW          = myWaitFor(s.start_time)}
				{@const r            = occRatio(s.start_time, s.capacity)}
				{@const isFull       = r >= 1}
				{@const lockedElsewhere = (!!myAnyBooking && !myB) || (!!myAnyWait && !myW)}

				<div class="tds-slot-card" style="--slot-accent:{pillColor(r)};">
					<div class="tds-slot-head">
						<div class="tds-slot-head__left">
							<span class="tds-slot-time">
								{String(s.start_time).slice(0,5)} – {String(s.end_time).slice(0,5)} Uhr
							</span>
							<span class="tds-slot-stats">{slotBookings.length}/{s.capacity} belegt{#if slotWait.length} · {slotWait.length} warten{/if}</span>
						</div>
						{#if s.isSpecial}
							<span class="tds-slot-badge">Sonder</span>
						{/if}
						{#if s.note}
							<span class="tds-slot-note">{s.note}</span>
						{/if}
					</div>

					<!-- Lane circles -->
					<div class="tds-lanes">
						{#each slotBookings as b (b.id)}
							{@const pl = getPlayer(b.player_id)}
							{@const isMe = b.player_id === $playerId}
							<button
								class="tds-lane tds-lane--taken"
								class:tds-lane--mine={isMe}
								onclick={() => { if (isMe && !isSameDayOrPast) storno(b.id); }}
								disabled={!isMe || isSameDayOrPast || saving}
								title={isMe ? 'Storno' : shortName(pl?.name)}
							>
								<img class="tds-lane-img" src={imgPath(pl?.photo, pl?.name)} alt={pl?.name ?? ''} draggable="false" onerror={(e) => { e.currentTarget.style.display='none'; e.currentTarget.nextElementSibling?.classList.remove('tds-lane-initial--hidden'); }} />
								<span class="tds-lane-initial tds-lane-initial--hidden">{(pl?.name ?? '?').slice(0,1).toUpperCase()}</span>
								{#if isMe}
									<span class="tds-lane-badge tds-lane-badge--me">Du</span>
								{/if}
								<span class="tds-lane-name">{shortName(pl?.name) ?? '—'}</span>
							</button>
						{/each}

						{#each Array(freeSpots) as _, i (i)}
							<button
								class="tds-lane tds-lane--free"
								onclick={() => { if (!lockedElsewhere) book(s.start_time); }}
								disabled={saving || !$playerId || lockedElsewhere}
								aria-label="Freier Platz"
							>
								<span class="material-symbols-outlined tds-lane-plus">add</span>
								<span class="tds-lane-name tds-lane-name--muted">Frei</span>
							</button>
						{/each}
					</div>

					<!-- Waitlist strip -->
					{#if slotWait.length > 0}
						<div class="tds-wait-row">
							<span class="tds-wait-label">
								<span class="material-symbols-outlined">hourglass_top</span>
								Warteliste
							</span>
							<div class="tds-wait-circles">
								{#each slotWait as w (w.id)}
									{@const pl = getPlayer(w.player_id)}
									{@const isMe = w.player_id === $playerId}
									<div class="tds-wait-item" class:tds-wait-item--me={isMe} title="{shortName(pl?.name)} · Pos {w.position}">
										<div class="tds-wait-circle">
											<img src={imgPath(pl?.photo, pl?.name)} alt={pl?.name ?? ''} draggable="false" onerror={(e) => { e.currentTarget.style.display='none'; e.currentTarget.nextElementSibling?.classList.remove('tds-lane-initial--hidden'); }} />
											<span class="tds-lane-initial tds-lane-initial--hidden">{(pl?.name ?? '?').slice(0,1).toUpperCase()}</span>
											<span class="tds-wait-pos">{w.position}</span>
										</div>
										<span class="tds-lane-name">{shortName(pl?.name) ?? '—'}</span>
									</div>
								{/each}
							</div>
						</div>
					{/if}

					<!-- Action button -->
					<div class="tds-action-wrap">
						{#if myB}
							<button
								class="mw-btn mw-btn--wide tds-btn-storno"
								onclick={() => storno(myB.id)}
								disabled={saving || isSameDayOrPast}
							>
								<span class="material-symbols-outlined">event_busy</span>
								Storno
							</button>
							{#if isSameDayOrPast}
								<p class="tds-hint">Storno am selben Tag nicht mehr möglich.</p>
							{:else}
								<p class="tds-hint tds-hint--ok">Du bist gebucht. Viel Spaß beim Training!</p>
							{/if}
						{:else if myW}
							<button
								class="mw-btn mw-btn--wide mw-btn--ghost"
								onclick={() => leaveWaitlist(myW.id)}
								disabled={saving}
							>
								Von Warteliste abmelden
							</button>
							<p class="tds-hint">Du bist auf Position {myW.position}. Du wirst automatisch benachrichtigt.</p>
						{:else if lockedElsewhere}
							<p class="tds-hint">Du bist bereits in einem anderen Slot gebucht.</p>
						{:else if isFull}
							<button
								class="mw-btn mw-btn--wide tds-btn-waitlist"
								onclick={() => book(s.start_time)}
								disabled={saving || !$playerId}
							>
								<span class="material-symbols-outlined">hourglass_empty</span>
								Auf die Warteliste
							</button>
						{:else}
							<button
								class="mw-btn mw-btn--wide mw-btn--primary"
								onclick={() => book(s.start_time)}
								disabled={saving || !$playerId}
							>
								<span class="material-symbols-outlined">check</span>
								Buchen
							</button>
						{/if}
					</div>
				</div>
			{/each}
		</div>
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

	/* Stacked slot cards */
	.tds-slot-stack {
		display: flex; flex-direction: column; gap: var(--space-4);
	}

	.tds-slot-card {
		position: relative;
		background: linear-gradient(180deg, var(--color-surface-container-lowest, #fff) 0%, color-mix(in srgb, var(--slot-accent, var(--color-primary)) 4%, var(--color-surface-container-lowest, #fff)) 100%);
		border-radius: var(--radius-xl, 20px);
		border: 1.5px solid var(--color-outline-variant);
		padding: var(--space-4);
		box-shadow: var(--shadow-card);
		overflow: hidden;
	}
	.tds-slot-card::before {
		content: '';
		position: absolute; left: 0; top: 0; bottom: 0;
		width: 4px;
		background: var(--slot-accent, var(--color-outline-variant));
	}
	.tds-slot-badge {
		flex-shrink: 0;
		background: var(--color-primary); color: #fff;
		border-radius: 999px; padding: 2px 8px;
		font-size: 0.6rem; font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.05em;
		align-self: center;
	}

	.tds-slot-head {
		display: flex; align-items: flex-start; gap: var(--space-3);
		margin-bottom: var(--space-4);
	}
	.tds-slot-head__left { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.tds-slot-time {
		font-family: var(--font-display);
		font-size: var(--text-title-sm); font-weight: 800;
		color: var(--color-on-surface);
	}
	.tds-slot-stats {
		font-size: var(--text-label-sm); font-weight: 600;
		color: var(--color-on-surface-variant);
	}
	.tds-slot-note {
		flex-shrink: 0;
		font-size: var(--text-label-sm); font-weight: 600;
		background: rgba(204,0,0,0.08); color: var(--color-primary);
		border-radius: 999px; padding: 2px 10px;
		align-self: center;
	}

	/* ── Lane circles ── */
	.tds-lanes {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-4) var(--space-3);
		justify-content: center;
		padding: var(--space-3) 0 var(--space-4);
	}

	.tds-lane {
		position: relative;
		display: flex; flex-direction: column; align-items: center; gap: 6px;
		width: 64px;
		background: none; border: none; padding: 0;
		font: inherit; color: inherit;
		-webkit-tap-highlight-color: transparent;
		cursor: pointer;
	}
	.tds-lane[disabled] { cursor: default; }

	/* Circle base */
	.tds-lane::before {
		content: '';
		position: absolute; top: 0; left: 50%;
		transform: translateX(-50%);
		width: 56px; height: 56px;
		border-radius: 50%;
		pointer-events: none;
	}

	/* Common shell for image/plus */
	.tds-lane-img,
	.tds-lane-plus,
	.tds-lane-initial {
		width: 56px; height: 56px;
		border-radius: 50%;
		display: flex; align-items: center; justify-content: center;
		object-fit: cover; object-position: top center;
		transition: transform 140ms cubic-bezier(0.32, 0.72, 0, 1), box-shadow 200ms ease, border-color 200ms ease;
	}
	.tds-lane-initial {
		position: absolute; top: 0; left: 50%; transform: translateX(-50%);
		font-family: var(--font-display); font-weight: 800; font-size: 1.2rem;
		color: var(--color-on-surface-variant);
		background: var(--color-surface-container);
	}
	.tds-lane-initial--hidden { display: none; }

	.tds-lane:not([disabled]):active .tds-lane-img,
	.tds-lane:not([disabled]):active .tds-lane-plus { transform: scale(0.92); }

	/* Free lane — dashed green, inviting pulse */
	.tds-lane--free .tds-lane-plus {
		border: 2.5px dashed rgba(34,197,94,0.55);
		background: rgba(34,197,94,0.05);
		color: rgba(34,197,94,0.8);
		font-variation-settings: 'FILL' 0, 'wght' 300, 'GRAD' 0, 'opsz' 24;
		font-size: 1.5rem;
	}
	.tds-lane--free:not([disabled]) .tds-lane-plus {
		animation: tds-pulse 2.4s ease-in-out infinite;
	}
	.tds-lane--free[disabled] .tds-lane-plus {
		border-color: rgba(0,0,0,0.1);
		background: rgba(0,0,0,0.03);
		color: rgba(0,0,0,0.2);
		animation: none;
	}
	@keyframes tds-pulse {
		0%, 100% { box-shadow: 0 0 0 0 rgba(34,197,94,0.25); }
		50%       { box-shadow: 0 0 0 6px rgba(34,197,94,0); }
	}

	/* Taken by someone */
	.tds-lane--taken .tds-lane-img,
	.tds-lane--taken .tds-lane-initial {
		border: 2.5px solid rgba(60,60,67,0.12);
		background: var(--color-surface-container);
	}

	/* Taken by me — gold ring */
	.tds-lane--mine .tds-lane-img,
	.tds-lane--mine .tds-lane-initial {
		border: 2.5px solid var(--color-secondary, #D4AF37);
		box-shadow: 0 0 0 3px rgba(212,175,55,0.28), 0 2px 10px rgba(212,175,55,0.25);
	}

	.tds-lane-name {
		font-size: 0.68rem; font-weight: 700;
		color: var(--color-on-surface);
		max-width: 64px;
		text-align: center;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.tds-lane-name--muted { color: var(--color-outline); font-weight: 500; }

	.tds-lane-badge {
		position: absolute; top: -4px; right: -2px;
		border-radius: 999px;
		padding: 1px 7px;
		font-size: 0.6rem; font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.04em;
		box-shadow: 0 2px 6px rgba(0,0,0,0.12);
	}
	.tds-lane-badge--me {
		background: var(--color-primary); color: #fff;
	}

	/* ── Waitlist strip ── */
	.tds-wait-row {
		margin-top: var(--space-3);
		padding-top: var(--space-3);
		border-top: 1px dashed var(--color-outline-variant);
	}
	.tds-wait-label {
		display: flex; align-items: center; gap: 4px;
		font-family: var(--font-display);
		font-size: var(--text-label-sm); font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.06em;
		color: #ea580c;
		margin-bottom: var(--space-3);
	}
	.tds-wait-label .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.tds-wait-circles {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-3);
		padding-bottom: 2px;
	}
	.tds-wait-item {
		display: flex; flex-direction: column; align-items: center; gap: 6px;
		width: 52px;
	}
	.tds-wait-circle {
		position: relative;
		width: 44px; height: 44px;
		border-radius: 50%;
		border: 2px solid rgba(234,88,12,0.4);
		background: rgba(234,88,12,0.06);
		display: flex; align-items: center; justify-content: center;
		overflow: visible;
	}
	.tds-wait-circle img {
		width: 100%; height: 100%;
		border-radius: 50%;
		object-fit: cover; object-position: top center;
	}
	.tds-wait-pos {
		position: absolute; bottom: -4px; right: -4px;
		min-width: 18px; height: 18px; border-radius: 999px;
		background: #ea580c; color: #fff;
		font-family: var(--font-display);
		font-size: 0.62rem; font-weight: 800;
		display: flex; align-items: center; justify-content: center;
		padding: 0 5px;
		box-shadow: 0 1px 4px rgba(234,88,12,0.45);
	}
	.tds-wait-item--me .tds-wait-circle {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 2px rgba(204,0,0,0.12);
	}

	/* Action */
	.tds-action-wrap { margin-top: var(--space-4); display: flex; flex-direction: column; gap: var(--space-2); }
	.tds-btn-waitlist {
		background: #ea580c;
		color: #fff;
		border: none;
	}
	.tds-btn-waitlist:hover:not(:disabled) { background: #c2410c; }
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
	.tds-hint--ok {
		color: #16a34a;
		font-weight: 600;
	}
</style>
