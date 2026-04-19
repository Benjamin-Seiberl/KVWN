<script>
	import { onMount }      from 'svelte';
	import { page }         from '$app/stores';
	import { sb }           from '$lib/supabase';
	import { setSubtab }    from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, MONTH_FULL, DAY_SHORT } from '$lib/utils/dates.js';

	const hubs = [
		{ key: 'events',    label: 'Events',    icon: 'calendar_month', desc: 'Vereinsveranstaltungen' },
		{ key: 'trainings', label: 'Trainings', icon: 'fitness_center', desc: 'Bahnbuchungen'          },
	];

	let events    = $state([]);
	let templates = $state([]);
	let overrides = $state([]);
	let loading   = $state(true);

	function toDateKey(d) {
		return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
	}

	onMount(async () => {
		try {
			const today = toDateStr(new Date());
			const in14  = new Date(); in14.setDate(in14.getDate() + 13);
			const to14  = toDateKey(in14);

			const [
				{ data: ev, error: e1 },
				{ data: t,  error: e2 },
				{ data: o,  error: e3 },
			] = await Promise.all([
				sb.from('events').select('id, title, date, time, location')
					.gte('date', today).order('date', { ascending: true }).limit(3),
				sb.from('training_templates').select('*').eq('active', true),
				sb.from('training_overrides').select('*').gte('date', today).lte('date', to14),
			]);
			if (e1) { triggerToast('Fehler: ' + e1.message); }
			if (e2) { triggerToast('Fehler: ' + e2.message); }
			if (e3) { triggerToast('Fehler: ' + e3.message); }
			events    = ev ?? [];
			templates = t  ?? [];
			overrides = o  ?? [];
		} finally {
			loading = false;
		}
	});

	const nextTrainings = $derived.by(() => {
		if (!templates.length) return [];
		const sessions = [];
		const base = new Date(); base.setHours(0,0,0,0);
		for (let i = 0; i < 14; i++) {
			const d   = new Date(base); d.setDate(base.getDate() + i);
			const dow = d.getDay();
			const key = toDateKey(d);
			for (const tpl of templates.filter(t => t.day_of_week === dow)) {
				const sh = Number(String(tpl.start_time).slice(0,2));
				const eh = Number(String(tpl.end_time).slice(0,2));
				for (let h = sh; h < eh; h++) {
					const startTime = `${String(h).padStart(2,'0')}:00`;
					const ov = overrides.find(o => o.date === key && String(o.start_time).slice(0,5) === startTime);
					if (ov?.closed) continue;
					sessions.push({ date: key, dateObj: d, startTime, laneCount: tpl.lane_count });
				}
			}
		}
		return sessions;
	});

	const upcomingTrainingDays = $derived.by(() => {
		const map = new Map();
		for (const s of nextTrainings) {
			if (!map.has(s.date)) map.set(s.date, { date: s.date, dateObj: s.dateObj, slots: [] });
			map.get(s.date).slots.push(s);
		}
		return [...map.values()].slice(0, 3);
	});

	function dayLabel(dateObj) {
		const base = new Date(); base.setHours(0,0,0,0);
		const diff = Math.round((dateObj - base) / 86400000);
		if (diff === 0) return 'Heute';
		if (diff === 1) return 'Morgen';
		return DAY_SHORT[dateObj.getDay()];
	}

	function go(key) {
		setSubtab($page.url.pathname, key);
	}
</script>

