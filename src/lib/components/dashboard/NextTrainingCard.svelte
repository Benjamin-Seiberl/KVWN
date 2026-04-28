<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { DAY_SHORT, MONTH_SHORT, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import TrainingDetailSheet from '$lib/components/kalender/TrainingDetailSheet.svelte';

	// Nächster Trainings-TAG (alle Slots dieses Tages, Tagessumme im Display).
	let dayDate  = $state(null);    // 'YYYY-MM-DD' — Datum-Badge + Sheet
	let daySlots = $state([]);      // alle Slots des Tages: { date, start_time, end_time, capacity, isSpecial, note }
	let bookings = $state([]);      // alle Bookings des Tages (inkl. lane_number, start_time)
	let waitlist = $state([]);      // alle Waitlist-Einträge des Tages
	let loading  = $state(true);
	let bookingOpen = $state(false);

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
			const futureCandidates = candidates.filter(c =>
				c.date > nowStr || (c.date === nowStr && c.end_time > nowTimeStr)
			);
			const nextDate = futureCandidates[0]?.date ?? null;

			if (!nextDate) {
				dayDate = null;
				daySlots = [];
				bookings = [];
				waitlist = [];
				return;
			}

			dayDate  = nextDate;
			daySlots = futureCandidates.filter(c => c.date === nextDate);

			// Bookings + Waitlist für den ganzen Tag laden.
			const [bkRes, wlRes] = await Promise.all([
				sb.from('training_bookings')
					.select('id, player_id, lane_number, start_time')
					.eq('date', nextDate),
				sb.from('training_waitlist')
					.select('id, player_id, position, start_time')
					.eq('date', nextDate)
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

	// ── Derived (nur für Display) ──
	const myBooking      = $derived(bookings.find(b => b.player_id === $playerId) ?? null);
	const myWait         = $derived(waitlist.find(w => w.player_id === $playerId) ?? null);
	const totalCapacity  = $derived(daySlots.reduce((a, s) => a + (s.capacity ?? 0), 0));
	const freeSpotsTotal = $derived(Math.max(0, totalCapacity - bookings.length));
	const isFullDay      = $derived(totalCapacity > 0 && freeSpotsTotal === 0);
	const isSpecial      = $derived(daySlots.some(s => s.isSpecial));
	const dayNote        = $derived(daySlots.find(s => s.note)?.note ?? null);

	const dateBadge = $derived.by(() => {
		if (!dayDate) return null;
		const d = new Date(dayDate + 'T12:00:00');
		return {
			dow:   DAY_SHORT[d.getDay()],
			day:   d.getDate(),
			month: MONTH_SHORT[d.getMonth()],
			days:  daysUntil(dayDate),
		};
	});

	const dayLabel = $derived.by(() => {
		if (!dateBadge) return '';
		if (dateBadge.days === 0) return 'Heute';
		if (dateBadge.days === 1) return 'Morgen';
		return `In ${dateBadge.days} Tagen`;
	});

	const ariaLabel = $derived.by(() => {
		if (!dateBadge) return 'Training Details öffnen';
		if (myBooking) {
			return `Training ${dayLabel}, du bist gebucht auf Bahn ${myBooking.lane_number}. Details öffnen`;
		}
		if (myWait) {
			return `Training ${dayLabel}, du stehst auf der Warteliste auf Position ${myWait.position}. Details öffnen`;
		}
		if (isFullDay) {
			return `Training ${dayLabel}, voll belegt, ${waitlist.length} auf Warteliste. Details öffnen`;
		}
		return `Training ${dayLabel}, ${freeSpotsTotal} von ${totalCapacity} Plätzen frei. Details öffnen`;
	});

	function openSheet() {
		if (!dayDate) return;
		bookingOpen = true;
	}

	function onKeydownCard(e) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			openSheet();
		}
	}
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
	{:else if !dayDate}
		<div class="ntc ntc--empty">
			<span class="material-symbols-outlined ntc-empty-icon">event_busy</span>
			<span class="ntc-empty-text">Kein Training geplant</span>
		</div>
	{:else}
		<button
			class="ntc"
			onclick={openSheet}
			onkeydown={onKeydownCard}
			aria-label={ariaLabel}
		>
			<div class="ntc-date">
				<span class="ntc-date-dow">{dateBadge.dow}</span>
				<span class="ntc-date-day">{dateBadge.day}</span>
				<span class="ntc-date-month">{dateBadge.month}</span>
			</div>
			<div class="ntc-body">
				<span class="ntc-label">
					{dayLabel}{#if isSpecial} · Sondertraining{/if}
				</span>

				{#if myBooking}
					<span class="ntc-status">Du bist drin · Bahn {myBooking.lane_number} · {String(myBooking.start_time).slice(0,5)}</span>
					{#if totalCapacity > 0}
						<span class="ntc-meta">{freeSpotsTotal} / {totalCapacity} Plätze frei</span>
					{/if}
				{:else if myWait}
					<span class="ntc-status">Warteliste · Position {myWait.position} · {String(myWait.start_time).slice(0,5)}</span>
					<span class="ntc-meta">Voll · {waitlist.length} wartend</span>
				{:else if isFullDay}
					<span class="ntc-status ntc-status--full">Voll belegt</span>
					<span class="ntc-meta">{waitlist.length} auf Warteliste</span>
				{:else}
					<span class="ntc-status">{freeSpotsTotal} / {totalCapacity} Plätze frei</span>
				{/if}

				{#if dayNote}
					<span class="ntc-note">{dayNote}</span>
				{/if}
			</div>
			<span class="material-symbols-outlined ntc-chevron" aria-hidden="true">chevron_right</span>
		</button>
	{/if}
</div>

<TrainingDetailSheet bind:open={bookingOpen} date={dayDate} onReload={load} />

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
		color: var(--color-secondary);
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
		align-items: center;
		gap: var(--space-3);
		background: linear-gradient(135deg, var(--color-surface-container-lowest) 0%, color-mix(in srgb, var(--color-secondary) 4%, var(--color-surface-container-lowest)) 100%);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-card);
		padding: var(--space-3);
		border-left: 4px solid var(--color-secondary);
		text-align: left;
		font: inherit;
		color: inherit;
		border-top: none;
		border-right: none;
		border-bottom: none;
		width: 100%;
		cursor: pointer;
		transition: transform 120ms ease, box-shadow 120ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.ntc:hover { box-shadow: var(--shadow-float); }
	.ntc:active { transform: scale(0.99); }
	.ntc:focus-visible {
		outline: 2px solid var(--color-secondary);
		outline-offset: 2px;
	}

	.ntc--skeleton,
	.ntc--empty {
		flex-direction: row;
		align-items: center;
		border-left-color: var(--color-outline-variant);
	}
	.ntc--skeleton {
		cursor: default;
	}
	.ntc--skeleton .ntc-date {
		width: 54px;
		height: 54px;
		border-radius: var(--radius-lg);
		background: var(--color-surface-container);
		flex-shrink: 0;
	}

	.ntc--empty {
		gap: var(--space-3);
		color: var(--color-on-surface-variant);
		cursor: default;
	}
	.ntc-empty-icon {
		font-size: 1.5rem;
		color: var(--color-outline);
	}
	.ntc-empty-text {
		font-size: var(--text-body-md);
	}

	.ntc-date {
		flex-shrink: 0;
		width: 54px;
		height: 54px;
		border-radius: var(--radius-lg);
		background: linear-gradient(135deg, var(--color-secondary), color-mix(in srgb, var(--color-secondary) 60%, black));
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.15);
		color: #fff;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0;
		padding: 4px;
	}
	.ntc-date-dow {
		font-size: 0.55rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		opacity: 0.9;
		line-height: 1;
	}
	.ntc-date-day {
		font-family: var(--font-display);
		font-size: 1.25rem;
		font-weight: 800;
		line-height: 1;
	}
	.ntc-date-month {
		font-size: 0.55rem;
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
		gap: 3px;
	}
	.ntc-label {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: color-mix(in srgb, var(--color-secondary) 80%, black);
	}
	.ntc-status {
		font-family: var(--font-display);
		font-size: 1rem;
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.ntc-status--full {
		color: color-mix(in srgb, var(--color-primary) 75%, var(--color-on-surface));
	}
	.ntc-meta {
		font-size: var(--text-label-sm);
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
	.ntc-chevron {
		font-size: 1.1rem;
		color: color-mix(in srgb, var(--color-secondary) 50%, var(--color-outline));
		flex-shrink: 0;
	}
</style>
