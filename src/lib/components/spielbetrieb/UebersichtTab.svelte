<script>
	import { onMount }      from 'svelte';
	import { get }          from 'svelte/store';
	import { page }         from '$app/stores';
	import { goto }         from '$app/navigation';
	import { sb }           from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { shortTime }                              from '$lib/utils/league.js';
	import { matchEnded }                             from '$lib/utils/matchTiming.js';
	import { BEWERB_LABEL } from '$lib/constants/competitions.js';
	import { shortName }    from '$lib/utils/players.js';
	import BottomSheet      from '$lib/components/BottomSheet.svelte';
	import CarpoolCard      from '$lib/components/spielbetrieb/CarpoolCard.svelte';
	import OpenMatchesSheet from '$lib/components/spielbetrieb/OpenMatchesSheet.svelte';
	import PillSwitcher     from '$lib/components/ui/PillSwitcher.svelte';
	import SpielbetriebeTab from '$lib/components/spielbetrieb/SpielbetriebeTab.svelte';
	import TurniereTab      from '$lib/components/spielbetrieb/TurniereTab.svelte';
	import LandesbewerbeTab from '$lib/components/spielbetrieb/LandesbewerbeTab.svelte';
	import { seasonStart }  from '$lib/utils/season.js';

	// ── Inline pill-switcher (Spiele/Turnier/Landesbewerb) ────────────────────
	const _VALID_PILLS = ['spiele', 'turnier', 'landesbewerb'];
	const _initialPill = get(page).url.searchParams.get('pill');
	let activePill = $state(_VALID_PILLS.includes(_initialPill) ? _initialPill : 'spiele');

	$effect(() => {
		const url = new URL($page.url);
		if (url.searchParams.get('pill') !== activePill) {
			url.searchParams.set('pill', activePill);
			goto(url.pathname + url.search, { replaceState: true, keepFocus: true, noScroll: true });
		}
	});

	function jumpToComp(pill) {
		activePill = pill;
		// Scroll to the section after the next tick so DOM updates first
		setTimeout(() => {
			document.getElementById('sp-comp-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
		}, 50);
	}

	// ── State ─────────────────────────────────────────────────────────────────
	let upcomingMatches = $state([]);          // matches in next 21 days
	let pastMatches     = $state([]);          // league matches in last 14 days (for results + nudge)
	let tournaments     = $state([]);          // active turniere
	let landesbewerbe   = $state([]);          // open registrations / upcoming
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

	let openMatchesCount     = $state(0);
	let openMatchesSheetOpen = $state(false);

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
		if (!me)                       return { kind: 'out',      label: 'Du bist nicht dabei' };
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

	function matchPublished(m) {
		return (m.game_plans ?? []).some(gp => gp.result_published_at);
	}

	const resultNudgeMatch = $derived.by(() => {
		if ($playerRole !== 'kapitaen') return null;
		return pastMatches.find(m => matchEnded(m) && !matchPublished(m)) ?? null;
	});

	// ── Hub row ───────────────────────────────────────────────────────────────
	const nextLeagueMatch = $derived(upcomingMatches.find(m => matchTypeOf(m) === 'league') ?? null);
	const tournamentCount = $derived(tournaments.length);
	const nextTournament  = $derived(tournaments[0] ?? null);
	const landesCount     = $derived(landesbewerbe.length);
	const nextLandes      = $derived(landesbewerbe[0] ?? null);

	// ── Letzte Ergebnisse ─────────────────────────────────────────────────────
	const recentResults = $derived(pastMatches.filter(m => matchPublished(m) && matchHasScores(m)).slice(0, 3));

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
				.select('id, date, time, opponent, home_away, league_id, cal_week, leagues(name), game_plans(id, result_published_at, game_plan_players(score, played))')
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

			// 4: own carpool seats
			pid ? sb.from('match_carpool_seats')
				.select('carpool_id, match_carpools!inner(match_id)')
				.eq('passenger_id', pid)
				: Promise.resolve({ data: [] }),

			// 5: own driving
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
		myCarpoolSeats  = results[4].data ?? [];
		myDriving       = results[5].data ?? [];

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

		loadOpenMatchesCount();

		loading = false;
	}

	async function loadOpenMatchesCount() {
		const { data, error } = await sb
			.from('matches')
			.select('id, opponent, game_plans(result_published_at)')
			.not('league_id', 'is', null)
			.eq('is_tournament', false)
			.eq('is_landesbewerb', false)
			.eq('is_friendly', false)
			.gte('date', seasonStart());
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		openMatchesCount = (data ?? []).filter(m =>
			m.opponent !== 'spielfrei' &&
			(m.game_plans ?? []).every(gp => !gp.result_published_at)
		).length;
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

	function statusLabel(s) {
		return ({ voting: 'Abstimmung', voting_closed: 'Geschlossen', scheduling: 'Terminplanung', confirmed: 'Bestätigt' })[s] ?? s;
	}

	function openResultEntry(matchId) {
		activePill = 'spiele';
		const url = new URL($page.url);
		url.searchParams.set('pill', 'spiele');
		if (matchId) url.searchParams.set('match', String(matchId));
		goto(url.pathname + url.search, { keepFocus: true, noScroll: true });
		setTimeout(() => {
			document.getElementById('sp-comp-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
		}, 50);
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
		<button class="hero-card" onclick={() => jumpToComp(heroSubtabFor(heroType))}>
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
	{#if urgentTournament || urgentLandesbewerb || resultNudgeMatch || carpoolNeededMatch}
		<div class="action-cards">

			{#if urgentTournament}
				<button class="action-card action-card--gold" onclick={() => jumpToComp('turnier')}>
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
				<button class="action-card action-card--gold" onclick={() => jumpToComp('landesbewerb')}>
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
				<button class="action-card action-card--blue" onclick={() => openResultEntry(resultNudgeMatch.id)}>
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

		<button class="hub-card" onclick={() => jumpToComp('spiele')}>
			<span class="material-symbols-outlined hub-icon">sports</span>
			<span class="hub-label">Spiele</span>
			{#if nextLeagueMatch}
				<span class="hub-info">{nextLeagueMatch.home_away === 'HEIM' ? 'vs.' : 'bei'} {shortName(nextLeagueMatch.opponent)}</span>
				<span class="hub-sub">{fmtDate(nextLeagueMatch.date)}</span>
			{:else}
				<span class="hub-info hub-info--muted">Kein Spiel</span>
			{/if}
		</button>

		<button class="hub-card" onclick={() => jumpToComp('turnier')}>
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

		<button class="hub-card" onclick={() => jumpToComp('landesbewerb')}>
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

	{#if openMatchesCount > 0}
		<button class="open-matches-pill" onclick={() => openMatchesSheetOpen = true}>
			<span class="material-symbols-outlined">scoreboard</span>
			<span>{openMatchesCount} {openMatchesCount === 1 ? 'offenes Spiel' : 'offene Spiele'} · alle anzeigen</span>
			<span class="material-symbols-outlined">arrow_forward</span>
		</button>
	{/if}

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
			<button class="more-btn" onclick={() => jumpToComp('spiele')}>Alle Ergebnisse →</button>
		</div>
	{/if}

	<!-- ── Bewerbe (Spiele · Turnier · Landesbewerb) ──────────────────────── -->
	<section class="sp-comp-section" id="sp-comp-section">
		<div class="sp-comp-pillbar">
			<PillSwitcher
				items={[
					{ key: 'spiele',       label: 'Spiele',       icon: 'sports'            },
					{ key: 'turnier',      label: 'Turnier',      icon: 'military_tech'     },
					{ key: 'landesbewerb', label: 'Landesbewerb', icon: 'workspace_premium' },
				]}
				value={activePill}
				onSelect={(k) => (activePill = k)}
			/>
		</div>

		{#if activePill === 'spiele'}<SpielbetriebeTab />{/if}
		{#if activePill === 'turnier'}<TurniereTab />{/if}
		{#if activePill === 'landesbewerb'}<LandesbewerbeTab />{/if}
	</section>

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

<OpenMatchesSheet bind:open={openMatchesSheetOpen} />

<style>
	.ueb-page { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-5); }

	/* ── Inline Bewerbe-Section (Spiele/Turnier/Landesbewerb) ───────────── */
	.sp-comp-section {
		margin-top: var(--space-6);
		padding-top: var(--space-4);
		border-top: 1px solid var(--color-outline-variant);
	}
	.sp-comp-pillbar {
		position: sticky;
		top: 0;
		z-index: 5;
		background: var(--color-surface-container-lowest);
		padding: var(--space-2) 0;
		margin-bottom: var(--space-3);
	}

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

	/* ── Feed item primitives (still used by result-nudge action card) ─── */
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

	/* ── Open-Matches Pill ────────────────────────────────────────────── */
	.open-matches-pill {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		width: 100%;
		padding: var(--space-3) var(--space-4);
		margin-top: var(--space-3);
		background: var(--color-surface-container);
		color: var(--color-on-surface);
		border: none;
		border-radius: var(--radius-full);
		font: var(--text-label-md);
		font-family: var(--font-body);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease;
	}
	.open-matches-pill:hover { background: var(--color-surface-container-high, var(--color-surface-container)); }
	.open-matches-pill .material-symbols-outlined { font-size: 18px; color: var(--color-primary); }
	.open-matches-pill > span:nth-child(2) { flex: 1; text-align: left; }

	/* ── Sheets ───────────────────────────────────────────────────────── */
	.sheet-loading { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.sheet-loading-icon { font-size: 2rem; opacity: 0.4; }
</style>
