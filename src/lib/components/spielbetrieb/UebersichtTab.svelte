<script>
	import { onMount }    from 'svelte';
	import { page }       from '$app/stores';
	import { sb }         from '$lib/supabase';
	import { setSubtab }  from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { BEWERB_LABEL } from '$lib/constants/competitions.js';

	const hubs = [
		{ key: 'spiele',       label: 'Spiele',       icon: 'emoji_events',     desc: 'Spielplan & Ergebnisse'   },
		{ key: 'turnier',      label: 'Turnier',       icon: 'military_tech',    desc: 'Interne Turniere'         },
		{ key: 'landesbewerb', label: 'Landesbewerb',  icon: 'workspace_premium',desc: 'Verbandswettbewerbe'      },
		{ key: 'statistiken',  label: 'Statistiken',   icon: 'bar_chart',        desc: 'Auswertungen & Rankings'  },
	];

	let matches     = $state([]);
	let tournaments = $state([]);
	let bewerbe     = $state([]);
	let loading     = $state(true);

	onMount(async () => {
		try {
			const today = toDateStr(new Date());
			const [
				{ data: m,  error: e1 },
				{ data: t,  error: e2 },
				{ data: lb, error: e3 },
			] = await Promise.all([
				sb.from('matches')
					.select('id, date, time, home_away, opponent, location')
					.gte('date', today)
					.neq('opponent', 'spielfrei')
					.order('date', { ascending: true })
					.limit(3),
				sb.from('tournaments')
					.select('id, title, status, tournament_votes(vote)')
					.in('status', ['voting', 'scheduling', 'confirmed'])
					.order('created_at', { ascending: false })
					.limit(2),
				sb.from('landesbewerbe')
					.select('id, title, type, registration_deadline, landesbewerb_registrations(id)')
					.gt('registration_deadline', new Date().toISOString())
					.order('registration_deadline', { ascending: true })
					.limit(2),
			]);
			if (e1) { triggerToast('Fehler: ' + e1.message); }
			if (e2) { triggerToast('Fehler: ' + e2.message); }
			if (e3) { triggerToast('Fehler: ' + e3.message); }
			matches     = m  ?? [];
			tournaments = t  ?? [];
			bewerbe     = lb ?? [];
		} finally {
			loading = false;
		}
	});

	function go(key) {
		setSubtab($page.url.pathname, key);
	}

	function statusLabel(s) {
		if (s === 'voting')      return 'Abstimmung';
		if (s === 'scheduling')  return 'Terminplanung';
		if (s === 'confirmed')   return 'Bestätigt';
		return s;
	}

	function yesCount(votes) {
		return (votes ?? []).filter(v => v.vote === 'yes').length;
	}
</script>

