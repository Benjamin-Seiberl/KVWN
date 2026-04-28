<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { goto } from '$app/navigation';
	import { triggerToast } from '$lib/stores/toast.js';
	import { playerId } from '$lib/stores/auth.js';

	import { DAY_SHORT, MONTH_SHORT, fmtTime } from '$lib/utils/dates.js';
	import ContextMenu from '$lib/components/ContextMenu.svelte';
	import EventDetailSheet from '$lib/components/kalender/EventDetailSheet.svelte';

	let events        = $state([]);
	let rsvpMap       = $state(new Map());   // event_id → 'yes' | 'no'
	let dismissedIds  = $state(new Set());   // Set<event_id>
	let loading       = $state(true);

	// Detail-Sheet
	let sheetOpen  = $state(false);
	let sheetEvent = $state(null);

	// Swipe-State pro Card (Map<event_id, deltaX>)
	let swipeOffsets = $state(new Map());

	// ── Visible (nicht ausgeblendete) Events ────────────────────────────────────
	const visibleEvents = $derived(events.filter(e => !dismissedIds.has(e.id)));
	const allDismissed  = $derived(events.length > 0 && visibleEvents.length === 0);

	// ── Daten laden ─────────────────────────────────────────────────────────────
	async function load() {
		loading = true;
		try {
			const todayStr = new Date().toISOString().split('T')[0];
			const pid = $playerId;

			const eventsP = sb
				.from('events')
				.select('id, title, date, time, location, description, external_id')
				.gte('date', todayStr)
				.order('date')
				.order('time')
				.limit(5);

			const rsvpP = pid
				? sb.from('event_rsvps').select('event_id, response').eq('player_id', pid)
				: Promise.resolve({ data: [], error: null });

			const dismissP = pid
				? sb.from('event_dismissals').select('event_id').eq('player_id', pid)
				: Promise.resolve({ data: [], error: null });

			const [evRes, rsvpRes, dismRes] = await Promise.all([eventsP, rsvpP, dismissP]);

			if (evRes.error)   { triggerToast('Fehler: ' + evRes.error.message);   return; }
			if (rsvpRes.error) { triggerToast('Fehler: ' + rsvpRes.error.message); return; }
			if (dismRes.error) { triggerToast('Fehler: ' + dismRes.error.message); return; }

			events = evRes.data ?? [];

			const m = new Map();
			for (const r of (rsvpRes.data ?? [])) m.set(r.event_id, r.response);
			rsvpMap = m;

			const s = new Set();
			for (const d of (dismRes.data ?? [])) s.add(d.event_id);
			dismissedIds = s;
		} finally {
			loading = false;
		}
	}

	onMount(load);

	// ── RSVP setzen / toggeln ───────────────────────────────────────────────────
	function rsvpFor(eventId) {
		return rsvpMap.get(eventId) ?? null;
	}

	async function setRsvp(eventId, response) {
		if (!$playerId) { triggerToast('Bitte zuerst anmelden'); return; }
		const previous = rsvpMap.get(eventId) ?? null;
		const next = previous === response ? null : response;

		// Optimistic
		const m = new Map(rsvpMap);
		if (next === null) m.delete(eventId);
		else m.set(eventId, next);
		rsvpMap = m;

		if (next === null) {
			const { error } = await sb.from('event_rsvps')
				.delete()
				.eq('event_id', eventId)
				.eq('player_id', $playerId);
			if (error) {
				// rollback
				const r = new Map(rsvpMap);
				if (previous === null) r.delete(eventId);
				else r.set(eventId, previous);
				rsvpMap = r;
				triggerToast('Fehler: ' + error.message);
				return;
			}
			triggerToast('Antwort entfernt');
		} else {
			const { error } = await sb.from('event_rsvps').upsert(
				{ event_id: eventId, player_id: $playerId, response: next },
				{ onConflict: 'event_id,player_id' },
			);
			if (error) {
				const r = new Map(rsvpMap);
				if (previous === null) r.delete(eventId);
				else r.set(eventId, previous);
				rsvpMap = r;
				triggerToast('Fehler: ' + error.message);
				return;
			}
			triggerToast(next === 'yes' ? 'Zugesagt' : 'Abgesagt');
		}
	}

	// ── Event ausblenden ────────────────────────────────────────────────────────
	async function dismiss(eventId) {
		if (!$playerId) { triggerToast('Bitte zuerst anmelden'); return; }
		const wasDismissed = dismissedIds.has(eventId);
		if (wasDismissed) return;

		// Optimistic
		const s = new Set(dismissedIds);
		s.add(eventId);
		dismissedIds = s;

		const { error } = await sb.from('event_dismissals').upsert(
			{ event_id: eventId, player_id: $playerId },
			{ onConflict: 'event_id,player_id' },
		);
		if (error) {
			const r = new Set(dismissedIds);
			r.delete(eventId);
			dismissedIds = r;
			triggerToast('Fehler: ' + error.message);
			return;
		}
		triggerToast('Ausgeblendet');
	}

	// ── Detail-Sheet öffnen ─────────────────────────────────────────────────────
	function openSheet(ev) {
		sheetEvent = ev;
		sheetOpen  = true;
	}

	// ── ContextMenu-Aktionen pro Event ──────────────────────────────────────────
	function contextActionsFor(ev) {
		const r = rsvpFor(ev.id);
		return [
			{
				label: r === 'yes' ? 'Zusage zurücknehmen' : 'Zusagen',
				icon:  'check_circle',
				fn:    () => setRsvp(ev.id, 'yes'),
			},
			{
				label: r === 'no' ? 'Absage zurücknehmen' : 'Absagen',
				icon:  'cancel',
				fn:    () => setRsvp(ev.id, 'no'),
			},
			{
				label: 'Details öffnen',
				icon:  'info',
				fn:    () => openSheet(ev),
			},
			{
				label: 'Ausblenden',
				icon:  'visibility_off',
				fn:    () => dismiss(ev.id),
				destructive: true,
			},
		];
	}

	// ── Swipe-to-Hide (Pointer-Events, vanilla) ─────────────────────────────────
	const swipeState = new Map(); // event_id → { startX, startY, lastX, lastT, velocity, active, decided }
	const SWIPE_THRESHOLD_DIST = 80;     // px nach links → hide
	const SWIPE_THRESHOLD_FAST = 40;     // px nach links + velocity > 0.4 → hide
	const HORIZ_LOCK_THRESH    = 8;      // px bevor Achse entschieden wird

	function setOffset(eventId, dx) {
		const m = new Map(swipeOffsets);
		if (dx === 0) m.delete(eventId);
		else m.set(eventId, dx);
		swipeOffsets = m;
	}

	function onSwipeDown(eventId, e) {
		if (e.pointerType === 'mouse' && e.button !== 0) return;
		swipeState.set(eventId, {
			startX:   e.clientX,
			startY:   e.clientY,
			lastX:    e.clientX,
			lastT:    Date.now(),
			velocity: 0,
			active:   false,
			decided:  false,
			captured: false,
		});
	}

	function onSwipeMove(eventId, e) {
		const st = swipeState.get(eventId);
		if (!st) return;
		const dx = e.clientX - st.startX;
		const dy = e.clientY - st.startY;

		if (!st.decided) {
			if (Math.abs(dx) < HORIZ_LOCK_THRESH && Math.abs(dy) < HORIZ_LOCK_THRESH) return;
			// Achse festlegen
			if (Math.abs(dx) > Math.abs(dy)) {
				st.decided = true;
				st.active  = true;
				try { e.currentTarget.setPointerCapture(e.pointerId); st.captured = true; } catch {}
			} else {
				// vertikal-dominant: Geste an Layout-Scroll abgeben
				st.decided = true;
				st.active  = false;
			}
		}

		if (!st.active) return;

		// Velocity tracken
		const now = Date.now();
		const dt  = now - st.lastT;
		if (dt > 0) st.velocity = (e.clientX - st.lastX) / dt;
		st.lastX = e.clientX;
		st.lastT = now;

		// Nur nach links translaten; nach rechts leicht resistant
		const offset = dx < 0 ? dx : dx * 0.18;
		setOffset(eventId, offset);
		try { e.preventDefault(); } catch {}
	}

	function onSwipeUp(eventId, e) {
		const st = swipeState.get(eventId);
		if (!st) return;
		swipeState.delete(eventId);

		if (!st.active) {
			setOffset(eventId, 0);
			return;
		}

		const dx = e.clientX - st.startX;
		const v  = st.velocity; // negativ wenn nach links

		const shouldHide =
			dx < -SWIPE_THRESHOLD_DIST ||
			(dx < -SWIPE_THRESHOLD_FAST && v < -0.4);

		if (shouldHide) {
			// off-screen wischen, dann hide
			setOffset(eventId, -window.innerWidth);
			setTimeout(() => {
				dismiss(eventId);
				setOffset(eventId, 0); // reset (Card verschwindet ohnehin via filter)
			}, 180);
		} else {
			// zurückfedern
			setOffset(eventId, 0);
		}
	}

	function onSwipeCancel(eventId) {
		swipeState.delete(eventId);
		setOffset(eventId, 0);
	}

	// ── Card-Tap (öffnet Sheet) ─────────────────────────────────────────────────
	function onCardKeydown(ev, e) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			openSheet(ev);
		}
	}

	// ── RSVP-Pill Click (mit stopPropagation) ───────────────────────────────────
	function onPillClick(eventId, response, e) {
		e.stopPropagation();
		setRsvp(eventId, response);
	}

	function onPillKeydown(eventId, response, e) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			e.stopPropagation();
			setRsvp(eventId, response);
		}
	}
