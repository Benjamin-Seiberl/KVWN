<script>
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { setSubtab } from '$lib/stores/subtab.js';
	import { goto } from '$app/navigation';
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';
	import { roundCodeFor } from '$lib/utils/roundCode.js';

	// Signale (eine Summary-Karte je Signal-Typ):
	// a) Anzahl Spieler mit confirmed=NULL auf aktuell veröffentlichten Aufstellungen.
	// b) Kommender cal_week mit Match aber keiner published Aufstellung.
	// c) Neue Abwesenheiten (letzte 7d) die mit einer published Aufstellung kollidieren.
	let unconfirmedCount = $state(0);
	let missingLineup    = $state(null);   // { round, match } oder null
	let absenceConflicts = $state([]);     // [{ playerName, date, opponent }]
	let loading          = $state(true);

	async function load(pid) {
		loading = true;
		try {
			const todayStr = toDateStr(new Date());
			const until = new Date(); until.setDate(until.getDate() + 21);
			const untilStr = toDateStr(until);

			// Fenster-Matches für Aufstellungs-Checks.
			const { data: matches, error: mErr } = await sb.from('matches')
				.select('id, date, time, opponent, cal_week, league_id, leagues(name)')
				.gte('date', todayStr).lte('date', untilStr)
				.eq('is_tournament', false)
				.eq('is_landesbewerb', false)
				.order('date').order('time');
			if (mErr) { triggerToast('Fehler: ' + mErr.message); return; }

			const upcomingMatches = matches ?? [];
			const calWeeks = [...new Set(upcomingMatches.map(m => m.cal_week).filter(Boolean))];

			// Aufstellungen im Fenster (published).
			const { data: plans, error: pErr } = calWeeks.length
				? await sb.from('game_plans')
					.select('id, cal_week, league_id, lineup_published_at, game_plan_players(id, confirmed, player_id, players(name))')
					.in('cal_week', calWeeks)
				: { data: [], error: null };
			if (pErr) { triggerToast('Fehler: ' + pErr.message); return; }

			// a) Unbestätigte Spieler (published, deadline noch nicht weg).
			let unconfirmed = 0;
			const publishedPlansByKey = new Map();
			for (const p of (plans ?? [])) {
				if (!p.lineup_published_at) continue;
				publishedPlansByKey.set(`${p.cal_week}|${p.league_id}`, p);
				for (const gpp of (p.game_plan_players ?? [])) {
					if (gpp.confirmed === null) unconfirmed += 1;
				}
			}
			unconfirmedCount = unconfirmed;

			// b) Aufstellung fehlt für nächste cal_week mit Match.
			let firstMissing = null;
			for (const m of upcomingMatches) {
				const key = `${m.cal_week}|${m.league_id}`;
				const plan = publishedPlansByKey.get(key);
				if (!plan) {
					firstMissing = m;
					break;
				}
			}
			if (firstMissing) {
				// Rundencode aus allen Saison-Matches (gleiche league_id) berechnen.
				const { data: seasonMatches } = await sb.from('matches')
					.select('date, league_id')
					.eq('league_id', firstMissing.league_id);
				const round = roundCodeFor(firstMissing.date, seasonMatches ?? []);
				missingLineup = { match: firstMissing, round };
			} else {
				missingLineup = null;
			}

			// c) Neue Abwesenheiten (letzte 7d) die kollidieren.
			const sinceStr = toDateStr(new Date(Date.now() - 7 * 86400000));
			const { data: absences, error: aErr } = await sb.from('absences')
				.select('id, player_id, from_date, to_date, created_at, players(name)')
				.gte('created_at', sinceStr + 'T00:00:00')
				.lte('from_date', untilStr);
			if (aErr) { triggerToast('Fehler: ' + aErr.message); return; }

			const conflicts = [];
			for (const a of (absences ?? [])) {
				// Alle aktiv-published Aufstellungen dieses Spielers im Fenster laden
				for (const p of publishedPlansByKey.values()) {
					const entry = (p.game_plan_players ?? []).find(e => e.player_id === a.player_id);
					if (!entry) continue;
					const match = upcomingMatches.find(m =>
						m.cal_week === p.cal_week && m.league_id === p.league_id
					);
					if (!match) continue;
					if (match.date < a.from_date || match.date > a.to_date) continue;
					conflicts.push({
						playerName: a.players?.name ?? 'Spieler',
						date: match.date,
						opponent: match.opponent,
					});
					if (conflicts.length >= 3) break;
				}
				if (conflicts.length >= 3) break;
			}
			absenceConflicts = conflicts;
		} finally {
			loading = false;
		}
	}

	let loaded = false;
	$effect(() => {
		if ($playerRole === 'kapitaen' && $playerId && !loaded) {
			loaded = true;
			load($playerId);
		}
	});

	function openAufstellungen() {
		setSubtab('/spielbetrieb', 'aufstellungen');
		goto('/spielbetrieb');
	}

	let totalSignals = $derived(
		(unconfirmedCount > 0 ? 1 : 0) +
		(missingLineup ? 1 : 0) +
		absenceConflicts.length
	);
