<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { goto } from '$app/navigation';
	import { DAY_SHORT, MONTH_SHORT, toDateStr, daysUntil } from '$lib/utils/dates.js';

	// Nächster Trainings-Slot (chronologisch). Enthält Datum + Zeitfenster.
	let slot     = $state(null);    // { date, start_time, end_time, capacity, isSpecial, note }
	let bookings = $state([]);      // bookings des gefundenen Slots (inkl. lane_number)
	let waitlist = $state([]);      // waitlist-Einträge des gefundenen Slots
	let loading  = $state(true);
	let busy     = $state(false);
	let state    = $state(null);    // null | 'booked' | 'cancelled' | 'waitlisted'

	function timeLabel(t) { return t ? t.slice(0, 5) : ''; }

	async function load() {
		loading = true;
		try {
			const todayStr = toDateStr(new Date());

			// 30-Tage-Fenster absuchen (Templates sind wöchentlich recurring).
			const until = new Date();
			until.setDate(until.getDate() + 30);

			const [tplRes, spRes, ovRes] = await Promise.all([
				sb.from('training_templates').select('*').eq('active', true),
				sb.from('training_specials').select('*').gte('date', todayStr).lte('date', toDateStr(until)),
				sb.from('training_overrides').select('*').gte('date', todayStr).lte('date', toDateStr(until)),
			]);
			if (tplRes.error || spRes.error || ovRes.error) {
				const err = tplRes.error ?? spRes.error ?? ovRes.error;
				triggerToast('Fehler: ' + err.message);
				return;
			}

			const templates = tplRes.data ?? [];
			const specials  = spRes.data ?? [];
			const overrides = ovRes.data ?? [];

			// Slots expandieren, chronologisch sortieren, ersten (date >= today, slot-end > now) nehmen.
			const now = new Date();
			const candidates = [];

			// Templates für jeden Tag im Fenster
			for (let d = new Date(now); d <= until; d.setDate(d.getDate() + 1)) {
				const date = toDateStr(d);
				const dow  = d.getDay();
				for (const t of templates.filter(x => x.day_of_week === dow)) {
					const sh = Number(String(t.start_time).slice(0, 2));
					const eh = Number(String(t.end_time).slice(0, 2));
					for (let h = sh; h < eh; h++) {
						const startTime = `${String(h).padStart(2,'0')}:00:00`;
						const endTime   = `${String(h+1).padStart(2,'0')}:00:00`;
						const ov = overrides.find(o => o.date === date && String(o.start_time).slice(0,5) === startTime.slice(0,5));
						if (ov?.closed) continue;
						candidates.push({
							date,
							start_time: startTime,
							end_time:   endTime,
							capacity:   t.lane_count,
							note:       ov?.note ?? null,
							isSpecial:  false,
						});
					}
				}
			}

			// Specials
			for (const s of specials) {
				const ov = overrides.find(o => o.date === s.date && String(o.start_time).slice(0,5) === String(s.start_time).slice(0,5));
				if (ov?.closed) continue;
				candidates.push({
					date:       s.date,
					start_time: s.start_time,
					end_time:   s.end_time,
					capacity:   s.capacity,
					note:       s.note ?? ov?.note ?? null,
					isSpecial:  true,
				});
			}

			// Sortieren & ersten zukünftigen (End-Zeit > now) finden.
			candidates.sort((a, b) => {
				if (a.date !== b.date) return a.date.localeCompare(b.date);
				return a.start_time.localeCompare(b.start_time);
			});

			const nowStr     = toDateStr(now);
			const nowTimeStr = String(now.getHours()).padStart(2,'0') + ':' + String(now.getMinutes()).padStart(2,'0') + ':00';
			const next = candidates.find(c => c.date > nowStr || (c.date === nowStr && c.end_time > nowTimeStr));

			if (!next) {
				slot = null;
				bookings = [];
				waitlist = [];
				return;
			}

			slot = next;

			// Bookings + Waitlist für den konkreten Slot laden.
			const [bkRes, wlRes] = await Promise.all([
				sb.from('training_bookings')
					.select('id, player_id, lane_number')
					.eq('date', next.date)
					.eq('start_time', next.start_time),
				sb.from('training_waitlist')
					.select('id, player_id, position')
					.eq('date', next.date)
					.eq('start_time', next.start_time)
					.order('position'),
			]);
			if (bkRes.error || wlRes.error) {
				const err = bkRes.error ?? wlRes.error;
				triggerToast('Fehler: ' + err.message);
				return;
			}
			bookings = bkRes.data ?? [];
			waitlist = wlRes.data ?? [];
		} finally {
			loading = false;
		}
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			load();
		}
	});

	// ── Derived ──
	const myBooking  = $derived(bookings.find(b => b.player_id === $playerId) ?? null);
	const myWait     = $derived(waitlist.find(w => w.player_id === $playerId) ?? null);
	const freeSpots  = $derived(slot ? Math.max(0, slot.capacity - bookings.length) : 0);
	const isFull     = $derived(!!slot && freeSpots <= 0);

	const dateBadge = $derived.by(() => {
		if (!slot) return null;
		const d = new Date(slot.date + 'T12:00:00');
		return {
			dow:   DAY_SHORT[d.getDay()],
			day:   d.getDate(),
			month: MONTH_SHORT[d.getMonth()],
			days:  daysUntil(slot.date),
		};
	});

	// ── Aktionen ──
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
			state = 'booked';
			triggerToast('Gebucht (Bahn ' + data.lane + ')');
		} else if (data?.status === 'waitlisted') {
			state = 'waitlisted';
			triggerToast('Auf Warteliste (Position ' + data.position + ')');
		} else if (data?.status === 'already_booked') {
			triggerToast('Bereits gebucht');
		} else if (data?.status === 'already_waitlisted') {
			triggerToast('Bereits auf Warteliste');
		} else if (data?.status === 'lane_taken') {
			triggerToast('Bahn war schon belegt — bitte nochmal probieren');
		}
		busy = false;
		setTimeout(() => { state = null; load(); }, 1400);
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
			state = 'waitlisted';
			triggerToast('Auf Warteliste (Position ' + data.position + ')');
		} else if (data?.status === 'booked') {
			// Kann passieren, wenn zwischenzeitlich ein Platz frei wurde.
			state = 'booked';
			triggerToast('Gebucht (Bahn ' + data.lane + ')');
		} else if (data?.status === 'already_waitlisted') {
			triggerToast('Bereits auf Warteliste');
		} else if (data?.status === 'already_booked') {
			triggerToast('Bereits gebucht');
		}
		busy = false;
		setTimeout(() => { state = null; load(); }, 1400);
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
		state = 'cancelled';
		triggerToast('Storniert');
		busy = false;
		setTimeout(() => { state = null; load(); }, 1400);
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
		state = 'cancelled';
		triggerToast('Von Warteliste abgemeldet');
		busy = false;
		setTimeout(() => { state = null; load(); }, 1400);
	}

	// Same-day lock: Storno am selben Tag nicht mehr möglich.
	const isSameDayOrPast = $derived(!!slot && slot.date <= toDateStr(new Date()));