<div class="ueb-page">
	<!-- Nav Hub -->
	<div class="ueb-hub-grid">
		{#each hubs as h}
			<button class="ueb-hub-tile" onclick={() => go(h.key)}>
				<span class="material-symbols-outlined ueb-hub-icon">{h.icon}</span>
				<div class="ueb-hub-text">
					<span class="ueb-hub-label">{h.label}</span>
					<span class="ueb-hub-desc">{h.desc}</span>
				</div>
				<span class="material-symbols-outlined ueb-hub-arrow">chevron_right</span>
			</button>
		{/each}
	</div>

	<!-- Nächste Spiele -->
	<div class="ueb-section">
		<div class="ueb-sec-head">
			<span class="material-symbols-outlined ueb-sec-icon">emoji_events</span>
			<span class="ueb-sec-title">Nächste Spiele</span>
		</div>
		{#if loading}
			<div class="ueb-skeleton"></div>
			<div class="ueb-skeleton"></div>
		{:else if matches.length === 0}
			<p class="ueb-empty">Keine kommenden Spiele</p>
		{:else}
			<div class="ueb-list">
				{#each matches as m}
					{@const days = daysUntil(m.date)}
					<div class="ueb-match-row">
						<div class="ueb-date-chip" class:ueb-date-chip--urgent={days <= 3}>
							<span class="ueb-date-chip-date">{fmtDate(m.date)}</span>
							{#if m.time}<span class="ueb-date-chip-time">{fmtTime(m.time)}</span>{/if}
						</div>
						<div class="ueb-match-info">
							<span class="ueb-match-opp">{m.opponent}</span>
							<span class="ueb-match-badge" class:ueb-match-badge--heim={m.home_away === 'heim'}>
								{m.home_away === 'heim' ? 'Heim' : 'Auswärts'}
							</span>
						</div>
					</div>
				{/each}
			</div>
		{/if}
		<button class="ueb-more-btn" onclick={() => go('spiele')}>Alle Spiele</button>
	</div>

	<!-- Aktive Turniere -->
	<div class="ueb-section">
		<div class="ueb-sec-head">
			<span class="material-symbols-outlined ueb-sec-icon">military_tech</span>
			<span class="ueb-sec-title">Aktive Turniere</span>
		</div>
		{#if loading}
			<div class="ueb-skeleton"></div>
		{:else if tournaments.length === 0}
			<p class="ueb-empty">Keine aktiven Turniere</p>
		{:else}
			<div class="ueb-list">
				{#each tournaments as t}
					<div class="ueb-turnier-row">
						<div class="ueb-turnier-info">
							<span class="ueb-turnier-title">{t.title}</span>
							<span class="ueb-status-badge ueb-status-badge--{t.status}">{statusLabel(t.status)}</span>
						</div>
						{#if t.status === 'voting'}
							<span class="ueb-turnier-votes">{yesCount(t.tournament_votes)} Ja</span>
						{/if}
					</div>
				{/each}
			</div>
		{/if}
		<button class="ueb-more-btn" onclick={() => go('turnier')}>Alle Turniere</button>
	</div>

	<!-- Anmeldungen offen -->
	{#if loading || bewerbe.length > 0}
		<div class="ueb-section">
			<div class="ueb-sec-head">
				<span class="material-symbols-outlined ueb-sec-icon">workspace_premium</span>
				<span class="ueb-sec-title">Anmeldungen offen</span>
			</div>
			{#if loading}
				<div class="ueb-skeleton"></div>
			{:else}
				<div class="ueb-list">
					{#each bewerbe as lb}
						{@const days = daysUntil(lb.registration_deadline.slice(0,10))}
						<div class="ueb-bewerb-row">
							<div class="ueb-bewerb-info">
								<span class="ueb-bewerb-title">{lb.title}</span>
								<span class="ueb-bewerb-type">{BEWERB_LABEL[lb.type] ?? lb.type}</span>
							</div>
							<div class="ueb-bewerb-deadline" class:ueb-bewerb-deadline--urgent={days <= 7}>
								<span class="material-symbols-outlined">schedule</span>
								{days === 0 ? 'Heute' : days === 1 ? 'Morgen' : `${days} Tage`}
							</div>
						</div>
					{/each}
				</div>
			{/if}
			<button class="ueb-more-btn" onclick={() => go('landesbewerb')}>Alle Bewerbe</button>
		</div>
	{/if}
</div>

<style>
.ueb-page {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
	padding: var(--space-5);
}

/* Hub Grid */
.ueb-hub-grid {
	display: grid;
	grid-template-columns: 1fr 1fr;
	gap: var(--space-3);
}

.ueb-hub-tile {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) var(--space-3);
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 14px;
	cursor: pointer;
	text-align: left;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms;
	grid-column: span 2;
}

.ueb-hub-tile:active { background: var(--color-surface-container-low); }

.ueb-hub-icon {
	font-size: 1.4rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	flex-shrink: 0;
}

.ueb-hub-text {
	flex: 1;
	display: flex;
	flex-direction: column;
	gap: 1px;
	min-width: 0;
}

.ueb-hub-label {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.9rem;
	color: var(--color-on-surface);
}

.ueb-hub-desc {
	font-size: 0.75rem;
	color: var(--color-on-surface-variant);
}

.ueb-hub-arrow {
	color: var(--color-on-surface-variant);
	font-size: 1.1rem;
	flex-shrink: 0;
}

/* Sections */
.ueb-section {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.ueb-sec-head {
	display: flex;
	align-items: center;
	gap: var(--space-2);
}

.ueb-sec-icon {
	font-size: 1rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.ueb-sec-title {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.875rem;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-primary);
}

.ueb-skeleton {
	height: 48px;
	background: var(--color-surface-container-low);
	border-radius: 10px;
	animation: pulse 1.4s ease-in-out infinite;
}

@keyframes pulse {
	0%, 100% { opacity: 1; }
	50%       { opacity: 0.5; }
}

.ueb-empty {
	font-size: 0.85rem;
	color: var(--color-on-surface-variant);
	margin: 0;
	text-align: center;
	padding: var(--space-2) 0;
}

.ueb-list {
	display: flex;
	flex-direction: column;
	gap: 0;
}

/* Match rows */
.ueb-match-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-2) 0;
	border-top: 1px solid var(--color-surface-container);
}

.ueb-match-row:first-child { border-top: none; padding-top: 0; }

.ueb-date-chip {
	display: flex;
	flex-direction: column;
	align-items: center;
	min-width: 72px;
	padding: 4px 8px;
	border-radius: 8px;
	background: var(--color-surface-container-low);
	flex-shrink: 0;
}

.ueb-date-chip--urgent { background: rgba(204,0,0,0.1); }

.ueb-date-chip-date {
	font-family: var(--font-display);
	font-size: 0.72rem;
	font-weight: 800;
	color: var(--color-on-surface);
}

.ueb-date-chip-time {
	font-size: 0.68rem;
	font-weight: 700;
	color: var(--color-on-surface-variant);
}

.ueb-match-info {
	flex: 1;
	display: flex;
	flex-direction: column;
	gap: 2px;
	min-width: 0;
}

.ueb-match-opp {
	font-weight: 700;
	font-size: 0.88rem;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.ueb-match-badge {
	font-size: 0.68rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	padding: 1px 7px;
	border-radius: 999px;
	background: var(--color-surface-container);
	color: var(--color-on-surface-variant);
	width: fit-content;
}

.ueb-match-badge--heim {
	background: rgba(204,0,0,0.12);
	color: var(--color-primary);
}

/* Turnier rows */
.ueb-turnier-row {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: var(--space-3);
	padding: var(--space-2) 0;
	border-top: 1px solid var(--color-surface-container);
}

.ueb-turnier-row:first-child { border-top: none; padding-top: 0; }

.ueb-turnier-info {
	display: flex;
	flex-direction: column;
	gap: 2px;
	min-width: 0;
}

.ueb-turnier-title {
	font-weight: 700;
	font-size: 0.88rem;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.ueb-status-badge {
	font-size: 0.68rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	padding: 2px 8px;
	border-radius: 999px;
	width: fit-content;
}

.ueb-status-badge--voting      { background: rgba(234,179,8,0.15);  color: #92400e; }
.ueb-status-badge--scheduling  { background: rgba(59,130,246,0.12); color: #1d4ed8; }
.ueb-status-badge--confirmed   { background: rgba(22,163,74,0.12);  color: #15803d; }

.ueb-turnier-votes {
	font-family: var(--font-display);
	font-size: 0.85rem;
	font-weight: 800;
	color: var(--color-primary);
	flex-shrink: 0;
}

/* Bewerb rows */
.ueb-bewerb-row {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: var(--space-3);
	padding: var(--space-2) 0;
	border-top: 1px solid var(--color-surface-container);
}

.ueb-bewerb-row:first-child { border-top: none; padding-top: 0; }

.ueb-bewerb-info {
	display: flex;
	flex-direction: column;
	gap: 2px;
	min-width: 0;
}

.ueb-bewerb-title {
	font-weight: 700;
	font-size: 0.88rem;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.ueb-bewerb-type {
	font-size: 0.72rem;
	font-weight: 700;
	color: var(--color-on-surface-variant);
	text-transform: uppercase;
	letter-spacing: 0.05em;
}

.ueb-bewerb-deadline {
	display: flex;
	align-items: center;
	gap: 3px;
	font-size: 0.78rem;
	font-weight: 700;
	color: var(--color-on-surface-variant);
	flex-shrink: 0;
}

.ueb-bewerb-deadline .material-symbols-outlined { font-size: 0.9rem; }

.ueb-bewerb-deadline--urgent { color: var(--color-primary); }

.ueb-more-btn {
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
