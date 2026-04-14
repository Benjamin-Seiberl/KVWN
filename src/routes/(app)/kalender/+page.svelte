<script>
	// ── State ────────────────────────────────────────────────
	let today      = new Date();
	let viewYear   = $state(today.getFullYear());
	let viewMonth  = $state(today.getMonth()); // 0-based
	let selectedDay = $state(today.getDate());

	// Demo-Trainingsdaten: [YYYY-MM-DD] → [{ time, title, desc, type }]
	// type: 'training' | 'match'
	const trainingData = {
		[fmt(today.getFullYear(), today.getMonth(), today.getDate())]: [
			{ time: '17:00–19:00', title: 'Vereinstraining', desc: 'Kegelhalle Wiener Neustadt', type: 'training' },
			{ time: '19:00–20:00', title: 'Technik-Einheit', desc: 'Nur Startaufstellung', type: 'training' },
		],
		[fmt(today.getFullYear(), today.getMonth(), today.getDate() + 3)]: [
			{ time: '14:00–18:00', title: 'Bundesliga – Heimspiel', desc: 'vs. KC Linz', type: 'match' },
		],
		[fmt(today.getFullYear(), today.getMonth(), today.getDate() + 7)]: [
			{ time: '17:00–19:00', title: 'Vereinstraining', desc: 'Kegelhalle Wiener Neustadt', type: 'training' },
		],
		[fmt(today.getFullYear(), today.getMonth(), today.getDate() + 10)]: [
			{ time: '10:00–14:00', title: 'Landesliga – Auswärts', desc: 'bei KC Graz', type: 'match' },
		],
	};

	// Hilfsfunktionen
	function fmt(y, m, d) {
		const date = new Date(y, m, d);
		return date.getFullYear() + '-' +
			String(date.getMonth() + 1).padStart(2, '0') + '-' +
			String(date.getDate()).padStart(2, '0');
	}

	function daysInMonth(y, m) {
		return new Date(y, m + 1, 0).getDate();
	}

	function firstWeekday(y, m) {
		// Mo=0 … So=6
		const d = new Date(y, m, 1).getDay();
		return d === 0 ? 6 : d - 1;
	}

	const MONTH_NAMES = ['Jänner','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
	const DAY_NAMES   = ['Mo','Di','Mi','Do','Fr','Sa','So'];

	function prevMonth() {
		if (viewMonth === 0) { viewMonth = 11; viewYear--; }
		else viewMonth--;
		selectedDay = null;
	}

	function nextMonth() {
		if (viewMonth === 11) { viewMonth = 0; viewYear++; }
		else viewMonth++;
		selectedDay = null;
	}

	function selectDay(d) {
		selectedDay = d;
	}

	function hasEvent(d) {
		return !!trainingData[fmt(viewYear, viewMonth, d)];
	}

	function eventType(d) {
		const events = trainingData[fmt(viewYear, viewMonth, d)];
		if (!events) return null;
		if (events.some(e => e.type === 'match')) return 'match';
		return 'training';
	}

	function isToday(d) {
		return viewYear === today.getFullYear() &&
			viewMonth === today.getMonth() &&
			d === today.getDate();
	}

	const selectedKey = $derived(
		selectedDay ? fmt(viewYear, viewMonth, selectedDay) : null
	);
	const selectedEvents = $derived(
		selectedKey ? (trainingData[selectedKey] ?? []) : []
	);

	const selectedLabel = $derived(() => {
		if (!selectedDay) return '';
		const d = new Date(viewYear, viewMonth, selectedDay);
		const weekdays = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];
		return weekdays[d.getDay()] + ', ' + selectedDay + '. ' + MONTH_NAMES[viewMonth];
	});

	// Kalender-Grid aufbauen
	const calendarCells = $derived(() => {
		const cells = [];
		const offset = firstWeekday(viewYear, viewMonth);
		const days   = daysInMonth(viewYear, viewMonth);
		// Vormonat-Lücken
		const prevDays = daysInMonth(
			viewMonth === 0 ? viewYear - 1 : viewYear,
			viewMonth === 0 ? 11 : viewMonth - 1
		);
		for (let i = 0; i < offset; i++) {
			cells.push({ day: prevDays - offset + 1 + i, current: false });
		}
		for (let d = 1; d <= days; d++) {
			cells.push({ day: d, current: true });
		}
		// Nächsten Monat auffüllen bis 7er-Raster
		const remaining = (7 - (cells.length % 7)) % 7;
		for (let i = 1; i <= remaining; i++) {
			cells.push({ day: i, current: false });
		}
		return cells;
	});