</script>

<div class="ntc-wrap">
	<div class="sec-head">
		<span class="material-symbols-outlined sec-icon">sports_tennis</span>
		<h3 class="sec-title">Nächstes Training</h3>
	</div>

	{#if loading}
		<div class="ntc ntc--skeleton">
			<div class="ntc-date shimmer-box"></div>
			<div class="ntc-body">
				<div class="shimmer-box" style="width:60%;height:12px;border-radius:4px"></div>
				<div class="shimmer-box" style="width:85%;height:16px;border-radius:5px;margin-top:6px"></div>
				<div class="shimmer-box" style="width:50%;height:11px;border-radius:4px;margin-top:6px"></div>
			</div>
		</div>
	{:else if !slot}
		<div class="ntc ntc--empty">
			<span class="material-symbols-outlined ntc-empty-icon">event_busy</span>
			<span class="ntc-empty-text">Kein Training geplant</span>
		</div>
	{:else}
		<div class="ntc">
			<button
				class="ntc-main"
				onclick={() => goto('/kalender?date=' + slot.date)}
				aria-label="Zum Training im Kalender"
			>
				<div class="ntc-date">
					<span class="ntc-date-dow">{dateBadge.dow}</span>
					<span class="ntc-date-day">{dateBadge.day}</span>
					<span class="ntc-date-month">{dateBadge.month}</span>
				</div>
				<div class="ntc-body">
					<span class="ntc-label">
						{#if dateBadge.days === 0}
							Heute
						{:else if dateBadge.days === 1}
							Morgen
						{:else}
							In {dateBadge.days} Tagen
						{/if}
						{#if slot.isSpecial} · Sondertraining{/if}
					</span>
					<span class="ntc-time">{timeLabel(slot.start_time)} – {timeLabel(slot.end_time)} Uhr</span>
					<span class="ntc-meta">
						{#if myBooking}
							Gebucht · Bahn {myBooking.lane_number}
						{:else if myWait}
							Warteliste · Position {myWait.position}
						{:else if isFull}
							Voll belegt · {waitlist.length} auf Warteliste
						{:else}
							{freeSpots} von {slot.capacity} {freeSpots === 1 ? 'Platz' : 'Plätzen'} frei
						{/if}
					</span>
					{#if slot.note}
						<span class="ntc-note">{slot.note}</span>
					{/if}
				</div>
			</button>

			<div class="ntc-cta">
				{#if state === 'booked'}
					<div class="ntc-result ntc-result--ok">
						<span class="material-symbols-outlined">check_circle</span>
						Gebucht
					</div>
				{:else if state === 'waitlisted'}
					<div class="ntc-result ntc-result--wait">
						<span class="material-symbols-outlined">hourglass_top</span>
						Auf Warteliste
					</div>
				{:else if state === 'cancelled'}
					<div class="ntc-result ntc-result--off">
						<span class="material-symbols-outlined">cancel</span>
						Storniert
					</div>
				{:else if myBooking}
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
		</div>
	{/if}
</div>

<style>
	.ntc-wrap {
		padding: 0 var(--space-5);
	}

	/* Section-head (scoped — siehe MyNextMatchCard) */
	.sec-head {
		display: flex;
		align-items: center;
		gap: 7px;
		margin-bottom: var(--space-3);
	}
	.sec-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sec-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	.ntc {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-card);
		padding: var(--space-4);
		border-left: 4px solid var(--color-primary);
	}

	.ntc--skeleton {
		flex-direction: row;
		align-items: center;
		border-left-color: var(--color-outline-variant);
	}
	.ntc--skeleton .ntc-date {
		width: 62px;
		height: 62px;
		border-radius: var(--radius-lg);
		background: var(--color-surface-container);
		flex-shrink: 0;
	}

	.ntc--empty {
		flex-direction: row;
		align-items: center;
		gap: var(--space-3);
		border-left-color: var(--color-outline-variant);
		color: var(--color-on-surface-variant);
	}
	.ntc-empty-icon {
		font-size: 1.5rem;
		color: var(--color-outline);
	}
	.ntc-empty-text {
		font-size: var(--text-body-md);
	}

	.ntc-main {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		background: none;
		border: none;
		padding: 0;
		text-align: left;
		width: 100%;
		cursor: pointer;
		font: inherit;
		color: inherit;
	}
	.ntc-main:active { opacity: 0.8; }

	.ntc-date {
		flex-shrink: 0;
		width: 62px;
		height: 62px;
		border-radius: var(--radius-lg);
		background: linear-gradient(135deg, var(--color-primary), color-mix(in srgb, var(--color-primary) 55%, black));
		color: #fff;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0;
		padding: 4px;
	}
	.ntc-date-dow {
		font-size: 0.6rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		opacity: 0.9;
		line-height: 1;
	}
	.ntc-date-day {
		font-family: var(--font-display);
		font-size: 1.4rem;
		font-weight: 800;
		line-height: 1;
	}
	.ntc-date-month {
		font-size: 0.6rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		opacity: 0.85;
		line-height: 1;
	}

	.ntc-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.ntc-label {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-primary);
	}
	.ntc-time {
		font-family: var(--font-display);
		font-size: 1.05rem;
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.ntc-meta {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
	}
	.ntc-note {
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-on-surface-variant);
		background: var(--color-surface-container);
		padding: 2px 8px;
		border-radius: var(--radius-full);
		align-self: flex-start;
		margin-top: 2px;
	}

	.ntc-cta {
		display: flex;
		justify-content: stretch;
	}
	.ntc-cta > * { flex: 1; }

	.ntc-result {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 10px 14px;
		border-radius: var(--radius-md);
		font-family: var(--font-display);
		font-size: 0.85rem;
		font-weight: 800;
		width: 100%;
	}
	.ntc-result .material-symbols-outlined {
		font-size: 1.05rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.ntc-result--ok {
		background: rgba(45, 122, 58, 0.12);
		color: var(--color-success);
	}
	.ntc-result--wait {
		background: rgba(234, 88, 12, 0.1);
		color: #ea580c;
	}
	.ntc-result--off {
		background: rgba(204, 0, 0, 0.1);
		color: var(--color-primary);
	}
</style>
