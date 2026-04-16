<script>
	import { onMount }   from 'svelte';
	import { page }      from '$app/stores';
	import { sb }        from '$lib/supabase';
	import { playerId }  from '$lib/stores/auth';
	import { currentSubtab } from '$lib/stores/subtab.js';
	import StatsView     from '$lib/components/statistiken/StatsView.svelte';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	// ── State ─────────────────────────────────────────────────
	let loading     = $state(true);
	let plans       = $state([]);   // [{ match, players[], playerStats{} }]
	let current     = $state(0);

	let trackEl     = $state(null);
	let wrapperEl   = $state(null);
	let tabsEl      = $state(null);

	const initMatchId = $page.url.searchParams.get('matchId');
	const activeView  = $derived($currentSubtab === 'statistiken' ? 'statistiken' : 'spielbetrieb');

	// ── Hilfsfunktionen ───────────────────────────────────────
	function getWeekRange() {
		const today = new Date();
		const day   = today.getDay();
		const diffToMon = day === 0 ? -6 : 1 - day;
		const mon = new Date(today); mon.setDate(today.getDate() + diffToMon);
		const sun = new Date(mon);   sun.setDate(mon.getDate() + 6);
		const fmt = d => d.getFullYear() + '-' +
			String(d.getMonth() + 1).padStart(2, '0') + '-' +
			String(d.getDate()).padStart(2, '0');
		return { from: fmt(mon), to: fmt(sun) };
	}

	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '. \u2022 ' +
			(m.time ? m.time.substring(0, 5) : '') + ' Uhr';
	}

	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function formTrend(avg5, overallAvg) {
		if (!avg5 || !overallAvg) return null;
		return +(avg5 - overallAvg).toFixed(1);
	}

	// ── Daten laden ───────────────────────────────────────────
	async function loadData() {
		const range = getWeekRange();
		const { data: matches } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, is_tournament, tournament_title, leagues(name)')
			.gte('date', range.from)
			.lte('date', range.to)
			.order('date').order('time');

		if (!matches?.length) { loading = false; return; }

		const loaded = [];
		for (const m of matches) {
			if (!m.cal_week || !m.league_id) continue;
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, game_plan_players(id, position, player_id, player_name, players(name, photo))')
				.eq('cal_week', m.cal_week)
				.eq('league_id', m.league_id)
				.maybeSingle();

			const players = (gp?.game_plan_players ?? [])
				.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));

			loaded.push({ match: m, gamePlanId: gp?.id ?? null, players });
		}

		plans = loaded;

		if (initMatchId) {
			const idx = plans.findIndex(p => p.match.id === initMatchId);
			if (idx >= 0) current = idx;
		}

		// Spieler-Statistiken laden
		const playerIds = [...new Set(
			loaded.flatMap(p => p.players.filter(x => x.player_id).map(x => x.player_id))
		)];

		if (playerIds.length) {
			const { data: recent } = await sb
				.from('game_plan_players')
				.select('player_id, score, game_plans!inner(cal_week)')
				.in('player_id', playerIds)
				.eq('played', true)
				.not('score', 'is', null)
				.order('cal_week', { referencedTable: 'game_plans', ascending: false });

			const scoreMap = {};
			for (const g of recent ?? []) {
				if (!scoreMap[g.player_id]) scoreMap[g.player_id] = [];
				scoreMap[g.player_id].push(Number(g.score));
			}

			for (const plan of plans) {
				const stats = {};
				for (const p of plan.players) {
					if (!p.player_id) continue;
					const scores = scoreMap[p.player_id] ?? [];
					const last5  = scores.slice(0, 5);
					stats[p.player_id] = {
						overallAvg: scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : null,
						avg5:       last5.length  ? Math.round(last5.reduce((a, b) => a + b, 0)  / last5.length)  : null,
					};
				}
				plan.playerStats = stats;
			}
			plans = [...plans];
		}

		loading = false;
	}

	// ── Swipe-Carousel ────────────────────────────────────────
	function carousel(widget) {
		// pressing = pointer is down, direction not yet decided
		// dragging = confirmed horizontal swipe – we own the gesture
		let pressing = false, dragging = false;
		let startX = 0, startY = 0, startOff = 0;
		let lastX = 0, lastT = 0, velocity = 0, currentX = 0;

		const track = () => trackEl;
		const W     = () => widget.offsetWidth;

		function moveTo(x, animate) {
			const t = track();
			if (!t) return;
			currentX = x;
			t.style.transition = animate ? 'transform 0.45s cubic-bezier(0.34, 1.4, 0.64, 1)' : 'none';
			t.style.transform  = `translateX(${x}px)`;
		}

		function snapTo(index) {
			current = Math.max(0, Math.min(plans.length - 1, index));
			moveTo(-current * W(), true);
			tabsEl?.querySelectorAll('.sb-tab')[current]
				?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
		}

		function onDown(e) {
			if (e.pointerType === 'mouse' && e.button !== 0) return;
			pressing = true;
			dragging = false;
			startX   = e.clientX;
			startY   = e.clientY;
			startOff = currentX;
			lastX    = e.clientX;
			lastT    = Date.now();
			velocity = 0;
		}

		function onMove(e) {
			if (!pressing) return;

			const absDx = Math.abs(e.clientX - startX);
			const absDy = Math.abs(e.clientY - startY);

			if (!dragging) {
				// Wait for at least 6 px of movement before deciding
				if (absDx < 6 && absDy < 6) return;

				if (absDy >= absDx) {
					// Vertical dominant → release to browser scroll, stop tracking
					pressing = false;
					return;
				}

				// Horizontal dominant → own this gesture
				dragging = true;
				widget.setPointerCapture(e.pointerId);
				const t = track();
				if (t) t.style.transition = 'none';
			}

			const dx   = e.clientX - startX;
			const minX = -(plans.length - 1) * W();
			const raw  = startOff + dx;
			const x    = raw > 0    ? raw * 0.18
			           : raw < minX ? minX + (raw - minX) * 0.18
			           : raw;
			currentX = x;
			track().style.transform = `translateX(${x}px)`;

			const now = Date.now(), dt = now - lastT;
			if (dt > 0) velocity = (e.clientX - lastX) / dt;
			lastX = e.clientX;
			lastT = now;
		}

		function onUp(e) {
			if (!pressing && !dragging) return;
			const wasDragging = dragging;
			pressing = false;
			dragging = false;

			if (!wasDragging) return; // was a tap, not a swipe

			const dx = e.clientX - startX;
			const w  = W();
			let next = current;
			if      (dx < -(w * 0.18) || velocity < -0.35) next = current + 1;
			else if (dx >  (w * 0.18) || velocity >  0.35) next = current - 1;
			snapTo(next);
		}

		function onCancel() {
			if (dragging) snapTo(current); // snap back if mid-swipe
			pressing = false;
			dragging = false;
		}

		widget.addEventListener('pointerdown',   onDown);
		widget.addEventListener('pointermove',   onMove);
		widget.addEventListener('pointerup',     onUp);
		widget.addEventListener('pointercancel', onCancel);
		widget._snapTo = snapTo;

		return {
			destroy() {
				widget.removeEventListener('pointerdown',   onDown);
				widget.removeEventListener('pointermove',   onMove);
				widget.removeEventListener('pointerup',     onUp);
				widget.removeEventListener('pointercancel', onCancel);
			}
		};
	}

	function goToSlide(i) {
		current = i;
		wrapperEl?._snapTo?.(i);
	}

	onMount(() => loadData());
