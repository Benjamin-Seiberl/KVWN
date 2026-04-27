<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate } from '$lib/utils/dates.js';
	import { imgPath, shortName, BLANK_IMG } from '$lib/utils/players.js';
	import ContextMenu from '$lib/components/ContextMenu.svelte';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let loading         = $state(true);
	let players         = $state([]);   // alle Spieler mit Stats, nach Schnitt sortiert
	let myStats         = $state(null); // eingeloggter Spieler
	let myScores        = $state([]);   // letzte 6 Ergebnisse (älteste zuerst, für Chart)
	let clubAvgSeries   = $state([]);   // [{ round, avg, count }] – Vereinsschnitt pro Runde
	let seasonStats     = $state(null); // Saison-KPIs: { clubAvg, clubAvgPrev, homeAvg, awayAvg, myAvg, myAvgPrev }

	// ── Daten laden ────────────────────────────────────────
	onMount(async () => {
		const { data: playerData, error: pErr } = await sb
			.from('players')
			.select('id, name, photo')
			.eq('active', true)
			.order('name');
		if (pErr) { triggerToast('Fehler: ' + pErr.message); loading = false; return; }
		if (!playerData?.length) { loading = false; return; }

		// Scores + Match-Metadaten parallel laden.
		// Match-Metadaten (date, opponent, home_away, round) per cal_week+league_id zuordenbar.
		const [{ data: allScores, error: sErr }, { data: matchMeta, error: mErr }] = await Promise.all([
			sb.from('game_plan_players')
				.select('player_id, score, game_plans!inner(cal_week, league_id)')
				.in('player_id', playerData.map(p => p.id))
				.eq('played', true)
				.not('score', 'is', null)
				.order('cal_week', { referencedTable: 'game_plans', ascending: false })
				.limit(1000),
			sb.from('matches')
				.select('cal_week, league_id, round, date, opponent, home_away, is_tournament')
				.not('round', 'is', null),
		]);
		if (sErr) { triggerToast('Fehler: ' + sErr.message); loading = false; return; }
		if (mErr) { triggerToast('Fehler: ' + mErr.message); loading = false; return; }

		// Lookup: `${cal_week}_${league_id}` → match-Metadaten.
		// Nur reguläre Ligaspiele – Turniere (NÖ-Cup) werden für Heim/Auswärts/Runden ausgeschlossen.
		const matchLookup = {};
		for (const m of matchMeta ?? []) {
			if (m.is_tournament) continue;
			matchLookup[`${m.cal_week}_${m.league_id}`] = m;
		}

		// Scores pro Spieler – alle Spiele (inkl. NÖ-Cup für Schnitte) +
		// pro Spieler eine reichere Liste mit { score, date, opponent, home_away, round } für Drilldown.
		const scoreMap = {};        // pid → number[]
		const scoreRichMap = {};    // pid → { score, date, opponent, home_away, round }[] (sortiert: neueste zuerst)
		for (const g of allScores ?? []) {
			if (!scoreMap[g.player_id]) scoreMap[g.player_id] = [];
			if (!scoreRichMap[g.player_id]) scoreRichMap[g.player_id] = [];
			scoreMap[g.player_id].push(Number(g.score));

			const { cal_week, league_id } = g.game_plans ?? {};
			const meta = matchLookup[`${cal_week}_${league_id}`];
			scoreRichMap[g.player_id].push({
				score:     Number(g.score),
				date:      meta?.date ?? null,
				opponent:  meta?.opponent ?? null,
				home_away: meta?.home_away ?? null,
				round:     meta?.round ?? null,
			});
		}

		// Vereinsschnitt pro Match-Runde (z.B. F01, H03)
		const roundMap = {};
		for (const g of allScores ?? []) {
			const { cal_week, league_id } = g.game_plans ?? {};
			if (cal_week == null || league_id == null) continue;
			const meta = matchLookup[`${cal_week}_${league_id}`];
			if (!meta?.round) continue;
			if (!roundMap[meta.round]) roundMap[meta.round] = [];
			roundMap[meta.round].push(Number(g.score));
		}
		clubAvgSeries = Object.entries(roundMap)
			.map(([round, scores]) => ({
				round,
				avg:   Math.round(scores.reduce((a, b) => a + b, 0) / scores.length),
				count: scores.length,
			}))
			// F01 < F02 < H01 < H02 … funktioniert lexikografisch
			.sort((a, b) => a.round.localeCompare(b.round))
			.slice(-6); // letzte 6 Runden

		// ── Saison-KPIs (Verein) ──────────────────────────────
		// Saison-Logik: aktuelle Saison-Hälfte (H = Herbst-/Vorrunde, F = Frühjahr-/Rückrunde)
		// Vergleichshälfte: andere Hälfte derselben Saison (oder vorherige Hälfte falls nichts vorhanden).
		const allRoundScores = Object.entries(roundMap); // [round, scores[]]
		const hRounds = allRoundScores.filter(([r]) => r.startsWith('H'));
		const fRounds = allRoundScores.filter(([r]) => r.startsWith('F'));

		function avgOf(roundList) {
			const flat = roundList.flatMap(([, sc]) => sc);
			return flat.length ? Math.round(flat.reduce((a, b) => a + b, 0) / flat.length) : null;
		}

		const hAvg = avgOf(hRounds);
		const fAvg = avgOf(fRounds);

		// Welche Hälfte ist "aktuell"? → richtet sich nach dem Kalendermonat:
		// Sep–Dez (Monat ≥ 8) = Vorrunde (H), Jan–Mai = Rückrunde (F).
		// Falls die "aktuelle" Hälfte keine Daten hat, fallback auf die andere.
		const hasH = hRounds.length > 0;
		const hasF = fRounds.length > 0;
		const monthNow = new Date().getMonth(); // 0=Jan
		const seasonIsF = monthNow < 8;          // Jan-Aug → F, Sep-Dez → H
		const currentIsF = seasonIsF ? (hasF || !hasH) : (hasH ? false : true);
		const clubAvg     = currentIsF ? fAvg : hAvg;
		const clubAvgPrev = currentIsF ? hAvg : fAvg;

		// Heim/Auswärts-Schnitt (Verein, alle Liga-Spiele dieser Saison-Hälfte falls möglich;
		// fallback: über alles)
		let homeScores = [];
		let awayScores = [];
		for (const g of allScores ?? []) {
			const { cal_week, league_id } = g.game_plans ?? {};
			const meta = matchLookup[`${cal_week}_${league_id}`];
			if (!meta) continue;
			// Nur aktuelle Saison-Hälfte falls beide Hälften existieren
			if (hasH && hasF) {
				const isF = meta.round?.startsWith('F');
				if (currentIsF && !isF) continue;
				if (!currentIsF && isF) continue;
			}
			if (meta.home_away === 'HEIM') homeScores.push(Number(g.score));
			else if (meta.home_away)        awayScores.push(Number(g.score));
		}
		const homeAvg = homeScores.length
			? Math.round(homeScores.reduce((a, b) => a + b, 0) / homeScores.length)
			: null;
		const awayAvg = awayScores.length
			? Math.round(awayScores.reduce((a, b) => a + b, 0) / awayScores.length)
			: null;

		// Spieler mit Stats aufbauen
		const withStats = playerData
			.map(p => {
				const scores  = scoreMap[p.id] ?? [];
				const rich    = scoreRichMap[p.id] ?? [];
				const avg     = scores.length
					? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length)
					: null;
				const avg5    = scores.slice(0, 5).length
					? Math.round(scores.slice(0, 5).reduce((a, b) => a + b, 0) / scores.slice(0, 5).length)
					: null;
				const best    = scores.length ? Math.max(...scores) : null;

				// Heim/Auswärts pro Spieler
				const myHome = rich.filter(r => r.home_away === 'HEIM').map(r => r.score);
				const myAway = rich.filter(r => r.home_away && r.home_away !== 'HEIM').map(r => r.score);
				const homeAvgP = myHome.length ? Math.round(myHome.reduce((a, b) => a + b, 0) / myHome.length) : null;
				const awayAvgP = myAway.length ? Math.round(myAway.reduce((a, b) => a + b, 0) / myAway.length) : null;

				// H vs. F Trend (eigene Schnitte je Hälfte)
				const myH = rich.filter(r => r.round?.startsWith('H')).map(r => r.score);
				const myF = rich.filter(r => r.round?.startsWith('F')).map(r => r.score);
				const hAvgP = myH.length ? Math.round(myH.reduce((a, b) => a + b, 0) / myH.length) : null;
				const fAvgP = myF.length ? Math.round(myF.reduce((a, b) => a + b, 0) / myF.length) : null;

				return {
					...p,
					scores,
					richScores:  rich,         // [{ score, date, opponent, home_away, round }]
					avg, avg5, best,
					gamesPlayed: scores.length,
					homeAvg:     homeAvgP,
					awayAvg:     awayAvgP,
					avgH:        hAvgP,
					avgF:        fAvgP,
				};
			})
			.filter(p => p.gamesPlayed > 0)
			.sort((a, b) => (b.avg ?? 0) - (a.avg ?? 0));

		players = withStats;

		// Eigenen Spieler finden
		const pid = $playerId;
		let myAvg     = null;
		let myAvgPrev = null;
		if (pid) {
			const me = withStats.find(p => p.id === pid);
			if (me) {
				myStats  = { ...me, rank: withStats.indexOf(me) + 1 };
				myScores = [...me.scores.slice(0, 6)].reverse(); // älteste zuerst
				// Mein Schnitt aktuelle/vorige Hälfte
				myAvg     = currentIsF ? me.avgF : me.avgH;
				myAvgPrev = currentIsF ? me.avgH : me.avgF;
				// Falls keine "aktuelle Hälfte"-Daten: Fallback auf Gesamt-Schnitt
				if (myAvg == null) myAvg = me.avg;
			}
		}

		seasonStats = {
			clubAvg,
			clubAvgPrev,
			homeAvg,
			awayAvg,
			myAvg,
			myAvgPrev,
			currentLabel: currentIsF ? 'Rückrunde' : 'Vorrunde',
			prevLabel:    currentIsF ? 'Vorrunde'  : 'Rückrunde',
		};

		loading = false;
	});

	// ── SVG-Chart-Helfer ───────────────────────────────────
	const W = 600, H = 200, PAD = 30;

	function chartPoints(scores) {
		if (scores.length < 2) return [];
		const min = Math.min(...scores) - PAD;
		const max = Math.max(...scores) + PAD;
		const range = max - min || 1;
		return scores.map((s, i) => ({
			x: (i / (scores.length - 1)) * W,
			y: H - ((s - min) / range) * H,
			score: s,
		}));
	}

	function linePath(pts) {
		return pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ');
	}

	function areaPath(pts) {
		if (!pts.length) return '';
		return linePath(pts) + ` L ${W} ${H} L 0 ${H} Z`;
	}

	// ── Trend-Pfeil ────────────────────────────────────────
	function trend(p) {
		if (!p.avg5 || !p.avg) return 0;
		return p.avg5 - p.avg;
	}

	// ── Achievements ───────────────────────────────────────
	function achievements(me) {
		if (!me) return [];
		const list = [];
		if (me.rank === 1) list.push({ icon: 'emoji_events', text: 'Vereinsmeister – Platz #1' });
		else if (me.rank <= 3) list.push({ icon: 'military_tech', text: `Top 3 im Vereinsranking (Platz #${me.rank})` });
		if (me.best && me.avg && me.best >= me.avg + 30) list.push({ icon: 'workspace_premium', text: `Persönlicher Bahnrekord: ${me.best} Holz` });
		if (me.avg5 && me.avg && me.avg5 > me.avg + 10) list.push({ icon: 'trending_up', text: 'Formkurve zeigt deutlich nach oben' });
		if (me.gamesPlayed >= 20) list.push({ icon: 'verified', text: `Erfahren: ${me.gamesPlayed} Spiele absolviert` });
		if (!list.length && me.gamesPlayed > 0) list.push({ icon: 'sports_score', text: `${me.gamesPlayed} Spiele – weiter so!` });
		return list;
	}

	// Spieler-Rang-Farbe
	function rankColor(i) {
		if (i === 0) return 'rank-gold';
		if (i === 1) return 'rank-silver';
		if (i === 2) return 'rank-bronze';
		return '';
	}

	// ── Player detail sheet ──────────────────────────────────
	let detailOpen   = $state(false);
	let detailPlayer = $state(null);

	function openDetail(p) {
		detailPlayer = p;
		detailOpen = true;
	}

	function playerActions(p, rank) {
		return [
			{
				label: 'Details anzeigen',
				icon:  'person',
				fn:    () => openDetail({ ...p, rank: rank + 1 }),
			},
			{
				label: 'Stats teilen',
				icon:  'share',
				fn:    async () => {
					const text = `${p.name} – Schnitt: ${p.avg} Holz | Bestleistung: ${p.best ?? '–'} | Rang #${rank + 1}`;
					if (navigator.share) {
						try { await navigator.share({ title: p.name, text }); } catch {}
					} else {
						await navigator.clipboard.writeText(text);
						triggerToast(`Stats von ${p.name} kopiert`);
					}
				},
			},
		];
	}

	// Δ-Helper für KPI-Cards
	function delta(curr, prev) {
		if (curr == null || prev == null) return null;
		return curr - prev;
	}
