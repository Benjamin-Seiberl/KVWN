<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import ContextMenu from '$lib/components/ContextMenu.svelte';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let loading         = $state(true);
	let players         = $state([]);   // alle Spieler mit Stats, nach Schnitt sortiert
	let myStats         = $state(null); // eingeloggter Spieler
	let myScores        = $state([]);   // letzte 6 Ergebnisse (älteste zuerst, für Chart)
	let clubAvgSeries   = $state([]);   // [{ week, avg, count }] – Vereinsschnitt pro Runde

	// ── Bild-Pfad ──────────────────────────────────────────
	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function initials(name) {
		if (!name) return '?';
		const parts = name.trim().split(' ');
		return parts.length >= 2
			? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
			: name[0].toUpperCase();
	}

	// ── Daten laden ────────────────────────────────────────
	onMount(async () => {
		const { data: playerData } = await sb
			.from('players')
			.select('id, name, photo')
			.eq('active', true)
			.order('name');

		if (!playerData?.length) { loading = false; return; }

		// Scores laden – cal_week + league_id für Runden-Lookup mitladen
		const [{ data: allScores }, { data: matchRounds }] = await Promise.all([
			sb.from('game_plan_players')
				.select('player_id, score, game_plans!inner(cal_week, league_id)')
				.in('player_id', playerData.map(p => p.id))
				.eq('played', true)
				.not('score', 'is', null)
				.order('cal_week', { referencedTable: 'game_plans', ascending: false })
				.limit(1000),
			// Runden-Bezeichnungen aller Ligaspiele (NÖ-Cup ausgeschlossen)
			sb.from('matches')
				.select('cal_week, league_id, round, is_tournament')
				.not('round', 'is', null),
		]);

		// Lookup: `${cal_week}_${league_id}` → round-Bezeichnung
		// Nur reguläre Ligaspiele – Turniere (NÖ-Cup) werden übersprungen
		const roundLookup = {};
		for (const m of matchRounds ?? []) {
			if (m.is_tournament) continue;
			roundLookup[`${m.cal_week}_${m.league_id}`] = m.round;
		}

		// Scores pro Spieler – alle Spiele inkl. NÖ-Cup
		const scoreMap = {};
		for (const g of allScores ?? []) {
			if (!scoreMap[g.player_id]) scoreMap[g.player_id] = [];
			scoreMap[g.player_id].push(Number(g.score));
		}

		// Vereinsschnitt pro Match-Runde (z.B. F01, H03)
		const roundMap = {};
		for (const g of allScores ?? []) {
			const { cal_week, league_id } = g.game_plans ?? {};
			if (cal_week == null || league_id == null) continue;
			const round = roundLookup[`${cal_week}_${league_id}`];
			if (!round) continue;
			if (!roundMap[round]) roundMap[round] = [];
			roundMap[round].push(Number(g.score));
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

		// Spieler mit Stats aufbauen
		const withStats = playerData
			.map(p => {
				const scores = scoreMap[p.id] ?? [];
				const avg  = scores.length
					? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length)
					: null;
				const avg5 = scores.slice(0, 5).length
					? Math.round(scores.slice(0, 5).reduce((a, b) => a + b, 0) / scores.slice(0, 5).length)
					: null;
				const best = scores.length ? Math.max(...scores) : null;
				return { ...p, scores, avg, avg5, best, gamesPlayed: scores.length };
			})
			.filter(p => p.gamesPlayed > 0)
			.sort((a, b) => (b.avg ?? 0) - (a.avg ?? 0));

		players = withStats;

		// Eigenen Spieler finden
		const pid = $playerId;
		if (pid) {
			const me = withStats.find(p => p.id === pid);
			if (me) {
				myStats  = { ...me, rank: withStats.indexOf(me) + 1 };
				myScores = [...me.scores.slice(0, 6)].reverse(); // älteste zuerst
			}
		}

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
		<div class="stats-loading">
			<span class="material-symbols-outlined loading-icon">hourglass_top</span>
			<p>Lade Statistiken…</p>
		</div>

	{:else}

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
				<svg viewBox="0 0 {W} {H}" preserveAspectRatio="none" class="chart-svg">
					<defs>
						<linearGradient id="chartGrad" x1="0%" y1="0%" x2="0%" y2="100%">
							<stop offset="0%" style="stop-color:#CC0000;stop-opacity:0.18"/>
							<stop offset="100%" style="stop-color:#CC0000;stop-opacity:0"/>
						</linearGradient>
					</defs>
					<path d={areaPath(pts)} fill="url(#chartGrad)" />
					<path d={linePath(pts)} fill="none" stroke="#CC0000" stroke-width="4"
						stroke-linecap="round" stroke-linejoin="round"/>
					{#each pts as pt, i}
						<circle
							cx={pt.x} cy={pt.y} r={i === pts.length - 1 ? 7 : 4}
							fill={i === pts.length - 1 ? '#CC0000' : 'white'}
							stroke="#CC0000" stroke-width="2.5"
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
				<svg viewBox="0 0 {W} {H}" preserveAspectRatio="none" class="chart-svg">
					<defs>
						<linearGradient id="clubGrad" x1="0%" y1="0%" x2="0%" y2="100%">
							<stop offset="0%"   style="stop-color:#D4AF37;stop-opacity:0.22"/>
							<stop offset="100%" style="stop-color:#D4AF37;stop-opacity:0"/>
						</linearGradient>
					</defs>
					<path d={areaPath(cPts)} fill="url(#clubGrad)" />
					<path d={linePath(cPts)} fill="none" stroke="#D4AF37" stroke-width="4"
						stroke-linecap="round" stroke-linejoin="round"/>
					{#each cPts as pt, i}
						<circle
							cx={pt.x} cy={pt.y} r={i === cPts.length - 1 ? 7 : 4}
							fill={i === cPts.length - 1 ? '#D4AF37' : 'white'}
							stroke="#D4AF37" stroke-width="2.5"
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
				{#each players as p, i}
					{@const isMe = myStats?.id === p.id}
					<ContextMenu actions={playerActions(p, i)}>
						<div class="ranking-row" class:ranking-row--me={isMe} onclick={() => openDetail({ ...p, rank: i + 1 })} role="button" tabindex="0">
							<span class="rank-num {rankColor(i)}">{i + 1}</span>

							<div class="ranking-avatar">
								{#if imgPath(p.photo, p.name)}
									<img src={imgPath(p.photo, p.name)} alt={p.name}
										onerror={(e) => { e.currentTarget.style.display='none'; e.currentTarget.nextElementSibling.style.display='flex'; }}/>
									<span class="avatar-fallback" style="display:none">{initials(p.name)}</span>
								{:else}
									<span class="avatar-fallback">{initials(p.name)}</span>
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
						onerror={(e) => { e.currentTarget.style.display='none'; }}/>
				{/if}
				<span class="pds-initial">{initials(detailPlayer.name)}</span>
			</div>
			<div>
				<h3 class="pds-name">{detailPlayer.name}</h3>
				<p class="pds-rank">Rang #{detailPlayer.rank} im Vereinsranking</p>
			</div>
		</div>

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

		{#if detailPlayer.scores?.length >= 2}
			<p class="pds-section">Letzte Ergebnisse</p>
			<div class="pds-scores">
				{#each [...detailPlayer.scores].slice(0, 8).reverse() as s, i}
					<div class="pds-score-chip" class:pds-score-chip--latest={i === 0}>
						{s}
					</div>
				{/each}
			</div>
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

/* ── Loading ────────────────────────────────────────────── */
.stats-loading {
	display: flex;
	flex-direction: column;
	align-items: center;
	justify-content: center;
	gap: var(--space-3);
	min-height: 30dvh;
	color: var(--color-outline);
	font-size: var(--text-body-md);
}
.loading-icon { font-size: 2.5rem; animation: spin 1.2s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

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
	background: rgba(212, 175, 55, 0.1);
	border: 1px solid rgba(212, 175, 55, 0.3);
	border-radius: 12px;
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
	color: rgba(212, 175, 55, 0.7);
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
.trend-up   { font-size: var(--text-label-sm); color: #16a34a; font-weight: 700; }
.trend-down { font-size: var(--text-label-sm); color: var(--color-error); font-weight: 700; }

/* ── Ranking-Liste ── */
.ranking-list { display: flex; flex-direction: column; }
.ranking-row { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-3) var(--space-5); border-top: 1px solid var(--color-surface-container); transition: background 0.15s; }
.ranking-row:first-child { border-top: none; }
.ranking-row--me { background: var(--gradient-primary); }
.ranking-row--me .ranking-name,
.ranking-row--me .ranking-avg,
.ranking-row--me .rank-num { color: #fff; }
.ranking-row--me .trend-icon { color: rgba(255,255,255,0.75); }

.rank-num { font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 900; width: 1.5rem; text-align: center; flex-shrink: 0; color: var(--color-on-surface-variant); }
.rank-gold   { color: #D4AF37; }
.rank-silver { color: #8A9299; }
.rank-bronze { color: #C47B35; }

.ranking-avatar { width: 2.25rem; height: 2.25rem; border-radius: var(--radius-full); overflow: hidden; flex-shrink: 0; background: var(--color-surface-container); display: flex; align-items: center; justify-content: center; }
.ranking-avatar img { width: 100%; height: 100%; object-fit: cover; }
.avatar-fallback { font-family: var(--font-display); font-size: var(--text-label-md); font-weight: 700; color: var(--color-on-surface-variant); }

.ranking-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px; }
.ranking-name { font-family: var(--font-display); font-size: var(--text-body-md); font-weight: 700; color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ranking-avg { font-size: var(--text-label-sm); font-weight: 600; color: var(--color-on-surface-variant); }

.trend-icon { font-size: 1.25rem; flex-shrink: 0; }
.trend-icon--up   { color: #16a34a; }
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
	background: var(--color-surface-container-low);
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
.pds-scores {
	display: flex; flex-wrap: wrap; gap: var(--space-2);
	margin-bottom: var(--space-4);
}
.pds-score-chip {
	padding: 6px 14px;
	background: var(--color-surface-container-low);
	border: 1.5px solid var(--color-outline-variant);
	border-radius: var(--radius-full);
	font-weight: 700; font-size: var(--text-body-sm);
	color: var(--color-on-surface);
}
.pds-score-chip--latest {
	background: rgba(204, 0, 0, 0.08);
	border-color: var(--color-primary);
	color: var(--color-primary);
}
</style>
