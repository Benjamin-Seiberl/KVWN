<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	let stats = $state({
		players: null, matches: null, news: null, polls: null, events: null, teams: null,
	});

	// Status-Board
	let openLineups    = $state(0);  // Matches diese + nächste Woche ohne vollst. Aufstellung
	let pendingScores  = $state(0);  // Vergangene Matches ohne Ergebnisse
	let activePolls    = $state(0);  // Laufende Umfragen
	let pendingFeedback = $state(0); // Feedback-Einträge (Placeholder)

	async function count(table) {
		const { count: c } = await sb.from(table).select('*', { count: 'exact', head: true });
		return c ?? 0;
	}

	onMount(async () => {
		const today = new Date().toISOString().slice(0, 10);

		// Zähler
		const [players, matches, news, polls, events, teams] = await Promise.all([
			count('players'), count('matches'), count('announcements'),
			count('polls'), count('events'), count('teams'),
		]);
		stats = { players, matches, news, polls, events, teams };

		// Status: offene Aufstellungen (Matches in den nächsten 14 Tagen)
		const in14 = new Date(); in14.setDate(in14.getDate() + 14);
		const { data: upcomingMatches } = await sb
			.from('matches')
			.select('id')
			.gte('date', today)
			.lte('date', in14.toISOString().slice(0, 10));

		if (upcomingMatches?.length) {
			const { data: gamePlans } = await sb
				.from('game_plans')
				.select('id, match_id')
				.in('match_id', upcomingMatches.map(m => m.id));
			// Matches ohne game_plan = noch gar keine Aufstellung
			const withPlan = new Set(gamePlans?.map(g => g.match_id) ?? []);
			openLineups = upcomingMatches.filter(m => !withPlan.has(m.id)).length;
		}

		// Status: vergangene Matches ohne Ergebnisse
		const { data: pastMatches } = await sb
			.from('matches')
			.select('id')
			.lt('date', today)
			.limit(20);

		if (pastMatches?.length) {
			const { data: scoredPlans } = await sb
				.from('game_plan_players')
				.select('game_plans!inner(match_id)')
				.eq('played', true)
				.not('score', 'is', null)
				.in('game_plans.match_id', pastMatches.map(m => m.id));
			const withScores = new Set(scoredPlans?.map(g => g.game_plans?.match_id).filter(Boolean) ?? []);
			pendingScores = pastMatches.filter(m => !withScores.has(m.id)).length;
		}

		// Status: aktive Polls (ohne Deadline oder Deadline in der Zukunft)
		const { data: activePollData } = await sb
			.from('polls')
			.select('id')
			.or(`deadline.is.null,deadline.gte.${new Date().toISOString()}`);
		activePolls = activePollData?.length ?? 0;
	});

	const tiles = $derived([
		{ href: '/admin/spieler',  icon: 'group',          label: 'Spieler',  value: stats.players },
		{ href: '/admin/teams',    icon: 'diversity_3',    label: 'Teams',    value: stats.teams },
		{ href: '/admin/saison',   icon: 'event_note',     label: 'Matches',  value: stats.matches },
		{ href: '/admin/news',     icon: 'campaign',       label: 'News',     value: stats.news },
		{ href: '/admin/news',     icon: 'ballot',         label: 'Polls',    value: stats.polls },
		{ href: '/admin/saison',   icon: 'calendar_month', label: 'Events',   value: stats.events },
	]);
</script>

