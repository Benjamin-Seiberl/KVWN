<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';
	import { MONTH_FULL } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import TrainingDetailSheet from '$lib/components/kalender/TrainingDetailSheet.svelte';
	import MatchDetailSheet from '$lib/components/kalender/MatchDetailSheet.svelte';
	import EventDetailSheet from '$lib/components/kalender/EventDetailSheet.svelte';

	const today = new Date();
	let viewYear    = $state(today.getFullYear());
	let viewMonth   = $state(today.getMonth());
	let selectedDay = $state(today.getDate());

	let matches   = $state([]);
	let events    = $state([]);
	let templates = $state([]);
	let overrides = $state([]);
	let specials  = $state([]);

	const WEEKDAY_LONG = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];
	const DAY_NAMES_WEEK = ['Mo','Di','Mi','Do','Fr','Sa','So'];

	function fmt(y, m, d) {
		return `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
	}
	function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
	function firstWeekday(y, m) {
		const d = new Date(y, m, 1).getDay();
		return d === 0 ? 6 : d - 1;
	}

	async function loadMonth() {
		const from = fmt(viewYear, viewMonth, 1);
		const to   = fmt(viewYear, viewMonth, daysInMonth(viewYear, viewMonth));
		const [
			{ data: m,  error: e1 },
			{ data: ev, error: e2 },
			{ data: t,  error: e3 },
			{ data: o,  error: e4 },
			{ data: s,  error: e5 },
		] = await Promise.all([
			sb.from('matches').select('id, date, time, home_away, opponent, location, round, is_tournament, is_landesbewerb, tournament_title, league_id, leagues(name)').gte('date', from).lte('date', to),
			sb.from('events').select('*').gte('date', from).lte('date', to),
			sb.from('training_templates').select('*').eq('active', true),
			sb.from('training_overrides').select('*').gte('date', from).lte('date', to),
			sb.from('training_specials').select('*').gte('date', from).lte('date', to),
		]);
		const err = e1 ?? e2 ?? e3 ?? e4 ?? e5;
		if (err) { triggerToast('Fehler: ' + err.message); return; }
		matches   = m ?? [];
		events    = ev ?? [];
		templates = t ?? [];
		overrides = o ?? [];
		specials  = s ?? [];
	}

	function prevMonth() {
		if (viewMonth === 0) { viewMonth = 11; viewYear--; } else viewMonth--;
		selectedDay = null;
		loadMonth();
	}
	function nextMonth() {
		if (viewMonth === 11) { viewMonth = 0; viewYear++; } else viewMonth++;
		selectedDay = null;
		loadMonth();
	}

	function isToday(d) {
		return viewYear === today.getFullYear() && viewMonth === today.getMonth() && d === today.getDate();
	}

	function hasMatch(key) {
		return matches.some(x => x.date === key && x.opponent?.toLowerCase() !== 'spielfrei');
	}
	function hasEvent(key) {
		return events.some(x => x.date === key);
	}
	function hasTraining(key) {
		const d = new Date(key + 'T00:00:00');
		const dow = d.getDay();
		if (specials.some(s => s.date === key)) return true;
		const tpls = templates.filter(t => t.day_of_week === dow);
		if (tpls.length === 0) return false;
		for (const tpl of tpls) {
			const sh = Number(String(tpl.start_time).slice(0,2));
			const eh = Number(String(tpl.end_time).slice(0,2));
			for (let h = sh; h < eh; h++) {
				const startTime = `${String(h).padStart(2,'0')}:00`;
				const ov = overrides.find(o => o.date === key && String(o.start_time).slice(0,5) === startTime);
				if (!ov?.closed) return true;
			}
		}
		return false;
	}

	// ── Calendar grid ─────────────────────────────────────────────────────────
	const calendarCells = $derived.by(() => {
		const cells = [];
		const offset = firstWeekday(viewYear, viewMonth);
		const dim    = daysInMonth(viewYear, viewMonth);
		const prevDim = daysInMonth(viewMonth === 0 ? viewYear - 1 : viewYear, viewMonth === 0 ? 11 : viewMonth - 1);
		for (let i = 0; i < offset; i++) cells.push({ day: prevDim - offset + 1 + i, current: false });
		for (let d = 1; d <= dim; d++) cells.push({ day: d, current: true });
		const remaining = (7 - (cells.length % 7)) % 7;
		for (let i = 1; i <= remaining; i++) cells.push({ day: i, current: false });
		return cells;
	});

	const selectedKey = $derived(selectedDay ? fmt(viewYear, viewMonth, selectedDay) : null);

	const selectedLabel = $derived.by(() => {
		if (!selectedDay) return '';
		const d = new Date(viewYear, viewMonth, selectedDay);
		return WEEKDAY_LONG[d.getDay()] + ', ' + selectedDay + '. ' + MONTH_FULL[viewMonth];
	});

	// ── Day timeline ──────────────────────────────────────────────────────────
	function toMinutes(t) {
		if (!t) return 0;
		const s = String(t);
		return Number(s.slice(0,2)) * 60 + Number(s.slice(3,5));
	}

	const dayTimeline = $derived.by(() => {
		if (!selectedKey) return [];
		const items = [];

		for (const m of matches.filter(m => m.date === selectedKey && m.opponent?.toLowerCase() !== 'spielfrei')) {
			items.push({ type: 'match', sortTime: toMinutes(m.time), data: m });
		}
		for (const ev of events.filter(e => e.date === selectedKey)) {
			items.push({ type: 'event', sortTime: toMinutes(ev.time), data: ev });
		}

		// Trainings: expand for this day only
		const d = new Date(selectedKey + 'T00:00:00');
		const dow = d.getDay();
		const tplSlots = [];
		for (const tpl of templates.filter(t => t.day_of_week === dow)) {
			const sh = Number(String(tpl.start_time).slice(0,2));
			const eh = Number(String(tpl.end_time).slice(0,2));
			for (let h = sh; h < eh; h++) {
				const startTime = `${String(h).padStart(2,'0')}:00`;
				const endTime   = `${String(h+1).padStart(2,'0')}:00`;
				const ov = overrides.find(o => o.date === selectedKey && String(o.start_time).slice(0,5) === startTime);
				if (ov?.closed) continue;
				tplSlots.push({ start_time: startTime, end_time: endTime });
			}
		}
		for (const sp of specials.filter(s => s.date === selectedKey)) {
			tplSlots.push({ start_time: String(sp.start_time).slice(0,5), end_time: String(sp.end_time).slice(0,5) });
		}
		if (tplSlots.length > 0) {
			tplSlots.sort((a,b) => a.start_time.localeCompare(b.start_time));
			const first = tplSlots[0];
			const last  = tplSlots[tplSlots.length - 1];
			items.push({
				type: 'training',
				sortTime: toMinutes(first.start_time),
				data: { date: selectedKey, startTime: first.start_time, endTime: last.end_time },
			});
		}

		items.sort((a, b) => a.sortTime - b.sortTime);
		return items;
	});

	// ── Sheets ────────────────────────────────────────────────────────────────
	let trSheetOpen    = $state(false);
	let trSheetDate    = $state(null);
	let matchSheetOpen = $state(false);
	let matchSheetData = $state(null);
	let eventSheetOpen = $state(false);
	let eventSheetData = $state(null);

	function openMatchSheet(m) { matchSheetData = m; matchSheetOpen = true; }
	function openEventSheet(e) { eventSheetData = e; eventSheetOpen = true; }
	function openTrSheet(d)    { trSheetDate = d;   trSheetOpen    = true; }

	onMount(loadMonth);
</script>

<div class="mo-page">
	<div class="kal-card">
		<div class="kal-month-nav">
			<button class="kal-nav-btn" onclick={prevMonth} aria-label="Vorheriger Monat">
				<span class="material-symbols-outlined">chevron_left</span>
			</button>
			<span class="kal-month-label">
				{MONTH_FULL[viewMonth]} <span class="kal-month-year">{viewYear}</span>
			</span>
			<button class="kal-nav-btn" onclick={nextMonth} aria-label="Nächster Monat">
				<span class="material-symbols-outlined">chevron_right</span>
			</button>
		</div>

		<div class="kal-grid kal-grid--header">
			{#each DAY_NAMES_WEEK as d}<div class="kal-day-label">{d}</div>{/each}
		</div>

		<div class="kal-grid kal-grid--days">
			{#each calendarCells as cell}
				{#if cell.current}
					{@const key = fmt(viewYear, viewMonth, cell.day)}
					{@const mt  = hasMatch(key)}
					{@const ev  = hasEvent(key)}
					{@const tr  = hasTraining(key)}
					<div class="kal-cell">
						<button
							class="kal-day-btn"
							class:kal-day-btn--today={isToday(cell.day)}
							class:kal-day-btn--selected={selectedDay === cell.day}
							onclick={() => selectedDay = cell.day}
						>
							{cell.day}
							{#if mt || ev || tr}
								<span class="kal-dots">
									{#if mt}<span class="kal-dot kal-dot--match"></span>{/if}
									{#if tr}<span class="kal-dot kal-dot--training"></span>{/if}
									{#if ev}<span class="kal-dot kal-dot--event"></span>{/if}
								</span>
							{/if}
						</button>
					</div>
				{:else}
					<div class="kal-cell kal-cell--ghost">
						<span class="kal-day-ghost">{cell.day}</span>
					</div>
				{/if}
			{/each}
		</div>

		<div class="kal-legend">
			<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--match"></span><span>Match</span></div>
			<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--training"></span><span>Training</span></div>
			<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--event"></span><span>Event</span></div>
		</div>
	</div>

	<section class="kal-slots">
		{#if selectedDay}
			<h2 class="kal-slots-heading">
				<span class="material-symbols-outlined">event</span>
				{selectedLabel}
			</h2>

			{#if dayTimeline.length === 0}
				<div class="kal-no-events">
					<span class="material-symbols-outlined kal-no-events-icon">event_available</span>
					<p>Nichts geplant</p>
				</div>
			{:else}
				<div class="kal-event-list">
					{#each dayTimeline as item}

						{#if item.type === 'match'}
							{@const m = item.data}
							{@const isTourney = m.is_tournament || m.is_landesbewerb}
							<button class="kal-event-card kal-event-card--match" onclick={() => openMatchSheet(m)}>
								<div class="kal-event-time-col kal-event-time-col--match">
									<span class="kal-event-time-text">{shortTime(m.time) || '—'}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label">{isTourney ? (m.is_landesbewerb ? 'Landesbewerb' : 'Turnier') : 'Match'}{m.round ? ' ' + m.round : ''}</div>
									<h3 class="kal-event-title">
										{#if isTourney}{m.tournament_title ?? m.opponent}{:else}{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}{/if}
									</h3>
									{#if m.location}<p class="kal-event-desc">{m.location}</p>{/if}
								</div>
							</button>

						{:else if item.type === 'training'}
							{@const tr = item.data}
							<button class="kal-event-card kal-event-card--training" onclick={() => openTrSheet(tr.date)}>
								<div class="kal-event-time-col kal-event-time-col--training">
									<span class="kal-event-time-text">{tr.startTime}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label kal-event-type-label--training">Training</div>
									<h3 class="kal-event-title">{tr.startTime} – {tr.endTime} Uhr</h3>
									<p class="kal-event-desc">Plätze ansehen & buchen</p>
								</div>
							</button>

						{:else if item.type === 'event'}
							{@const ev = item.data}
							<button class="kal-event-card kal-event-card--event" onclick={() => openEventSheet(ev)}>
								<div class="kal-event-time-col kal-event-time-col--event">
									<span class="kal-event-time-text">{shortTime(ev.time) || '—'}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label kal-event-type-label--event">Termin</div>
									<h3 class="kal-event-title">{ev.title}</h3>
									{#if ev.location}<p class="kal-event-desc">{ev.location}</p>{/if}
								</div>
							</button>

						{/if}
					{/each}
				</div>
			{/if}
		{:else}
			<div class="kal-no-events">
				<span class="material-symbols-outlined kal-no-events-icon">touch_app</span>
				<p>Tag auswählen</p>
			</div>
		{/if}
	</section>
</div>

<TrainingDetailSheet bind:open={trSheetOpen} date={trSheetDate} onReload={loadMonth} />
<MatchDetailSheet    bind:open={matchSheetOpen} match={matchSheetData} />
<EventDetailSheet    bind:open={eventSheetOpen} event={eventSheetData} />

<style>
	.mo-page { display: flex; flex-direction: column; gap: var(--space-6); padding: var(--space-5) var(--space-5) var(--space-8); }

	.kal-month-nav { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-3); }
	.kal-month-label { font-family: var(--font-display); font-size: 0.8rem; font-weight: 700; color: var(--color-on-surface-variant); letter-spacing: 0.04em; }
	.kal-month-year { font-weight: 500; color: var(--color-outline); }
	.kal-nav-btn { width: 1.6rem; height: 1.6rem; display: flex; align-items: center; justify-content: center; border-radius: var(--radius-sm); background: none; color: var(--color-outline); transition: background 0.12s, transform 0.1s; border: 0; cursor: pointer; }
	.kal-nav-btn .material-symbols-outlined { font-size: 1.1rem; }
	.kal-nav-btn:active { transform: scale(0.88); background: var(--color-surface-container); }

	.kal-card { background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: var(--space-5); overflow: hidden; }
	.kal-grid { display: grid; grid-template-columns: repeat(7, 1fr); width: 100%; }
	.kal-grid--header { margin-bottom: var(--space-3); }
	.kal-day-label { text-align: center; font-size: var(--text-label-sm); font-weight: 700; color: var(--color-outline); text-transform: uppercase; letter-spacing: 0.05em; }
	.kal-grid--days { gap: 2px 0; }
	.kal-cell { display: flex; justify-content: center; align-items: center; padding: 2px 1px; min-width: 0; }
	.kal-cell--ghost { opacity: 0.25; }
	.kal-day-ghost { font-size: var(--text-body-md); color: var(--color-outline); padding: 0.4rem; }
	.kal-day-btn { position: relative; width: 100%; aspect-ratio: 1; max-width: 2.75rem; border-radius: var(--radius-md); font-size: var(--text-body-md); font-weight: 500; color: var(--color-on-surface); display: flex; align-items: center; justify-content: center; transition: background 0.12s, transform 0.1s; flex-direction: column; background: none; border: 0; cursor: pointer; }
	.kal-day-btn--today { font-weight: 800; background: var(--color-surface-container); }
	.kal-day-btn--selected { background: var(--color-primary) !important; color: #fff !important; font-weight: 800; box-shadow: var(--shadow-float); }
	.kal-dots { position: absolute; bottom: 4px; display: flex; gap: 2px; }
	.kal-dot { width: 4px; height: 4px; border-radius: 50%; }
	.kal-dot--match    { background: var(--color-secondary); }
	.kal-dot--event    { background: #2a78b4; }
	.kal-dot--training { background: var(--color-primary); }
	.kal-day-btn--selected .kal-dot { background: rgba(255,255,255,0.9); }
	.kal-legend { display: flex; gap: var(--space-4); padding-top: var(--space-4); margin-top: var(--space-4); border-top: 1px solid var(--color-surface-container); flex-wrap: wrap; }
	.kal-legend-item { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-label-sm); font-weight: 600; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.05em; }
	.kal-legend-dot { width: 10px; height: 10px; border-radius: 50%; }
	.kal-legend-dot--match    { background: var(--color-secondary); }
	.kal-legend-dot--event    { background: #2a78b4; }
	.kal-legend-dot--training { background: var(--color-primary); }

	.kal-slots-heading { display: flex; align-items: center; gap: var(--space-2); font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: var(--space-4); }
	.kal-slots-heading .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); }
	.kal-event-list { display: flex; flex-direction: column; gap: var(--space-4); }

	.kal-event-card { width: 100%; text-align: left; display: flex; background: linear-gradient(145deg, #ffffff, #f9f9f9); box-shadow: 8px 8px 24px #e8e8e8, -4px -4px 16px #ffffff; border-radius: var(--radius-lg); overflow: hidden; border: 1.5px solid #fff; color: inherit; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; font: inherit; }
	.kal-event-card:active { transform: scale(0.98); }
	.kal-event-card--match    { border: 1.5px solid rgba(212, 175, 55, 0.3); }
	.kal-event-card--event    { border: 1.5px solid rgba(42, 120, 180, 0.25); }
	.kal-event-card--training { border: 1.5px solid rgba(204, 0, 0, 0.22); }

	.kal-event-time-col { width: 3.5rem; flex-shrink: 0; display: flex; align-items: center; justify-content: center; margin: 4px; border-radius: var(--radius-md); padding: var(--space-2) var(--space-1); }
	.kal-event-time-col--match    { background: var(--color-secondary-container, #f5e6b2); }
	.kal-event-time-col--event    { background: #bfdaf0; }
	.kal-event-time-col--training { background: rgba(204, 0, 0, 0.12); }
	.kal-event-time-text { writing-mode: vertical-rl; text-orientation: mixed; transform: rotate(180deg); font-family: var(--font-display); font-size: 0.68rem; font-weight: 700; letter-spacing: 0.04em; color: #334; line-height: 1.3; white-space: nowrap; }
	.kal-event-card--training .kal-event-time-text { color: var(--color-primary); }

	.kal-event-body { flex: 1; padding: var(--space-4) var(--space-4) var(--space-4) var(--space-3); display: flex; flex-direction: column; gap: var(--space-2); }
	.kal-event-type-label { font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: #8a6f1e; }
	.kal-event-type-label--event    { color: #2a78b4; }
	.kal-event-type-label--training { color: var(--color-primary); }
	.kal-event-title { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 700; line-height: 1.2; margin: 0; }
	.kal-event-desc { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin: 0; }

	.kal-no-events { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.kal-no-events-icon { font-size: 2.5rem; opacity: 0.5; }
	.kal-no-events p { font-size: var(--text-body-md); font-weight: 500; }
</style>
