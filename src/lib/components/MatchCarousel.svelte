<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { goto } from '$app/navigation';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	let matches  = $state([]);
	let kaders   = $state([]);
	let loading  = $state(true);
	let current  = $state(0);

	let widgetEl = $state(null);
	let trackEl  = $state(null);

	// ── Datum-Hilfsfunktionen ──────────────────────────────────
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

	function formatTime(t) { return t ? t.substring(0, 5) : ''; }

	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '. \u2022 ' + formatTime(m.time) + ' Uhr';
	}

	function imgPath(name) {
		return name ? '/images/' + encodeURIComponent(name) + '.jpg' : '';
	}

	// ── Daten laden ────────────────────────────────────────────
	async function loadData() {
		const range = getWeekRange();
		const { data, error } = await sb
			.from('matches')
			.select('id, date, time, home_away, opponent, cal_week, leagues(name)')
			.gte('date', range.from)
			.lte('date', range.to)
			.order('date')
			.order('time');

		if (error || !data?.length) { loading = false; return; }
		matches = data;

		kaders = await Promise.all(matches.map(async m => {
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, leagues!inner(name), game_plan_players(player_name, score, played, position, players(name))')
				.eq('cal_week', m.cal_week)
				.eq('leagues.name', m.leagues?.name ?? '')
				.maybeSingle();
			return (gp?.game_plan_players ?? []).sort((a, b) => a.position - b.position);
		}));

		loading = false;
	}

	// ── Carousel-Drag (Svelte Action) ─────────────────────────
	function carousel(widget) {
		let startX = 0, startOff = 0, lastX = 0, lastT = 0, velocity = 0, dragging = false;

		const track  = () => trackEl;
		const W      = () => widget.offsetWidth;
		const stride = () => W() - 12;
		const count  = () => matches.length;

		function moveTo(x, animate) {
			const t = track();
			if (!t) return;
			t.style.transition = animate ? 'transform 0.42s cubic-bezier(0.25, 1, 0.5, 1)' : 'none';
			t.style.transform  = 'translateX(' + x + 'px)';
		}

		function glowChip() {
			const slides = track()?.querySelectorAll('.match-slide');
			const chip   = slides?.[current]?.querySelector('.chip--league');
			if (!chip) return;
			chip.classList.remove('chip--league--glow');
			void chip.offsetWidth;
			chip.classList.add('chip--league--glow');
		}

		function snapTo(index) {
			current = Math.max(0, Math.min(count() - 1, index));
			moveTo(-current * stride(), true);
			glowChip();
		}

		function onDown(e) {
			if (e.pointerType === 'mouse' && e.button !== 0) return;
			dragging = true;
			startX   = e.clientX;
			startOff = -current * stride();
			lastX    = e.clientX;
			lastT    = Date.now();
			velocity = 0;
			track().style.transition = 'none';
			widget.setPointerCapture(e.pointerId);
		}

		function onMove(e) {
			if (!dragging) return;
			const delta = e.clientX - startX;
			const s     = stride();
			const minX  = -(count() - 1) * s;
			const raw   = startOff + delta;
			const x     = raw > 0 ? raw * 0.18 : raw < minX ? minX + (raw - minX) * 0.18 : raw;
			track().style.transform = 'translateX(' + x + 'px)';
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
			if      (delta < -(w * 0.2) || velocity < -0.4) next = current + 1;
			else if (delta >  (w * 0.2) || velocity >  0.4) next = current - 1;
			snapTo(next);
		}

		widget.addEventListener('pointerdown',  onDown);
		widget.addEventListener('pointermove',  onMove);
		widget.addEventListener('pointerup',    onUp);
		widget.addEventListener('pointercancel', () => { dragging = false; snapTo(current); });

		return {
			destroy() {
				widget.removeEventListener('pointerdown',  onDown);
				widget.removeEventListener('pointermove',  onMove);
				widget.removeEventListener('pointerup',    onUp);
			}
		};
	}

	onMount(loadData);
</script>

<!-- Widget -->
<div class="widget widget--match-combined" bind:this={widgetEl} use:carousel>
	<div class="widget-hero-bg"></div>

	<div class="match-track" bind:this={trackEl}>
		{#if loading}
			<div class="match-slide match-slide--active">
				<div class="match-hero-content" style="justify-content:center">
					<p class="match-label">Lade Spiele…</p>
				</div>
			</div>
		{:else if matches.length === 0}
			<div class="match-slide match-slide--active">
				<div class="match-hero-content" style="justify-content:center">
					<p class="match-label">Diese Woche</p>
					<h2 class="match-title">Keine Spiele</h2>
				</div>
			</div>
		{:else}
			{#each matches as m, i}
				{@const kader = kaders[i] ?? []}
				<div class="match-slide" class:match-slide--active={i === current}>
					<!-- Hero -->
					<div class="match-hero-content">
						<div class="match-meta">
							<span class="chip chip--league">{m.leagues?.name ?? ''}</span>
							{#if m.home_away === 'HEIM'}
								<span class="chip chip--home">Heimspiel</span>
							{:else}
								<span class="chip chip--away">Auswärts</span>
							{/if}
							{#if matches.length > 1}
								<span class="match-counter">{i + 1}&nbsp;/&nbsp;{matches.length}</span>
							{/if}
						</div>
						<div>
							<p class="match-vs-label">vs.</p>
							<h2 class="match-title">{m.opponent}</h2>
						</div>
						<p class="match-label">{dateLabel(m)}</p>
					</div>

					<!-- Kader -->
					<div class="widget-kader-panel">
						{#if kader.length > 0}
							<div class="kader-avatars">
								{#each kader as p}
									{@const name = p.players?.name ?? p.player_name}
									<div class="kader-player">
										<img
											class="kader-avatar"
											src={imgPath(name)}
											alt={name ?? ''}
											onerror={(e) => e.currentTarget.style.display = 'none'}
										/>
									</div>
								{/each}
							</div>
						{:else}
							<p class="kader-empty-text">Noch keine Aufstellung</p>
						{/if}
						<button class="btn-aufstellung" onclick={() => goto('/spielbetrieb')}>
							Aufstellung ansehen
							<span class="material-symbols-outlined">chevron_right</span>
						</button>
					</div>
				</div>
			{/each}
		{/if}
	</div>
</div>

<!-- Dots außerhalb -->
{#if matches.length > 1}
	<div class="match-dots-external">
		{#each matches as _, i}
			<span class="match-dot" class:match-dot--active={i === current}></span>
		{/each}
	</div>
{/if}
