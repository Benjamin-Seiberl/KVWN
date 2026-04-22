<script>
	import { onMount }    from 'svelte';
	import { goto }       from '$app/navigation';
	import { sb }         from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { setSubtab }  from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { leagueTiming, offsetTime, shortTime } from '$lib/utils/league.js';
	import { imgPath, shortName, BLANK_IMG }        from '$lib/utils/players.js';
	import { toDateStr, fmtDate, DAY_SHORT }        from '$lib/utils/dates.js';
	import BottomSheet    from '$lib/components/BottomSheet.svelte';
	import CarpoolCard    from '$lib/components/spielbetrieb/CarpoolCard.svelte';
	import TrainingDetailSheet from '$lib/components/kalender/TrainingDetailSheet.svelte';
	import MatchDetailSheet    from '$lib/components/kalender/MatchDetailSheet.svelte';
	import EventDetailSheet    from '$lib/components/kalender/EventDetailSheet.svelte';

	// ── Date helpers ─────────────────────────────────────────────────────────
	function daysUntilLabel(dateStr) {
		const now = new Date(); now.setHours(0,0,0,0);
		const d   = Math.round((new Date(dateStr + 'T00:00:00') - now) / 86400000);
		if (d === 0) return 'Heute';
		if (d === 1) return 'Morgen';
		if (d < 0)   return null;
		return `in ${d} Tagen`;
	}

	function fmt(y, m, d) {
		return `${y}-${String(m+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
	}

	// ── State ─────────────────────────────────────────────────────────────────
	let heroEvent      = $state(null);
	let upcomingEvents = $state([]);
	let matches        = $state([]);
	let pastMatches    = $state([]);
	let templates      = $state([]);
	let nextOverrides  = $state([]);
	let nextSpecials   = $state([]);
	let nextBookings   = $state([]);
	let keyDuties      = $state([]);
	let allPlayers     = $state([]);
	let loading        = $state(true);

	// Carpool sheet (lazy-loaded per match)
	let carpoolSheetOpen   = $state(false);
	let carpoolSheetMatch  = $state(null);
	let carpoolSheetData   = $state([]);
	let carpoolSheetMeetup = $state(null);
	let carpoolLoading     = $state(false);

	// Key duty swap sheet
	let keySheetOpen = $state(false);
	let keySheetItem = $state(null); // { date, start_time, currentPlayerId }

	// Training detail sheet
	let trSheetOpen = $state(false);
	let trSheetDate = $state(null);
	function openTrSheet(date) {
		trSheetDate = date;
		trSheetOpen = true;
	}

	// Match + event detail sheets
	let matchSheetOpen = $state(false);
	let matchSheetData = $state(null);
	function openMatchSheet(m) { matchSheetData = m; matchSheetOpen = true; }

	let eventSheetOpen = $state(false);
	let eventSheetData = $state(null);
	function openEventSheet(e) { eventSheetData = e; eventSheetOpen = true; }

	// ── Date range constants ──────────────────────────────────────────────────
	const today  = toDateStr(new Date());
	const plus14 = toDateStr(new Date(Date.now() + 14 * 86400000));
	const minus2 = toDateStr(new Date(Date.now() - 2 * 86400000));

	// ── Training expansion (same logic as +page.svelte) ───────────────────────
	const nextTrainings = $derived.by(() => {
		const sessions = [];
		const base = new Date(); base.setHours(0,0,0,0);
		for (let i = 0; i < 14; i++) {
			const d   = new Date(base); d.setDate(base.getDate() + i);
			const dow = d.getDay();
			const key = fmt(d.getFullYear(), d.getMonth(), d.getDate());

			for (const tpl of templates.filter(t => t.day_of_week === dow)) {
				const sh = Number(String(tpl.start_time).slice(0,2));
				const eh = Number(String(tpl.end_time).slice(0,2));
				for (let h = sh; h < eh; h++) {
					const startTime = `${String(h).padStart(2,'0')}:00`;
					const endTime   = `${String(h+1).padStart(2,'0')}:00`;
					const ov = nextOverrides.find(o => o.date === key && String(o.start_time).slice(0,5) === startTime);
					if (ov?.closed) continue;
					sessions.push({ date: key, dateObj: d, start_time: startTime, end_time: endTime, capacity: tpl.lane_count, note: ov?.note ?? null });
				}
			}

			for (const sp of nextSpecials.filter(s => s.date === key)) {
				sessions.push({
					date: key, dateObj: d,
					start_time: String(sp.start_time).slice(0,5),
					end_time:   String(sp.end_time).slice(0,5),
					capacity:   sp.capacity,
					note:       sp.note ?? null,
					special:    true,
				});
			}
		}
		sessions.sort((a,b) =>
			a.date === b.date
				? a.start_time.localeCompare(b.start_time)
				: a.date.localeCompare(b.date)
		);
		return sessions;
	});

	// Group slots by day for feed (one row per day)
	const nextTrainingDays = $derived.by(() => {
		const map = new Map();
		for (const s of nextTrainings) {
			if (!map.has(s.date)) map.set(s.date, { date: s.date, dateObj: s.dateObj, slots: [] });
			map.get(s.date).slots.push(s);
		}
		return [...map.values()];
	});

	function dayRatio(day) {
		if (!day.slots.length) return 0;
		const rs = day.slots.map(s => s.capacity > 0 ? bookingsFor(s.date, s.start_time) / s.capacity : 0);
		return rs.reduce((a,b) => a + b, 0) / rs.length;
	}

	// ── Occupancy helpers ─────────────────────────────────────────────────────
	function bookingsFor(date, startTime) {
		return nextBookings.filter(b => b.date === date && String(b.start_time).slice(0,5) === startTime).length;
	}

	function occRatio(date, startTime, laneCount) {
		return laneCount > 0 ? bookingsFor(date, startTime) / laneCount : 0;
	}

	function occColor(ratio) {
		if (ratio < 0.5)  return '#16a34a';
		if (ratio < 0.85) return '#ea580c';
		return '#dc2626';
	}

	// ── Key duty helpers ──────────────────────────────────────────────────────
	function keyDutyFor(date, startTime) {
		return keyDuties.find(k => k.date === date && String(k.start_time).slice(0,5) === startTime) ?? null;
	}

	function keyDutyPlayerName(duty) {
		return duty?.players?.name ?? null;
	}

	// ── Birthday pills ────────────────────────────────────────────────────────
	const birthdayPills = $derived.by(() => {
		const now = new Date(); now.setHours(0,0,0,0);
		const pills = [];
		for (const p of allPlayers) {
			if (!p.birth_date) continue;
			const [by, bm, bd] = p.birth_date.split('-').map(Number);
			let bday = new Date(now.getFullYear(), bm - 1, bd);
			if (bday < now) bday = new Date(now.getFullYear() + 1, bm - 1, bd);
			const diff = Math.round((bday - now) / 86400000);
			if (diff >= 0 && diff < 14) {
				pills.push({ date: toDateStr(bday), name: p.name, age: bday.getFullYear() - by });
			}
		}
		return pills;
	});

	// ── Match-end check ───────────────────────────────────────────────────────
	function matchEnded(m) {
		if (!m?.time) return false;
		const timing  = leagueTiming(m.leagues?.name ?? '');
		const endStr  = offsetTime(m.time, timing.matchDurationMin);
		if (!endStr) return false;
		const [eh, em] = endStr.split(':').map(Number);
		const end = new Date(m.date + 'T00:00:00');
		end.setHours(eh, em + 10, 0, 0);
		return new Date() >= end;
	}

	function matchHasScores(m) {
		return (m.game_plans ?? []).some(gp =>
			(gp.game_plan_players ?? []).some(p => p.score != null)
		);
	}

	// ── Action card derived ───────────────────────────────────────────────────
	const urgentTournament = $derived(
		matches.find(m =>
			m.registration_deadline &&
			m.registration_deadline >= today &&
			m.registration_deadline <= plus14 &&
			m.tournament_status !== 'confirmed'
		) ?? null
	);

	const resultNudgeMatch = $derived.by(() => {
		if ($playerRole !== 'kapitaen') return null;
		return pastMatches.find(m => matchEnded(m) && !matchHasScores(m)) ?? null;
	});

	// ── Hub card derived ──────────────────────────────────────────────────────
	const nextMatch      = $derived(matches[0] ?? null);
	const nextTrainingDay = $derived(nextTrainingDays[0] ?? null);
	const eventCount     = $derived(upcomingEvents.length);
	const nextEventDays  = $derived(upcomingEvents.length ? daysUntilLabel(upcomingEvents[0].date) : null);

	// ── 14-day feed ───────────────────────────────────────────────────────────
	const feedItems = $derived.by(() => {
		const items = [];
		for (const ev of upcomingEvents)
			items.push({ type: 'event',    sortKey: ev.date + 'T' + (ev.time ?? '23:59'), data: ev });
		for (const m of matches)
			items.push({ type: 'match',    sortKey: m.date  + 'T' + (m.time  ?? '23:59'), data: m  });
		for (const day of nextTrainingDays)
			items.push({ type: 'training', sortKey: day.date + 'T' + day.slots[0].start_time, data: day });
		for (const bp of birthdayPills)
			items.push({ type: 'birthday', sortKey: bp.date + 'T12:00',                    data: bp });
		if ($playerRole === 'kapitaen') {
			for (const m of pastMatches) {
				if (matchEnded(m) && !matchHasScores(m))
					items.push({ type: 'result-nudge', sortKey: m.date + 'T' + (m.time ?? '23:59'), data: m });
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

	// ── Key duty actions ──────────────────────────────────────────────────────
	async function takeKeyDuty(date, startTime) {
		if (!$playerId) return;
		keyDuties = [
			...keyDuties.filter(k => !(k.date === date && String(k.start_time).slice(0,5) === startTime)),
			{ date, start_time: startTime, player_id: $playerId, players: { name: '' } },
		];
		const { error } = await sb.from('training_key_duties').upsert({ date, start_time: startTime, player_id: $playerId });
		if (error) {
			triggerToast('Fehler beim Übernehmen');
			loadData();
		} else {
			triggerToast('Schlüssel-Dienst übernommen');
			const { data } = await sb.from('training_key_duties').select('date, start_time, player_id, players(name)').eq('date', date).eq('start_time', startTime).maybeSingle();
			if (data) keyDuties = [...keyDuties.filter(k => !(k.date === date && String(k.start_time).slice(0,5) === startTime)), data];
		}
	}

	async function releaseKeyDuty(date, startTime) {
		keyDuties = keyDuties.filter(k => !(k.date === date && String(k.start_time).slice(0,5) === startTime));
		const { error } = await sb.from('training_key_duties').delete().eq('date', date).eq('start_time', startTime);
		if (error) { triggerToast('Fehler beim Freigeben'); loadData(); }
		else        { triggerToast('Schlüssel-Dienst freigegeben'); }
	}

	function openKeySwapSheet(date, startTime, currentPlayerId) {
		keySheetItem = { date, start_time: startTime, currentPlayerId };
		keySheetOpen = true;
	}

	async function swapKeyDuty() {
		if (!keySheetItem) return;
		await releaseKeyDuty(keySheetItem.date, keySheetItem.start_time);
		await takeKeyDuty(keySheetItem.date, keySheetItem.start_time);
		keySheetOpen = false;
	}

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

	// ── Data loading ──────────────────────────────────────────────────────────
	async function loadData() {
		loading = true;
		const pid = $playerId;
		const queries = [
			sb.from('events').select('id, title, date, time, location').gte('date', today).order('date').limit(1),
			sb.from('events').select('id, title, date, time, location').gte('date', today).lte('date', plus14).order('date'),
			sb.from('matches')
				.select('id, date, time, opponent, home_away, is_tournament, is_landesbewerb, tournament_title, tournament_status, registration_deadline, league_id, leagues(name)')
				.gte('date', today).lte('date', plus14).order('date'),
			sb.from('matches')
				.select('id, date, time, opponent, home_away, league_id, leagues(name), game_plans(id, game_plan_players(score, played))')
				.gte('date', minus2).lt('date', today).order('date'),
			sb.from('training_templates').select('*').eq('active', true),
			sb.from('training_overrides').select('*').gte('date', today).lte('date', plus14),
			sb.from('training_specials').select('*').gte('date', today).lte('date', plus14),
			sb.from('training_bookings').select('date, start_time, player_id').gte('date', today).lte('date', plus14),
			sb.from('training_key_duties').select('date, start_time, player_id, players(name)').gte('date', today).lte('date', plus14),
			sb.from('players').select('id, name, photo, birth_date').not('birth_date', 'is', null),
		];
		const results = await Promise.all(queries);
		heroEvent      = results[0].data?.[0] ?? null;
		upcomingEvents = results[1].data ?? [];
		matches        = results[2].data ?? [];
		pastMatches    = results[3].data ?? [];
		templates      = results[4].data ?? [];
		nextOverrides  = results[5].data ?? [];
		nextSpecials   = results[6].data ?? [];
		nextBookings   = results[7].data ?? [];
		keyDuties      = results[8].data ?? [];
		allPlayers     = results[9].data ?? [];
		loading        = false;
	}

	onMount(loadData);
</script>

<!-- ── Loading ──────────────────────────────────────────────────────────────── -->
{#if loading}
	<div class="ueb-loading">
		<div class="ueb-skeleton shimmer-box"></div>
		<div class="ueb-skeleton ueb-skeleton--short shimmer-box"></div>
		<div class="ueb-skeleton shimmer-box"></div>
	</div>

{:else}
<div class="ueb-page">

	<!-- ── Section 1: Hero Event ────────────────────────────────────────────── -->
	{#if heroEvent}
		{@const du = daysUntilLabel(heroEvent.date)}
		<button class="hero-card" onclick={() => openEventSheet(heroEvent)}>
			<span class="hero-eyebrow">Nächstes Event</span>
			<h2 class="hero-title">{heroEvent.title}</h2>
			<div class="hero-meta">
				<span class="material-symbols-outlined hero-meta-icon">calendar_today</span>
				<span>{fmtDate(heroEvent.date)}{heroEvent.time ? ' · ' + shortTime(heroEvent.time) + ' Uhr' : ''}</span>
				{#if heroEvent.location}
					<span class="hero-sep">·</span>
					<span class="material-symbols-outlined hero-meta-icon">location_on</span>
					<span>{heroEvent.location}</span>
				{/if}
			</div>
			{#if du}<span class="hero-badge">{du}</span>{/if}
		</button>
	{/if}

	<!-- ── Section 2: Action Cards ──────────────────────────────────────────── -->
	{#if urgentTournament || resultNudgeMatch}
		<div class="action-cards">

			{#if urgentTournament}
				<button class="action-card action-card--gold" onclick={() => setSubtab('/spielbetrieb', 'turnier')}>
					<span class="material-symbols-outlined action-icon">military_tech</span>
					<div class="action-body">
						<span class="action-title">Anmeldefrist läuft ab</span>
						<span class="action-sub">{urgentTournament.tournament_title ?? urgentTournament.opponent}</span>
						<span class="action-sub">Frist: {fmtDate(urgentTournament.registration_deadline)}</span>
					</div>
					<span class="action-cta">Ansehen →</span>
				</button>
			{/if}

			{#if resultNudgeMatch}
				<button class="action-card action-card--blue" onclick={() => { goto('/profil'); setSubtab('/profil', 'admin'); }}>
					<span class="material-symbols-outlined action-icon">edit_note</span>
					<div class="action-body">
						<span class="action-title">Ergebnis eintragen</span>
						<span class="action-sub">{resultNudgeMatch.opponent} · {fmtDate(resultNudgeMatch.date)}</span>
						{#if resultNudgeMatch.time}
							<span class="action-sub">Spielende: {shortTime(offsetTime(resultNudgeMatch.time, leagueTiming(resultNudgeMatch.leagues?.name ?? '').matchDurationMin))}</span>
						{/if}
					</div>
					<span class="action-cta">Eintragen →</span>
				</button>
			{/if}

		</div>
	{/if}

	<!-- ── Section 3: Hub Cards ─────────────────────────────────────────────── -->
	<div class="hub-row">

		<button class="hub-card" onclick={() => nextTrainingDay && openTrSheet(nextTrainingDay.date)} disabled={!nextTrainingDay}>
			<span class="material-symbols-outlined hub-icon">fitness_center</span>
			<span class="hub-label">Training</span>
			{#if nextTrainingDay}
				{@const ratio = dayRatio(nextTrainingDay)}
				{@const first = nextTrainingDay.slots[0]}
				<span class="hub-info">{DAY_SHORT[nextTrainingDay.dateObj.getDay()]} · {first.start_time}</span>
				<div class="hub-bar" style="--bar-ratio:{ratio}; --bar-color:{occColor(ratio)}"></div>
			{:else}
				<span class="hub-info hub-info--muted">Kein Training</span>
			{/if}
		</button>

		<button class="hub-card" onclick={() => heroEvent && openEventSheet(heroEvent)} disabled={!heroEvent}>
			<span class="material-symbols-outlined hub-icon">calendar_month</span>
			<span class="hub-label">Events</span>
			{#if eventCount > 0}
				<span class="hub-info">{eventCount} {eventCount === 1 ? 'Event' : 'Events'}</span>
				{#if nextEventDays}<span class="hub-sub">{nextEventDays}</span>{/if}
			{:else}
				<span class="hub-info hub-info--muted">Keine Events</span>
			{/if}
		</button>

		<button class="hub-card" onclick={() => nextMatch && openMatchSheet(nextMatch)} disabled={!nextMatch}>
			<span class="material-symbols-outlined hub-icon">sports</span>
			<span class="hub-label">Spiele</span>
			{#if nextMatch}
				<span class="hub-info">{nextMatch.home_away === 'HEIM' ? 'vs.' : 'bei'} {nextMatch.opponent?.split(' ').slice(-1)[0]}</span>
				<span class="hub-sub">{fmtDate(nextMatch.date)}</span>
			{:else}
				<span class="hub-info hub-info--muted">Kein Spiel</span>
			{/if}
		</button>

	</div>

	<!-- ── Section 4: 14-day Feed ────────────────────────────────────────────── -->
	<div class="feed-section">
		<h3 class="feed-heading">
			<span class="material-symbols-outlined">date_range</span>
			Nächste 14 Tage
		</h3>

		{#if feedByDate.length === 0}
			<div class="feed-empty">
				<span class="material-symbols-outlined">event_available</span>
				<p>Keine Termine in den nächsten 14 Tagen</p>
			</div>
		{:else}
			<div class="feed-list">
				{#each feedByDate as group}
					<div class="feed-date-group">
						<span class="feed-date-chip">{fmtDate(group.date)}</span>
						<div class="feed-group-items">
							{#each group.items as item}

								{#if item.type === 'match'}
									{@const m = item.data}
									{@const isAway   = m.home_away !== 'HEIM'}
									{@const isTourney = m.is_tournament || m.is_landesbewerb}
									<button class="feed-item feed-item--match feed-item--btn" class:feed-item--tourney={isTourney} onclick={() => openMatchSheet(m)}>
										<span class="feed-item-icon material-symbols-outlined"
											style="color:{isTourney ? '#b45309' : '#1e3a5f'}"
										>{isTourney ? 'military_tech' : 'sports'}</span>
										<div class="feed-item-body">
											<span class="feed-item-title">
												{isTourney ? (m.tournament_title ?? m.opponent) : (m.home_away === 'HEIM' ? 'vs. ' : 'bei ') + m.opponent}
											</span>
											<span class="feed-item-sub">
												{#if m.time}{shortTime(m.time)} Uhr{/if}
												<span class="feed-chip feed-chip--home-away" class:feed-chip--away={isAway}>{m.home_away === 'HEIM' ? 'Heim' : 'Auswärts'}</span>
												{#if isTourney && m.registration_deadline === today}
													<span class="feed-chip feed-chip--red">Anmeldung heute!</span>
												{/if}
											</span>
										</div>
										{#if isAway && !isTourney}
											<span
												class="feed-action-btn"
												role="button"
												tabindex="0"
												onclick={(e) => { e.stopPropagation(); openCarpoolSheet(m); }}
												onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); openCarpoolSheet(m); } }}
											>
												<span class="material-symbols-outlined">directions_car</span>
												Fahrt
											</span>
										{/if}
									</button>

								{:else if item.type === 'training'}
									{@const day   = item.data}
									{@const first = day.slots[0]}
									{@const last  = day.slots[day.slots.length - 1]}
									{@const ratio = dayRatio(day)}
									{@const duty  = keyDutyFor(day.date, first.start_time)}
									{@const isMe  = duty?.player_id === $playerId}
									<button class="feed-item feed-item--training feed-item--btn" onclick={() => openTrSheet(day.date)}>
										<span class="feed-item-icon material-symbols-outlined" style="color:var(--color-primary)">fitness_center</span>
										<div class="feed-item-body">
											<span class="feed-item-title">Training</span>
											<span class="feed-item-sub">{first.start_time} – {last.end_time} Uhr</span>
											<div class="feed-occ-bar" style="--bar-ratio:{ratio}; --bar-color:{occColor(ratio)}"></div>
										</div>
										{#if !duty}
											<span
												class="feed-key-chip feed-key-chip--free"
												role="button"
												tabindex="0"
												onclick={(e) => { e.stopPropagation(); takeKeyDuty(day.date, first.start_time); }}
												onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); takeKeyDuty(day.date, first.start_time); } }}
											>
												<span class="material-symbols-outlined">key</span>frei
											</span>
										{:else if isMe}
											<span
												class="feed-key-chip feed-key-chip--me"
												role="button"
												tabindex="0"
												onclick={(e) => { e.stopPropagation(); releaseKeyDuty(day.date, first.start_time); }}
												onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); releaseKeyDuty(day.date, first.start_time); } }}
											>
												<span class="material-symbols-outlined">key</span>Ich
											</span>
										{:else}
											<span
												class="feed-key-chip feed-key-chip--other"
												role="button"
												tabindex="0"
												onclick={(e) => { e.stopPropagation(); openKeySwapSheet(day.date, first.start_time, duty.player_id); }}
												onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); openKeySwapSheet(day.date, first.start_time, duty.player_id); } }}
											>
												<span class="material-symbols-outlined">key</span>{keyDutyPlayerName(duty)?.split(' ').pop() ?? '?'}
											</span>
										{/if}
									</button>

								{:else if item.type === 'event'}
									{@const ev = item.data}
									<button class="feed-item feed-item--event feed-item--btn" onclick={() => openEventSheet(ev)}>
										<span class="feed-item-icon material-symbols-outlined" style="color:#14532d">event</span>
										<div class="feed-item-body">
											<span class="feed-item-title">{ev.title}</span>
											<span class="feed-item-sub">
												{#if ev.time}{shortTime(ev.time)} Uhr{/if}
												{#if ev.location}<span class="feed-item-loc"><span class="material-symbols-outlined">location_on</span>{ev.location}</span>{/if}
											</span>
										</div>
									</button>

								{:else if item.type === 'birthday'}
									{@const bp = item.data}
									<div class="feed-item feed-item--birthday">
										<span class="feed-item-icon material-symbols-outlined" style="color:#f472b6">cake</span>
										<span class="feed-item-title feed-birthday-text">{bp.name} wird {bp.age}</span>
									</div>

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

<!-- ── Carpool BottomSheet ──────────────────────────────────────────────────── -->
<BottomSheet bind:open={carpoolSheetOpen} title="Fahrgemeinschaft">
	{#if carpoolLoading}
		<div class="sheet-loading">
			<span class="material-symbols-outlined sheet-loading-icon">directions_car</span>
			<p>Lädt…</p>
		</div>
	{:else if carpoolSheetMatch}
		<CarpoolCard match={carpoolSheetMatch} meetup={carpoolSheetMeetup} carpools={carpoolSheetData} onChanged={() => openCarpoolSheet(carpoolSheetMatch)} />
	{/if}
</BottomSheet>

<!-- ── Training detail BottomSheet ─────────────────────────────────────────── -->
<TrainingDetailSheet bind:open={trSheetOpen} date={trSheetDate} onReload={loadData} />

<!-- ── Match + Event detail BottomSheets ───────────────────────────────────── -->
<MatchDetailSheet bind:open={matchSheetOpen} match={matchSheetData} />
<EventDetailSheet bind:open={eventSheetOpen} event={eventSheetData} />

<!-- ── Key duty swap BottomSheet ────────────────────────────────────────────── -->
<BottomSheet bind:open={keySheetOpen} title="Schlüssel-Dienst">
	{#if keySheetItem}
		{@const duty = keyDutyFor(keySheetItem.date, keySheetItem.start_time)}
		<p class="key-sheet-text"><strong>{keyDutyPlayerName(duty) ?? 'Jemand'}</strong> hat aktuell den Schlüssel-Dienst.</p>
		<button class="key-sheet-btn key-sheet-btn--swap" onclick={swapKeyDuty}>
			<span class="material-symbols-outlined">swap_horiz</span>Dienst übernehmen
		</button>
		<button class="key-sheet-btn key-sheet-btn--cancel" onclick={() => keySheetOpen = false}>Abbrechen</button>
	{/if}
</BottomSheet>

<style>
	.ueb-page { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-5); }

	.ueb-loading { padding: var(--space-5); display: flex; flex-direction: column; gap: var(--space-4); }
	.ueb-skeleton { height: 80px; border-radius: var(--radius-lg); }
	.ueb-skeleton--short { height: 48px; }

	/* Hero */
	.hero-card {
		position: relative; width: 100%; text-align: left;
		background: linear-gradient(135deg, #14532d 0%, #166534 40%, #15803d 100%);
		border-radius: var(--radius-xl, 20px); padding: var(--space-5) var(--space-5) var(--space-6);
		color: #fff; box-shadow: 0 8px 28px rgba(20,83,45,0.35); border: none; cursor: pointer;
		-webkit-tap-highlight-color: transparent; transition: transform 120ms ease, box-shadow 120ms ease; overflow: hidden;
	}
	.hero-card::before {
		content: ''; position: absolute; inset: 0;
		background: radial-gradient(ellipse at 80% 20%, rgba(255,255,255,0.08) 0%, transparent 60%); pointer-events: none;
	}
	.hero-card:active { transform: scale(0.98); box-shadow: 0 4px 16px rgba(20,83,45,0.28); }
	.hero-eyebrow { display: block; font-size: var(--text-label-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; opacity: 0.75; margin-bottom: var(--space-2); }
	.hero-title { font-family: var(--font-display); font-size: 1.35rem; font-weight: 800; line-height: 1.2; margin: 0 0 var(--space-3); }
	.hero-meta { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-label-md); opacity: 0.85; flex-wrap: wrap; }
	.hero-meta-icon { font-size: 0.9rem; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20; }
	.hero-sep { opacity: 0.5; }
	.hero-badge { position: absolute; top: var(--space-4); right: var(--space-4); background: rgba(255,255,255,0.18); backdrop-filter: blur(4px); border: 1px solid rgba(255,255,255,0.25); border-radius: 999px; padding: 3px 10px; font-size: var(--text-label-sm); font-weight: 700; }

	/* Action Cards */
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
	.action-body { flex: 1; display: flex; flex-direction: column; gap: 2px; }
	.action-title { font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); }
	.action-sub   { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); }
	.action-cta   { font-size: var(--text-label-sm); font-weight: 700; flex-shrink: 0; }
	.action-card--warn .action-cta, .action-card--gold .action-cta { color: #92400e; }
	.action-card--blue .action-cta { color: #1d4ed8; }

	/* Hub Row */
	.hub-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); }
	.hub-card { display: flex; flex-direction: column; align-items: flex-start; gap: 3px; padding: var(--space-4) var(--space-3); background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); border: 1.5px solid var(--color-outline-variant); box-shadow: var(--shadow-card); cursor: pointer; -webkit-tap-highlight-color: transparent; text-align: left; transition: transform 100ms ease; overflow: hidden; }
	.hub-card:active { transform: scale(0.96); }
	.hub-icon  { font-size: 1.2rem; color: var(--color-primary); font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; margin-bottom: 2px; }
	.hub-label { font-family: var(--font-display); font-size: var(--text-label-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-on-surface); }
	.hub-info  { font-size: 0.68rem; font-weight: 600; color: var(--color-on-surface-variant); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }
	.hub-info--muted { opacity: 0.5; }
	.hub-sub   { font-size: 0.62rem; color: var(--color-outline); }
	.hub-bar   { width: 100%; height: 4px; background: rgba(0,0,0,0.06); border-radius: 2px; margin-top: 4px; position: relative; overflow: hidden; }
	.hub-bar::after { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: calc(var(--bar-ratio, 0) * 100%); background: var(--bar-color, #16a34a); border-radius: 2px; transition: width 400ms ease; }

	/* Feed */
	.feed-section { display: flex; flex-direction: column; gap: var(--space-4); }
	.feed-heading { display: flex; align-items: center; gap: var(--space-2); font-family: var(--font-display); font-size: var(--text-title-sm); font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em; margin: 0; }
	.feed-heading .material-symbols-outlined { font-size: 1.1rem; color: var(--color-primary); font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.feed-empty { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.feed-empty .material-symbols-outlined { font-size: 2.5rem; opacity: 0.5; }
	.feed-list { display: flex; flex-direction: column; gap: var(--space-4); }
	.feed-date-group { display: flex; flex-direction: column; gap: var(--space-2); }
	.feed-date-chip { display: inline-flex; align-self: flex-start; background: var(--color-surface-container); border-radius: 999px; padding: 3px 10px; font-size: var(--text-label-sm); font-weight: 700; color: var(--color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.06em; }
	.feed-group-items { display: flex; flex-direction: column; gap: var(--space-2); }

	.feed-item { display: flex; align-items: center; gap: var(--space-3); background: var(--color-surface-container-lowest, #fff); border-radius: var(--radius-lg); padding: var(--space-3) var(--space-4); box-shadow: var(--shadow-card); border: 1.5px solid transparent; }
	.feed-item--btn { width: 100%; text-align: left; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; border: none; }
	.feed-item--btn:active { transform: scale(0.98); }
	.feed-item--match    { border-color: rgba(30,58,95,0.12); }
	.feed-item--tourney  { border-color: rgba(180,83,9,0.25); }
	.feed-item--training { border-color: rgba(204,0,0,0.1); }
	.feed-item--event    { border-color: rgba(20,83,45,0.15); }
	.feed-item--birthday { background: transparent; box-shadow: none; border: none; padding: var(--space-2) 0; }
	.feed-item--result-nudge { border-color: rgba(29,78,216,0.2); border-left: 3px solid #1d4ed8; }

	.feed-item-icon { font-size: 1.2rem; flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.feed-item-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.feed-item-title { font-weight: 700; font-size: var(--text-label-md); color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.feed-item-sub   { font-size: var(--text-label-sm); color: var(--color-on-surface-variant); display: flex; align-items: center; gap: var(--space-2); flex-wrap: wrap; }
	.feed-item-loc   { display: flex; align-items: center; gap: 2px; }
	.feed-item-loc .material-symbols-outlined { font-size: 0.8rem; }

	.feed-chip { display: inline-flex; border-radius: 999px; padding: 1px 7px; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; }
	.feed-chip--home-away { background: rgba(30,58,95,0.1); color: #1e3a5f; }
	.feed-chip--away      { background: rgba(30,58,95,0.18); }
	.feed-chip--red       { background: #fee2e2; color: #dc2626; }

	.feed-action-btn { display: flex; align-items: center; gap: 4px; padding: 5px 10px; border-radius: var(--radius-md); background: #dbeafe; color: #1d4ed8; border: none; font-size: var(--text-label-sm); font-weight: 700; cursor: pointer; flex-shrink: 0; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; }
	.feed-action-btn:active { transform: scale(0.94); }
	.feed-action-btn .material-symbols-outlined { font-size: 0.9rem; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20; }

	.feed-occ-bar { width: 100%; height: 4px; background: rgba(0,0,0,0.06); border-radius: 2px; position: relative; overflow: hidden; margin-top: 4px; }
	.feed-occ-bar::after { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: calc(var(--bar-ratio, 0) * 100%); background: var(--bar-color, #16a34a); border-radius: 2px; }

	.feed-key-chip { display: flex; align-items: center; gap: 3px; padding: 4px 8px; border-radius: var(--radius-md); font-size: var(--text-label-sm); font-weight: 700; border: none; cursor: pointer; flex-shrink: 0; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease; }
	.feed-key-chip:active { transform: scale(0.94); }
	.feed-key-chip .material-symbols-outlined { font-size: 0.85rem; }
	.feed-key-chip--free  { background: rgba(0,0,0,0.05); color: var(--color-on-surface-variant); }
	.feed-key-chip--me    { background: rgba(212,175,55,0.15); color: #92400e; }
	.feed-key-chip--other { background: rgba(0,0,0,0.07); color: var(--color-on-surface-variant); }

	.feed-birthday-text { font-size: var(--text-label-md); background: linear-gradient(90deg, #fde047, #fb923c, #f472b6); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; font-weight: 700; }

	/* Sheets */
	.sheet-loading { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-10) var(--space-4); color: var(--color-outline); }
	.sheet-loading-icon { font-size: 2rem; opacity: 0.4; }
	.key-sheet-text { font-size: var(--text-body-md); color: var(--color-on-surface-variant); text-align: center; padding: var(--space-4) 0 var(--space-6); }
	.key-sheet-btn { width: 100%; padding: var(--space-4); border-radius: var(--radius-lg); font-size: var(--text-label-md); font-weight: 700; cursor: pointer; border: none; margin-bottom: var(--space-3); -webkit-tap-highlight-color: transparent; display: flex; align-items: center; justify-content: center; gap: var(--space-2); }
	.key-sheet-btn--swap   { background: var(--color-primary); color: #fff; }
	.key-sheet-btn--cancel { background: var(--color-surface-container); color: var(--color-on-surface-variant); }
</style>