<!-- ── Status-Board ──────────────────────────────────── -->
<section class="status-board">
	<h2 class="board-title">Was ist offen?</h2>

	<a href="/admin/saison" class="status-item" class:status-item--warn={openLineups > 0}>
		<div class="status-icon">
			<span class="material-symbols-outlined">group_add</span>
		</div>
		<div class="status-text">
			<p class="status-label">Aufstellungen</p>
			<p class="status-val">
				{#if openLineups > 0}
					{openLineups} Match{openLineups !== 1 ? 'es' : ''} noch ohne Aufstellung
				{:else}
					Alle kommenden Aufstellungen erledigt ✓
				{/if}
			</p>
		</div>
		<span class="material-symbols-outlined status-chevron">chevron_right</span>
	</a>

	<a href="/spielbetrieb" class="status-item" class:status-item--warn={pendingScores > 0}>
		<div class="status-icon">
			<span class="material-symbols-outlined">scoreboard</span>
		</div>
		<div class="status-text">
			<p class="status-label">Ergebnisse</p>
			<p class="status-val">
				{#if pendingScores > 0}
					{pendingScores} vergangene Match{pendingScores !== 1 ? 'es' : ''} ohne Ergebnis
				{:else}
					Alle Ergebnisse eingetragen ✓
				{/if}
			</p>
		</div>
		<span class="material-symbols-outlined status-chevron">chevron_right</span>
	</a>

	<a href="/admin/news" class="status-item">
		<div class="status-icon">
			<span class="material-symbols-outlined">poll</span>
		</div>
		<div class="status-text">
			<p class="status-label">Aktive Umfragen</p>
			<p class="status-val">
				{#if activePolls > 0}
					{activePolls} Umfrage{activePolls !== 1 ? 'n' : ''} läuft gerade
				{:else}
					Keine aktiven Umfragen
				{/if}
			</p>
		</div>
		<span class="material-symbols-outlined status-chevron">chevron_right</span>
	</a>
</section>

<!-- ── Zähler-Kacheln ───────────────────────────────── -->
<h2 class="board-title board-title--secondary">Übersicht</h2>
<div class="admin-grid">
	{#each tiles as t}
		<a class="admin-tile" href={t.href}>
			<span class="material-symbols-outlined admin-tile__icon">{t.icon}</span>
			<span class="admin-tile__value">{t.value ?? '–'}</span>
			<span class="admin-tile__label">{t.label}</span>
		</a>
	{/each}
</div>

<style>
/* ── Status-Board ──────────────────────────── */
.board-title {
	font-family: 'Lexend', sans-serif;
	font-weight: 700;
	font-size: 0.8rem;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: var(--color-on-surface-variant, #666);
	margin: 0 0 var(--space-2, 8px);
}

.board-title--secondary {
	margin-top: var(--space-5, 20px);
}

.status-board {
	display: flex;
	flex-direction: column;
	gap: var(--space-2, 8px);
	margin-bottom: 0;
}

.status-item {
	display: flex;
	align-items: center;
	gap: var(--space-3, 12px);
	padding: var(--space-3, 12px) var(--space-4, 16px);
	background: var(--color-surface, #fff);
	border: 1px solid var(--color-border, #eee);
	border-radius: 14px;
	text-decoration: none;
	color: inherit;
	transition: background 0.12s;
}

.status-item:active { background: var(--color-surface-container-low, #f3f3f4); }

.status-item--warn {
	border-left: 4px solid var(--color-primary, #CC0000);
	background: rgba(204,0,0,0.03);
}

.status-icon {
	width: 40px;
	height: 40px;
	border-radius: 12px;
	background: var(--color-surface-container, #ebebec);
	display: grid;
	place-items: center;
	flex-shrink: 0;
}

.status-item--warn .status-icon {
	background: rgba(204,0,0,0.1);
}

.status-icon .material-symbols-outlined { font-size: 1.3rem; color: var(--color-on-surface-variant, #666); }
.status-item--warn .status-icon .material-symbols-outlined { color: var(--color-primary, #CC0000); }

.status-text { flex: 1; min-width: 0; }
.status-label { font-weight: 700; font-size: 0.9rem; color: var(--color-on-surface, #1a1c1c); margin: 0; }
.status-val { font-size: 0.82rem; color: var(--color-on-surface-variant, #666); margin: 2px 0 0; }
.status-item--warn .status-val { color: var(--color-primary, #CC0000); font-weight: 600; }
.status-chevron { color: var(--color-on-surface-variant, #aaa); font-size: 1.25rem; flex-shrink: 0; }

/* ── Zähler-Kacheln ────────────────────────── */
.admin-grid {
	display: grid;
	grid-template-columns: repeat(3, 1fr);
	gap: var(--space-3, 12px);
}

.admin-tile {
	display: flex;
	flex-direction: column;
	gap: 4px;
	padding: var(--space-4, 16px);
	background: var(--color-surface, #fff);
	border: 1px solid var(--color-border, #eee);
	border-radius: 14px;
	text-decoration: none;
	color: inherit;
	transition: transform 0.1s;
}

.admin-tile:active { transform: scale(0.97); }
.admin-tile__icon  { font-size: 1.5rem; color: var(--color-primary, #CC0000); }
.admin-tile__value { font-family: 'Lexend', sans-serif; font-weight: 700; font-size: 1.4rem; }
.admin-tile__label { color: var(--color-on-surface-variant, #666); font-size: 0.82rem; }
</style>