</script>

{#if !loading && $playerRole === 'kapitaen' && totalSignals > 0}
	<div class="ctb">
		<div class="sec-head">
			<span class="material-symbols-outlined sec-icon">bolt</span>
			<h3 class="sec-title">Kapitän-Aufgaben</h3>
		</div>

		<div class="ctb-list">
			{#if unconfirmedCount > 0}
				<button
					class="ctb-card"
					onclick={openAufstellungen}
					aria-label="Unbestätigte Spieler anzeigen"
				>
					<div class="ctb-body">
						<span class="ctb-title">
							{unconfirmedCount === 1
								? '1 Spieler noch unbestätigt'
								: `${unconfirmedCount} Spieler noch unbestätigt`}
						</span>
						<span class="ctb-meta">Aktuelle Aufstellung</span>
					</div>
					<span class="ctb-cta">Anzeigen →</span>
				</button>
			{/if}

			{#if missingLineup}
				<button
					class="ctb-card"
					onclick={openAufstellungen}
					aria-label="Aufstellung erstellen"
				>
					<div class="ctb-body">
						<span class="ctb-title">
							Aufstellung fehlt{missingLineup.round ? ` für ${missingLineup.round}` : ''}
						</span>
						<span class="ctb-meta">
							{#if missingLineup.match.leagues?.name}{missingLineup.match.leagues.name} · {/if}
							{fmtDate(missingLineup.match.date)}
						</span>
					</div>
					<span class="ctb-cta">Erstellen →</span>
				</button>
			{/if}

			{#each absenceConflicts as c (c.playerName + c.date)}
				<button
					class="ctb-card ctb-card--soft"
					onclick={openAufstellungen}
					aria-label="Abwesenheit prüfen"
				>
					<div class="ctb-body">
						<span class="ctb-title">Neue Abwesenheit: {c.playerName}</span>
						<span class="ctb-meta">Kollidiert mit {c.opponent} · {fmtDate(c.date)}</span>
					</div>
					<span class="ctb-cta">Prüfen →</span>
				</button>
			{/each}
		</div>
	</div>
{/if}

<style>
	.ctb {
		padding: 0 var(--space-5);
	}

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

	.ctb-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.ctb-card {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		width: 100%;
		text-align: left;
		background: var(--color-surface-container-lowest);
		border: none;
		border-left: 4px solid var(--color-primary);
		border-radius: var(--radius-lg);
		padding: var(--space-3) var(--space-4);
		box-shadow: var(--shadow-card);
		cursor: pointer;
		font: inherit;
		-webkit-tap-highlight-color: transparent;
		transition: transform 100ms ease;
	}
	.ctb-card:active {
		transform: scale(0.97);
	}
	.ctb-card--soft {
		border-left-color: color-mix(in srgb, var(--color-primary) 40%, transparent);
	}

	.ctb-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.ctb-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.ctb-meta {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.ctb-cta {
		flex-shrink: 0;
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-primary);
	}
</style>