</script>

<div class="page active">
	<div class="kal-page">

		<!-- ── Monats-Header ──────────────────────────────── -->
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

		<!-- ── Monatsansicht ─────────────────────────────── -->
		<div class="kal-card">
			<!-- Wochentag-Labels -->
			<div class="kal-grid kal-grid--header">
				{#each DAY_NAMES as d}
					<div class="kal-day-label">{d}</div>
				{/each}
			</div>

			<!-- Tage -->
			<div class="kal-grid kal-grid--days">
				{#each calendarCells() as cell}
					{#if cell.current}
						{@const type = eventType(cell.day)}
						<div class="kal-cell">
							<button
								class="kal-day-btn"
								class:kal-day-btn--today={isToday(cell.day)}
								class:kal-day-btn--selected={selectedDay === cell.day}
								class:kal-day-btn--training={type === 'training'}
								class:kal-day-btn--match={type === 'match'}
								onclick={() => selectDay(cell.day)}
							>
								{cell.day}
								{#if type}
									<span class="kal-dot" class:kal-dot--match={type === 'match'}></span>
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

			<!-- Legende -->
			<div class="kal-legend">
				<div class="kal-legend-item">
					<span class="kal-legend-dot kal-legend-dot--training"></span>
					<span>Training</span>
				</div>
				<div class="kal-legend-item">
					<span class="kal-legend-dot kal-legend-dot--match"></span>
					<span>Wettkampf</span>
				</div>
			</div>
		</div>

		<!-- ── Trainings-Slots ────────────────────────────── -->
		<section class="kal-slots">
			{#if selectedDay}
				<h2 class="kal-slots-heading">
					<span class="material-symbols-outlined">event</span>
					{selectedLabel()}
				</h2>

				{#if selectedEvents.length === 0}
					<div class="kal-no-events">
						<span class="material-symbols-outlined kal-no-events-icon">event_available</span>
						<p>Kein Training geplant</p>
					</div>
				{:else}
					<div class="kal-event-list">
						{#each selectedEvents as ev}
							<div class="kal-event-card" class:kal-event-card--match={ev.type === 'match'}>
								<!-- Zeit-Säule -->
								<div class="kal-event-time-col" class:kal-event-time-col--match={ev.type === 'match'}>
									<span class="kal-event-time-text">{ev.time}</span>
								</div>
								<!-- Inhalt -->
								<div class="kal-event-body">
									<div class="kal-event-type-label">
										{ev.type === 'match' ? 'Wettkampf' : 'Training'}
									</div>
									<h3 class="kal-event-title">{ev.title}</h3>
									<p class="kal-event-desc">{ev.desc}</p>
									<button class="kal-event-btn" class:kal-event-btn--match={ev.type === 'match'}>
										{#if ev.type === 'match'}
											Zur Aufstellung
										{:else}
											Details ansehen
										{/if}
									</button>
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
/* ── Seiten-Container ─────────────────────────────────── */
.kal-page {
	padding: var(--space-5) var(--space-5) var(--space-8);
	display: flex;
	flex-direction: column;
	gap: var(--space-6);
}

/* ── Monats-Header ────────────────────────────────────── */
.kal-month-header {
	padding-top: var(--space-2);
}

.kal-month-nav {
	display: flex;
	align-items: center;
	justify-content: space-between;
}

.kal-month-label {
	display: flex;
	flex-direction: column;
	align-items: center;
}

.kal-month-name {
	font-family: var(--font-display);
	font-size: var(--text-headline-md);
	font-weight: 800;
	color: var(--color-on-surface);
	line-height: 1;
}

.kal-month-year {
	font-family: var(--font-display);
	font-size: var(--text-label-md);
	font-weight: 700;
	color: var(--color-primary);
	text-transform: uppercase;
	letter-spacing: 0.12em;
	margin-top: 2px;
}

.kal-nav-btn {
	width: 2.5rem;
	height: 2.5rem;
	display: flex;
	align-items: center;
	justify-content: center;
	border-radius: var(--radius-md);
	background: var(--color-surface-container-low);
	color: var(--color-on-surface-variant);
	transition: background 0.15s, transform 0.1s;
}

.kal-nav-btn:hover  { background: var(--color-surface-container); }
.kal-nav-btn:active { transform: scale(0.92); }

/* ── Kalender-Karte ───────────────────────────────────── */
.kal-card {
	background: var(--color-surface-container-lowest);
	border-radius: var(--radius-lg);
	box-shadow: var(--shadow-card);
	padding: var(--space-5);
}

.kal-grid {
	display: grid;
	grid-template-columns: repeat(7, 1fr);
}

.kal-grid--header {
	margin-bottom: var(--space-3);
}

.kal-day-label {
	text-align: center;
	font-size: var(--text-label-sm);
	font-weight: 700;
	color: var(--color-outline);
	text-transform: uppercase;
	letter-spacing: 0.05em;
}

.kal-grid--days {
	gap: 2px 0;
}

.kal-cell {
	display: flex;
	justify-content: center;
	align-items: center;
	padding: 3px 0;
}

.kal-cell--ghost {
	opacity: 0.25;
}

.kal-day-ghost {
	font-size: var(--text-body-md);
	color: var(--color-outline);
	padding: 0.6rem;
}

/* Tages-Button */
.kal-day-btn {
	position: relative;
	width: 2.75rem;
	height: 2.75rem;
	border-radius: var(--radius-md);
	font-size: var(--text-body-md);
	font-weight: 500;
	color: var(--color-on-surface);
	display: flex;
	align-items: center;
	justify-content: center;
	transition: background 0.12s, transform 0.1s;
	flex-direction: column;
}

.kal-day-btn:hover  { background: var(--color-surface-container-low); }
.kal-day-btn:active { transform: scale(0.88); }

/* Heute */
.kal-day-btn--today {
	font-weight: 800;
	background: var(--color-surface-container);
	color: var(--color-on-surface);
}

/* Ausgewählt */
.kal-day-btn--selected {
	background: var(--color-primary) !important;
	color: #fff !important;
	font-weight: 800;
	box-shadow: var(--shadow-float);
}

/* Training-Tag */
.kal-day-btn--training {
	background: rgba(204, 0, 0, 0.07);
	color: var(--color-primary);
	font-weight: 700;
}

/* Wettkampf-Tag */
.kal-day-btn--match {
	background: rgba(212, 175, 55, 0.12);
	color: var(--color-on-secondary-container);
	font-weight: 700;
	border: 2px solid rgba(212, 175, 55, 0.4);
}

/* Punkt-Indikator */
.kal-dot {
	position: absolute;
	bottom: 5px;
	width: 5px;
	height: 5px;
	border-radius: var(--radius-full);
	background: var(--color-primary);
}

.kal-dot--match {
	background: var(--color-secondary);
}

.kal-day-btn--selected .kal-dot {
	background: rgba(255,255,255,0.8);
}

/* ── Legende ──────────────────────────────────────────── */
.kal-legend {
	display: flex;
	gap: var(--space-6);
	padding-top: var(--space-4);
	margin-top: var(--space-4);
	border-top: 1px solid var(--color-surface-container);
}

.kal-legend-item {
	display: flex;
	align-items: center;
	gap: var(--space-2);
	font-size: var(--text-label-sm);
	font-weight: 600;
	color: var(--color-on-surface-variant);
	text-transform: uppercase;
	letter-spacing: 0.05em;
}

.kal-legend-dot {
	width: 10px;
	height: 10px;
	border-radius: var(--radius-full);
	flex-shrink: 0;
}

.kal-legend-dot--training { background: var(--color-primary); }
.kal-legend-dot--match    { background: var(--color-secondary); }

/* ── Slot-Bereich ─────────────────────────────────────── */

.kal-slots-heading {
	display: flex;
	align-items: center;
	gap: var(--space-2);
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 800;
	color: var(--color-on-surface);
	text-transform: uppercase;
	letter-spacing: 0.04em;
	margin-bottom: var(--space-4);
}

.kal-slots-heading .material-symbols-outlined {
	font-size: 1.1rem;
	color: var(--color-primary);
}

.kal-event-list {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
}

/* Luxury-Card ─ Training */
.kal-event-card {
	display: flex;
	background: linear-gradient(145deg, #ffffff, #f9f9f9);
	box-shadow: 8px 8px 24px #e8e8e8, -4px -4px 16px #ffffff;
	border-radius: var(--radius-lg);
	overflow: hidden;
	border: 1.5px solid #fff;
}

.kal-event-card--match {
	border: 1.5px solid rgba(212, 175, 55, 0.3);
}

/* Zeit-Säule */
.kal-event-time-col {
	width: 3.5rem;
	flex-shrink: 0;
	display: flex;
	align-items: center;
	justify-content: center;
	background: var(--color-primary);
	border-radius: calc(var(--radius-lg) - 2px) 0 0 calc(var(--radius-lg) - 2px);
	margin: 4px;
	border-radius: var(--radius-md);
	padding: var(--space-2) var(--space-1);
}

.kal-event-time-col--match {
	background: var(--color-secondary-container);
}

.kal-event-time-text {
	writing-mode: vertical-rl;
	text-orientation: mixed;
	transform: rotate(180deg);
	font-family: var(--font-display);
	font-size: 0.65rem;
	font-weight: 700;
	letter-spacing: 0.05em;
	text-transform: uppercase;
	color: #fff;
	line-height: 1.2;
}

.kal-event-time-col--match .kal-event-time-text {
	color: var(--color-on-secondary-container);
}

/* Inhalt */
.kal-event-body {
	flex: 1;
	padding: var(--space-4) var(--space-4) var(--space-4) var(--space-3);
	display: flex;
	flex-direction: column;
	gap: var(--space-1);
}

.kal-event-type-label {
	font-size: var(--text-label-sm);
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: var(--color-primary);
}

.kal-event-card--match .kal-event-type-label {
	color: var(--color-on-secondary-container);
}

.kal-event-title {
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 700;
	color: var(--color-on-surface);
	line-height: 1.2;
}

.kal-event-desc {
	font-size: var(--text-label-md);
	color: var(--color-on-surface-variant);
	margin-top: 1px;
}

.kal-event-btn {
	margin-top: var(--space-3);
	align-self: flex-start;
	padding: var(--space-2) var(--space-4);
	background: var(--color-primary);
	color: #fff;
	border-radius: var(--radius-md);
	font-size: var(--text-label-sm);
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	box-shadow: 0 4px 12px rgba(158, 0, 0, 0.2);
	transition: transform 0.1s, box-shadow 0.1s;
}

.kal-event-btn:active {
	transform: scale(0.95);
	box-shadow: 0 2px 6px rgba(158, 0, 0, 0.15);
}

.kal-event-btn--match {
	background: var(--color-surface-container-lowest);
	color: var(--color-primary);
	border: 2px solid var(--color-primary);
	box-shadow: none;
}

/* Leer-Zustand */
.kal-no-events {
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	gap: var(--space-3);
	padding: var(--space-10) var(--space-4);
	color: var(--color-outline);
}

.kal-no-events-icon {
	font-size: 2.5rem;
	opacity: 0.5;
}

.kal-no-events p {
	font-size: var(--text-body-md);
	font-weight: 500;
}
</style>
