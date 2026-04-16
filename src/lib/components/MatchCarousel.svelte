<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import BottomSheet from './BottomSheet.svelte';
	import { playerId } from '$lib/stores/auth';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
	const DAY_NAMES_LONG = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];

	let matches  = $state([]);
	let loading  = $state(true);
	let current     = $state(0);
	let dotProgress = $state(0);

	let wrapperEl = $state(null);
	let widgetEl  = $state(null);
	let trackEl   = $state(null);

	let sheetOpen = $state(false);
	let sheetIdx  = $state(0);
	let sheetLineup = $state([]);
	let lineupLoading = $state(false);

	function formatTime(t) { return t ? t.substring(0, 5) : ''; }

	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '. \u2022 ' + formatTime(m.time) + ' Uhr';
	}

	function dateLabelLong(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES_LONG[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '.' + d.getFullYear() +
			(m.time ? ' · ' + formatTime(m.time) + ' Uhr' : '');
	}

	function getWeekRange() {
		const today = new Date();
		const day   = today.getDay();
		const diffToMon = day === 0 ? -6 : 1 - day;
		const mon = new Date(today);
		mon.setDate(today.getDate() + diffToMon);
		const sun = new Date(mon);
		sun.setDate(mon.getDate() + 6);
		const fmt = d => d.getFullYear() + '-' +
			String(d.getMonth() + 1).padStart(2, '0') + '-' +
			String(d.getDate()).padStart(2, '0');
		return { from: fmt(mon), to: fmt(sun) };
	}

	async function loadData() {
		const range = getWeekRange();
		const today = new Date();
		const todayStr = today.getFullYear() + '-' +
			String(today.getMonth() + 1).padStart(2, '0') + '-' +
			String(today.getDate()).padStart(2, '0');

		const { data, error } = await sb
			.from('matches')
			.select('id, date, time, home_away, opponent, cal_week, league_id, location, leagues(name)')
			.gte('date', todayStr)
			.lte('date', range.to)
			.order('date')
			.order('time');

		if (error || !data?.length) { loading = false; return; }
		matches = data;
		loading = false;
	}

	async function openMatchDetail(idx) {
		sheetIdx = idx;
		sheetOpen = true;
		sheetLineup = [];
		lineupLoading = true;

		const m = matches[idx];
		if (!m?.cal_week || !m?.league_id) { lineupLoading = false; return; }

		const { data: gp } = await sb
			.from('game_plans')
			.select('id, game_plan_players(id, position, player_id, player_name, confirmed, players(name, photo))')
			.eq('cal_week', m.cal_week)
			.eq('league_id', m.league_id)
			.maybeSingle();

		if (gp?.game_plan_players) {
			sheetLineup = gp.game_plan_players.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));
		}
		lineupLoading = false;
	}

	function carousel(widget) {
		let startX = 0, startOff = 0, lastX = 0, lastT = 0;
		let velocity = 0, dragging = false;
		let currentX = 0;

		const track  = () => trackEl;
		const W      = () => widget.offsetWidth;
		const stride = () => widgetEl?.offsetWidth ?? W();
		const count  = () => matches.length;

		function moveTo(x, animate) {
			const t = track();
			if (!t) return;
			currentX = x;
			t.style.transition = animate ? 'transform 0.32s ease' : 'none';
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

			const now = Date.now();
			const dt  = now - lastT;
			if (dt > 0) velocity = (e.clientX - lastX) / dt;
			lastX = e.clientX;
			lastT = now;
		}

		function onUp(e) {
			if (!dragging) return;
			dragging = false;
			const delta = e.clientX - startX;
			const w = W();
			let next = current;
			if      (delta < -(w * 0.18) || velocity < -0.35) next = current + 1;
			else if (delta >  (w * 0.18) || velocity >  0.35) next = current - 1;
			snapTo(next);
			// Tap: <8px movement → open detail
			if (Math.abs(delta) < 8) {
				openMatchDetail(current);
			}
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

	onMount(async () => {
		await loadData();
	});
</script>

<div class="carousel-container" bind:this={wrapperEl} use:carousel>

<div class="widget widget--match-combined" bind:this={widgetEl}>
	<div class="widget-hero-bg"></div>

	<div class="match-track" bind:this={trackEl}>
		{#if loading}
			<div class="match-slide match-slide--skeleton">
				<div class="match-hero-content">
					<div class="skel-bar skel-bar--league shimmer-box"></div>
					<div class="skel-bar skel-bar--opponent shimmer-box"></div>
					<div class="skel-bar skel-bar--date shimmer-box"></div>
				</div>
			</div>
		{:else if matches.length === 0}
			<div class="match-slide">
				<div class="match-hero-content" style="justify-content:center">
					<p class="match-label">Diese Woche</p>
					<h2 class="match-title">Keine Spiele</h2>
				</div>
			</div>
		{:else}
			{#each matches as m, i}
				<div class="match-slide">
					<div class="match-hero-content">
						<div class="match-meta">
							<p class="match-league-name">{m.leagues?.name ?? ''}</p>
							{#if matches.length > 1}
								<span class="match-counter">{i + 1}&nbsp;/&nbsp;{matches.length}</span>
							{/if}
						</div>

						<div>
							<div style="display:flex; align-items:center; gap: var(--space-2); margin-bottom: 2px;">
								{#if m.home_away === 'HEIM'}
									<span class="chip chip--home">Heim</span>
								{:else}
									<span class="chip chip--away">Auswärts</span>
								{/if}
								<p class="match-vs-label" style="margin:0">vs.</p>
							</div>
							<h2 class="match-title">{m.opponent}</h2>
						</div>
						<p class="match-label">{dateLabel(m)}</p>
					</div>
				</div>
			{/each}
		{/if}
	</div>
</div>

{#if matches.length > 1}
	<div class="match-dots-external">
		{#each matches as _, i}
			{@const dist = Math.abs(dotProgress - i)}
			{@const w    = dist < 1 ? 6 + 14 * (1 - dist) : 6}
			{@const active = dist < 0.5}
			<span
				class="match-dot"
				style="width: {w}px; background: {active ? 'var(--color-primary)' : 'var(--color-outline-variant)'}"
			></span>
		{/each}
	</div>
{/if}

</div>

<!-- Match Detail Sheet -->
{#if matches.length > 0}
	{@const sm = matches[sheetIdx]}
	{#if sm}
		<BottomSheet bind:open={sheetOpen} title="Match-Details">
			<div class="mds-hero">
				<div class="mds-league">{sm.leagues?.name ?? ''}</div>
				<div class="mds-chips">
					{#if sm.home_away === 'HEIM'}
						<span class="chip chip--home">Heim</span>
					{:else}
						<span class="chip chip--away">Auswärts</span>
					{/if}
				</div>
				<h2 class="mds-opponent">vs. {sm.opponent}</h2>
				<p class="mds-date">
					<span class="material-symbols-outlined" style="font-size:1rem;vertical-align:-3px">calendar_month</span>
					{dateLabelLong(sm)}
				</p>
				{#if sm.location}
					<p class="mds-date" style="margin-top: var(--space-1);">
						<span class="material-symbols-outlined" style="font-size:1rem;vertical-align:-3px">location_on</span>
						{sm.location}
					</p>
				{/if}
			</div>

			<!-- Aufstellung -->
			<p class="mds-section">Aufstellung</p>
			{#if lineupLoading}
				<div class="mds-lineup">
					{#each [0,1,2,3] as _}
						<div class="mds-player-skel">
							<div class="skel-avatar shimmer-box" style="width:36px;height:36px"></div>
							<div class="skel-bar shimmer-box" style="width:80px;height:14px;border-radius:6px"></div>
						</div>
					{/each}
				</div>
			{:else if sheetLineup.length > 0}
				<div class="mds-lineup">
					{#each sheetLineup as p}
						{@const name = p.players?.name ?? p.player_name}
						{@const isMe = p.player_id === $playerId}
						<div class="mds-player" class:mds-player--me={isMe}>
							<div class="mds-avatar">
								<span class="mds-initial">{(name ?? '?').slice(0,1)}</span>
							</div>
							<span class="mds-name">{name}</span>
							<span class="mds-pos">{p.position ?? ''}</span>
							{#if p.confirmed === true}
								<span class="material-symbols-outlined mds-check">check_circle</span>
							{:else if p.confirmed === false}
								<span class="material-symbols-outlined mds-declined">cancel</span>
							{/if}
						</div>
					{/each}
				</div>
			{:else}
				<p class="mds-empty">Noch keine Aufstellung eingetragen.</p>
			{/if}
		</BottomSheet>
	{/if}
{/if}
