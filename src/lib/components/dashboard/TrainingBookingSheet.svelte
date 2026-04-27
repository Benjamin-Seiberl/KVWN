<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { DAY_SHORT, MONTH_SHORT, fmtDate, toDateStr } from '$lib/utils/dates.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let {
		open = $bindable(false),
		slot = null,
		bookings = [],
		waitlist = [],
		upcomingSlots = [],
		onReload,
	} = $props();

	let busy = $state(false);

	// Lokal gewählter Slot (für "Andere Termine"). Wenn null → der vom Parent gelieferte `slot`.
	let selectedSlot       = $state(null);
	let selectedBookings   = $state([]);
	let selectedWaitlist   = $state([]);
	let selectedLoading    = $state(false);
	let altOpen            = $state(false);

	// Beim Öffnen / Slot-Wechsel: lokale Auswahl zurücksetzen.
	$effect(() => {
		if (!open) {
			selectedSlot     = null;
			selectedBookings = [];
			selectedWaitlist = [];
			altOpen          = false;
		}
	});

	function timeLabel(t) { return t ? t.slice(0, 5) : ''; }

	function shortDateLabel(dStr) {
		const d = new Date(dStr + 'T12:00:00');
		return `${DAY_SHORT[d.getDay()]} ${d.getDate()}. ${MONTH_SHORT[d.getMonth()]}`;
	}

	const activeSlot     = $derived(selectedSlot ?? slot);
	const activeBookings = $derived(selectedSlot ? selectedBookings : bookings);
	const activeWaitlist = $derived(selectedSlot ? selectedWaitlist : waitlist);

	const myBooking = $derived(activeSlot ? (activeBookings.find(b => b.player_id === $playerId) ?? null) : null);
	const myWait    = $derived(activeSlot ? (activeWaitlist.find(w => w.player_id === $playerId) ?? null) : null);
	const freeSpots = $derived(activeSlot ? Math.max(0, activeSlot.capacity - activeBookings.length) : 0);
	const isFull    = $derived(!!activeSlot && freeSpots <= 0);
	const isSameDayOrPast = $derived(!!activeSlot && activeSlot.date <= toDateStr(new Date()));

	async function selectSlot(s) {
		if (selectedLoading) return;
		selectedLoading = true;
		try {
			const [bkRes, wlRes] = await Promise.all([
				sb.from('training_bookings')
					.select('id, player_id, lane_number')
					.eq('date', s.date)
					.eq('start_time', s.start_time),
				sb.from('training_waitlist')
					.select('id, player_id, position')
					.eq('date', s.date)
					.eq('start_time', s.start_time)
					.order('position'),
			]);
			if (bkRes.error || wlRes.error) {
				const err = bkRes.error ?? wlRes.error;
				triggerToast('Fehler: ' + err.message);
				return;
			}
			selectedSlot     = s;
			selectedBookings = bkRes.data ?? [];
			selectedWaitlist = wlRes.data ?? [];
			altOpen          = false;
		} finally {
			selectedLoading = false;
		}
	}

	async function finishAndClose() {
		await onReload?.();
		open = false;
	}

	async function book() {
		if (!activeSlot || busy || !$playerId) return;
		// Erste freie Bahn finden.
		const takenLanes = new Set(activeBookings.map(b => b.lane_number));
		let lane = 1;
		for (let i = 1; i <= activeSlot.capacity; i++) {
			if (!takenLanes.has(i)) { lane = i; break; }
		}
		busy = true;
		const { data, error } = await sb.rpc('book_training_lane', {
			p_date:  activeSlot.date,
			p_start: activeSlot.start_time,
			p_lane:  lane,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}
		if (data?.status === 'booked') {
			triggerToast('Gebucht (Bahn ' + data.lane + ')');
		} else if (data?.status === 'waitlisted') {
			triggerToast('Auf Warteliste (Position ' + data.position + ')');
		} else if (data?.status === 'already_booked') {
			triggerToast('Bereits gebucht');
		} else if (data?.status === 'already_waitlisted') {
			triggerToast('Bereits auf Warteliste');
		} else if (data?.status === 'lane_taken') {
			triggerToast('Bahn war schon belegt — bitte nochmal probieren');
		}
		busy = false;
		await finishAndClose();
	}

	async function joinWaitlist() {
		if (!activeSlot || busy || !$playerId) return;
		busy = true;
		// RPC mit Bahn 1 — bei voller Auslastung routet die RPC automatisch auf die Warteliste.
		const { data, error } = await sb.rpc('book_training_lane', {
			p_date:  activeSlot.date,
			p_start: activeSlot.start_time,
			p_lane:  1,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}
		if (data?.status === 'waitlisted') {
			triggerToast('Auf Warteliste (Position ' + data.position + ')');
		} else if (data?.status === 'booked') {
			triggerToast('Gebucht (Bahn ' + data.lane + ')');
		} else if (data?.status === 'already_waitlisted') {
			triggerToast('Bereits auf Warteliste');
		} else if (data?.status === 'already_booked') {
			triggerToast('Bereits gebucht');
		}
		busy = false;
		await finishAndClose();
	}

	async function cancel() {
		if (!myBooking || busy) return;
		busy = true;
		const { error } = await sb.rpc('cancel_training_booking', { p_booking_id: myBooking.id });
		if (error) {
			if (error.message.includes('same_day_storno_forbidden')) {
				triggerToast('Storno am selben Tag nicht mehr möglich');
			} else {
				triggerToast('Fehler: ' + error.message);
			}
			busy = false;
			return;
		}
		triggerToast('Storniert');
		busy = false;
		await finishAndClose();
	}

	async function leaveWaitlist() {
		if (!myWait || busy) return;
		busy = true;
		const { error } = await sb.from('training_waitlist').delete().eq('id', myWait.id);
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}
		triggerToast('Von Warteliste abgemeldet');
		busy = false;
		await finishAndClose();
	}
</script>

<BottomSheet bind:open title="Training">
	{#if activeSlot}
		<div class="tbs">
			<div class="tbs-head">
				<h2 class="tbs-title">
					Training – {fmtDate(activeSlot.date)}
				</h2>
				<p class="tbs-time">
					{timeLabel(activeSlot.start_time)} – {timeLabel(activeSlot.end_time)} Uhr
					{#if activeSlot.isSpecial} · Sondertraining{/if}
				</p>
				{#if activeSlot.note}
					<p class="tbs-note">{activeSlot.note}</p>
				{/if}
			</div>

			<div class="tbs-meta">
				<div class="tbs-cap">
					<span class="material-symbols-outlined">groups</span>
					<span>{activeBookings.length}/{activeSlot.capacity} belegt</span>
				</div>
				{#if myBooking}
					<div class="tbs-state tbs-state--ok">
						<span class="material-symbols-outlined">check_circle</span>
						Gebucht · Bahn {myBooking.lane_number}
					</div>
				{:else if myWait}
					<div class="tbs-state tbs-state--wait">
						<span class="material-symbols-outlined">hourglass_top</span>
						Warteliste · Position {myWait.position}
					</div>
				{:else if isFull}
					<div class="tbs-state tbs-state--full">
						<span class="material-symbols-outlined">block</span>
						Voll belegt · {activeWaitlist.length} auf Warteliste
					</div>
				{:else}
					<div class="tbs-state">
						{freeSpots} von {activeSlot.capacity} {freeSpots === 1 ? 'Platz' : 'Plätzen'} frei
					</div>
				{/if}
			</div>

			<div class="tbs-actions">
				{#if myBooking}
					<button
						class="mw-btn mw-btn--ghost mw-btn--wide"
						onclick={cancel}
						disabled={busy || isSameDayOrPast}
					>
						<span class="material-symbols-outlined">close</span>
						Stornieren
					</button>
				{:else if myWait}
					<button
						class="mw-btn mw-btn--ghost mw-btn--wide"
						onclick={leaveWaitlist}
						disabled={busy}
					>
						<span class="material-symbols-outlined">close</span>
						Warteliste verlassen
					</button>
				{:else if isFull}
					<button
						class="mw-btn mw-btn--soft mw-btn--wide"
						onclick={joinWaitlist}
						disabled={busy || !$playerId}
					>
						<span class="material-symbols-outlined">hourglass_top</span>
						Warteliste
					</button>
				{:else}
					<button
						class="mw-btn mw-btn--primary mw-btn--wide"
						onclick={book}
						disabled={busy || !$playerId}
					>
						<span class="material-symbols-outlined">add</span>
						Buchen
					</button>
				{/if}
			</div>

			{#if upcomingSlots && upcomingSlots.length > 0}
				<div class="tbs-alt">
					<button
						type="button"
						class="tbs-alt-toggle"
						onclick={() => altOpen = !altOpen}
						aria-expanded={altOpen}
					>
						<span class="material-symbols-outlined">event_available</span>
						<span class="tbs-alt-toggle-label">Andere Termine</span>
						<span class="tbs-alt-count">{upcomingSlots.length}</span>
						<span class="material-symbols-outlined tbs-alt-chevron" class:tbs-alt-chevron--open={altOpen}>
							expand_more
						</span>
					</button>

					{#if altOpen}
						<ul class="tbs-alt-list" role="list">
							{#each upcomingSlots as s (s.date + s.start_time)}
								{@const isActive = selectedSlot && s.date === selectedSlot.date && s.start_time === selectedSlot.start_time}
								<li>
									<button
										type="button"
										class="tbs-alt-item"
										class:tbs-alt-item--active={isActive}
										onclick={() => selectSlot(s)}
										disabled={selectedLoading}
										aria-label={`Training am ${shortDateLabel(s.date)} um ${timeLabel(s.start_time)} Uhr wählen`}
									>
										<div class="tbs-alt-item-when">
											<span class="tbs-alt-item-date">{shortDateLabel(s.date)}</span>
											<span class="tbs-alt-item-time">{timeLabel(s.start_time)} – {timeLabel(s.end_time)} Uhr</span>
										</div>
										<div class="tbs-alt-item-meta">
											{#if s.freeSpots > 0}
												<span class="tbs-alt-item-free">
													{s.freeSpots} {s.freeSpots === 1 ? 'Platz' : 'Plätze'} frei
												</span>
											{:else}
												<span class="tbs-alt-item-full">
													Voll
													{#if s.waitCount > 0} · {s.waitCount} Warteliste{/if}
												</span>
											{/if}
											{#if s.isSpecial}
												<span class="tbs-alt-item-special">Sonder</span>
											{/if}
										</div>
									</button>
								</li>
							{/each}
						</ul>
					{/if}
				</div>
			{/if}

			<a class="tbs-link" href={`/kalender?date=${activeSlot.date}`}>
				<span class="material-symbols-outlined">calendar_month</span>
				Im Kalender öffnen
			</a>
		</div>
	{/if}
</BottomSheet>

<style>
	.tbs {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-2) var(--space-5) var(--space-6);
	}

	.tbs-head {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.tbs-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-md);
		font-weight: 800;
		color: var(--color-on-surface);
	}
	.tbs-time {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-body-md);
		font-weight: 700;
		color: var(--color-primary);
	}
	.tbs-note {
		margin: var(--space-2) 0 0;
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		background: var(--color-surface-container);
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
	}

	.tbs-meta {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		background: var(--color-surface-container);
		border-radius: var(--radius-lg);
	}
	.tbs-cap,
	.tbs-state {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-size: var(--text-body-sm);
		font-weight: 600;
		color: var(--color-on-surface-variant);
	}
	.tbs-cap .material-symbols-outlined,
	.tbs-state .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tbs-state--ok {
		color: var(--color-success);
	}
	.tbs-state--wait {
		color: var(--color-warning);
	}
	.tbs-state--full {
		color: var(--color-primary);
	}

	.tbs-actions {
		display: flex;
		gap: var(--space-2);
	}
	.tbs-actions > * { flex: 1; }

	.tbs-link {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: var(--space-2);
		font-size: var(--text-body-sm);
		font-weight: 700;
		color: var(--color-primary);
		text-decoration: none;
		border-radius: var(--radius-md);
	}
	.tbs-link .material-symbols-outlined {
		font-size: 1rem;
	}
	.tbs-link:active { opacity: 0.7; }

	/* ── Andere Termine ───────────────────────────────────────────────── */
	.tbs-alt {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		border-top: 1px solid var(--color-outline-variant);
		padding-top: var(--space-3);
	}
	.tbs-alt-toggle {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		width: 100%;
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container);
		border: none;
		border-radius: var(--radius-md);
		font: inherit;
		font-size: var(--text-body-sm);
		font-weight: 700;
		color: var(--color-on-surface);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.tbs-alt-toggle:active { opacity: 0.85; }
	.tbs-alt-toggle .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.tbs-alt-toggle-label { flex: 1; text-align: left; }
	.tbs-alt-count {
		min-width: 1.4rem;
		height: 1.4rem;
		padding: 0 6px;
		background: var(--color-primary);
		color: var(--color-on-primary);
		border-radius: var(--radius-full);
		font-family: var(--font-display);
		font-size: 0.7rem;
		font-weight: 800;
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.tbs-alt-chevron {
		transition: transform 180ms ease;
	}
	.tbs-alt-chevron--open {
		transform: rotate(180deg);
	}

	.tbs-alt-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.tbs-alt-item {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--color-outline-variant);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-md);
		font: inherit;
		text-align: left;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: border-color 120ms ease, background 120ms ease;
	}
	.tbs-alt-item:active { background: var(--color-surface-container); }
	.tbs-alt-item:disabled { opacity: 0.5; cursor: default; }
	.tbs-alt-item--active {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 6%, transparent);
	}
	.tbs-alt-item-when {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex: 1;
		min-width: 0;
	}
	.tbs-alt-item-date {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.tbs-alt-item-time {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.tbs-alt-item-meta {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		flex-shrink: 0;
	}
	.tbs-alt-item-free {
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-success);
	}
	.tbs-alt-item-full {
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-primary);
	}
	.tbs-alt-item-special {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-secondary);
	}
</style>
