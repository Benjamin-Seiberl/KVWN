<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';

	let today       = new Date();
	let viewYear    = $state(today.getFullYear());
	let viewMonth   = $state(today.getMonth());
	let selectedDay = $state(today.getDate());

	let matches   = $state([]);   // aus public.matches im Monat
	let events    = $state([]);   // aus public.events im Monat
	let templates = $state([]);   // training_templates
	let overrides = $state([]);   // training_overrides (für sichtbaren Monat)
	let bookings  = $state([]);   // training_bookings
	let players   = $state([]);   // für Avatare in Bahn-Kreisen

	function fmt(y, m, d) {
		return `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
	}
	function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
	function firstWeekday(y, m) {
		const d = new Date(y, m, 1).getDay();
		return d === 0 ? 6 : d - 1;
	}

	const MONTH_NAMES = ['Jänner','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
	const DAY_NAMES   = ['Mo','Di','Mi','Do','Fr','Sa','So'];

	async function loadMonth() {
		const from = fmt(viewYear, viewMonth, 1);
		const to   = fmt(viewYear, viewMonth, daysInMonth(viewYear, viewMonth));
		const [{ data: m }, { data: ev }, { data: t }, { data: o }, { data: b }, { data: p }] = await Promise.all([
			sb.from('matches').select('id, date, time, home_away, opponent, location, round, is_tournament, tournament_title').gte('date', from).lte('date', to),
			sb.from('events').select('*').gte('date', from).lte('date', to),
			sb.from('training_templates').select('*').eq('active', true),
			sb.from('training_overrides').select('*').gte('date', from).lte('date', to),
			sb.from('training_bookings').select('*').gte('date', from).lte('date', to),
			sb.from('players').select('id, name, avatar_url, photo'),
		]);
		matches   = m ?? [];
		events    = ev ?? [];
		templates = t ?? [];
		overrides = o ?? [];
		bookings  = b ?? [];
		players   = p ?? [];
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

	function eventType(d) {
		const key = fmt(viewYear, viewMonth, d);
		if (matches.some(x => x.date === key)) return 'match';
		if (events.some(x  => x.date === key)) return 'event';
		// Training-Block an diesem Wochentag?
		const dow = new Date(viewYear, viewMonth, d).getDay();
		if (templates.some(t => t.day_of_week === dow)) return 'training';
		return null;
	}

	function getPlayer(id) {
		return players.find(p => p.id === id);
	}

	function hasRosterConflict(date, startTime) {
		// Ist an diesem Datum ein Match oder Event, das den Slot blockiert?
		return matches.some(m => m.date === date) || events.some(e => e.date === date && e.time && String(e.time).slice(0,5) <= startTime);
	}

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

	const selectedMatches = $derived(matches.filter(m => m.date === selectedKey));
	const selectedEvents  = $derived(events.filter(e => e.date === selectedKey));
	const selectedTrainings = $derived.by(() => {
		if (!selectedKey) return [];
		const dow = new Date(viewYear, viewMonth, selectedDay).getDay();
		const todayTpls = templates.filter(t => t.day_of_week === dow);
		const blocks = [];
		for (const t of todayTpls) {
			const sh = Number(String(t.start_time).slice(0,2));
			const eh = Number(String(t.end_time).slice(0,2));
			for (let h = sh; h < eh; h++) {
				const start = `${String(h).padStart(2,'0')}:00`;
				const ov = overrides.find(o => o.date === selectedKey && String(o.start_time).slice(0,5) === start);
				if (ov?.closed) continue;
				blocks.push({
					date: selectedKey,
					start_time: start,
					lane_count: t.lane_count,
					note: ov?.note,
				});
			}
		}
		return blocks;
	});

	const selectedLabel = $derived.by(() => {
		if (!selectedDay) return '';
		const d = new Date(viewYear, viewMonth, selectedDay);
		const weekdays = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];
		return weekdays[d.getDay()] + ', ' + selectedDay + '. ' + MONTH_NAMES[viewMonth];
	});

	function bookingsFor(date, startTime) {
		return bookings.filter(b => b.date === date && String(b.start_time).slice(0,5) === startTime);
	}
	function myBooking(date, startTime) {
		return bookingsFor(date, startTime).find(b => b.player_id === $playerId);
	}

	async function bookLane(date, startTime, lane) {
		if (!$playerId) return;
		const mine = myBooking(date, startTime);
		if (mine && mine.lane_number === lane) {
			await sb.from('training_bookings').delete().eq('id', mine.id);
		} else if (mine) {
			await sb.from('training_bookings').update({ lane_number: lane }).eq('id', mine.id);
		} else {
			await sb.from('training_bookings').insert({
				date, start_time: startTime, lane_number: lane, player_id: $playerId,
			});
		}
		loadMonth();
	}

	onMount(loadMonth);
</script>

<div class="page active">
	<div class="kal-page">

		<div class="kal-month-header">
			<div class="kal-month-nav">
				<button class="kal-nav-btn" onclick={prevMonth} aria-label="Vorheriger Monat">
					<span class="material-symbols-outlined">chevron_left</span>
				</button>
				<div class="kal-month-label">
					<span class="kal-month-name">{MONTH_NAMES[viewMonth]}</span>
					<span class="kal-month-year">{viewYear}</span>
				</div>
				<button class="kal-nav-btn" onclick={nextMonth} aria-label="Nächster Monat">
					<span class="material-symbols-outlined">chevron_right</span>
				</button>
			</div>
		</div>

		<div class="kal-card">
			<div class="kal-grid kal-grid--header">
				{#each DAY_NAMES as d}<div class="kal-day-label">{d}</div>{/each}
			</div>
			<div class="kal-grid kal-grid--days">
				{#each calendarCells as cell}
					{#if cell.current}
						{@const type = eventType(cell.day)}
						<div class="kal-cell">
							<button
								class="kal-day-btn"
								class:kal-day-btn--today={isToday(cell.day)}
								class:kal-day-btn--selected={selectedDay === cell.day}
								class:kal-day-btn--training={type === 'training'}
								class:kal-day-btn--match={type === 'match'}
								class:kal-day-btn--event={type === 'event'}
								onclick={() => selectedDay = cell.day}
							>
								{cell.day}
								{#if type}
									<span class="kal-dot" class:kal-dot--match={type === 'match'} class:kal-dot--event={type === 'event'}></span>
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
				<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--training"></span><span>Training</span></div>
				<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--match"></span><span>Match</span></div>
				<div class="kal-legend-item"><span class="kal-legend-dot kal-legend-dot--event"></span><span>Event</span></div>
			</div>
		</div>

		<section class="kal-slots">
			{#if selectedDay}
				<h2 class="kal-slots-heading">
					<span class="material-symbols-outlined">event</span>
					{selectedLabel}
				</h2>

				{#if selectedMatches.length === 0 && selectedEvents.length === 0 && selectedTrainings.length === 0}
					<div class="kal-no-events">
						<span class="material-symbols-outlined kal-no-events-icon">event_available</span>
						<p>Nichts geplant</p>
					</div>
				{:else}
					<div class="kal-event-list">
						{#each selectedMatches as m}
							<a class="kal-event-card kal-event-card--match" href="/spielbetrieb">
								<div class="kal-event-time-col kal-event-time-col--match">
									<span class="kal-event-time-text">{String(m.time ?? '').slice(0,5)}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label">{m.is_tournament ? 'Turnier' : 'Match'} {m.round ?? ''}</div>
									<h3 class="kal-event-title">{m.home_away === 'HEIM' ? '' : 'bei '}{m.opponent}</h3>
									<p class="kal-event-desc">{m.location ?? ''}</p>
									<span class="kal-event-btn kal-event-btn--match">Zur Aufstellung</span>
								</div>
							</a>
						{/each}

						{#each selectedEvents as ev}
							<div class="kal-event-card kal-event-card--event">
								<div class="kal-event-time-col kal-event-time-col--event">
									<span class="kal-event-time-text">{String(ev.time ?? '').slice(0,5) || '—'}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label kal-event-type-label--event">Termin</div>
									<h3 class="kal-event-title">{ev.title}</h3>
									<p class="kal-event-desc">{ev.location ?? ''}{ev.description ? ' · ' + ev.description : ''}</p>
								</div>
							</div>
						{/each}

						{#each selectedTrainings as slot}
							{@const taken = bookingsFor(slot.date, slot.start_time)}
							{@const blocked = hasRosterConflict(slot.date, slot.start_time)}
							<div class="kal-event-card">
								<div class="kal-event-time-col">
									<span class="kal-event-time-text">{slot.start_time}</span>
								</div>
								<div class="kal-event-body">
									<div class="kal-event-type-label">Training</div>
									<h3 class="kal-event-title">{slot.lane_count} Bahnen · 1 Stunde</h3>
									{#if blocked}
										<p class="kal-event-desc">Blockiert (Match/Event)</p>
									{:else}
										<div class="lanes">
											{#each Array(slot.lane_count) as _, i}
												{@const laneNum = i + 1}
												{@const b = taken.find(x => x.lane_number === laneNum)}
												{@const mine = b?.player_id === $playerId}
												<button
													class="lane"
													class:lane--taken={!!b && !mine}
													class:lane--mine={mine}
													onclick={() => bookLane(slot.date, slot.start_time, laneNum)}
													aria-label="Bahn {laneNum}"
												>
													{#if b}
														{@const pl = getPlayer(b.player_id)}
														{#if pl?.avatar_url || pl?.photo}
															<img src={pl.avatar_url || pl.photo} alt="" />
														{:else}
															<span>{(pl?.name || '?').slice(0,1)}</span>
														{/if}
													{:else}
														<span class="material-symbols-outlined">add</span>
													{/if}
												</button>
											{/each}
										</div>
									{/if}
								</div>
							</div>
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
</div>

<style>
	.kal-page { padding: var(--space-5) var(--space-5) var(--space-8); display: flex; flex-direction: column; gap: var(--space-6); }
	.kal-month-header { padding-top: var(--space-2); }
	.kal-month-nav { display: flex; align-items: center; justify-content: space-between; }
	.kal-month-label { display: flex; flex-direction: column; align-items: center; }
	.kal-month-name { font-family: var(--font-display); font-size: var(--text-headline-md); font-weight: 800; color: var(--color-on-surface); line-height: 1; }
	.kal-month-year { font-family: var(--font-display); font-size: var(--text-label-md); font-weight: 700; color: var(--color-primary); text-transform: uppercase; letter-spacing: 0.12em; margin-top: 2px; }
	.kal-nav-btn { width: 2.5rem; height: 2.5rem; display: flex; align-items: center; justify-content: center; border-radius: var(--radius-md); background: var(--color-surface-container-low); color: var(--color-on-surface-variant); transition: background 0.15s, transform 0.1s; border: 0; cursor: pointer; }
	.kal-nav-btn:active { transform: scale(0.92); }
	.kal-card { background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: var(--space-5); }
	.kal-grid { display: grid; grid-template-columns: repeat(7, 1fr); }
	.kal-grid--header { margin-bottom: var(--space-3); }
	.kal-day-label { text-align: center; font-size: var(--text-label-sm); font-weight: 700; color: var(--color-outline); text-transform: uppercase; letter-spacing: 0.05em; }
	.kal-grid--days { gap: 2px 0; }
	.kal-cell { display: flex; justify-content: center; align-items: center; padding: 3px 0; }
	.kal-cell--ghost { opacity: 0.25; }
	.kal-day-ghost { font-size: var(--text-body-md); color: var(--color-outline); padding: 0.6rem; }
	.kal-day-btn { position: relative; width: 2.75rem; height: 2.75rem; border-radius: var(--radius-md); font-size: var(--text-body-md); font-weight: 500; color: var(--color-on-surface); display: flex; align-items: center; justify-content: center; transition: background 0.12s, transform 0.1s; flex-direction: column; background: none; border: 0; cursor: pointer; }
	.kal-day-btn--today { font-weight: 800; background: var(--color-surface-container); }
	.kal-day-btn--selected { background: var(--color-primary) !important; color: #fff !important; font-weight: 800; box-shadow: var(--shadow-float); }
	.kal-day-btn--training { background: rgba(204, 0, 0, 0.07); color: var(--color-primary); font-weight: 700; }
	.kal-day-btn--match { background: rgba(212, 175, 55, 0.12); font-weight: 700; border: 2px solid rgba(212, 175, 55, 0.4); }
	.kal-day-btn--event { background: rgba(42, 120, 180, 0.1); color: #2a78b4; font-weight: 700; }
	.kal-dot { position: absolute; bottom: 5px; width: 5px; height: 5px; border-radius: 50%; background: var(--color-primary); }
	.kal-dot--match { background: var(--color-secondary); }
	.kal-dot--event { background: #2a78b4; }
	.kal-day-btn--selected .kal-dot { background: rgba(255,255,255,0.8); }
	.kal-legend { display: flex; gap: var(--space-6); padding-top: var(--space-4); margin-top: var(--space-4); border-top: 1px solid var(--color-surface-container); }
	.kal-legend-item { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-label-sm); font-weight: 600; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.05em; }
	.kal-legend-dot { width: 10px; height: 10px; border-radius: 50%; }
	.kal-legend-dot--training { background: var(--color-primary); }
	.kal-legend-dot--match    { background: var(--color-secondary); }
	.kal-legend-dot--event    { background: #2a78b4; }
	.kal-slots-heading { display: flex; align-items: center; gap: var(--space-2); font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: var(--space-4); }
	.kal-slots-heading .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); }
	.kal-event-list { display: flex; flex-direction: column; gap: var(--space-4); }
	.kal-event-card { display: flex; background: linear-gradient(145deg, #ffffff, #f9f9f9); box-shadow: 8px 8px 24px #e8e8e8, -4px -4px 16px #ffffff; border-radius: var(--radius-lg); overflow: hidden; border: 1.5px solid #fff; text-decoration: none; color: inherit; }
	.kal-event-card--match { border: 1.5px solid rgba(212, 175, 55, 0.3); }
	.kal-event-card--event { border: 1.5px solid rgba(42, 120, 180, 0.25); }
	.kal-event-time-col { width: 3.5rem; flex-shrink: 0; display: flex; align-items: center; justify-content: center; background: var(--color-primary); margin: 4px; border-radius: var(--radius-md); padding: var(--space-2) var(--space-1); }
	.kal-event-time-col--match { background: var(--color-secondary-container, #f5e6b2); }
	.kal-event-time-col--event { background: #bfdaf0; }
	.kal-event-time-text { writing-mode: vertical-rl; text-orientation: mixed; transform: rotate(180deg); font-family: var(--font-display); font-size: 0.65rem; font-weight: 700; letter-spacing: 0.05em; text-transform: uppercase; color: #fff; line-height: 1.2; }
	.kal-event-time-col--match .kal-event-time-text, .kal-event-time-col--event .kal-event-time-text { color: #334; }
	.kal-event-body { flex: 1; padding: var(--space-4) var(--space-4) var(--space-4) var(--space-3); display: flex; flex-direction: column; gap: var(--space-1); }
	.kal-event-type-label { font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: var(--color-primary); }
	.kal-event-type-label--event { color: #2a78b4; }
	.kal-event-card--match .kal-event-type-label { color: #8a6f1e; }
	.kal-event-title { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 700; line-height: 1.2; margin: 0; }
	.kal-event-desc { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin-top: 1px; }
	.kal-event-btn { margin-top: var(--space-3); align-self: flex-start; padding: var(--space-2) var(--space-4); background: var(--color-primary); color: #fff; border-radius: var(--radius-md); font-size: var(--text-label-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.1em; }
	.kal-event-btn--match { background: var(--color-surface-container-lowest, #fff); color: var(--color-primary); border: 2px solid var(--color-primary); }
	.lanes { display: flex; gap: 6px; margin-top: var(--space-2); flex-wrap: wrap; }
	.lane { width: 40px; height: 40px; border-radius: 50%; border: 2px dashed var(--color-border, #ccc); background: #fff; display: grid; place-items: center; cursor: pointer; padding: 0; overflow: hidden; color: var(--color-text-soft, #aaa); }
	.lane img { width: 100%; height: 100%; object-fit: cover; }
	.lane--taken { border-style: solid; border-color: var(--color-text-soft, #aaa); color: #666; background: #f4f4f4; }
	.lane--mine { border-color: var(--color-secondary, #D4AF37); box-shadow: 0 0 0 2px rgba(212,175,55,0.3); }
	.kal-no-events { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.kal-no-events-icon { font-size: 2.5rem; opacity: 0.5; }
	.kal-no-events p { font-size: var(--text-body-md); font-weight: 500; }
</style>