</script>

<div class="stats-wrap">

	<!-- ── Hero-Header ─────────────────────────────────── -->
	<div class="stats-hero">
		<span class="stats-eyebrow">Statistiken</span>
		<h1 class="stats-headline">PERFORMANCE<br/>INSIGHTS</h1>

		{#if myStats}
		<div class="hero-chips">
			<div class="hero-chip hero-chip--primary">
				<span class="hero-chip-label">Mein Schnitt</span>
				<span class="hero-chip-value">{myStats.avg}</span>
			</div>
			<div class="hero-chip">
				<span class="hero-chip-label">Rang</span>
				<span class="hero-chip-value">#{myStats.rank}</span>
			</div>
		</div>
		{/if}
	</div>

	{#if loading}
		<!-- Saison-KPI skeleton -->
		<div class="skel-kpi-row">
			{#each [0,1,2] as _}
				<div class="skel-kpi-card shimmer-box"></div>
			{/each}
		</div>

		<!-- Formkurve card skeleton -->
		<div class="skel-chart-card">
			<div class="skel-chart-title shimmer-box"></div>
			<div class="skel-chart-sub shimmer-box"></div>
			<div class="skel-chart-area shimmer-box"></div>
		</div>

		<!-- Schnell-Stats skeleton -->
		<div class="skel-quick-stats">
			{#each [0,1,2] as _}
				<div class="skel-quick-cell">
					<div class="skel-qs-icon shimmer-box"></div>
					<div class="skel-qs-label shimmer-box"></div>
					<div class="skel-qs-value shimmer-box"></div>
				</div>
			{/each}
		</div>

		<!-- Vereinsranking skeleton -->
		<div class="skel-ranking-card">
			<div class="skel-ranking-header">
				<div class="skel-ranking-htitle shimmer-box"></div>
			</div>
			{#each [0,1,2,3,4] as _}
				<div class="skel-ranking-row">
					<div class="skel-rank-num shimmer-box"></div>
					<div class="skel-row-avatar shimmer-box"></div>
					<div class="skel-row-info">
						<div class="skel-row-name shimmer-box"></div>
						<div class="skel-row-avg shimmer-box"></div>
					</div>
				</div>
			{/each}
		</div>

	{:else}

		<!-- ── Saison-KPI-Block ─────────────────────────── -->
		{#if seasonStats}
			{@const clubDelta = delta(seasonStats.clubAvg, seasonStats.clubAvgPrev)}
			{@const myDelta   = delta(seasonStats.myAvg,   seasonStats.myAvgPrev)}
			{@const haHome    = seasonStats.homeAvg}
			{@const haAway    = seasonStats.awayAvg}
			{@const haHomeLeads = haHome != null && haAway != null && haHome > haAway}
			{@const haAwayLeads = haHome != null && haAway != null && haAway > haHome}
			<div class="kpi-row" role="list" aria-label="Saison-Übersicht">
				<!-- Liga-Schnitt Verein -->
				<div class="kpi-card mw-card" role="listitem">
					<span class="kpi-label">Verein · {seasonStats.currentLabel}</span>
					<div class="kpi-value-row">
						<span class="kpi-value">{seasonStats.clubAvg ?? '–'}</span>
						{#if clubDelta != null}
							<span class="kpi-delta" class:kpi-delta--up={clubDelta > 0} class:kpi-delta--down={clubDelta < 0}>
								<span class="material-symbols-outlined">
									{clubDelta > 0 ? 'arrow_upward' : clubDelta < 0 ? 'arrow_downward' : 'remove'}
								</span>
								{clubDelta > 0 ? '+' : ''}{clubDelta}
							</span>
						{/if}
					</div>
					<span class="kpi-sub">vs. {seasonStats.prevLabel} {seasonStats.clubAvgPrev ?? '–'}</span>
				</div>

				<!-- Heim vs. Auswärts -->
				<div class="kpi-card mw-card kpi-card--split" role="listitem">
					<span class="kpi-label">Heim vs. Auswärts</span>
					<div class="kpi-split-row">
						<div class="kpi-split-cell" class:kpi-split-cell--lead={haHomeLeads}>
							<span class="material-symbols-outlined kpi-split-icon">home</span>
							<span class="kpi-split-value">{haHome ?? '–'}</span>
							<span class="kpi-split-cap">Heim</span>
						</div>
						<div class="kpi-split-divider" aria-hidden="true">
							{#if haHome != null && haAway != null}
								<span class="material-symbols-outlined">
									{haHomeLeads ? 'chevron_left' : haAwayLeads ? 'chevron_right' : 'drag_handle'}
								</span>
							{/if}
						</div>
						<div class="kpi-split-cell" class:kpi-split-cell--lead={haAwayLeads}>
							<span class="material-symbols-outlined kpi-split-icon">directions_car</span>
							<span class="kpi-split-value">{haAway ?? '–'}</span>
							<span class="kpi-split-cap">Auswärts</span>
						</div>
					</div>
				</div>

				<!-- Mein Saison-Schnitt -->
				<div class="kpi-card mw-card kpi-card--me" role="listitem">
					<span class="kpi-label">Mein Schnitt · {seasonStats.currentLabel}</span>
					<div class="kpi-value-row">
						<span class="kpi-value">{seasonStats.myAvg ?? '–'}</span>
						{#if myDelta != null}
							<span class="kpi-delta" class:kpi-delta--up={myDelta > 0} class:kpi-delta--down={myDelta < 0}>
								<span class="material-symbols-outlined">
									{myDelta > 0 ? 'arrow_upward' : myDelta < 0 ? 'arrow_downward' : 'remove'}
								</span>
								{myDelta > 0 ? '+' : ''}{myDelta}
							</span>
						{/if}
					</div>
					<span class="kpi-sub">
						{#if seasonStats.myAvgPrev != null}
							vs. {seasonStats.prevLabel} {seasonStats.myAvgPrev}
						{:else}
							noch keine Vergleichswerte
						{/if}
					</span>
				</div>
			</div>
		{/if}

		<!-- ── Formkurve ──────────────────────────────────── -->
		{#if myScores.length >= 2}
		{@const pts = chartPoints(myScores)}
		<div class="stat-card">
			<div class="stat-card-header">
				<div>
					<h2 class="stat-card-title">Formkurve</h2>
					<p class="stat-card-sub">Letzte {myScores.length} Punktspiele · Gesamtholz</p>
				</div>
				<div class="chart-legend">
					<span class="legend-dot legend-dot--primary"></span>
					<span class="legend-label">Meine Ergebnisse</span>
				</div>
			</div>

			<!-- SVG-Chart -->
			<div class="chart-wrap">
				<svg viewBox="0 0 {W} {H}" preserveAspectRatio="none" class="chart-svg chart-svg--primary">
					<defs>
						<linearGradient id="chartGrad" x1="0%" y1="0%" x2="0%" y2="100%">
							<stop offset="0%" class="chart-grad-start"/>
							<stop offset="100%" class="chart-grad-end"/>
						</linearGradient>
					</defs>
					<path d={areaPath(pts)} fill="url(#chartGrad)" />
					<path class="chart-line" d={linePath(pts)} fill="none" stroke-width="4"
						stroke-linecap="round" stroke-linejoin="round"/>
					{#each pts as pt, i}
						<circle
							class={i === pts.length - 1 ? 'chart-dot chart-dot--last' : 'chart-dot'}
							cx={pt.x} cy={pt.y} r={i === pts.length - 1 ? 7 : 4}
							stroke-width="2.5"
						/>
					{/each}
				</svg>
			</div>

			<div class="chart-axis">
				{#each myScores as s, i}
					<span class:axis-active={i === myScores.length - 1}>
						{myScores.length > 1 ? `S${i + 1}` : ''}
					</span>
				{/each}
			</div>

			<div class="chart-scores">
				{#each myScores as s, i}
					<span class:score-active={i === myScores.length - 1}>{s}</span>
				{/each}
			</div>
		</div>
		{/if}

		<!-- ── Vereinsschnitt pro Runde ─────────────────────── -->
		{#if clubAvgSeries.length >= 2}
		{@const clubScores = clubAvgSeries.map(w => w.avg)}
		{@const cPts = chartPoints(clubScores)}
		{@const overallClubAvg = Math.round(clubScores.reduce((a,b)=>a+b,0)/clubScores.length)}
		<div class="stat-card">
			<div class="stat-card-header">
				<div>
					<h2 class="stat-card-title">Vereinsschnitt</h2>
					<p class="stat-card-sub">
						Ø aller Spieler · letzte {clubAvgSeries.length} Runden
						({clubAvgSeries[0].round}–{clubAvgSeries.at(-1).round})
					</p>
				</div>
				<div class="club-avg-badge">
					<span class="club-avg-num">{overallClubAvg}</span>
					<span class="club-avg-label">Ø Verein</span>
				</div>
			</div>

			<!-- SVG Chart -->
			<div class="chart-wrap">
				<svg viewBox="0 0 {W} {H}" preserveAspectRatio="none" class="chart-svg chart-svg--club">
					<defs>
						<linearGradient id="clubGrad" x1="0%" y1="0%" x2="0%" y2="100%">
							<stop offset="0%"   class="club-grad-start"/>
							<stop offset="100%" class="club-grad-end"/>
						</linearGradient>
					</defs>
					<path d={areaPath(cPts)} fill="url(#clubGrad)" />
					<path class="chart-line" d={linePath(cPts)} fill="none" stroke-width="4"
						stroke-linecap="round" stroke-linejoin="round"/>
					{#each cPts as pt, i}
						<circle
							class={i === cPts.length - 1 ? 'chart-dot chart-dot--last' : 'chart-dot'}
							cx={pt.x} cy={pt.y} r={i === cPts.length - 1 ? 7 : 4}
							stroke-width="2.5"
						/>
					{/each}
				</svg>
			</div>

			<!-- X-Achse: Rundenbezeichnungen (z.B. F01, H03) -->
			<div class="chart-axis chart-axis--club">
				{#each clubAvgSeries as w, i}
					<span class:axis-active--club={i === clubAvgSeries.length - 1}>{w.round}</span>
				{/each}
			</div>

			<!-- Schnitt-Werte -->
			<div class="chart-scores chart-scores--club">
				{#each clubAvgSeries as w, i}
					<span class:score-active--club={i === clubAvgSeries.length - 1}>{w.avg}</span>
				{/each}
			</div>

			<!-- Ergebnisanzahl pro Runde -->
			<div class="club-round-row">
				{#each clubAvgSeries as w}
					<span class="club-round-count">{w.count}×</span>
				{/each}
			</div>
		</div>
		{/if}

		<!-- ── Schnell-Stats ──────────────────────────────── -->
		{#if myStats}
		<div class="quick-stats">
			<div class="quick-stat">
				<span class="material-symbols-outlined qs-icon">sports_score</span>
				<div>
					<p class="qs-label">Beste Partie</p>
					<p class="qs-value">{myStats.best ?? '–'} Holz</p>
				</div>
			</div>
			<div class="quick-stat">
				<span class="material-symbols-outlined qs-icon">calendar_month</span>
				<div>
					<p class="qs-label">Spiele gesamt</p>
					<p class="qs-value">{myStats.gamesPlayed}</p>
				</div>
			</div>
			<div class="quick-stat">
				<span class="material-symbols-outlined qs-icon">trending_up</span>
				<div>
					<p class="qs-label">Ø letzte 5</p>
					<p class="qs-value">
						{myStats.avg5 ?? '–'}
						{#if myStats.avg5 && myStats.avg}
							{#if myStats.avg5 > myStats.avg}
								<span class="trend-up">▲{myStats.avg5 - myStats.avg}</span>
							{:else if myStats.avg5 < myStats.avg}
								<span class="trend-down">▼{myStats.avg - myStats.avg5}</span>
							{/if}
						{/if}
					</p>
				</div>
			</div>
		</div>
		{/if}

		<!-- ── Vereinsranking ─────────────────────────────── -->
		<div class="stat-card stat-card--flush">
			<div class="stat-card-header stat-card-header--padded">
				<h2 class="stat-card-title">Vereinsranking</h2>
				<span class="material-symbols-outlined" style="color: var(--color-secondary);">emoji_events</span>
			</div>

			<div class="ranking-list">
				{#each players as p, i (p.id)}
					{@const isMe = myStats?.id === p.id}
					<ContextMenu actions={playerActions(p, i)}>
						<div class="ranking-row" class:ranking-row--me={isMe} onclick={() => openDetail({ ...p, rank: i + 1 })} onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openDetail({ ...p, rank: i + 1 }); } }} role="button" tabindex="0" aria-label={`${p.name}, Rang ${i + 1}, Schnitt ${p.avg} Holz. Antippen für Details.`}>
							<span class="rank-num {rankColor(i)}">{i + 1}</span>

							<div class="ranking-avatar">
								{#if imgPath(p.photo, p.name)}
									<img src={imgPath(p.photo, p.name)} alt={p.name}
										onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}/>
								{:else}
									<span class="avatar-fallback">{shortName(p.name)}</span>
								{/if}
							</div>

							<div class="ranking-info">
								<span class="ranking-name">{p.name}{isMe ? ' (Ich)' : ''}</span>
								<span class="ranking-avg">Ø {p.avg} Holz</span>
							</div>

							{#if trend(p) > 5}
								<span class="material-symbols-outlined trend-icon trend-icon--up">trending_up</span>
							{:else if trend(p) < -5}
								<span class="material-symbols-outlined trend-icon trend-icon--down">trending_down</span>
							{:else if p.gamesPlayed > 0}
								<span class="material-symbols-outlined trend-icon trend-icon--flat">trending_flat</span>
							{/if}
						</div>
					</ContextMenu>
				{/each}

				{#if !players.length}
					<p class="ranking-empty">Noch keine Ergebnisse vorhanden.</p>
				{/if}
			</div>
		</div>

		<!-- ── Letzte Erfolge ─────────────────────────────── -->
		{#if myStats && achievements(myStats).length}
		<div class="stat-card achievements-card">
			<h3 class="achievements-title">Meine Erfolge</h3>
			<div class="achievements-list">
				{#each achievements(myStats) as a}
					<div class="achievement-row">
						<span class="material-symbols-outlined achievement-icon">{a.icon}</span>
						<span class="achievement-text">{a.text}</span>
					</div>
				{/each}
			</div>
		</div>
		{/if}

	{/if}
</div>

<!-- Player detail sheet -->
{#if detailPlayer}
	<BottomSheet bind:open={detailOpen} title={detailPlayer.name}>
		<div class="pds-hero">
			<div class="pds-avatar">
				{#if imgPath(detailPlayer.photo, detailPlayer.name)}
					<img src={imgPath(detailPlayer.photo, detailPlayer.name)} alt={detailPlayer.name}
						onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}/>
				{/if}
				<span class="pds-initial">{shortName(detailPlayer.name)}</span>
			</div>
			<div>
				<h3 class="pds-name">{detailPlayer.name}</h3>
				<p class="pds-rank">Rang #{detailPlayer.rank} im Vereinsranking</p>
			</div>
		</div>

		<!-- Schnitt / Letzte 5 / Best / Spiele -->
		<div class="pds-stats">
			<div class="pds-stat">
				<span class="pds-stat-value">{detailPlayer.avg ?? '–'}</span>
				<span class="pds-stat-label">Ø Gesamt</span>
			</div>
			<div class="pds-stat">
				<span class="pds-stat-value">{detailPlayer.avg5 ?? '–'}</span>
				<span class="pds-stat-label">Ø letzte 5</span>
			</div>
			<div class="pds-stat">
				<span class="pds-stat-value">{detailPlayer.best ?? '–'}</span>
				<span class="pds-stat-label">Bestleistung</span>
			</div>
			<div class="pds-stat">
				<span class="pds-stat-value">{detailPlayer.gamesPlayed}</span>
				<span class="pds-stat-label">Spiele</span>
			</div>
		</div>

		<!-- Heim vs. Auswärts (Spieler) -->
		{#if detailPlayer.homeAvg != null || detailPlayer.awayAvg != null}
			{@const pHome = detailPlayer.homeAvg}
			{@const pAway = detailPlayer.awayAvg}
			{@const pHomeLeads = pHome != null && pAway != null && pHome > pAway}
			{@const pAwayLeads = pHome != null && pAway != null && pAway > pHome}
			<p class="pds-section">Heim vs. Auswärts</p>
			<div class="pds-split">
				<div class="pds-split-cell" class:pds-split-cell--lead={pHomeLeads}>
					<span class="material-symbols-outlined pds-split-icon">home</span>
					<span class="pds-split-value">{pHome ?? '–'}</span>
					<span class="pds-split-cap">Heim</span>
				</div>
				<div class="pds-split-cell" class:pds-split-cell--lead={pAwayLeads}>
					<span class="material-symbols-outlined pds-split-icon">directions_car</span>
					<span class="pds-split-value">{pAway ?? '–'}</span>
					<span class="pds-split-cap">Auswärts</span>
				</div>
			</div>
		{/if}

		<!-- Trend H vs. F -->
		{#if detailPlayer.avgH != null && detailPlayer.avgF != null}
			{@const dHF = detailPlayer.avgF - detailPlayer.avgH}
			<p class="pds-section">Vor- vs. Rückrunde</p>
			<div class="pds-trend-row">
				<div class="pds-trend-cell">
					<span class="pds-trend-cap">Vorrunde</span>
					<span class="pds-trend-value">{detailPlayer.avgH}</span>
				</div>
				<span
					class="pds-trend-arrow"
					class:pds-trend-arrow--up={dHF > 0}
					class:pds-trend-arrow--down={dHF < 0}
				>
					<span class="material-symbols-outlined">
						{dHF > 0 ? 'arrow_forward' : dHF < 0 ? 'arrow_backward' : 'drag_handle'}
					</span>
					{dHF > 0 ? '+' : ''}{dHF}
				</span>
				<div class="pds-trend-cell">
					<span class="pds-trend-cap">Rückrunde</span>
					<span class="pds-trend-value">{detailPlayer.avgF}</span>
				</div>
			</div>
		{/if}

		<!-- Letzte 6 Ergebnisse mit Datum + Gegner -->
		{#if detailPlayer.richScores?.length}
			<p class="pds-section">Letzte Ergebnisse</p>
			<ul class="pds-recent" role="list">
				{#each detailPlayer.richScores.slice(0, 6) as r, i (i)}
					<li class="pds-recent-row" class:pds-recent-row--latest={i === 0} role="listitem">
						<div class="pds-recent-meta">
							<span class="pds-recent-date">{r.date ? fmtDate(r.date) : '–'}</span>
							<span class="pds-recent-opp">
								{#if r.opponent}
									{r.home_away === 'HEIM' ? 'vs. ' : r.home_away ? 'bei ' : ''}{r.opponent}
								{:else}
									–
								{/if}
							</span>
						</div>
						<span class="pds-recent-score">{r.score}</span>
					</li>
				{/each}
			</ul>
		{/if}
	</BottomSheet>
{/if}

<style>
.stats-wrap {
	display: flex;
	flex-direction: column;
	gap: var(--space-5);
	padding: var(--space-5);
}

/* ── Hero-Header ────────────────────────────────────────── */
.stats-hero { display: flex; flex-direction: column; gap: var(--space-2); }

.stats-eyebrow {
	font-family: var(--font-body);
	font-size: var(--text-label-md);
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.12em;
	color: var(--color-secondary);
}

.stats-headline {
	font-family: var(--font-display);
	font-size: clamp(2rem, 10vw, 3rem);
	font-weight: 900;
	line-height: 1.0;
	letter-spacing: -0.02em;
	color: var(--color-on-surface);
}

.hero-chips { display: flex; gap: var(--space-3); margin-top: var(--space-2); }

.hero-chip {
	flex: 1;
	background: var(--color-surface-container-lowest);
	border-radius: var(--radius-lg);
	padding: var(--space-4);
	box-shadow: var(--shadow-card);
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.hero-chip--primary { background: var(--gradient-primary); }

.hero-chip-label {
	font-size: var(--text-label-sm);
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-on-surface-variant);
}
.hero-chip--primary .hero-chip-label { color: rgba(255,255,255,0.75); }

.hero-chip-value {
	font-family: var(--font-display);
	font-size: 1.75rem;
	font-weight: 900;
	color: var(--color-on-surface);
	line-height: 1.1;
}
.hero-chip--primary .hero-chip-value { color: #fff; }

/* ── Saison-KPI-Block ─────────────────────────────────── */
.kpi-row {
	display: grid;
	grid-template-columns: repeat(3, minmax(0, 1fr));
	gap: var(--space-3);
}
@media (max-width: 600px) {
	.kpi-row {
		display: flex;
		gap: var(--space-3);
		overflow-x: auto;
		scroll-snap-type: x mandatory;
		padding-bottom: var(--space-1);
		scrollbar-width: none;
		-webkit-overflow-scrolling: touch;
	}
	.kpi-row::-webkit-scrollbar { display: none; }
	.kpi-card {
		flex: 0 0 78%;
		scroll-snap-align: start;
	}
}
.kpi-card {
	/* Override mw-card margin so it works inside grid/flex container */
	margin: 0;
	padding: var(--space-3) var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-1);
	min-height: 88px;
}
.kpi-card--me {
	border-left: 3px solid var(--color-primary);
}
.kpi-card--split {
	gap: var(--space-2);
}
.kpi-label {
	font-family: var(--font-body);
	font-size: var(--text-label-sm);
	font-weight: 700;
	letter-spacing: 0.06em;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}
.kpi-value-row {
	display: flex;
	align-items: baseline;
	gap: var(--space-2);
}
.kpi-value {
	font-family: var(--font-display);
	font-size: 1.6rem;
	font-weight: 900;
	color: var(--color-on-surface);
	font-variant-numeric: tabular-nums;
	line-height: 1;
}
.kpi-delta {
	display: inline-flex;
	align-items: center;
	gap: 2px;
	font-family: var(--font-display);
	font-size: var(--text-label-md);
	font-weight: 800;
	color: var(--color-on-surface-variant);
}
.kpi-delta .material-symbols-outlined {
	font-size: 0.95rem;
	font-variation-settings: 'FILL' 1, 'wght' 700, 'GRAD' 0, 'opsz' 20;
}
.kpi-delta--up   { color: var(--color-success); }
.kpi-delta--down { color: var(--color-primary); }
.kpi-sub {
	font-family: var(--font-body);
	font-size: var(--text-label-sm);
	font-weight: 600;
	color: var(--color-on-surface-variant);
}

.kpi-split-row {
	display: grid;
	grid-template-columns: 1fr auto 1fr;
	gap: var(--space-1);
	align-items: center;
}
.kpi-split-cell {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 2px;
	padding: var(--space-1) 0;
	border-radius: var(--radius-sm);
	transition: background 150ms ease;
}
.kpi-split-cell--lead {
	background: color-mix(in srgb, var(--color-primary) 6%, transparent);
}
.kpi-split-icon {
	font-size: 1rem;
	color: var(--color-on-surface-variant);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}
.kpi-split-cell--lead .kpi-split-icon { color: var(--color-primary); }
.kpi-split-value {
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 900;
	color: var(--color-on-surface);
	font-variant-numeric: tabular-nums;
	line-height: 1;
}
.kpi-split-cell--lead .kpi-split-value { color: var(--color-primary); }
.kpi-split-cap {
	font-family: var(--font-body);
	font-size: 0.62rem;
	font-weight: 800;
	letter-spacing: 0.08em;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}
.kpi-split-divider {
	display: flex;
	align-items: center;
	justify-content: center;
	color: var(--color-outline);
}
.kpi-split-divider .material-symbols-outlined {
	font-size: 1.1rem;
}

/* ── Loading-Skeletons ──────────────────────────────────── */
.skel-kpi-row { display: flex; gap: var(--space-3); }
.skel-kpi-card {
	flex: 1;
	height: 88px;
	border-radius: var(--radius-lg);
}

/* ── Karte ──────────────────────────────────────────────── */
.stat-card {
	background: var(--color-surface-container-lowest);
	border-radius: var(--radius-xl);
	box-shadow: var(--shadow-card);
	overflow: hidden;
	padding: var(--space-5);
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
}
.stat-card--flush { padding: 0; }
.stat-card-header { display: flex; justify-content: space-between; align-items: flex-start; gap: var(--space-3); }
.stat-card-header--padded { padding: var(--space-5) var(--space-5) var(--space-3); }
.stat-card-title { font-family: var(--font-display); font-size: var(--text-title-md); font-weight: 800; letter-spacing: -0.01em; color: var(--color-on-surface); }
.stat-card-sub { font-size: var(--text-label-md); color: var(--color-on-surface-variant); margin-top: 2px; }

/* ── Chart-Legende ── */
.chart-legend { display: flex; align-items: center; gap: var(--space-2); flex-shrink: 0; }
.legend-dot { width: 8px; height: 8px; border-radius: var(--radius-full); background: var(--color-surface-container-highest); }
.legend-dot--primary { background: var(--color-primary); }
.legend-dot--club    { background: var(--color-secondary); }
.legend-label { font-size: var(--text-label-sm); font-weight: 700; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.07em; }

/* ── SVG-Chart ── */
.chart-wrap { width: 100%; height: 9rem; }
.chart-svg  { width: 100%; height: 100%; }
/* SVG color tokens (CSS-variables can't be applied via SVG attributes directly) */
.chart-svg--primary .chart-line { stroke: var(--color-primary); }
.chart-svg--primary .chart-dot  { fill: white; stroke: var(--color-primary); }
.chart-svg--primary .chart-dot--last { fill: var(--color-primary); }
.chart-svg--primary .chart-grad-start { stop-color: var(--color-primary); stop-opacity: 0.18; }
.chart-svg--primary .chart-grad-end   { stop-color: var(--color-primary); stop-opacity: 0; }
.chart-svg--club    .chart-line { stroke: var(--color-secondary); }
.chart-svg--club    .chart-dot  { fill: white; stroke: var(--color-secondary); }
.chart-svg--club    .chart-dot--last { fill: var(--color-secondary); }
.chart-svg--club    .club-grad-start { stop-color: var(--color-secondary); stop-opacity: 0.22; }
.chart-svg--club    .club-grad-end   { stop-color: var(--color-secondary); stop-opacity: 0; }
.chart-axis { display: flex; justify-content: space-between; font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: var(--color-on-surface-variant); margin-top: var(--space-2); }
.chart-axis .axis-active { color: var(--color-primary); }
.chart-scores { display: flex; justify-content: space-between; font-family: var(--font-display); font-size: var(--text-label-md); font-weight: 600; color: var(--color-on-surface-variant); margin-top: 2px; }
.chart-scores .score-active { color: var(--color-primary); font-weight: 800; }
.chart-axis--club .axis-active--club   { color: var(--color-secondary); }
.chart-scores--club .score-active--club { color: var(--color-secondary); font-weight: 800; }

/* ── Vereinsschnitt-spezifisch ── */
.club-avg-badge {
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: var(--space-2) var(--space-3);
	background: color-mix(in srgb, var(--color-secondary) 10%, transparent);
	border: 1px solid color-mix(in srgb, var(--color-secondary) 30%, transparent);
	border-radius: var(--radius-md);
	flex-shrink: 0;
}
.club-avg-num {
	font-family: var(--font-display);
	font-size: 1.3rem;
	font-weight: 900;
	color: var(--color-secondary);
	line-height: 1;
}
.club-avg-label {
	font-size: 0.62rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: color-mix(in srgb, var(--color-secondary) 70%, var(--color-on-surface-variant));
	margin-top: 2px;
}

.club-round-row {
	display: flex;
	justify-content: space-between;
	margin-top: 2px;
}
.club-round-count {
	font-size: 0.58rem;
	font-weight: 700;
	color: var(--color-on-surface-variant);
	opacity: 0.5;
	text-align: center;
	flex: 1;
}

/* ── Schnell-Stats ── */
.quick-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); }
.quick-stat { background: var(--color-surface-container-lowest); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: var(--space-4); display: flex; flex-direction: column; gap: var(--space-2); align-items: flex-start; }
.qs-icon { font-size: 1.25rem; color: var(--color-secondary); font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
.qs-label { font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.07em; color: var(--color-on-surface-variant); line-height: 1.2; }
.qs-value { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 900; color: var(--color-on-surface); display: flex; align-items: center; gap: var(--space-1); }
.trend-up   { font-size: var(--text-label-sm); color: var(--color-success); font-weight: 700; }
.trend-down { font-size: var(--text-label-sm); color: var(--color-error); font-weight: 700; }

/* ── Ranking-Liste ── */
.ranking-list { display: flex; flex-direction: column; }
.ranking-row { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-3) var(--space-5); border-top: 1px solid var(--color-surface-container); transition: background 0.15s; min-height: 44px; }
.ranking-row:first-child { border-top: none; }
.ranking-row--me { background: var(--gradient-primary); }
.ranking-row--me .ranking-name,
.ranking-row--me .ranking-avg,
.ranking-row--me .rank-num { color: #fff; }
.ranking-row--me .trend-icon { color: rgba(255,255,255,0.75); }

.rank-num { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 900; width: 1.5rem; text-align: center; flex-shrink: 0; color: var(--color-on-surface-variant); }
.rank-gold   { color: var(--color-secondary); }
.rank-silver { color: var(--color-outline); }
.rank-bronze { color: color-mix(in srgb, var(--color-secondary) 60%, var(--color-on-surface)); }

.ranking-avatar { width: 2.25rem; height: 2.25rem; border-radius: var(--radius-full); overflow: hidden; flex-shrink: 0; background: var(--color-surface-container); display: flex; align-items: center; justify-content: center; }
.ranking-avatar img { width: 100%; height: 100%; object-fit: cover; }
.avatar-fallback { font-family: var(--font-display); font-size: var(--text-label-md); font-weight: 700; color: var(--color-on-surface-variant); }

.ranking-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px; }
.ranking-name { font-family: var(--font-display); font-size: var(--text-body-md); font-weight: 700; color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ranking-avg { font-size: var(--text-label-sm); font-weight: 600; color: var(--color-on-surface-variant); }

.trend-icon { font-size: 1.25rem; flex-shrink: 0; }
.trend-icon--up   { color: var(--color-success); }
.trend-icon--down { color: var(--color-error); }
.trend-icon--flat { color: var(--color-on-surface-variant); }
.ranking-empty { padding: var(--space-6); text-align: center; color: var(--color-on-surface-variant); font-size: var(--text-body-md); }

/* ── Achievements ── */
.achievements-card { border-left: 4px solid var(--color-secondary); }
.achievements-title { font-size: var(--text-label-md); font-weight: 900; text-transform: uppercase; letter-spacing: 0.12em; color: var(--color-secondary); }
.achievements-list { display: flex; flex-direction: column; gap: var(--space-3); }
.achievement-row { display: flex; align-items: center; gap: var(--space-3); }
.achievement-icon { font-size: 1.25rem; color: var(--color-secondary); flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
.achievement-text { font-size: var(--text-body-md); font-weight: 600; color: var(--color-on-surface); }

/* ── Player detail sheet ── */
.ranking-row { cursor: pointer; -webkit-tap-highlight-color: transparent; }
.ranking-row:focus-visible {
	outline: 2px solid var(--color-primary);
	outline-offset: -2px;
}

.pds-hero {
	display: flex; align-items: center; gap: var(--space-3);
	margin-bottom: var(--space-4);
	padding-bottom: var(--space-3);
	border-bottom: 1px solid var(--color-outline-variant);
}
.pds-avatar {
	width: 56px; height: 56px; border-radius: 50%;
	overflow: hidden; background: var(--color-surface-container-highest);
	display: grid; place-items: center; flex-shrink: 0; position: relative;
}
.pds-avatar img { width: 100%; height: 100%; object-fit: cover; position: absolute; inset: 0; }
.pds-initial { font-weight: 800; font-size: 1.2rem; color: var(--color-outline); }
.pds-name { margin: 0; font-family: var(--font-display); font-weight: 700; font-size: var(--text-title-sm); color: var(--color-on-surface); }
.pds-rank { margin: 2px 0 0; font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }

.pds-stats {
	display: grid; grid-template-columns: repeat(4, 1fr);
	gap: var(--space-2); margin-bottom: var(--space-4);
}
.pds-stat {
	display: flex; flex-direction: column; align-items: center;
	padding: var(--space-3) var(--space-2);
	background: var(--color-surface-container);
	border-radius: var(--radius-md);
}
.pds-stat-value {
	font-family: var(--font-display); font-weight: 800;
	font-size: var(--text-title-sm); color: var(--color-primary);
}
.pds-stat-label {
	font-size: 0.65rem; font-weight: 700;
	text-transform: uppercase; letter-spacing: 0.05em;
	color: var(--color-outline); margin-top: 2px; text-align: center;
}

.pds-section {
	font-size: var(--text-label-sm); font-weight: 700;
	letter-spacing: 0.07em; text-transform: uppercase;
	color: var(--color-outline); margin: 0 0 var(--space-2);
}

/* Heim/Auswärts-Split (Spieler) */
.pds-split {
	display: grid;
	grid-template-columns: 1fr 1fr;
	gap: var(--space-2);
	margin-bottom: var(--space-4);
}
.pds-split-cell {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 2px;
	padding: var(--space-3) var(--space-2);
	background: var(--color-surface-container);
	border-radius: var(--radius-md);
	border: 1.5px solid transparent;
}
.pds-split-cell--lead {
	border-color: color-mix(in srgb, var(--color-primary) 35%, transparent);
	background: color-mix(in srgb, var(--color-primary) 6%, var(--color-surface-container));
}
.pds-split-icon {
	font-size: 1.1rem;
	color: var(--color-on-surface-variant);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}
.pds-split-cell--lead .pds-split-icon { color: var(--color-primary); }
.pds-split-value {
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 900;
	color: var(--color-on-surface);
	font-variant-numeric: tabular-nums;
}
.pds-split-cell--lead .pds-split-value { color: var(--color-primary); }
.pds-split-cap {
	font-size: 0.65rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-on-surface-variant);
}

/* Trend H vs. F */
.pds-trend-row {
	display: flex;
	align-items: center;
	gap: var(--space-2);
	padding: var(--space-3) var(--space-3);
	background: var(--color-surface-container);
	border-radius: var(--radius-md);
	margin-bottom: var(--space-4);
}
.pds-trend-cell {
	display: flex;
	flex-direction: column;
	gap: 2px;
	flex: 1;
	min-width: 0;
}
.pds-trend-cap {
	font-family: var(--font-body);
	font-size: 0.65rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	color: var(--color-on-surface-variant);
}
.pds-trend-value {
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 900;
	color: var(--color-on-surface);
	font-variant-numeric: tabular-nums;
}
.pds-trend-arrow {
	display: inline-flex;
	align-items: center;
	gap: 2px;
	font-family: var(--font-display);
	font-size: var(--text-label-md);
	font-weight: 800;
	color: var(--color-on-surface-variant);
}
.pds-trend-arrow .material-symbols-outlined {
	font-size: 1rem;
	font-variation-settings: 'FILL' 1, 'wght' 700, 'GRAD' 0, 'opsz' 20;
}
.pds-trend-arrow--up   { color: var(--color-success); }
.pds-trend-arrow--down { color: var(--color-primary); }

/* Recent results list */
.pds-recent {
	list-style: none;
	margin: 0 0 var(--space-4);
	padding: 0;
	display: flex;
	flex-direction: column;
	gap: var(--space-1);
}
.pds-recent-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-2) var(--space-3);
	background: var(--color-surface-container);
	border-radius: var(--radius-md);
	border: 1.5px solid transparent;
}
.pds-recent-row--latest {
	border-color: color-mix(in srgb, var(--color-primary) 35%, transparent);
	background: color-mix(in srgb, var(--color-primary) 6%, var(--color-surface-container));
}
.pds-recent-meta {
	display: flex;
	flex-direction: column;
	gap: 2px;
	flex: 1;
	min-width: 0;
}
.pds-recent-date {
	font-family: var(--font-body);
	font-size: 0.7rem;
	font-weight: 700;
	letter-spacing: 0.06em;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}
.pds-recent-opp {
	font-family: var(--font-body);
	font-size: var(--text-body-md);
	font-weight: 600;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}
.pds-recent-score {
	font-family: var(--font-display);
	font-size: var(--text-title-sm);
	font-weight: 900;
	color: var(--color-on-surface);
	font-variant-numeric: tabular-nums;
	flex-shrink: 0;
}
.pds-recent-row--latest .pds-recent-score { color: var(--color-primary); }
</style>
