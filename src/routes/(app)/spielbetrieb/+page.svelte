<script>
	import { onMount }        from 'svelte';
	import { page }           from '$app/stores';
	import { sb }             from '$lib/supabase';
	import { playerRole, playerId } from '$lib/stores/auth';
	import BottomSheet        from '$lib/components/BottomSheet.svelte';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	// ── State ────────────────────────────────────────────────
	let loading    = $state(true);
	let plans      = $state([]);   // [{ match, gamePlanId, players[] }]
	let current    = $state(0);
	let editMode   = $state(false);

	// Kapitän: Spieler-Picker
	let pickerOpen  = $state(false);
	let pickerSlot  = $state(null); // { gamePlanPlayerId, position }
	let pickerQuery = $state('');
	let allPlayers  = $state([]);

	let trackEl     = $state(null);
	let wrapperEl   = $state(null);

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

	function imgPath(name) {
		return name ? '/images/' + encodeURIComponent(name) + '.jpg' : '';
	}

	function shortName(name) {
		if (!name) return '–';
		const parts = name.trim().split(' ');
		if (parts.length < 2) return name;
		return parts[0] + ' ' + parts[parts.length - 1].charAt(0) + '.';
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
				.select('id, game_plan_players(id, position, player_id, player_name, score, confirmed, played, players(name))')
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

		// Zur matchId springen wenn via URL übergeben
		if (initMatchId) {
			const idx = plans.findIndex(p => p.match.id === initMatchId);
			if (idx >= 0) current = idx;
		}

		loading = false;
	}

	async function loadAllPlayers() {
		const { data } = await sb
			.from('players')
			.select('id, name')
			.eq('active', true)
			.order('name');
		allPlayers = data ?? [];
	}

	// ── Swipe-Carousel ────────────────────────────────────
	let dotProgress = $state(0);

	function carousel(widget) {
		let startX = 0, startOff = 0, lastX = 0, lastT = 0;
		let velocity = 0, dragging = false, currentX = 0;

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
			dotProgress = Math.max(0, Math.min(count() - 1, -x / stride()));
		}

		function snapTo(index) {
			current     = Math.max(0, Math.min(count() - 1, index));
			dotProgress = current;
			moveTo(-current * stride(), true);
		}

		function onDown(e) {
			if (e.pointerType === 'mouse' && e.button !== 0) return;
			dragging = true;
			startX   = e.clientX;
			startOff = currentX;
			lastX    = e.clientX;
			lastT    = Date.now();
			velocity = 0;
			const t  = track();
			if (t) t.style.transition = 'none';
			widget.setPointerCapture(e.pointerId);
		}

		function onMove(e) {
			if (!dragging) return;
			const delta = e.clientX - startX;
			const s     = stride();
			const minX  = -(count() - 1) * s;
			const raw   = startOff + delta;
			const x     = raw > 0    ? raw * 0.18
			            : raw < minX ? minX + (raw - minX) * 0.18
			            : raw;
			currentX = x;
			track().style.transform = 'translateX(' + x + 'px)';
			dotProgress = Math.max(0, Math.min(count() - 1, -x / s));
			const now = Date.now(), dt = now - lastT;
			if (dt > 0) velocity = (e.clientX - lastX) / dt;
			lastX = e.clientX;
			lastT = now;
		}

		function onUp(e) {
			if (!dragging) return;
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
		return {
			destroy() {
				widget.removeEventListener('pointerdown',  onDown);
				widget.removeEventListener('pointermove',  onMove);
				widget.removeEventListener('pointerup',    onUp);
			}
		};
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

		if (pickerSlot.gamePlanPlayerId) {
			// Bestehenden Eintrag updaten
			await sb
				.from('game_plan_players')
				.update({ player_id: player.id, player_name: player.name })
				.eq('id', pickerSlot.gamePlanPlayerId);
		} else {
			// Neuen Eintrag anlegen
			await sb
				.from('game_plan_players')
				.insert({
					game_plan_id: plans[current].gamePlanId,
					player_id:    player.id,
					player_name:  player.name,
					position:     pickerSlot.position,
				});
		}

		// Slide aktualisieren
		const gp = plans[current];
		const { data } = await sb
			.from('game_plan_players')
			.select('id, position, player_id, player_name, score, confirmed, played, players(name)')
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
			<!-- Swipe-Track -->
			<div class="sb-carousel" bind:this={wrapperEl} use:carousel>
				<div class="sb-track" bind:this={trackEl}>
					{#each plans as plan, i}
						{@const m = plan.match}
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
							<div class="sb-section-label">
								<span>Aufstellung</span>
								{#if plan.players.length > 0}
									<span class="sb-count">{plan.players.length} Spieler</span>
								{/if}
							</div>

							{#if plan.players.length === 0}
								<div class="sb-no-players">
									<span class="material-symbols-outlined">group_off</span>
									<p>Noch keine Aufstellung</p>
								</div>
							{:else}
								<div class="sb-player-grid">
									{#each plan.players as p}
										{@const name = p.players?.name ?? p.player_name ?? '–'}
										{@const isMe = p.player_id === $playerId}
										<button
											class="sb-player-card"
											class:sb-player-card--me={isMe}
											class:sb-player-card--editable={isKapitaen && editMode}
											class:sb-player-card--confirmed={p.confirmed === true}
											class:sb-player-card--declined={p.confirmed === false}
											onclick={() => openPicker({ gamePlanPlayerId: p.id, position: p.position })}
											disabled={!isKapitaen || !editMode}
										>
											<div class="sb-avatar-wrap">
												<img
													class="sb-avatar"
													src={imgPath(name)}
													alt={name}
													draggable="false"
													onerror={(e) => e.currentTarget.style.display='none'}
												/>
												{#if isKapitaen && editMode}
													<div class="sb-edit-overlay">
														<span class="material-symbols-outlined">edit</span>
													</div>
												{/if}
												{#if p.confirmed === true}
													<span class="sb-confirmed-badge" title="Bestätigt">
														<span class="material-symbols-outlined">check</span>
													</span>
												{:else if p.confirmed === false}
													<span class="sb-declined-badge" title="Abgelehnt">
														<span class="material-symbols-outlined">close</span>
													</span>
												{/if}
											</div>
											<span class="sb-player-name">{shortName(name)}</span>
											{#if p.score}
												<span class="sb-player-score">{p.score}</span>
											{/if}
										</button>
									{/each}

									<!-- Neuen Spieler hinzufügen (nur Kapitän & Editmode) -->
									{#if isKapitaen && editMode}
										<button
											class="sb-player-card sb-player-card--add"
											onclick={() => openPicker({ gamePlanPlayerId: null, position: plan.players.length + 1 })}
										>
											<div class="sb-avatar-wrap sb-avatar-add">
												<span class="material-symbols-outlined">person_add</span>
											</div>
											<span class="sb-player-name">Hinzufügen</span>
										</button>
									{/if}
								</div>
							{/if}

						</div>
					{/each}
				</div>
			</div>

			<!-- Dots -->
			{#if plans.length > 1}
				<div class="sb-dots">
					{#each plans as _, i}
						{@const dist   = Math.abs(dotProgress - i)}
						{@const w      = dist < 1 ? 6 + 14 * (1 - dist) : 6}
						{@const active = dist < 0.5}
						<span
							class="match-dot"
							style="width:{w}px; background:{active ? 'var(--color-primary)' : 'var(--color-outline-variant)'}"
						></span>
					{/each}
				</div>
			{/if}

			<!-- Kapitän-FAB -->
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
<BottomSheet bind:open={pickerOpen} title="Spieler auswählen">
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
		<div class="picker-list">
			{#each filteredPlayers as p}
				<button class="picker-item" onclick={() => assignPlayer(p)}>
					<img
						class="picker-avatar"
						src={imgPath(p.name)}
						alt={p.name}
						draggable="false"
						onerror={(e) => e.currentTarget.style.display='none'}
					/>
					<span class="picker-name">{p.name}</span>
					<span class="material-symbols-outlined picker-chevron">chevron_right</span>
				</button>
			{/each}
		</div>
	</div>
</BottomSheet>
