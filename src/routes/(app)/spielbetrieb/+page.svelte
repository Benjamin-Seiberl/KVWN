<script>
	import { onMount }        from 'svelte';
	import { page }           from '$app/stores';
	import { sb }             from '$lib/supabase';
	import { playerRole, playerId } from '$lib/stores/auth';
	import BottomSheet        from '$lib/components/BottomSheet.svelte';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	// ── State ────────────────────────────────────────────────
	let loading      = $state(true);
	let plans        = $state([]);   // [{ match, gamePlanId, players[] }]
	let current      = $state(0);
	let editMode     = $state(false);
	let playerStats  = $state({});   // { [playerId]: { avg5: number, overallAvg: number } }

	// Kapitän: Spieler-Picker
	let pickerOpen  = $state(false);
	let pickerSlot  = $state(null); // { gamePlanPlayerId, position }
	let pickerQuery = $state('');
	let allPlayers  = $state([]);

	let trackEl   = $state(null);
	let wrapperEl = $state(null);
	let tabsEl    = $state(null);

	const initMatchId = $page.url.searchParams.get('matchId');
	const isKapitaen  = $derived($playerRole === 'kapitaen' || $playerRole === 'admin');

	// ── Datum-Hilfsfunktionen ─────────────────────────────
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

	// photo = filename stem from players.photo; name = fallback
	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function shortName(name) {
		if (!name) return '–';
		const parts = name.trim().split(' ');
		if (parts.length < 2) return name;
		return parts[0] + ' ' + parts[parts.length - 1].charAt(0) + '.';
	}

	// Mannschaftsgröße je Liga
	function leagueConfig(leagueName) {
		const n = (leagueName ?? '').toLowerCase();
		if (n.includes('bundesliga') || n.includes('landesliga')) return { starterCount: 6, maxSubs: 4 };
		return { starterCount: 4, maxSubs: 2 };
	}

	// ── Daten laden ───────────────────────────────────────
	async function loadData() {
		const range = getWeekRange();
		const { data: matches } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', range.from)
			.lte('date', range.to)
			.order('date').order('time');

		if (!matches?.length) { loading = false; return; }

		const loaded = [];
		for (const m of matches) {
			if (!m.cal_week || !m.league_id) continue;
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, game_plan_players(id, position, player_id, player_name, score, confirmed, played, players(name, photo))')
				.eq('cal_week', m.cal_week)
				.eq('league_id', m.league_id)
				.maybeSingle();

			loaded.push({
				match:       m,
				gamePlanId:  gp?.id ?? null,
				players:     (gp?.game_plan_players ?? [])
					.sort((a, b) => (a.position ?? 99) - (b.position ?? 99)),
			});
		}

		plans = loaded;

		if (initMatchId) {
			const idx = plans.findIndex(p => p.match.id === initMatchId);
			if (idx >= 0) current = idx;
		}

		loading = false;
	}

	async function loadAllPlayers() {
		const { data } = await sb
			.from('players')
			.select('id, name, photo')
			.eq('active', true)
			.order('name');
		if (!data?.length) return;

		// Letzte Spielergebnisse für alle aktiven Spieler laden
		const { data: recent } = await sb
			.from('game_plan_players')
			.select('player_id, score, game_plans!inner(cal_week)')
			.in('player_id', data.map(p => p.id))
			.eq('played', true)
			.not('score', 'is', null)
			.order('cal_week', { referencedTable: 'game_plans', ascending: false })
			.limit(500);

		// Scores pro Spieler gruppieren (bereits DESC sortiert)
		const scoreMap = {};
		for (const g of recent ?? []) {
			if (!scoreMap[g.player_id]) scoreMap[g.player_id] = [];
			scoreMap[g.player_id].push(Number(g.score));
		}

		allPlayers = data.map(p => {
			const scores = scoreMap[p.id] ?? [];
			const last5  = scores.slice(0, 5);
			return {
				...p,
				recentScores: last5,
				avg_score: scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : null,
				avg5:      last5.length  ? Math.round(last5.reduce((a, b) => a + b, 0)  / last5.length)  : null,
			};
		}).sort((a, b) => (b.avg_score ?? 0) - (a.avg_score ?? 0));
	}

	function formTrend(p) {
		if (!p.avg5 || !p.avg_score) return null;
		return +(p.avg5 - p.avg_score).toFixed(1);
	}

	// ── Spieler-Statistiken laden ─────────────────────
	async function loadPlayerStats(loadedPlans) {
		const playerIds = [...new Set(
			loadedPlans.flatMap(plan =>
				plan.players.filter(p => p.player_id).map(p => p.player_id)
			)
		)];
		if (!playerIds.length) return;

		// Alle gespielten Ergebnisse für diese Spieler, neueste zuerst
		const { data } = await sb
			.from('game_plan_players')
			.select('player_id, score, game_plans!inner(cal_week)')
			.in('player_id', playerIds)
			.eq('played', true)
			.not('score', 'is', null)
			.order('cal_week', { referencedTable: 'game_plans', ascending: false });

		// Gruppiere Scores pro Spieler (bereits nach cal_week DESC sortiert)
		const grouped = {};
		for (const row of data ?? []) {
			const pid = row.player_id;
			if (!grouped[pid]) grouped[pid] = [];
			grouped[pid].push(Number(row.score));
		}

		// Berechne avg5 (letzte 5) und overallAvg
		const stats = {};
		for (const [pid, scores] of Object.entries(grouped)) {
			const last5 = scores.slice(0, 5);
			stats[pid] = {
				avg5:       Math.round(last5.reduce((a, b) => a + b, 0) / last5.length),
				overallAvg: Math.round(scores.reduce((a, b) => a + b, 0) / scores.length),
				count:      scores.length,
			};
		}
		playerStats = stats;
	}

	// ── Swipe-Carousel ────────────────────────────────────
	function carousel(widget) {
		let startX = 0, startY = 0, startOff = 0, lastX = 0, lastT = 0;
		let velocity = 0, dragging = false, currentX = 0;

		const DRAG_THRESHOLD = 8; // px – below this = click, not drag

		const track  = () => trackEl;
		const W      = () => widget.offsetWidth;
		const stride = () => W();
		const count  = () => plans.length;

		function moveTo(x, animate) {
			const t = track();
			if (!t) return;
			currentX = x;
			t.style.transition = animate
				? 'transform 0.45s cubic-bezier(0.34, 1.4, 0.64, 1)'
				: 'none';
			t.style.transform  = 'translateX(' + x + 'px)';
		}

		function snapTo(index) {
			current = Math.max(0, Math.min(count() - 1, index));
			moveTo(-current * stride(), true);
			if (tabsEl) {
				tabsEl.querySelectorAll('.sb-tab')[current]
					?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
			}
		}

		function onDown(e) {
			if (e.pointerType === 'mouse' && e.button !== 0) return;
			dragging = false;
			startX   = e.clientX;
			startY   = e.clientY;
			startOff = currentX;
			lastX    = e.clientX;
			lastT    = Date.now();
			velocity = 0;
		}

		function onMove(e) {
			const dx = Math.abs(e.clientX - startX);
			const dy = Math.abs(e.clientY - startY);
			if (!dragging) {
				if (dx < DRAG_THRESHOLD || dy > dx) return; // not a horizontal drag
				dragging = true;
				widget.setPointerCapture(e.pointerId);
				const t = track();
				if (t) t.style.transition = 'none';
			}
			const delta = e.clientX - startX;
			const s     = stride();
			const minX  = -(count() - 1) * s;
			const raw   = startOff + delta;
			const x     = raw > 0    ? raw * 0.18
			            : raw < minX ? minX + (raw - minX) * 0.18
			            : raw;
			currentX = x;
			track().style.transform = 'translateX(' + x + 'px)';
			const now = Date.now(), dt = now - lastT;
			if (dt > 0) velocity = (e.clientX - lastX) / dt;
			lastX = e.clientX;
			lastT = now;
		}

		function onUp(e) {
			if (!dragging) return; // was a click – don't interfere
			dragging = false;
			const delta = e.clientX - startX;
			const w     = W();
			let next    = current;
			if      (delta < -(w * 0.18) || velocity < -0.35) next = current + 1;
			else if (delta >  (w * 0.18) || velocity >  0.35) next = current - 1;
			snapTo(next);
		}

		widget.addEventListener('pointerdown',   onDown);
		widget.addEventListener('pointermove',   onMove);
		widget.addEventListener('pointerup',     onUp);
		widget.addEventListener('pointercancel', () => { dragging = false; snapTo(current); });

		widget._snapTo = snapTo;

		return {
			destroy() {
				widget.removeEventListener('pointerdown', onDown);
				widget.removeEventListener('pointermove', onMove);
				widget.removeEventListener('pointerup',   onUp);
			}
		};
	}

	function goToSlide(i) {
		current = i;
		wrapperEl?._snapTo?.(i);
	}

	// ── Kapitän: Spieler zuweisen ─────────────────────────
	function openPicker(slot) {
		if (!isKapitaen || !editMode) return;
		pickerSlot  = slot;
		pickerQuery = '';
		pickerOpen  = true;
	}

	async function assignPlayer(player) {
		if (!pickerSlot) return;
		pickerOpen = false;

		let gp = plans[current];

		// Kein Spielplan vorhanden → erst anlegen
		if (!gp.gamePlanId) {
			const m = gp.match;
			const { data: newGp, error } = await sb
				.from('game_plans')
				.insert({ cal_week: m.cal_week, league_id: m.league_id })
				.select('id')
				.single();
			if (error || !newGp) { pickerSlot = null; return; }
			plans[current] = { ...gp, gamePlanId: newGp.id };
			gp = plans[current];
		}

		if (pickerSlot.gamePlanPlayerId) {
			await sb
				.from('game_plan_players')
				.update({ player_id: player.id, player_name: player.name })
				.eq('id', pickerSlot.gamePlanPlayerId);
		} else {
			await sb
				.from('game_plan_players')
				.insert({
					game_plan_id: gp.gamePlanId,
					player_id:    player.id,
					player_name:  player.name,
					position:     pickerSlot.position,
				});
		}

		// UI aktualisieren
		const { data } = await sb
			.from('game_plan_players')
			.select('id, position, player_id, player_name, score, confirmed, played, players(name, photo)')
			.eq('game_plan_id', gp.gamePlanId);
		if (data) {
			plans[current] = {
				...gp,
				players: data.sort((a, b) => (a.position ?? 99) - (b.position ?? 99)),
			};
		}
		pickerSlot = null;
	}

	const filteredPlayers = $derived(
		pickerQuery.trim()
			? allPlayers.filter(p =>
				p.name.toLowerCase().includes(pickerQuery.toLowerCase()))
			: allPlayers
	);

	onMount(async () => {
		await loadData();
		await loadPlayerStats(plans);
		if (isKapitaen) await loadAllPlayers();
	});

	$effect(() => {
		if (isKapitaen && allPlayers.length === 0) loadAllPlayers();
	});