</script>

<div class="page active">

{#if activeView === 'statistiken'}
	<StatsView />
{:else}
<div class="sb-page">

	{#if loading}
		<div class="sb-loading">
			<span class="material-symbols-outlined sb-loading-icon">sports_score</span>
			<p>Lade Spielbetrieb…</p>
		</div>

	{:else if plans.length === 0}
		<div class="sb-empty">
			<span class="material-symbols-outlined sb-loading-icon">event_busy</span>
			<p>Keine Aufstellungen diese Woche</p>
		</div>

	{:else}

		<!-- Liga-Tabs (nur bei mehreren Matches) -->
		{#if plans.length > 1}
			<div class="sb-tabs-bar" bind:this={tabsEl}>
				{#each plans as plan, i}
					<button
						class="sb-tab"
						class:sb-tab--active={current === i}
						onclick={() => goToSlide(i)}
					>
						{plan.match.leagues?.name ?? 'Liga'}
					</button>
				{/each}
			</div>
		{/if}

		<!-- Swipe-Carousel -->
		<div class="sb-carousel" bind:this={wrapperEl} use:carousel>
			<div class="sb-track" bind:this={trackEl}>
				{#each plans as plan}
					{@const m = plan.match}
					{@const stats = plan.playerStats ?? {}}
					<div class="sb-slide">

						<!-- Match-Header -->
						<div class="sb-match-header">
							<p class="sb-league">{m.leagues?.name ?? ''}</p>
							<div class="sb-match-row">
								{#if m.home_away === 'HEIM'}
									<span class="chip chip--home">Heim</span>
								{:else}
									<span class="chip chip--away">Auswärts</span>
								{/if}
								<h2 class="sb-opponent">vs. {m.opponent}</h2>
							</div>
							<p class="sb-date">{dateLabel(m)}</p>
						</div>

						<!-- Aufstellung -->
						{#if plan.players.length === 0}
							<div class="sb-no-players">
								<span class="material-symbols-outlined">group_off</span>
								<p>Noch keine Aufstellung</p>
							</div>
						{:else}
							<div class="sb-lineup-list">
								{#each plan.players as p}
									{@const name      = p.players?.name ?? p.player_name ?? '–'}
									{@const photo     = p.players?.photo ?? null}
									{@const isMe      = p.player_id === $playerId}
									{@const pStat     = stats[p.player_id] ?? null}
									{@const trend     = formTrend(pStat?.avg5, pStat?.overallAvg)}

									<div
										class="picker-scout-card"
										class:picker-scout-card--me={isMe}
									>
										<!-- Foto -->
										<div class="picker-scout-photo-wrap">
											<img
												class="picker-scout-photo"
												src={imgPath(photo, name)}
												alt={name}
												draggable="false"
												onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
											/>
										</div>

										<!-- Info -->
										<div class="picker-scout-info">
											<div class="picker-scout-header">
												<span class="picker-scout-name">{name}</span>
												<!-- Position-Badge statt Add-Button -->
												<div class="sb-pos-badge">
													{p.position ?? '–'}
												</div>
											</div>

											<div class="picker-scout-stats">
												<div class="picker-scout-stat">
													<span class="picker-scout-stat-label">Schnitt</span>
													<span class="picker-scout-stat-value">
														{pStat?.overallAvg ?? '–'}&thinsp;<span class="picker-scout-stat-unit">Holz</span>
													</span>
												</div>
												<div class="picker-scout-stat">
													<span class="picker-scout-stat-label">Form (5 Spiele)</span>
													<div class="picker-scout-form-row">
														<span class="picker-scout-form-value">{pStat?.avg5 ?? '–'}</span>
														{#if trend !== null}
															<span
																class="picker-scout-trend"
																class:picker-scout-trend--up={trend >= 0}
																class:picker-scout-trend--down={trend < 0}
															>
																<span class="material-symbols-outlined">
																	{trend >= 0 ? 'trending_up' : 'trending_down'}
																</span>
																{trend >= 0 ? '+' : ''}{trend}
															</span>
														{/if}
													</div>
													{#if trend !== null}
														<span class="picker-scout-vs-label">vs. Schnitt</span>
													{/if}
												</div>
											</div>
										</div>
									</div>
								{/each}
							</div>
						{/if}

					</div>
				{/each}
			</div>
		</div>

	{/if}

</div>
{/if}

</div>