<div class="kueb-page">
	<!-- Nav Hub -->
	<div class="kueb-hub-grid">
		{#each hubs as h}
			<button class="kueb-hub-tile" onclick={() => go(h.key)}>
				<span class="material-symbols-outlined kueb-hub-icon">{h.icon}</span>
				<div class="kueb-hub-text">
					<span class="kueb-hub-label">{h.label}</span>
					<span class="kueb-hub-desc">{h.desc}</span>
				</div>
				<span class="material-symbols-outlined kueb-hub-arrow">chevron_right</span>
			</button>
		{/each}
	</div>

	<!-- Nächste Events -->
	<div class="kueb-section">
		<div class="kueb-sec-head">
			<span class="material-symbols-outlined kueb-sec-icon">calendar_month</span>
			<span class="kueb-sec-title">Nächste Events</span>
		</div>
		{#if loading}
			<div class="kueb-skeleton"></div>
			<div class="kueb-skeleton"></div>
		{:else if events.length === 0}
			<p class="kueb-empty">Keine bevorstehenden Events</p>
		{:else}
			<div class="kueb-list">
				{#each events as ev}
					{@const d = new Date(ev.date + 'T00:00:00')}
					<div class="kueb-event-row">
						<div class="kueb-day-badge">
							<span class="kueb-day-num">{d.getDate()}</span>
							<span class="kueb-day-mon">{MONTH_FULL[d.getMonth()].slice(0,3)}</span>
						</div>
						<div class="kueb-event-info">
							<span class="kueb-event-title">{ev.title}</span>
							{#if ev.location || ev.time}
								<span class="kueb-event-sub">
									{#if ev.time}{fmtTime(ev.time)}{/if}{#if ev.time && ev.location} · {/if}{ev.location ?? ''}
								</span>
							{/if}
						</div>
					</div>
				{/each}
			</div>
		{/if}
		<button class="kueb-more-btn" onclick={() => go('events')}>Alle Events</button>
	</div>

	<!-- Nächste Trainings -->
	<div class="kueb-section">
		<div class="kueb-sec-head">
			<span class="material-symbols-outlined kueb-sec-icon">fitness_center</span>
			<span class="kueb-sec-title">Nächste Trainings</span>
		</div>
		{#if loading}
			<div class="kueb-skeleton"></div>
			<div class="kueb-skeleton"></div>
		{:else if upcomingTrainingDays.length === 0}
			<p class="kueb-empty">Keine Trainings in den nächsten 14 Tagen</p>
		{:else}
			<div class="kueb-list">
				{#each upcomingTrainingDays as day}
					<div class="kueb-training-row">
						<div class="kueb-training-label-col">
							<span class="kueb-training-weekday">{dayLabel(day.dateObj)}</span>
							<span class="kueb-training-date">{day.dateObj.getDate()}. {MONTH_FULL[day.dateObj.getMonth()].slice(0,3)}</span>
						</div>
						<div class="kueb-training-slots">
							{#each day.slots as slot}
								<span class="kueb-slot-chip">{slot.startTime} · {slot.laneCount} Bahnen</span>
							{/each}
						</div>
					</div>
				{/each}
			</div>
		{/if}
		<button class="kueb-more-btn" onclick={() => go('trainings')}>Alle Trainings</button>
	</div>
</div>

<style>
.kueb-page {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
	padding: var(--space-5);
}

.kueb-hub-grid {
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.kueb-hub-tile {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-4) var(--space-4);
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 14px;
	cursor: pointer;
	text-align: left;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms;
}

.kueb-hub-tile:active { background: var(--color-surface-container-low); }

.kueb-hub-icon {
	font-size: 1.5rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	flex-shrink: 0;
}

.kueb-hub-text {
	flex: 1;
	display: flex;
	flex-direction: column;
	gap: 1px;
}

.kueb-hub-label {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.95rem;
	color: var(--color-on-surface);
}

.kueb-hub-desc {
	font-size: 0.78rem;
	color: var(--color-on-surface-variant);
}

.kueb-hub-arrow {
	color: var(--color-on-surface-variant);
	font-size: 1.1rem;
	flex-shrink: 0;
}

.kueb-section {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.kueb-sec-head {
	display: flex;
	align-items: center;
	gap: var(--space-2);
}

.kueb-sec-icon {
	font-size: 1rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.kueb-sec-title {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.875rem;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-primary);
}

.kueb-skeleton {
	height: 48px;
	background: var(--color-surface-container-low);
	border-radius: 10px;
	animation: kpulse 1.4s ease-in-out infinite;
}

@keyframes kpulse {
	0%, 100% { opacity: 1; }
	50%       { opacity: 0.5; }
}

.kueb-empty {
	font-size: 0.85rem;
	color: var(--color-on-surface-variant);
	margin: 0;
	text-align: center;
	padding: var(--space-2) 0;
}

.kueb-list {
	display: flex;
	flex-direction: column;
	gap: 0;
}

.kueb-event-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-2) 0;
	border-top: 1px solid var(--color-surface-container);
}

.kueb-event-row:first-child { border-top: none; padding-top: 0; }

.kueb-day-badge {
	display: flex;
	flex-direction: column;
	align-items: center;
	min-width: 36px;
	flex-shrink: 0;
}

.kueb-day-num {
	font-family: var(--font-display);
	font-size: 1.3rem;
	font-weight: 900;
	color: var(--color-primary);
	line-height: 1;
}

.kueb-day-mon {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}

.kueb-event-info {
	flex: 1;
	min-width: 0;
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.kueb-event-title {
	font-weight: 700;
	font-size: 0.88rem;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.kueb-event-sub {
	font-size: 0.75rem;
	color: var(--color-on-surface-variant);
}

.kueb-training-row {
	display: flex;
	align-items: flex-start;
	gap: var(--space-3);
	padding: var(--space-2) 0;
	border-top: 1px solid var(--color-surface-container);
}

.kueb-training-row:first-child { border-top: none; padding-top: 0; }

.kueb-training-label-col {
	min-width: 56px;
	flex-shrink: 0;
}

.kueb-training-weekday {
	display: block;
	font-family: var(--font-display);
	font-size: 0.8rem;
	font-weight: 800;
	color: var(--color-primary);
}

.kueb-training-date {
	display: block;
	font-size: 0.72rem;
	color: var(--color-on-surface-variant);
}

.kueb-training-slots {
	flex: 1;
	display: flex;
	flex-wrap: wrap;
	gap: 4px;
}

.kueb-slot-chip {
	font-size: 0.72rem;
	font-weight: 700;
	padding: 3px 9px;
	background: var(--color-surface-container-low);
	border-radius: 999px;
	color: var(--color-on-surface-variant);
	white-space: nowrap;
}

.kueb-more-btn {
	align-self: flex-start;
	background: none;
	border: none;
	padding: 0;
	font-size: 0.8rem;
	font-weight: 700;
	color: var(--color-primary);
	cursor: pointer;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
}
</style>
