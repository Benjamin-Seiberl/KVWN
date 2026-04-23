<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let { open = $bindable(false), slot = null, bookings = [], waitlist = [], onReload } = $props();

	let busy = $state(false);

	function timeLabel(t) { return t ? t.slice(0, 5) : ''; }

	const myBooking = $derived(slot ? (bookings.find(b => b.player_id === $playerId) ?? null) : null);
	const myWait    = $derived(slot ? (waitlist.find(w => w.player_id === $playerId) ?? null) : null);
	const freeSpots = $derived(slot ? Math.max(0, slot.capacity - bookings.length) : 0);
	const isFull    = $derived(!!slot && freeSpots <= 0);
	const isSameDayOrPast = $derived(!!slot && slot.date <= toDateStr(new Date()));

	async function finishAndClose() {
		await onReload?.();
		open = false;
	}

	async function book() {
		if (!slot || busy || !$playerId) return;
		// Erste freie Bahn finden.
		const takenLanes = new Set(bookings.map(b => b.lane_number));
		let lane = 1;
		for (let i = 1; i <= slot.capacity; i++) {
			if (!takenLanes.has(i)) { lane = i; break; }
		}
		busy = true;
		const { data, error } = await sb.rpc('book_training_lane', {
			p_date:  slot.date,
			p_start: slot.start_time,
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
		if (!slot || busy || !$playerId) return;
		busy = true;
		// RPC mit Bahn 1 — bei voller Auslastung routet die RPC automatisch auf die Warteliste.
		const { data, error } = await sb.rpc('book_training_lane', {
			p_date:  slot.date,
			p_start: slot.start_time,
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
	{#if slot}
		<div class="tbs">
			<div class="tbs-head">
				<h2 class="tbs-title">
					Training – {fmtDate(slot.date)}
				</h2>
				<p class="tbs-time">
					{timeLabel(slot.start_time)} – {timeLabel(slot.end_time)} Uhr
					{#if slot.isSpecial} · Sondertraining{/if}
				</p>
				{#if slot.note}
					<p class="tbs-note">{slot.note}</p>
				{/if}
			</div>

			<div class="tbs-meta">
				<div class="tbs-cap">
					<span class="material-symbols-outlined">groups</span>
					<span>{bookings.length}/{slot.capacity} belegt</span>
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
						Voll belegt · {waitlist.length} auf Warteliste
					</div>
				{:else}
					<div class="tbs-state">
						{freeSpots} von {slot.capacity} {freeSpots === 1 ? 'Platz' : 'Plätzen'} frei
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

			<a class="tbs-link" href={`/kalender?date=${slot.date}`}>
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
		color: #ea580c;
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
</style>
