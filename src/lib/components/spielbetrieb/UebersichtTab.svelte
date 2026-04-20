<script>
	import { onMount }      from 'svelte';
	import { goto }         from '$app/navigation';
	import { sb }           from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { setSubtab }    from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { leagueTiming, offsetTime, shortTime }    from '$lib/utils/league.js';
	import { BEWERB_LABEL } from '$lib/constants/competitions.js';
	import { shortName }    from '$lib/utils/players.js';
	import BottomSheet      from '$lib/components/BottomSheet.svelte';
	import CarpoolCard      from '$lib/components/spielbetrieb/CarpoolCard.svelte';

	// ── State ─────────────────────────────────────────────────────────────────
	let upcomingMatches = $state([]);          // matches in next 21 days
	let pastMatches     = $state([]);          // league matches in last 14 days (for results + nudge)
	let tournaments     = $state([]);          // active turniere
	let landesbewerbe   = $state([]);          // open registrations / upcoming
	let pendingLineups  = $state([]);          // own game_plan_players with confirmed=null
	let myCarpoolSeats  = $state([]);          // [{ match_carpools: { match_id } }]
	let myDriving       = $state([]);          // [{ match_id }]
	let allCarpools     = $state([]);          // carpools for upcoming away matches (count + driver flags)
	let lineupsByMatch  = $state(new Map());   // match_id → { published, deadline, players[] }
	let loading         = $state(true);

	let carpoolSheetOpen   = $state(false);
	let carpoolSheetMatch  = $state(null);
	let carpoolSheetData   = $state([]);
	let carpoolSheetMeetup = $state(null);
	let carpoolLoading     = $state(false);

	let lineupSheetOpen  = $state(false);
	let lineupSheetEntry = $state(null);

	// ── Date constants ────────────────────────────────────────────────────────
	const today   = toDateStr(new Date());
	const plus7   = toDateStr(new Date(Date.now() +  7 * 86400000));
	const plus14  = toDateStr(new Date(Date.now() + 14 * 86400000));
	const plus21  = toDateStr(new Date(Date.now() + 21 * 86400000));
	const minus14 = toDateStr(new Date(Date.now() - 14 * 86400000));

	// ── Helpers ───────────────────────────────────────────────────────────────
	function daysUntilLabel(dateStr) {
		if (!dateStr) return null;
		const d = daysUntil(dateStr);
		if (d === 0) return 'Heute';
		if (d === 1) return 'Morgen';
		if (d < 0)   return null;
		return `in ${d} Tagen`;
	}

	function deadlineDays(iso) {
		if (!iso) return null;
		return daysUntilLabel(iso.slice(0, 10));
	}

	function matchTypeOf(m) {
		if (m.is_tournament)   return 'tournament';
		if (m.is_landesbewerb) return 'landesbewerb';
		if (m.is_friendly)     return 'friendly';
		return 'league';
	}

	function eyebrowFor(type) {
		return ({
			league:       'Nächstes Spiel',
			tournament:   'Nächstes Turnier',
			landesbewerb: 'Nächster Landesbewerb',
			friendly:     'Freundschaftsspiel',
		})[type] ?? 'Nächstes Spiel';
	}

	function heroSubtabFor(type) {
		return ({ tournament: 'turnier', landesbewerb: 'landesbewerb' })[type] ?? 'spiele';
	}

	function matchEnded(m) {
		if (!m?.time) return false;
		const timing = leagueTiming(m.leagues?.name ?? '');
		const endStr = offsetTime(m.time, timing.matchDurationMin);
		if (!endStr) return false;
		const [eh, em] = endStr.split(':').map(Number);
		const end = new Date(m.date + 'T00:00:00');
		end.setHours(eh, em + 10, 0, 0);
		return new Date() >= end;
	}

	function teamTotal(m) {
		return (m.game_plans ?? []).reduce((acc, gp) =>
			acc + (gp.game_plan_players ?? []).reduce((s, p) => s + (Number(p.score) || 0), 0)
		, 0);
	}

	function matchHasScores(m) {
		return (m.game_plans ?? []).some(gp =>
			(gp.game_plan_players ?? []).some(p => p.score != null)
		);
	}

	function lineupStatusFor(matchId) {
		const lu = lineupsByMatch.get(matchId);
		if (!lu) return null;
		if (!lu.published) return { kind: 'pending',  label: 'Aufstellung folgt' };
		const me = lu.players.find(p => p.player_id === $playerId);
		if (!me)                       return { kind: 'out',      label: 'Du fehlst' };
		if (me.confirmed === true)     return { kind: 'in',       label: 'Du bist dabei' };
		if (me.confirmed === false)    return { kind: 'declined', label: 'Du hast abgesagt' };
		return                                { kind: 'await',    label: 'Bestätigung offen' };
	}

	function carpoolStatusFor(matchId) {
		const cps = allCarpools.filter(c => c.match_id === matchId);
		if (!cps.length) return { kind: 'none', label: 'Keine Fahrt' };
		const driving   = myDriving.some(d => d.match_id === matchId);
		const seated    = myCarpoolSeats.some(s => s.match_carpools?.match_id === matchId);
		if (driving) return { kind: 'driver', label: 'Du fährst' };
		if (seated)  return { kind: 'in',     label: 'Mitfahrt fix' };
		const free = cps.reduce((sum, c) => sum + Math.max(0, (c.seats_total ?? 0) - (c.seats_taken ?? 0)), 0);
		return { kind: 'open', label: free > 0 ? `${free} freie Plätze` : `${cps.length} Fahrten` };
	}

	// ── Hero ──────────────────────────────────────────────────────────────────
	const heroMatch = $derived(upcomingMatches[0] ?? null);
	const heroType  = $derived(heroMatch ? matchTypeOf(heroMatch) : null);

	// ── Action cards ──────────────────────────────────────────────────────────
	const pendingLineup = $derived.by(() =>
		pendingLineups.find(p => {
			const gp = p.game_plans;
			return gp?.lineup_published_at && (gp?.confirmation_deadline ?? '0') >= today;
		}) ?? null
	);

	const urgentTournament = $derived.by(() =>
		tournaments.find(t =>
			t.voting_deadline && t.voting_deadline.slice(0, 10) <= plus14 &&
			!(t.tournament_votes ?? []).some(v => v.player_id === $playerId)
		) ?? null
	);

	const urgentLandesbewerb = $derived.by(() =>
		landesbewerbe.find(lb =>
			lb.registration_deadline && lb.registration_deadline.slice(0, 10) <= plus14 &&
			!(lb.landesbewerb_registrations ?? []).some(r => r.player_id === $playerId)
		) ?? null
	);

	const carpoolNeededMatch = $derived.by(() => {
		// own confirmed away match within 7d, no carpool seat & not driving
		return upcomingMatches.find(m => {
			if (m.home_away === 'HEIM') return false;
			if (m.date > plus7) return false;
			const lu = lineupsByMatch.get(m.id);
			const me = lu?.players?.find(p => p.player_id === $playerId);
			if (!me || me.confirmed !== true) return false;
			const haveSeat   = myCarpoolSeats.some(s => s.match_carpools?.match_id === m.id);
			const amDriving  = myDriving.some(d => d.match_id === m.id);
			return !haveSeat && !amDriving;
		}) ?? null;
	});

	const resultNudgeMatch = $derived.by(() => {
		if ($playerRole !== 'kapitaen') return null;
		return pastMatches.find(m => matchEnded(m) && !matchHasScores(m)) ?? null;
	});

	// ── Hub row ───────────────────────────────────────────────────────────────
	const nextLeagueMatch = $derived(upcomingMatches.find(m => matchTypeOf(m) === 'league') ?? null);
	const tournamentCount = $derived(tournaments.length);
	const nextTournament  = $derived(tournaments[0] ?? null);
	const landesCount     = $derived(landesbewerbe.length);
	const nextLandes      = $derived(landesbewerbe[0] ?? null);

	// ── Letzte Ergebnisse ─────────────────────────────────────────────────────
	const recentResults = $derived(pastMatches.filter(m => matchHasScores(m)).slice(0, 3));

	// ── 21-day feed ───────────────────────────────────────────────────────────
	const feedItems = $derived.by(() => {
		const items = [];
		for (const m of upcomingMatches) {
			const t = matchTypeOf(m);
			items.push({
				type:    t === 'league' ? 'league-match' : t === 'friendly' ? 'friendly-match' : t === 'tournament' ? 'tournament-match' : 'landesbewerb-match',
				sortKey: m.date + 'T' + (m.time ?? '23:59'),
				data:    m,
			});
		}
		for (const tourn of tournaments) {
			const date = tourn.confirmed_date ?? tourn.voting_deadline?.slice(0, 10) ?? null;
			if (!date || date < today || date > plus21) continue;
			items.push({
				type:    'tournament-event',
				sortKey: date + 'T' + (tourn.confirmed_time ?? '23:59'),
				data:    tourn,
			});
		}
		for (const lb of landesbewerbe) {
			const date = lb.date ?? lb.registration_deadline?.slice(0, 10) ?? null;
			if (!date || date < today || date > plus21) continue;
			items.push({
				type:    'landesbewerb-event',
				sortKey: date + 'T' + (lb.time ?? '23:59'),
				data:    lb,
			});
		}
		if ($playerRole === 'kapitaen') {
			for (const m of pastMatches) {
				if (matchEnded(m) && !matchHasScores(m)) {
					items.push({ type: 'result-nudge', sortKey: m.date + 'T' + (m.time ?? '23:59'), data: m });
				}
			}
		}
		items.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
		return items;
	});

	const feedByDate = $derived.by(() => {
		const map = new Map();
		for (const item of feedItems) {
			const d = item.sortKey.slice(0, 10);
			if (!map.has(d)) map.set(d, []);
			map.get(d).push(item);
		}
		return [...map.entries()].map(([date, items]) => ({ date, items }));
	});

	// ── Loading ───────────────────────────────────────────────────────────────
	async function loadData() {
		loading = true;
		const pid = $playerId;

		const queries = [
			// 0: upcoming matches (all types) within 21d
			sb.from('matches')
				.select('id, date, time, opponent, home_away, location, league_id, cal_week, is_tournament, is_landesbewerb, is_friendly, tournament_title, tournament_location, leagues(name)')
				.gte('date', today).lte('date', plus21)
				.neq('opponent', 'spielfrei')
				.order('date'),

			// 1: past league matches (last 14d) with scores
			sb.from('matches')
				.select('id, date, time, opponent, home_away, league_id, cal_week, leagues(name), game_plans(id, game_plan_players(score, played))')
				.gte('date', minus14).lt('date', today)
				.not('league_id', 'is', null)
				.order('date', { ascending: false }),

			// 2: active tournaments
			sb.from('tournaments')
				.select('id, title, location, status, voting_deadline, confirmed_date, confirmed_time, tournament_votes(player_id, wants_to_play)')
				.in('status', ['voting', 'scheduling', 'confirmed'])
				.order('voting_deadline', { ascending: true, nullsFirst: false }),

			// 3: landesbewerbe with open registration or upcoming date
			sb.from('landesbewerbe')
				.select('id, title, typ, location, date, time, registration_deadline, landesbewerb_registrations(player_id)')
				.or(`registration_deadline.gt.${new Date().toISOString()},date.gte.${today}`)
				.order('registration_deadline', { ascending: true, nullsFirst: false }),

			// 4: own pending lineup confirmations
			pid ? sb.from('game_plan_players')
				.select('id, position, confirmed, player_name, players(name, photo), game_plans!inner(id, lineup_published_at, confirmation_deadline, cal_week, league_id, matches(id, date, time, opponent, home_away, league_id, leagues(name)))')
				.eq('player_id', pid)
				.is('confirmed', null)
				: Promise.resolve({ data: [] }),

			// 5: own carpool seats
			pid ? sb.from('match_carpool_seats')
				.select('carpool_id, match_carpools!inner(match_id)')
				.eq('passenger_id', pid)
				: Promise.resolve({ data: [] }),

			// 6: own driving
			pid ? sb.from('match_carpools')
				.select('id, match_id')
				.eq('driver_id', pid)
				: Promise.resolve({ data: [] }),
		];

		const results = await Promise.all(queries);
		upcomingMatches = results[0].data ?? [];
		pastMatches     = results[1].data ?? [];
		tournaments     = results[2].data ?? [];
		landesbewerbe   = results[3].data ?? [];
		pendingLineups  = results[4].data ?? [];
		myCarpoolSeats  = results[5].data ?? [];
		myDriving       = results[6].data ?? [];

		// Lineups for upcoming league matches (eager fetch via cal_week + league_id)
		const leagueMatches = upcomingMatches.filter(m => m.cal_week && m.league_id && !m.is_tournament && !m.is_landesbewerb);
		const map = new Map();
		if (leagueMatches.length) {
			const calWeeks  = [...new Set(leagueMatches.map(m => m.cal_week))];
			const leagueIds = [...new Set(leagueMatches.map(m => m.league_id))];
			const { data: gps } = await sb.from('game_plans')
				.select('id, cal_week, league_id, lineup_published_at, confirmation_deadline, game_plan_players(player_id, position, confirmed)')
				.in('cal_week', calWeeks)
				.in('league_id', leagueIds);
			for (const m of leagueMatches) {
				const gp = (gps ?? []).find(g => g.cal_week === m.cal_week && g.league_id === m.league_id);
				if (gp) {
					map.set(m.id, {
						published: !!gp.lineup_published_at,
						deadline:  gp.confirmation_deadline,
						players:   gp.game_plan_players ?? [],
						game_plan_id: gp.id,
					});
				}
			}
		}
		lineupsByMatch = map;

		// Carpools for upcoming away matches (any type)
		const awayIds = upcomingMatches.filter(m => m.home_away !== 'HEIM').map(m => m.id);
		if (awayIds.length) {
			const { data: cps } = await sb.from('match_carpools')
				.select('id, match_id, driver_id, seats_total, match_carpool_seats(passenger_id)')
				.in('match_id', awayIds);
			allCarpools = (cps ?? []).map(c => ({ ...c, seats_taken: (c.match_carpool_seats ?? []).length }));
		} else {
			allCarpools = [];
		}

		loading = false;
	}

	onMount(loadData);

	// ── Carpool sheet ─────────────────────────────────────────────────────────
	async function openCarpoolSheet(match) {
		carpoolSheetMatch  = match;
		carpoolSheetOpen   = true;
		carpoolLoading     = true;
		carpoolSheetData   = [];
		carpoolSheetMeetup = null;
		const [{ data: cp }, { data: mu }] = await Promise.all([
			sb.from('match_carpools')
				.select('id, match_id, driver_id, seats_total, depart_time, depart_from, note, driver:players!driver_id(name, photo), match_carpool_seats(passenger_id)')
				.eq('match_id', match.id),
			sb.from('match_meetups').select('*').eq('match_id', match.id).maybeSingle(),
		]);
		carpoolSheetData   = (cp ?? []).map(c => ({ ...c, seats: c.match_carpool_seats ?? [] }));
		carpoolSheetMeetup = mu;
		carpoolLoading     = false;
	}

	async function refreshCarpoolSheet() {
		if (!carpoolSheetMatch) return;
		await openCarpoolSheet(carpoolSheetMatch);
		await loadData();
	}

	// ── Lineup confirm sheet ──────────────────────────────────────────────────
	function openLineupSheet(entry) {
		lineupSheetEntry = entry;
		lineupSheetOpen  = true;
	}

	async function respondLineup(confirmed) {
		if (!lineupSheetEntry) return;
		const id = lineupSheetEntry.id;
		const { error } = await sb.from('game_plan_players').update({ confirmed }).eq('id', id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		triggerToast(confirmed ? 'Aufstellung bestätigt' : 'Absage registriert');
		pendingLineups   = pendingLineups.filter(p => p.id !== id);
		lineupSheetOpen  = false;
		lineupSheetEntry = null;
	}

	// quick-confirm from feed item
	async function quickConfirm(entryId, confirmed) {
		const { error } = await sb.from('game_plan_players').update({ confirmed }).eq('id', entryId);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		triggerToast(confirmed ? 'Bestätigt' : 'Abgesagt');
		pendingLineups = pendingLineups.filter(p => p.id !== entryId);
	}

	function statusLabel(s) {
		return ({ voting: 'Abstimmung', voting_closed: 'Geschlossen', scheduling: 'Terminplanung', confirmed: 'Bestätigt' })[s] ?? s;
	}
</script>

{#if loading}
	<div class="ueb-loading">
		<div class="ueb-skeleton ueb-skeleton--hero shimmer-box"></div>
		<div class="ueb-skeleton ueb-skeleton--row  shimmer-box"></div>
		<div class="ueb-skeleton              shimmer-box"></div>
		<div class="ueb-skeleton              shimmer-box"></div>
	</div>

{:else}
<div class="ueb-page">

	<!-- ── Hero — Next Match ─────────────────────────────────────────────── -->
	{#if heroMatch}
		{@const du     = daysUntilLabel(heroMatch.date)}
		{@const isAway = heroMatch.home_away !== 'HEIM'}
		{@const title  = heroType === 'tournament' || heroType === 'landesbewerb'
			? (heroMatch.tournament_title ?? heroMatch.opponent)
			: (isAway ? 'bei ' : 'vs. ') + heroMatch.opponent}
		<button class="hero-card" onclick={() => setSubtab('/spielbetrieb', heroSubtabFor(heroType))}>
			<span class="hero-eyebrow">{eyebrowFor(heroType)}</span>
			<h2 class="hero-title">{title}</h2>
			<div class="hero-meta">
				<span class="material-symbols-outlined hero-meta-icon">calendar_today</span>
				<span>{fmtDate(heroMatch.date)}{heroMatch.time ? ' · ' + shortTime(heroMatch.time) + ' Uhr' : ''}</span>
				{#if heroMatch.location || heroMatch.tournament_location}
					<span class="hero-sep">·</span>
					<span class="material-symbols-outlined hero-meta-icon">location_on</span>
					<span>{heroMatch.tournament_location ?? heroMatch.location}</span>
				{/if}
				{#if heroType === 'league' || heroType === 'friendly'}
					<span class="hero-sep">·</span>
					<span class="hero-chip">{isAway ? 'Auswärts' : 'Heim'}</span>
				{/if}
			</div>
			{#if du}<span class="hero-badge">{du}</span>{/if}
		</button>
	{/if}

	<!-- ── Action Cards — urgency only ──────────────────────────────────── -->
	{#if pendingLineup || urgentTournament || urgentLandesbewerb || resultNudgeMatch || carpoolNeededMatch}
		<div class="action-cards">

			{#if pendingLineup}
				{@const gp = pendingLineup.game_plans}
				{@const m  = gp?.matches}
				<button class="action-card action-card--warn" onclick={() => openLineupSheet(pendingLineup)}>
					<span class="material-symbols-outlined action-icon">warning</span>
					<div class="action-body">
						<span class="action-title">Aufstellung bestätigen</span>
						{#if m}<span class="action-sub">{(m.home_away === 'HEIM' ? 'vs. ' : 'bei ')}{m.opponent} · {fmtDate(m.date)}</span>{/if}
						{#if gp?.confirmation_deadline}<span class="action-sub">Frist: {fmtDate(gp.confirmation_deadline)}</span>{/if}
					</div>
					<span class="action-cta">Antworten →</span>
				</button>
			{/if}

			{#if urgentTournament}
				<button class="action-card action-card--gold" onclick={() => setSubtab('/spielbetrieb', 'turnier')}>
					<span class="material-symbols-outlined action-icon">military_tech</span>
					<div class="action-body">
						<span class="action-title">Turnier-Abstimmung</span>
						<span class="action-sub">{urgentTournament.title}</span>
						{#if urgentTournament.voting_deadline}<span class="action-sub">Frist: {fmtDate(urgentTournament.voting_deadline.slice(0,10))}</span>{/if}
					</div>
					<span class="action-cta">Abstimmen →</span>
				</button>
			{/if}

			{#if urgentLandesbewerb}
				<button class="action-card action-card--gold" onclick={() => setSubtab('/spielbetrieb', 'landesbewerb')}>
					<span class="material-symbols-outlined action-icon">workspace_premium</span>
					<div class="action-body">
						<span class="action-title">Landesbewerb anmelden</span>
						<span class="action-sub">{urgentLandesbewerb.title}</span>
						{#if urgentLandesbewerb.registration_deadline}<span class="action-sub">Frist: {fmtDate(urgentLandesbewerb.registration_deadline.slice(0,10))}</span>{/if}
					</div>
					<span class="action-cta">Anmelden →</span>
				</button>
			{/if}

			{#if carpoolNeededMatch}
				<button class="action-card action-card--blue" onclick={() => openCarpoolSheet(carpoolNeededMatch)}>
					<span class="material-symbols-outlined action-icon">directions_car</span>
					<div class="action-body">
						<span class="action-title">Mitfahrt finden</span>
						<span class="action-sub">bei {carpoolNeededMatch.opponent} · {fmtDate(carpoolNeededMatch.date)}</span>
					</div>
					<span class="action-cta">Suchen →</span>
				</button>
			{/if}

			{#if resultNudgeMatch}
				<button class="action-card action-card--blue" onclick={() => { goto('/profil'); setSubtab('/profil', 'admin'); }}>
					<span class="material-symbols-outlined action-icon">edit_note</span>
					<div class="action-body">
						<span class="action-title">Ergebnis eintragen</span>
						<span class="action-sub">{resultNudgeMatch.opponent} · {fmtDate(resultNudgeMatch.date)}</span>
					</div>
					<span class="action-cta">Eintragen →</span>
				</button>
			{/if}

		</div>
	{/if}

	<!-- ── Hub Row ─────────────────────────────────────────────────────── -->
	<div class="hub-row">

		<button class="hub-card" onclick={() => setSubtab('/spielbetrieb', 'spiele')}>
			<span class="material-symbols-outlined hub-icon">sports</span>
			<span class="hub-label">Spiele</span>
			{#if nextLeagueMatch}
				<span class="hub-info">{nextLeagueMatch.home_away === 'HEIM' ? 'vs.' : 'bei'} {shortName(nextLeagueMatch.opponent)}</span>
				<span class="hub-sub">{fmtDate(nextLeagueMatch.date)}</span>
			{:else}
				<span class="hub-info hub-info--muted">Kein Spiel</span>
			{/if}
		</button>

		<button class="hub-card" onclick={() => setSubtab('/spielbetrieb', 'turnier')}>
			<span class="material-symbols-outlined hub-icon">military_tech</span>
			<span class="hub-label">Turnier</span>
			{#if tournamentCount > 0}
				<span class="hub-info">{tournamentCount} {tournamentCount === 1 ? 'aktiv' : 'aktive'}</span>
				{#if nextTournament?.voting_deadline}
					{@const dd = deadlineDays(nextTournament.voting_deadline)}
					{#if dd}<span class="hub-sub">Frist {dd}</span>{/if}
				{/if}
			{:else}
				<span class="hub-info hub-info--muted">Keine</span>
			{/if}
		</button>

		<button class="hub-card" onclick={() => setSubtab('/spielbetrieb', 'landesbewerb')}>
			<span class="material-symbols-outlined hub-icon">workspace_premium</span>
			<span class="hub-label">Landesb.</span>
			{#if landesCount > 0}
				<span class="hub-info">{landesCount} {landesCount === 1 ? 'offen' : 'offen'}</span>
				{#if nextLandes?.registration_deadline}
					{@const dd = deadlineDays(nextLandes.registration_deadline)}
					{#if dd}<span class="hub-sub">Frist {dd}</span>{/if}
				{/if}
			{:else}
				<span class="hub-info hub-info--muted">Keine</span>
			{/if}
		</button>

	</div>

	<!-- ── Letzte Ergebnisse ───────────────────────────────────────────── -->
	{#if recentResults.length > 0}
		<div class="results-section">
			<h3 class="section-heading">
				<span class="material-symbols-outlined">scoreboard</span>
				Letzte Ergebnisse
			</h3>
			<div class="results-list">
				{#each recentResults as m}
					{@const total = teamTotal(m)}
					<div class="result-row">
						<div class="result-info">
							<span class="result-opp">{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}</span>
							<span class="result-meta">{fmtDate(m.date)} · {m.leagues?.name ?? ''}</span>
						</div>
						<div class="result-score">{total}</div>
					</div>
				{/each}
			</div>
			<button class="more-btn" onclick={() => setSubtab('/spielbetrieb', 'spiele')}>Alle Ergebnisse →</button>
		</div>
	{/if}

	<!-- ── 21-day Spielfeed ────────────────────────────────────────────── -->
	<div class="feed-section">
		<h3 class="section-heading">
			<span class="material-symbols-outlined">date_range</span>
			Nächste 21 Tage
		</h3>

		{#if feedByDate.length === 0}
			<div class="feed-empty">
				<span class="material-symbols-outlined">event_available</span>
				<p>Keine Termine in den nächsten 21 Tagen</p>
			</div>
		{:else}
			<div class="feed-list">
				{#each feedByDate as group}
					<div class="feed-date-group">
						<span class="feed-date-chip">{fmtDate(group.date)}</span>
						<div class="feed-group-items">
							{#each group.items as item}

								{#if item.type === 'league-match'}
									{@const m       = item.data}
									{@const isAway  = m.home_away !== 'HEIM'}
									{@const ls      = lineupStatusFor(m.id)}
									{@const cs      = isAway ? carpoolStatusFor(m.id) : null}
									{@const myEntry = pendingLineups.find(p => p.game_plans?.matches?.id === m.id)}
									<div class="feed-item feed-item--league">
										<span class="feed-item-icon material-symbols-outlined" style="color:#1e3a5f">sports</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{(isAway ? 'bei ' : 'vs. ') + m.opponent}</span>
											<span class="feed-item-sub">
												{#if m.time}{shortTime(m.time)} Uhr{/if}
												<span class="feed-chip feed-chip--home-away" class:feed-chip--away={isAway}>{isAway ? 'Auswärts' : 'Heim'}</span>
												{#if m.leagues?.name}<span class="feed-chip feed-chip--neutral">{m.leagues.name}</span>{/if}
												{#if ls}<span class="feed-chip feed-chip--lineup feed-chip--{ls.kind}">{ls.label}</span>{/if}
												{#if cs && cs.kind !== 'none'}<span class="feed-chip feed-chip--carpool feed-chip--cp-{cs.kind}">{cs.label}</span>{/if}
											</span>
										</div>
										<div class="feed-actions">
											{#if myEntry}
												<button class="quick-btn quick-btn--yes" aria-label="Bestätigen" onclick={(e) => { e.stopPropagation(); quickConfirm(myEntry.id, true); }}>
													<span class="material-symbols-outlined">check</span>
												</button>
												<button class="quick-btn quick-btn--no" aria-label="Absagen" onclick={(e) => { e.stopPropagation(); quickConfirm(myEntry.id, false); }}>
													<span class="material-symbols-outlined">close</span>
												</button>
											{:else if isAway}
												<button class="feed-action-btn" onclick={() => openCarpoolSheet(m)}>
													<span class="material-symbols-outlined">directions_car</span>
													Fahrt
												</button>
											{/if}
										</div>
									</div>

								{:else if item.type === 'friendly-match'}
									{@const m      = item.data}
									{@const isAway = m.home_away !== 'HEIM'}
									<div class="feed-item feed-item--friendly">
										<span class="feed-item-icon material-symbols-outlined" style="color:#15803d">handshake</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{(isAway ? 'bei ' : 'vs. ') + m.opponent}</span>
											<span class="feed-item-sub">
												{#if m.time}{shortTime(m.time)} Uhr{/if}
												<span class="feed-chip feed-chip--neutral">Freundschaft</span>
												<span class="feed-chip feed-chip--home-away" class:feed-chip--away={isAway}>{isAway ? 'Auswärts' : 'Heim'}</span>
											</span>
										</div>
										{#if isAway}
											<button class="feed-action-btn" onclick={() => openCarpoolSheet(m)}>
												<span class="material-symbols-outlined">directions_car</span>
												Fahrt
											</button>
										{/if}
									</div>

								{:else if item.type === 'tournament-match' || item.type === 'landesbewerb-match'}
									{@const m      = item.data}
									{@const isLB   = item.type === 'landesbewerb-match'}
									<button class="feed-item feed-item--tourney feed-item--btn" onclick={() => setSubtab('/spielbetrieb', isLB ? 'landesbewerb' : 'turnier')}>
										<span class="feed-item-icon material-symbols-outlined" style="color:#b45309">{isLB ? 'workspace_premium' : 'military_tech'}</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{m.tournament_title ?? m.opponent ?? (isLB ? 'Landesbewerb' : 'Turnier')}</span>
											<span class="feed-item-sub">
												{#if m.time}{shortTime(m.time)} Uhr{/if}
												{#if m.tournament_location}<span class="feed-item-loc"><span class="material-symbols-outlined">location_on</span>{m.tournament_location}</span>{/if}
											</span>
										</div>
									</button>

								{:else if item.type === 'tournament-event'}
									{@const t  = item.data}
									{@const dd = deadlineDays(t.voting_deadline)}
									<button class="feed-item feed-item--tourney feed-item--btn" onclick={() => setSubtab('/spielbetrieb', 'turnier')}>
										<span class="feed-item-icon material-symbols-outlined" style="color:#b45309">military_tech</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{t.title}</span>
											<span class="feed-item-sub">
												<span class="feed-chip feed-chip--status feed-chip--{t.status}">{statusLabel(t.status)}</span>
												{#if dd}<span class="feed-chip feed-chip--neutral">Frist {dd}</span>{/if}
												{#if t.location}<span class="feed-item-loc"><span class="material-symbols-outlined">location_on</span>{t.location}</span>{/if}
											</span>
										</div>
									</button>

								{:else if item.type === 'landesbewerb-event'}
									{@const lb = item.data}
									{@const dd = deadlineDays(lb.registration_deadline)}
									{@const registered = (lb.landesbewerb_registrations ?? []).some(r => r.player_id === $playerId)}
									<button class="feed-item feed-item--tourney feed-item--btn" onclick={() => setSubtab('/spielbetrieb', 'landesbewerb')}>
										<span class="feed-item-icon material-symbols-outlined" style="color:#b45309">workspace_premium</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{lb.title}</span>
											<span class="feed-item-sub">
												<span class="feed-chip feed-chip--neutral">{BEWERB_LABEL[lb.typ] ?? lb.typ ?? 'Bewerb'}</span>
												{#if dd}<span class="feed-chip feed-chip--lineup feed-chip--{registered ? 'in' : 'await'}">{registered ? 'Angemeldet' : 'Frist ' + dd}</span>{/if}
												{#if lb.location}<span class="feed-item-loc"><span class="material-symbols-outlined">location_on</span>{lb.location}</span>{/if}
											</span>
										</div>
									</button>

								{:else if item.type === 'result-nudge'}
									{@const m = item.data}
									<button class="feed-item feed-item--result-nudge feed-item--btn" onclick={() => { goto('/profil'); setSubtab('/profil', 'admin'); }}>
										<span class="feed-item-icon material-symbols-outlined" style="color:#1d4ed8">edit_note</span>
										<div class="feed-item-body">
											<span class="feed-item-title">Ergebnis eintragen →</span>
											<span class="feed-item-sub">{m.opponent} · {fmtDate(m.date)}</span>
										</div>
									</button>

								{/if}

							{/each}
						</div>
					</div>
				{/each}
			</div>
		{/if}
	</div>

</div>
{/if}

<!-- ── Carpool BottomSheet ──────────────────────────────────────────────── -->
<BottomSheet bind:open={carpoolSheetOpen} title="Fahrgemeinschaft">
	{#if carpoolLoading}
		<div class="sheet-loading">
			<span class="material-symbols-outlined sheet-loading-icon">directions_car</span>
			<p>Lädt…</p>
		</div>
	{:else if carpoolSheetMatch}
		<CarpoolCard match={carpoolSheetMatch} meetup={carpoolSheetMeetup} carpools={carpoolSheetData} onChanged={refreshCarpoolSheet} />
	{/if}
</BottomSheet>

<!-- ── Lineup-Confirm BottomSheet ──────────────────────────────────────── -->
<BottomSheet bind:open={lineupSheetOpen} title="Aufstellungsbestätigung">
	{#if lineupSheetEntry}
		{@const gp = lineupSheetEntry.game_plans}
		{@const m  = gp?.matches}
		<div class="lineup-sheet">
			{#if m}
				<div class="lineup-sheet-head">
					<span class="lineup-sheet-league">{m.leagues?.name ?? ''}</span>
					<h4 class="lineup-sheet-opp">{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}</h4>
					<p class="lineup-sheet-meta">{fmtDate(m.date)}{m.time ? ' · ' + shortTime(m.time) + ' Uhr' : ''}</p>
				</div>
			{/if}
			{#if gp?.confirmation_deadline}
				<p class="lineup-sheet-deadline">
					<span class="material-symbols-outlined">schedule</span>
					Frist: {fmtDate(gp.confirmation_deadline)}
				</p>
			{/if}
			<p class="lineup-sheet-pos">
				Deine Position: <strong>{lineupSheetEntry.position ?? '?'}</strong>
			</p>
			<div class="lineup-sheet-actions">
				<button class="lineup-sheet-btn lineup-sheet-btn--decline" onclick={() => respondLineup(false)}>
					<span class="material-symbols-outlined">close</span>Ablehnen
				</button>
				<button class="lineup-sheet-btn lineup-sheet-btn--confirm" onclick={() => respondLineup(true)}>
					<span class="material-symbols-outlined">check</span>Bestätigen
				</button>
			</div>
		</div>
	{/if}
</BottomSheet>

<style>
	.ueb-page { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-5); }

	.ueb-loading { padding: var(--space-5); display: flex; flex-direction: column; gap: var(--space-4); }
	.ueb-skeleton { height: 80px; border-radius: var(--radius-lg); }
	.ueb-skeleton--hero { height: 130px; }
	.ueb-skeleton--row  { height: 88px; }

	/* ── Hero — red gradient (spielbetrieb theme) ──────────────────────── */
	.hero-card {
		position: relative; width: 100%; text-align: left;
		background: linear-gradient(135deg, #7f1d1d 0%, #991b1b 40%, #b91c1c 100%);
		border-radius: var(--radius-xl, 20px); padding: var(--space-5) var(--space-5) var(--space-6);
		color: #fff; box-shadow: 0 8px 28px rgba(127,29,29,0.32); border: none; cursor: pointer;
		-webkit-tap-highlight-color: transparent; transition: transform 120ms ease, box-shadow 120ms ease; overflow: hidden;
	}
	.hero-card::before {
		content: ''; position: absolute; inset: 0;
		background: radial-gradient(ellipse at 80% 20%, rgba(255,255,255,0.10) 0%, transparent 60%); pointer-events: none;
	}
	.hero-card:active { transform: scale(0.98); box-shadow: 0 4px 16px rgba(127,29,29,0.28); }
	.hero-eyebrow { display: block; font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; opacity: 0.78; margin-bottom: var(--space-2); }
	.hero-title { font-family: var(--font-display); font-size: 1.35rem; font-weight: 800; line-height: 1.2; margin: 0 0 var(--space-3); }
	.hero-meta { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-label-md); opacity: 0.88; flex-wrap: wrap; }
	.hero-meta-icon { font-size: 0.9rem; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20; }
	.hero-sep { opacity: 0.5; }
	.hero-chip { background: rgba(255,255,255,0.18); border: 1px solid rgba(255,255,255,0.25); border-radius: 999px; padding: 1px 8px; font-size: 0.7rem; font-weight: 700; }
	.hero-badge { position: absolute; top: var(--space-4); right: var(--space-4); background: rgba(255,255,255,0.18); backdrop-filter: blur(4px); border: 1px solid rgba(255,255,255,0.25); border-radius: 999px; padding: 3px 10px; font-size: var(--text-label-sm); font-weight: 700; }

	/* ── Action Cards ─────────────────────────────────────────────────── */
	.action-cards { display: flex; flex-direction: column; gap: var(--space-3); }
	.action-card { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-4); border-radius: var(--radius-lg); border: 1.5px solid transparent; text-align: left; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; box-shadow: var(--shadow-card); }
	.action-card:active { transform: scale(0.98); }
	.action-card--warn { background: #fefce8; border-color: #fde047; }
	.action-card--gold { background: #fffbeb; border-color: #fbbf24; }
	.action-card--blue { background: #eff6ff; border-color: #93c5fd; }
	.action-icon { font-size: 1.4rem; flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.action-card--warn .action-icon { color: #ca8a04; }
	.action-card--gold .action-icon { color: #b45309; }
	.action-card--blue .action-icon { color: #1d4ed8; }
	.action-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.action-title { font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); }
	.action-sub   { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); }
	.action-cta   { font-size: var(--text-label-sm); font-weight: 700; flex-shrink: 0; }
	.action-card--warn .action-cta, .action-card--gold .action-cta { color: #92400e; }
	.action-card--blue .action-cta { color: #1d4ed8; }

	/* ── Hub Row ─────────────────────────────────────────────────────── */
	.hub-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); }
	.hub-card { display: flex; flex-direction: column; align-items: flex-start; gap: 3px; padding: var(--space-4) var(--space-3); background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); border: 1.5px solid var(--color-outline-variant); box-shadow: var(--shadow-card); cursor: pointer; -webkit-tap-highlight-color: transparent; text-align: left; transition: transform 100ms ease; overflow: hidden; }
	.hub-card:active { transform: scale(0.96); }
	.hub-icon  { font-size: 1.2rem; color: var(--color-primary); font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; margin-bottom: 2px; }
	.hub-label { font-family: var(--font-display); font-size: var(--text-label-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-on-surface); }
	.hub-info  { font-size: 0.7rem; font-weight: 700; color: var(--color-on-surface-variant); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }
	.hub-info--muted { opacity: 0.5; }
	.hub-sub   { font-size: 0.62rem; color: var(--color-outline); }

	/* ── Section heading shared ──────────────────────────────────────── */
	.section-heading { display: flex; align-items: center; gap: var(--space-2); font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em; margin: 0; color: var(--color-on-surface); }
	.section-heading .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }

	/* ── Letzte Ergebnisse ────────────────────────────────────────────── */
	.results-section { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-4); background: var(--color-surface-container-lowest); border: 1px solid var(--color-outline-variant); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); }
	.results-list { display: flex; flex-direction: column; gap: 0; }
	.result-row { display: flex; align-items: center; justify-content: space-between; gap: var(--space-3); padding: var(--space-2) 0; border-top: 1px solid var(--color-surface-container); }
	.result-row:first-child { border-top: none; padding-top: 0; }
	.result-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
	.result-opp  { font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.result-meta { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); }
	.result-score { font-family: var(--font-display); font-size: 1.1rem; font-weight: 800; color: var(--color-primary); flex-shrink: 0; }
	.more-btn { align-self: flex-start; background: none; border: none; padding: 0; font-size: var(--text-label-sm); font-weight: 700; color: var(--color-primary); cursor: pointer; font-family: inherit; -webkit-tap-highlight-color: transparent; }

	/* ── Feed ────────────────────────────────────────────────────────── */
	.feed-section { display: flex; flex-direction: column; gap: var(--space-4); }
	.feed-empty { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.feed-empty .material-symbols-outlined { font-size: 2.5rem; opacity: 0.5; }
	.feed-empty p { margin: 0; font-size: var(--text-label-md); }
	.feed-list { display: flex; flex-direction: column; gap: var(--space-4); }
	.feed-date-group { display: flex; flex-direction: column; gap: var(--space-2); }
	.feed-date-chip { display: inline-flex; align-self: flex-start; background: var(--color-surface-container); border-radius: 999px; padding: 3px 10px; font-size: var(--text-label-sm); font-weight: 700; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.06em; }
	.feed-group-items { display: flex; flex-direction: column; gap: var(--space-2); }

	.feed-item { display: flex; align-items: center; gap: var(--space-3); background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); padding: var(--space-3) var(--space-4); box-shadow: var(--shadow-card); border: 1.5px solid transparent; }
	.feed-item--btn { width: 100%; text-align: left; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; }
	.feed-item--btn:active { transform: scale(0.98); }
	.feed-item--league   { border-color: rgba(30,58,95,0.14); }
	.feed-item--friendly { border-color: rgba(20,83,45,0.18); }
	.feed-item--tourney  { border-color: rgba(180,83,9,0.25); }
	.feed-item--result-nudge { border-color: rgba(29,78,216,0.20); border-left: 3px solid #1d4ed8; }

	.feed-item-icon { font-size: 1.3rem; flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.feed-item-body { flex: 1; display: flex; flex-direction: column; gap: 4px; min-width: 0; }
	.feed-item-title { font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.feed-item-sub   { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); display: flex; align-items: center; gap: var(--space-2); flex-wrap: wrap; row-gap: 4px; }
	.feed-item-loc   { display: inline-flex; align-items: center; gap: 2px; }
	.feed-item-loc .material-symbols-outlined { font-size: 0.8rem; }

	.feed-chip { display: inline-flex; border-radius: 999px; padding: 1px 7px; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; }
	.feed-chip--neutral   { background: rgba(0,0,0,0.06); color: var(--color-on-surface-variant); }
	.feed-chip--home-away { background: rgba(30,58,95,0.10); color: #1e3a5f; }
	.feed-chip--away      { background: rgba(30,58,95,0.20); }

	.feed-chip--lineup           { background: rgba(0,0,0,0.06); color: var(--color-on-surface-variant); }
	.feed-chip--pending          { background: rgba(0,0,0,0.06); color: var(--color-on-surface-variant); }
	.feed-chip--in               { background: rgba(22,163,74,0.14);  color: #15803d; }
	.feed-chip--out              { background: rgba(0,0,0,0.06);       color: var(--color-on-surface-variant); }
	.feed-chip--declined         { background: rgba(204,0,0,0.10);     color: var(--color-primary); }
	.feed-chip--await            { background: rgba(234,179,8,0.18);   color: #92400e; }

	.feed-chip--carpool          { background: rgba(0,0,0,0.06); color: var(--color-on-surface-variant); }
	.feed-chip--cp-driver        { background: rgba(212,175,55,0.20);  color: #92400e; }
	.feed-chip--cp-in            { background: rgba(22,163,74,0.14);   color: #15803d; }
	.feed-chip--cp-open          { background: rgba(59,130,246,0.14);  color: #1d4ed8; }

	.feed-chip--status           { background: rgba(0,0,0,0.06); color: var(--color-on-surface-variant); }
	.feed-chip--voting           { background: rgba(234,179,8,0.18);   color: #92400e; }
	.feed-chip--voting_closed    { background: rgba(0,0,0,0.10);       color: var(--color-on-surface-variant); }
	.feed-chip--scheduling       { background: rgba(59,130,246,0.14);  color: #1d4ed8; }
	.feed-chip--confirmed        { background: rgba(22,163,74,0.14);   color: #15803d; }

	.feed-actions { display: flex; align-items: center; gap: var(--space-2); flex-shrink: 0; }
	.feed-action-btn { display: inline-flex; align-items: center; gap: 4px; padding: 5px 10px; border-radius: var(--radius-md); background: #dbeafe; color: #1d4ed8; border: none; font-size: var(--text-label-sm); font-weight: 700; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; }
	.feed-action-btn:active { transform: scale(0.94); }
	.feed-action-btn .material-symbols-outlined { font-size: 0.95rem; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20; }

	.quick-btn { width: 32px; height: 32px; display: inline-flex; align-items: center; justify-content: center; border-radius: 50%; border: none; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; }
	.quick-btn:active { transform: scale(0.92); }
	.quick-btn .material-symbols-outlined { font-size: 1.1rem; font-variation-settings: 'FILL' 1, 'wght' 600, 'GRAD' 0, 'opsz' 24; }
	.quick-btn--yes { background: rgba(22,163,74,0.14);  color: #15803d; }
	.quick-btn--no  { background: rgba(204,0,0,0.10);    color: var(--color-primary); }

	/* ── Sheets ───────────────────────────────────────────────────────── */
	.sheet-loading { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.sheet-loading-icon { font-size: 2rem; opacity: 0.4; }

	.lineup-sheet { padding: var(--space-2) 0 var(--space-4); display: flex; flex-direction: column; gap: var(--space-4); }
	.lineup-sheet-head { text-align: center; display: flex; flex-direction: column; gap: 4px; }
	.lineup-sheet-league { font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: var(--color-on-surface-variant); }
	.lineup-sheet-opp { font-family: var(--font-display); font-size: 1.2rem; font-weight: 800; margin: 0; color: var(--color-on-surface); }
	.lineup-sheet-meta { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin: 0; }
	.lineup-sheet-deadline { display: flex; align-items: center; justify-content: center; gap: var(--space-2); font-size: var(--text-label-md); color: var(--color-primary); margin: 0; }
	.lineup-sheet-deadline .material-symbols-outlined { font-size: 1rem; }
	.lineup-sheet-pos { text-align: center; font-size: var(--text-body-md); color: var(--color-on-surface); margin: 0; }
	.lineup-sheet-actions { display: flex; gap: var(--space-3); }
	.lineup-sheet-btn { flex: 1; padding: var(--space-3); border-radius: var(--radius-lg); font-size: var(--text-label-md); font-weight: 700; cursor: pointer; border: none; -webkit-tap-highlight-color: transparent; display: flex; align-items: center; justify-content: center; gap: var(--space-2); transition: transform 100ms ease; }
	.lineup-sheet-btn:active { transform: scale(0.97); }
	.lineup-sheet-btn--decline { background: var(--color-surface-container); color: var(--color-on-surface); }
	.lineup-sheet-btn--confirm { background: var(--color-primary);            color: #fff; }
</style>
