<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';
	import { MONTH_FULL } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import TrainingDetailSheet from '$lib/components/kalender/TrainingDetailSheet.svelte';
	import MatchDetailSheet from '$lib/components/kalender/MatchDetailSheet.svelte';
	import EventDetailSheet from '$lib/components/kalender/EventDetailSheet.svelte';

	const today = new Date(); today.setHours(0,0,0,0);

	function mondayOf(d) {
		const x = new Date(d); x.setHours(0,0,0,0);
		const dow = x.getDay();
		const diff = dow === 0 ? -6 : 1 - dow;
		x.setDate(x.getDate() + diff);
		return x;
	}
	function fmt(d) {
		return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
	}
	function isoWeek(d) {
		const x = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
		const dayNum = x.getUTCDay() || 7;
		x.setUTCDate(x.getUTCDate() + 4 - dayNum);
		const yearStart = new Date(Date.UTC(x.getUTCFullYear(), 0, 1));
		return Math.ceil((((x - yearStart) / 86400000) + 1) / 7);
	}

	let weekStart = $state(mondayOf(today));

	let matches   = $state([]);
	let events    = $state([]);
	let templates = $state([]);
	let overrides = $state([]);
	let specials  = $state([]);

	let selectedKey = $state(fmt(today));

	const WEEKDAY_SHORT = ['Mo','Di','Mi','Do','Fr','Sa','So'];
	const WEEKDAY_LONG  = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];

	const weekDays = $derived.by(() => {
		const days = [];
		for (let i = 0; i < 7; i++) {
			const d = new Date(weekStart); d.setDate(weekStart.getDate() + i);
			days.push({ date: d, key: fmt(d) });
		}
		return days;
	});

	const weekLabel = $derived.by(() => {
		const end = new Date(weekStart); end.setDate(weekStart.getDate() + 6);
		const sameMonth = weekStart.getMonth() === end.getMonth();
		const sameYear  = weekStart.getFullYear() === end.getFullYear();
		const startStr = `${weekStart.getDate()}.${sameMonth ? '' : ' ' + MONTH_FULL[weekStart.getMonth()].slice(0,3)}`;
		const endStr   = `${end.getDate()}. ${MONTH_FULL[end.getMonth()].slice(0,3)}${sameYear ? '' : ' ' + end.getFullYear()}`;
		return `KW ${isoWeek(weekStart)} · ${startStr} – ${endStr}`;
	});

	async function loadWeek() {
		const from = fmt(weekStart);
		const endD = new Date(weekStart); endD.setDate(weekStart.getDate() + 6);
		const to   = fmt(endD);
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

	function prevWeek() {
		const d = new Date(weekStart); d.setDate(weekStart.getDate() - 7);
		weekStart = d;
		loadWeek();
	}
	function nextWeek() {
		const d = new Date(weekStart); d.setDate(weekStart.getDate() + 7);
		weekStart = d;
		loadWeek();
	}

	function isTodayKey(key) { return key === fmt(today); }

	function toMinutes(t) {
		if (!t) return 0;
		const s = String(t);
		return Number(s.slice(0,2)) * 60 + Number(s.slice(3,5));
	}

	function trainingSlotsFor(key) {
		const d = new Date(key + 'T00:00:00');
		const dow = d.getDay();
		const slots = [];
		for (const tpl of templates.filter(t => t.day_of_week === dow)) {
			const sh = Number(String(tpl.start_time).slice(0,2));
			const eh = Number(String(tpl.end_time).slice(0,2));
			for (let h = sh; h < eh; h++) {
				const startTime = `${String(h).padStart(2,'0')}:00`;
				const endTime   = `${String(h+1).padStart(2,'0')}:00`;
				const ov = overrides.find(o => o.date === key && String(o.start_time).slice(0,5) === startTime);
				if (ov?.closed) continue;
				slots.push({ start_time: startTime, end_time: endTime });
			}
		}
		for (const sp of specials.filter(s => s.date === key)) {
			slots.push({ start_time: String(sp.start_time).slice(0,5), end_time: String(sp.end_time).slice(0,5) });
		}
		slots.sort((a,b) => a.start_time.localeCompare(b.start_time));
		return slots;
	}

	// Items per day for mini column list (sorted chronologically)
	function itemsForDay(key) {
		const items = [];
		for (const m of matches.filter(m => m.date === key && m.opponent?.toLowerCase() !== 'spielfrei')) {
			items.push({ type: 'match', sortTime: toMinutes(m.time), data: m });
		}
		for (const ev of events.filter(e => e.date === key)) {
			items.push({ type: 'event', sortTime: toMinutes(ev.time), data: ev });
		}
		const trs = trainingSlotsFor(key);
		if (trs.length > 0) {
			const first = trs[0];
			const last  = trs[trs.length - 1];
			items.push({
				type: 'training',
				sortTime: toMinutes(first.start_time),
				data: { date: key, startTime: first.start_time, endTime: last.end_time },
			});
		}
		items.sort((a,b) => a.sortTime - b.sortTime);
		return items;
	}

	function typeLetter(type) {
		if (type === 'training') return 'T';
		if (type === 'match')    return 'S';
		return 'E';
	}

	function miniTitle(item) {
		if (item.type === 'training') return 'Training';
		if (item.type === 'match')    return item.data.home_away === 'HEIM' ? 'vs. ' + (item.data.opponent?.split(' ')[0] ?? '') : 'bei ' + (item.data.opponent?.split(' ')[0] ?? '');
		return item.data.title;
	}

	const selectedLabel = $derived.by(() => {
		if (!selectedKey) return '';
		const d = new Date(selectedKey + 'T00:00:00');
		return WEEKDAY_LONG[d.getDay()] + ', ' + d.getDate() + '. ' + MONTH_FULL[d.getMonth()];
	});

	const selectedTimeline = $derived(selectedKey ? itemsForDay(selectedKey) : []);

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

	onMount(loadWeek);
</script>

<div class="wo-page">
	<div class="wo-card">
		<div class="wo-nav">
			<button class="wo-nav-btn" onclick={prevWeek} aria-label="Vorherige Woche">
				<span class="material-symbols-outlined">chevron_left</span>
			</button>
			<span class="wo-nav-label">{weekLabel}</span>
			<button class="wo-nav-btn" onclick={nextWeek} aria-label="Nächste Woche">
				<span class="material-symbols-outlined">chevron_right</span>
			</button>
		</div>

		<div class="wo-grid">
			{#each weekDays as day, i (day.key)}
				{@const items = itemsForDay(day.key)}
				{@const types = new Set(items.map(it => it.type))}
				<button
					class="wo-col"
					class:wo-col--today={isTodayKey(day.key)}
					class:wo-col--selected={selectedKey === day.key}
					onclick={() => selectedKey = day.key}
				>
					<span class="wo-col-label">{WEEKDAY_SHORT[i]}</span>
					<span class="wo-col-num">{day.date.getDate()}</span>

					<span class="wo-col-dots">
						{#if types.has('training')}<span class="wo-dot wo-dot--training"></span>{/if}
						{#if types.has('match')}<span class="wo-dot wo-dot--match"></span>{/if}
						{#if types.has('event')}<span class="wo-dot wo-dot--event"></span>{/if}
					</span>

					<div class="wo-col-list">
						{#each items.slice(0, 3) as item}
							<span class="wo-mini wo-mini--{item.type}">
								<span class="wo-mini-time">
									{#if item.type === 'training'}{item.data.startTime}
									{:else if item.type === 'match'}{shortTime(item.data.time)}
									{:else}{shortTime(item.data.time) || '—'}{/if}
								</span>
								<span class="wo-mini-letter">{typeLetter(item.type)}</span>
							</span>
						{/each}
						{#if items.length > 3}
							<span class="wo-mini wo-mini--more">+{items.length - 3}</span>
						{/if}
					</div>
				</button>
			{/each}
		</div>

		<div class="wo-legend">
			<div class="wo-legend-item"><span class="wo-legend-dot wo-legend-dot--match"></span><span>Spiel</span></div>
			<div class="wo-legend-item"><span class="wo-legend-dot wo-legend-dot--training"></span><span>Training</span></div>
			<div class="wo-legend-item"><span class="wo-legend-dot wo-legend-dot--event"></span><span>Event</span></div>
		</div>
	</div>

	<section class="wo-slots">
		{#if selectedKey}
			<h2 class="wo-slots-heading">
				<span class="material-symbols-outlined">event</span>
				{selectedLabel}
			</h2>

			{#if selectedTimeline.length === 0}
				<div class="wo-no-events">
					<span class="material-symbols-outlined wo-no-events-icon">event_available</span>
					<p>Nichts geplant</p>
				</div>
			{:else}
				<div class="wo-event-list">
					{#each selectedTimeline as item}

						{#if item.type === 'match'}
							{@const m = item.data}
							{@const isTourney = m.is_tournament || m.is_landesbewerb}
							<button class="wo-event-card wo-event-card--match" onclick={() => openMatchSheet(m)}>
								<div class="wo-event-time-col wo-event-time-col--match">
									<span class="wo-event-time-text">{shortTime(m.time) || '—'}</span>
								</div>
								<div class="wo-event-body">
									<div class="wo-event-type-label">{isTourney ? (m.is_landesbewerb ? 'Landesbewerb' : 'Turnier') : 'Match'}{m.round ? ' ' + m.round : ''}</div>
									<h3 class="wo-event-title">
										{#if isTourney}{m.tournament_title ?? m.opponent}{:else}{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}{/if}
									</h3>
									{#if m.location}<p class="wo-event-desc">{m.location}</p>{/if}
								</div>
							</button>

						{:else if item.type === 'training'}
							{@const tr = item.data}
							<button class="wo-event-card wo-event-card--training" onclick={() => openTrSheet(tr.date)}>
								<div class="wo-event-time-col wo-event-time-col--training">
									<span class="wo-event-time-text">{tr.startTime}</span>
								</div>
								<div class="wo-event-body">
									<div class="wo-event-type-label wo-event-type-label--training">Training</div>
									<h3 class="wo-event-title">{tr.startTime} – {tr.endTime} Uhr</h3>
									<p class="wo-event-desc">Plätze ansehen & buchen</p>
								</div>
							</button>

						{:else if item.type === 'event'}
							{@const ev = item.data}
							<button class="wo-event-card wo-event-card--event" onclick={() => openEventSheet(ev)}>
								<div class="wo-event-time-col wo-event-time-col--event">
									<span class="wo-event-time-text">{shortTime(ev.time) || '—'}</span>
								</div>
								<div class="wo-event-body">
									<div class="wo-event-type-label wo-event-type-label--event">Termin</div>
									<h3 class="wo-event-title">{ev.title}</h3>
									{#if ev.location}<p class="wo-event-desc">{ev.location}</p>{/if}
								</div>
							</button>

						{/if}
					{/each}
				</div>
			{/if}
		{/if}
	</section>
</div>

<TrainingDetailSheet bind:open={trSheetOpen} date={trSheetDate} onReload={loadWeek} />
<MatchDetailSheet    bind:open={matchSheetOpen} match={matchSheetData} />
<EventDetailSheet    bind:open={eventSheetOpen} event={eventSheetData} />

<style>
	.wo-page { display: flex; flex-direction: column; gap: var(--space-6); padding: var(--space-5) var(--space-5) var(--space-8); }

	.wo-card { background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: var(--space-4); overflow: hidden; }

	.wo-nav { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-3); }
	.wo-nav-label { font-family: var(--font-display); font-size: 0.8rem; font-weight: 700; color: var(--color-on-surface-variant); letter-spacing: 0.04em; text-align: center; flex: 1; }
	.wo-nav-btn { width: 1.6rem; height: 1.6rem; display: flex; align-items: center; justify-content: center; border-radius: var(--radius-sm); background: none; color: var(--color-outline); border: 0; cursor: pointer; transition: background 0.12s, transform 0.1s; }
	.wo-nav-btn .material-symbols-outlined { font-size: 1.1rem; }
	.wo-nav-btn:active { transform: scale(0.88); background: var(--color-surface-container); }

	.wo-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 3px; }
	.wo-col {
		display: flex; flex-direction: column; align-items: center; gap: 3px;
		min-width: 0; padding: var(--space-2) 2px;
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer; font: inherit; color: inherit;
		-webkit-tap-highlight-color: transparent;
		transition: background 120ms ease, transform 100ms ease, border-color 120ms ease;
		min-height: 110px;
	}
	.wo-col:active { transform: scale(0.97); }
	.wo-col--today { border-color: var(--color-primary); border-width: 2px; }
	.wo-col--selected { background: var(--color-primary); color: #fff; border-color: var(--color-primary); }
	.wo-col--selected .wo-col-label,
	.wo-col--selected .wo-col-num,
	.wo-col--selected .wo-mini-time,
	.wo-col--selected .wo-mini-letter { color: #fff; }
	.wo-col--selected .wo-mini { background: rgba(255,255,255,0.18); }
	.wo-col--selected .wo-dot { outline: 1px solid rgba(255,255,255,0.6); }

	.wo-col-label {
		font-size: 0.62rem; font-weight: 700; text-transform: uppercase;
		letter-spacing: 0.05em; color: var(--color-outline);
	}
	.wo-col-num {
		font-family: var(--font-display); font-size: 1rem; font-weight: 800;
		color: var(--color-on-surface); line-height: 1;
	}
	.wo-col-dots { display: flex; gap: 2px; min-height: 5px; }
	.wo-dot { width: 5px; height: 5px; border-radius: 50%; }
	.wo-dot--match    { background: var(--color-secondary); }
	.wo-dot--event    { background: #2a78b4; }
	.wo-dot--training { background: var(--color-primary); }

	.wo-col-list { display: flex; flex-direction: column; gap: 2px; width: 100%; padding: 0 1px; }
	.wo-mini {
		display: flex; align-items: center; justify-content: space-between; gap: 2px;
		padding: 1px 3px; border-radius: 3px;
		background: var(--color-surface-container);
		font-size: 0.58rem; font-weight: 600;
		line-height: 1.2;
		min-width: 0;
	}
	.wo-mini-time { color: var(--color-on-surface-variant); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.wo-mini-letter {
		flex-shrink: 0;
		font-weight: 800;
		font-size: 0.55rem;
		padding: 0 3px;
		border-radius: 2px;
	}
	.wo-mini--training .wo-mini-letter { background: rgba(204,0,0,0.15); color: var(--color-primary); }
	.wo-mini--match    .wo-mini-letter { background: color-mix(in srgb, var(--color-secondary) 25%, transparent); color: #8a6f1e; }
	.wo-mini--event    .wo-mini-letter { background: rgba(42,120,180,0.18); color: #2a78b4; }
	.wo-mini--more     { justify-content: center; font-size: 0.55rem; color: var(--color-outline); }

	.wo-legend { display: flex; gap: var(--space-4); padding-top: var(--space-3); margin-top: var(--space-3); border-top: 1px solid var(--color-surface-container); flex-wrap: wrap; justify-content: center; }
	.wo-legend-item { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-label-sm); font-weight: 600; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.05em; }
	.wo-legend-dot { width: 10px; height: 10px; border-radius: 50%; }
	.wo-legend-dot--match    { background: var(--color-secondary); }
	.wo-legend-dot--event    { background: #2a78b4; }
	.wo-legend-dot--training { background: var(--color-primary); }

	.wo-slots-heading { display: flex; align-items: center; gap: var(--space-2); font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: var(--space-4); }
	.wo-slots-heading .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); }

	.wo-event-list { display: flex; flex-direction: column; gap: var(--space-4); }

	.wo-event-card { width: 100%; text-align: left; display: flex; background: linear-gradient(145deg, #ffffff, #f9f9f9); box-shadow: 8px 8px 24px #e8e8e8, -4px -4px 16px #ffffff; border-radius: var(--radius-lg); overflow: hidden; border: 1.5px solid #fff; color: inherit; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; font: inherit; }
	.wo-event-card:active { transform: scale(0.98); }
	.wo-event-card--match    { border: 1.5px solid rgba(212, 175, 55, 0.3); }
	.wo-event-card--event    { border: 1.5px solid rgba(42, 120, 180, 0.25); }
	.wo-event-card--training { border: 1.5px solid rgba(204, 0, 0, 0.22); }

	.wo-event-time-col { width: 3.5rem; flex-shrink: 0; display: flex; align-items: center; justify-content: center; margin: 4px; border-radius: var(--radius-md); padding: var(--space-2) var(--space-1); }
	.wo-event-time-col--match    { background: var(--color-secondary-container, #f5e6b2); }
	.wo-event-time-col--event    { background: #bfdaf0; }
	.wo-event-time-col--training { background: rgba(204, 0, 0, 0.12); }
	.wo-event-time-text { writing-mode: vertical-rl; text-orientation: mixed; transform: rotate(180deg); font-family: var(--font-display); font-size: 0.68rem; font-weight: 700; letter-spacing: 0.04em; color: #334; line-height: 1.3; white-space: nowrap; }
	.wo-event-card--training .wo-event-time-text { color: var(--color-primary); }

	.wo-event-body { flex: 1; padding: var(--space-4) var(--space-4) var(--space-4) var(--space-3); display: flex; flex-direction: column; gap: var(--space-2); }
	.wo-event-type-label { font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: #8a6f1e; }
	.wo-event-type-label--event    { color: #2a78b4; }
	.wo-event-type-label--training { color: var(--color-primary); }
	.wo-event-title { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 700; line-height: 1.2; margin: 0; }
	.wo-event-desc { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin: 0; }

	.wo-no-events { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.wo-no-events-icon { font-size: 2.5rem; opacity: 0.5; }
	.wo-no-events p { font-size: var(--text-body-md); font-weight: 500; }
</style>