</script>

{#if loading || visibleEvents.length > 0 || allDismissed}
<div class="ue">
	<div class="ue-header">
		<div class="ue-header-left">
			<span class="material-symbols-outlined ue-icon">celebration</span>
			<h3 class="ue-title">Events</h3>
		</div>
		{#if events.length > 0}
			<button class="ue-more" onclick={() => goto('/kalender')}>
				Alle <span class="material-symbols-outlined" style="font-size:0.9rem">chevron_right</span>
			</button>
		{/if}
	</div>

	{#if loading}
		<div class="ue-list">
			{#each [0,1] as _}
				<div class="ue-item ue-item--skel">
					<div class="ue-item-date-col">
						<div class="skel-bar shimmer-box" style="width:24px;height:10px;border-radius:3px"></div>
						<div class="skel-bar shimmer-box" style="width:18px;height:18px;border-radius:4px;margin-top:2px"></div>
					</div>
					<div class="ue-item-body">
						<div class="skel-bar shimmer-box" style="width:70%;height:13px;border-radius:5px"></div>
						<div class="skel-bar shimmer-box" style="width:50%;height:10px;border-radius:4px;margin-top:4px"></div>
					</div>
				</div>
			{/each}
		</div>
	{:else if allDismissed}
		<button class="ue-empty" onclick={() => goto('/kalender')}>
			<span class="material-symbols-outlined">visibility_off</span>
			<span>Alle Events ausgeblendet · Tippe auf „Alle“ um sie wieder einzublenden</span>
		</button>
	{:else}
		<div class="ue-list">
			{#each visibleEvents as ev (ev.id)}
				{@const d  = new Date(ev.date + 'T12:00')}
				{@const r  = rsvpFor(ev.id)}
				{@const dx = swipeOffsets.get(ev.id) ?? 0}
				{@const showSwipeBg = dx < -SWIPE_THRESHOLD_FAST}

				<div class="ue-row">
					<!-- Hintergrund (rotes „Ausblenden") sichtbar wenn nach links gewischt -->
					<div class="ue-swipe-bg" class:ue-swipe-bg--armed={showSwipeBg}>
						<span class="material-symbols-outlined">visibility_off</span>
						<span class="ue-swipe-bg-label">Ausblenden</span>
					</div>

					<ContextMenu actions={contextActionsFor(ev)}>
						<div
							class="ue-item"
							class:ue-item--swiping={dx !== 0}
							style:transform="translateX({dx}px)"
							role="button"
							tabindex="0"
							aria-label="Event-Details öffnen: {ev.title}"
							onclick={() => openSheet(ev)}
							onkeydown={(e) => onCardKeydown(ev, e)}
							onpointerdown={(e) => onSwipeDown(ev.id, e)}
							onpointermove={(e)  => onSwipeMove(ev.id, e)}
							onpointerup={(e)    => onSwipeUp(ev.id, e)}
							onpointercancel={() => onSwipeCancel(ev.id)}
						>
							<div class="ue-item-date-col">
								<span class="ue-day">{DAY_SHORT[d.getDay()]}</span>
								<span class="ue-num">{d.getDate()}</span>
								<span class="ue-mon">{MONTH_SHORT[d.getMonth()]}</span>
							</div>
							<div class="ue-item-body">
								<span class="ue-item-title">{ev.title}</span>
								<span class="ue-item-meta">
									{#if ev.time}{fmtTime(ev.time)}{/if}
									{#if ev.location} · {ev.location}{/if}
								</span>
							</div>
							<div class="ue-rsvp">
								<!-- svelte-ignore a11y_no_static_element_interactions -->
								<span
									class="ue-pill ue-pill--yes"
									class:ue-pill--active={r === 'yes'}
									role="button"
									tabindex="0"
									aria-label={r === 'yes' ? 'Zusage zurücknehmen' : 'Zusagen'}
									aria-pressed={r === 'yes'}
									onclick={(e) => onPillClick(ev.id, 'yes', e)}
									onkeydown={(e) => onPillKeydown(ev.id, 'yes', e)}
									onpointerdown={(e) => e.stopPropagation()}
								>
									<span class="material-symbols-outlined">check</span>
								</span>
								<!-- svelte-ignore a11y_no_static_element_interactions -->
								<span
									class="ue-pill ue-pill--no"
									class:ue-pill--active={r === 'no'}
									role="button"
									tabindex="0"
									aria-label={r === 'no' ? 'Absage zurücknehmen' : 'Absagen'}
									aria-pressed={r === 'no'}
									onclick={(e) => onPillClick(ev.id, 'no', e)}
									onkeydown={(e) => onPillKeydown(ev.id, 'no', e)}
									onpointerdown={(e) => e.stopPropagation()}
								>
									<span class="material-symbols-outlined">close</span>
								</span>
							</div>
						</div>
					</ContextMenu>
				</div>
			{/each}
		</div>
	{/if}
</div>
{/if}

<EventDetailSheet
	bind:open={sheetOpen}
	event={sheetEvent}
	onEdited={load}
	onDeleted={load}
/>

<style>
	.ue {
		padding: 0 var(--space-5);
		margin: var(--space-2) 0;
	}
	.ue-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.ue-header-left {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.ue-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.ue-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}
	.ue-more {
		display: flex;
		align-items: center;
		gap: 2px;
		border: none;
		background: none;
		font: inherit;
		font-size: var(--text-label-md);
		font-weight: 600;
		color: var(--color-primary);
		cursor: pointer;
		padding: 4px 6px;
		border-radius: var(--radius-md);
	}
	.ue-more:active { opacity: 0.7; }

	.ue-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	/* Wrapper hält Hintergrund (Swipe-Hint) + Card übereinander */
	.ue-row {
		position: relative;
		border-radius: var(--radius-lg);
		overflow: hidden;
		isolation: isolate;
	}

	.ue-swipe-bg {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-2);
		padding: 0 var(--space-5);
		background: var(--color-primary);
		color: #fff;
		opacity: 0;
		transition: opacity 120ms ease;
		z-index: 0;
	}
	.ue-swipe-bg--armed { opacity: 1; }
	.ue-swipe-bg .material-symbols-outlined {
		font-size: 1.25rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.ue-swipe-bg-label {
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 700;
		letter-spacing: 0.02em;
	}

	.ue-item {
		position: relative;
		z-index: 1;
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		touch-action: pan-y;
		user-select: none;
	}
	.ue-item:not(.ue-item--swiping):active { transform: scale(0.997); }
	.ue-item--swiping { transition: none; }
	.ue-item:not(.ue-item--swiping) {
		transition: transform 220ms cubic-bezier(0.32, 0.72, 0, 1);
	}
	.ue-item--skel {
		pointer-events: none;
		cursor: default;
	}

	.ue-item-date-col {
		width: 40px;
		display: flex;
		flex-direction: column;
		align-items: center;
		flex-shrink: 0;
	}
	.ue-day {
		font-size: 0.6rem;
		font-weight: 700;
		text-transform: uppercase;
		color: var(--color-primary);
		letter-spacing: 0.03em;
	}
	.ue-num {
		font-family: var(--font-display);
		font-size: 1.15rem;
		font-weight: 800;
		color: var(--color-on-surface);
		line-height: 1.1;
	}
	.ue-mon {
		font-size: 0.55rem;
		font-weight: 600;
		color: var(--color-outline);
		text-transform: uppercase;
	}

	.ue-item-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.ue-item-title {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.ue-item-meta {
		font-size: var(--text-label-md);
		color: var(--color-on-surface-variant);
	}

	/* Inline-RSVP-Pills */
	.ue-rsvp {
		display: flex;
		gap: 6px;
		flex-shrink: 0;
	}
	.ue-pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-full);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-lowest);
		color: var(--color-on-surface-variant);
		cursor: pointer;
		transition: background 150ms ease, border-color 150ms ease, color 150ms ease, transform 80ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.ue-pill:active { transform: scale(0.92); }
	.ue-pill .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 20;
	}
	.ue-pill--yes.ue-pill--active {
		background: var(--color-secondary);
		border-color: var(--color-secondary);
		color: #fff;
	}
	.ue-pill--no.ue-pill--active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: #fff;
	}

	/* Empty-State (alle ausgeblendet) */
	.ue-empty {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container);
		border: none;
		border-radius: var(--radius-lg);
		font: inherit;
		font-size: var(--text-label-md);
		color: var(--color-on-surface-variant);
		text-align: left;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.ue-empty:active { opacity: 0.7; }
	.ue-empty .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-primary);
		flex-shrink: 0;
	}
</style>