</script>

<div class="page active">
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

			<!-- League Tabs -->
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

			<!-- Swipe Carousel -->
			<div class="sb-carousel" bind:this={wrapperEl} use:carousel>
				<div class="sb-track" bind:this={trackEl}>
					{#each plans as plan, i}
						{@const m      = plan.match}
						{@const cfg    = leagueConfig(m.leagues?.name)}
						{@const starters = plan.players.filter(p => (p.position ?? 99) <= cfg.starterCount)}
						{@const subs     = plan.players.filter(p => (p.position ?? 99) > cfg.starterCount)}
						{@const starterAvgs = starters.filter(p => p.player_id && playerStats[p.player_id]).map(p => playerStats[p.player_id].avg5)}
						{@const teamAvg5 = starterAvgs.length ? Math.round(starterAvgs.reduce((a, b) => a + b, 0) / starterAvgs.length) : null}
						{@const confirmedCount = starters.filter(p => p.confirmed === true).length}
						{@const declinedCount  = starters.filter(p => p.confirmed === false).length}
						<div class="sb-slide">

							<!-- Match Header -->
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
								<div class="sb-header-meta-row">
									<p class="sb-date">{dateLabel(m)}</p>
									{#if teamAvg5}
										<span class="sb-header-stat-pill">
											<span class="material-symbols-outlined">bar_chart</span>
											Ø&thinsp;{teamAvg5}
										</span>
									{/if}
								</div>
							</div>

							<!-- Players Area -->
							<div class="sb-players-area">

								{#if plan.players.length === 0 && !(isKapitaen && editMode)}
									<div class="sb-no-players">
										<span class="material-symbols-outlined">group_off</span>
										<p>Noch keine Aufstellung</p>
									</div>
								{:else}

									<!-- Startaufstellung -->
									<div class="sb-section-label">
										<span>Startaufstellung</span>
										<div class="sb-section-label-right">
											{#if confirmedCount > 0}
												<span class="sb-confirmed-chip sb-confirmed-chip--ok">
													<span class="material-symbols-outlined">check</span>
													{confirmedCount}
												</span>
											{/if}
											{#if declinedCount > 0}
												<span class="sb-confirmed-chip sb-confirmed-chip--no">
													<span class="material-symbols-outlined">close</span>
													{declinedCount}
												</span>
											{/if}
											<span class="sb-count">{starters.length}&thinsp;/&thinsp;{cfg.starterCount}</span>
										</div>
									</div>

									<div class="sb-player-list">
										{#each starters as p}
											{@const name  = p.players?.name ?? p.player_name ?? '–'}
											{@const photo = p.players?.photo ?? null}
											{@const isMe  = p.player_id === $playerId}
											{@const pStat = p.player_id ? playerStats[p.player_id] : null}
											<button
												class="sb-player-row"
												class:sb-player-row--me={isMe}
												class:sb-player-row--editable={isKapitaen && editMode}
												onclick={() => openPicker({ gamePlanPlayerId: p.id, position: p.position })}
												disabled={!isKapitaen || !editMode}
											>
												<div class="sb-row-avatar-wrap">
													<img
														class="sb-row-avatar"
														src={imgPath(photo, name)}
														alt={name}
														draggable="false"
														onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
													/>
													<span class="sb-pos">{p.position ?? '–'}</span>
													{#if isMe}
														<span class="sb-me-badge">Du</span>
													{/if}
													{#if isKapitaen && editMode}
														<div class="sb-edit-overlay-row">
															<span class="material-symbols-outlined">edit</span>
														</div>
													{/if}
												</div>
												<span class="sb-row-name">{shortName(name)}</span>
												<div class="sb-row-meta">
													{#if pStat}
														<span class="sb-row-score">&oslash;&thinsp;{pStat.avg5}</span>
													{:else if p.score}
														<span class="sb-row-score">&oslash;&thinsp;{p.score}</span>
													{/if}
													{#if p.confirmed === true}
														<span class="sb-status-badge sb-status-badge--confirmed">
															<span class="material-symbols-outlined">check</span>
														</span>
													{:else if p.confirmed === false}
														<span class="sb-status-badge sb-status-badge--declined">
															<span class="material-symbols-outlined">close</span>
															</span>
													{/if}
												</div>
											</button>
										{/each}

										<!-- Leere Startslots (EditMode) -->
										{#if isKapitaen && editMode}
											{#each Array.from({ length: Math.max(0, cfg.starterCount - starters.length) }, (_, i) => i) as j}
												<button
													class="sb-player-row sb-player-row--empty"
													onclick={() => openPicker({ gamePlanPlayerId: null, position: starters.length + j + 1 })}
												>
													<div class="sb-row-avatar-wrap">
														<div class="sb-row-avatar-add">
															<span class="material-symbols-outlined">person_add</span>
														</div>
														<span class="sb-pos sb-pos--empty">{starters.length + j + 1}</span>
													</div>
													<span class="sb-row-name sb-row-name--placeholder">Hinzufügen</span>
													<div class="sb-row-meta"></div>
												</button>
											{/each}
										{/if}
									</div>

									<!-- Ersatzspieler -->
									{#if subs.length > 0 || (isKapitaen && editMode && starters.length >= cfg.starterCount)}
										<div class="sb-section-label sb-section-label--sub">
											<span>Ersatzspieler</span>
											<span class="sb-count">{subs.length}</span>
										</div>

										<div class="sb-player-list">
											{#each subs as p}
												{@const name  = p.players?.name ?? p.player_name ?? '–'}
												{@const photo = p.players?.photo ?? null}
												{@const isMe  = p.player_id === $playerId}
												{@const pStat = p.player_id ? playerStats[p.player_id] : null}
												<button
													class="sb-player-row"
													class:sb-player-row--me={isMe}
													class:sb-player-row--editable={isKapitaen && editMode}
													onclick={() => openPicker({ gamePlanPlayerId: p.id, position: p.position })}
													disabled={!isKapitaen || !editMode}
												>
													<div class="sb-row-avatar-wrap">
														<img
															class="sb-row-avatar"
															src={imgPath(photo, name)}
															alt={name}
															draggable="false"
															onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
														/>
														<span class="sb-pos">{p.position ?? '–'}</span>
														{#if isMe}
															<span class="sb-me-badge">Du</span>
														{/if}
														{#if isKapitaen && editMode}
															<div class="sb-edit-overlay-row">
																<span class="material-symbols-outlined">edit</span>
															</div>
														{/if}
													</div>
													<span class="sb-row-name">{shortName(name)}</span>
													<div class="sb-row-meta">
														{#if pStat}
															<span class="sb-row-score">&oslash;&thinsp;{pStat.avg5}</span>
														{:else if p.score}
															<span class="sb-row-score">&oslash;&thinsp;{p.score}</span>
														{/if}
														{#if p.confirmed === true}
															<span class="sb-status-badge sb-status-badge--confirmed">
																<span class="material-symbols-outlined">check</span>
															</span>
														{:else if p.confirmed === false}
															<span class="sb-status-badge sb-status-badge--declined">
																<span class="material-symbols-outlined">close</span>
															</span>
														{/if}
													</div>
												</button>
											{/each}

											<!-- Ersatz hinzufügen (EditMode) -->
											{#if isKapitaen && editMode}
												<button
													class="sb-player-row sb-player-row--empty"
													onclick={() => openPicker({ gamePlanPlayerId: null, position: plan.players.length + 1 })}
												>
													<div class="sb-row-avatar-wrap">
														<div class="sb-row-avatar-add">
															<span class="material-symbols-outlined">person_add</span>
														</div>
														<span class="sb-pos sb-pos--empty">{plan.players.length + 1}</span>
													</div>
													<span class="sb-row-name sb-row-name--placeholder">Hinzufügen</span>
													<div class="sb-row-meta"></div>
												</button>
											{/if}
										</div>
									{/if}

								{/if}
							</div>

						</div>
					{/each}
				</div>
			</div>

			<!-- Kapitän FAB -->
			{#if isKapitaen}
				<button
					class="sb-fab"
					class:sb-fab--active={editMode}
					onclick={() => editMode = !editMode}
					aria-label={editMode ? 'Bearbeitung beenden' : 'Aufstellung bearbeiten'}
				>
					<span class="material-symbols-outlined">
						{editMode ? 'check' : 'edit'}
					</span>
				</button>
			{/if}
		{/if}

	</div>
</div>

<!-- Spieler-Picker (Kapitän) -->
<BottomSheet bind:open={pickerOpen} title="Spieleranalyse">
	<div class="picker">
		<div class="picker-search-wrap">
			<span class="material-symbols-outlined picker-search-icon">search</span>
			<input
				class="picker-search"
				type="search"
				placeholder="Name suchen…"
				bind:value={pickerQuery}
				autocomplete="off"
			/>
		</div>
		<div class="picker-scout-list">
			{#each filteredPlayers as p, idx}
				{@const trend  = formTrend(p)}
				{@const isTop  = idx === 0 && !pickerQuery.trim()}
				<button
					class="picker-scout-card"
					class:picker-scout-card--top={isTop}
					onclick={() => assignPlayer(p)}
				>
					<!-- Photo -->
					<div class="picker-scout-photo-wrap">
						<img
							class="picker-scout-photo"
							src={imgPath(p.photo, p.name)}
							alt={p.name}
							draggable="false"
							onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
						/>
					</div>

					<!-- Info -->
					<div class="picker-scout-info">
						<div class="picker-scout-header">
							<span class="picker-scout-name">{p.name}</span>
							<div class="picker-scout-add" class:picker-scout-add--top={isTop}>
								<span class="material-symbols-outlined">add</span>
							</div>
						</div>

						<div class="picker-scout-stats">
							<!-- Gesamtschnitt -->
							<div class="picker-scout-stat">
								<span class="picker-scout-stat-label">Schnitt</span>
								<span class="picker-scout-stat-value">
									{p.avg_score ?? '–'}&thinsp;<span class="picker-scout-stat-unit">Holz</span>
								</span>
							</div>

							<!-- Form letzte 5 -->
							<div class="picker-scout-stat">
								<span class="picker-scout-stat-label">Form (5 Spiele)</span>
								<div class="picker-scout-form-row">
									<span class="picker-scout-form-value">{p.avg5 ?? '–'}</span>
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
				</button>
			{/each}
		</div>
	</div>
</BottomSheet>
