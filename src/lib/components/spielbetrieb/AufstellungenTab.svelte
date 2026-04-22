<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { toDateStr, fmtDate, fmtTime, DAY_SHORT } from '$lib/utils/dates.js';
	import { imgPath } from '$lib/utils/players.js';
	import AdminAufstellung from '../admin/AdminAufstellung.svelte';
	import AbsenceSheet from '../dashboard/AbsenceSheet.svelte';

	let absenceOpen = $state(false);

	let editOpen    = $state(false);
	let editMatchId = $state(null);

	function openEdit(matchId) {
		editMatchId = matchId;
		editOpen    = true;
	}

	let wasEditOpen = false;
	$effect(() => {
		if (wasEditOpen && !editOpen) {
			editMatchId = null;
			load();
		}
		wasEditOpen = editOpen;
	});

	// Wochenbereich berechnen (Mo–So)
	function weekRange(offsetWeeks = 0) {
		const today = new Date();
		const day = today.getDay();
		const diffToMon = day === 0 ? -6 : 1 - day;
		const mon = new Date(today);
		mon.setDate(today.getDate() + diffToMon + offsetWeeks * 7);
		const sun = new Date(mon);
		sun.setDate(mon.getDate() + 6);
		return { from: toDateStr(mon), to: toDateStr(sun) };
	}

	let activeWeek = $state(0); // 0 = diese Woche, 1 = nächste Woche
	let loading    = $state(true);
	let matches    = $state([]);   // alle Matches der 2 Wochen
	let plans      = $state([]);   // game_plans mit game_plan_players
	let confirming = $state(null); // entry.id das gerade bestätigt wird

	let range0 = weekRange(0);
	let range1 = weekRange(1);

	async function load() {
		loading = true;
		try {
			// Matches beider Wochen laden
			const { data: mData, error: mErr } = await sb
				.from('matches')
				.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name, tier)')
				.gte('date', range0.from)
				.lte('date', range1.to)
				.order('date')
				.order('time');
			if (mErr) { triggerToast('Fehler: ' + mErr.message); return; }
			matches = mData ?? [];

			// Passende game_plans laden (alle cal_weeks + league_ids aus den Matches)
			const calWeeks = [...new Set(matches.map(m => m.cal_week).filter(Boolean))];
			if (!calWeeks.length) { plans = []; return; }

			const { data: pData, error: pErr } = await sb
				.from('game_plans')
				.select('id, cal_week, league_id, lineup_published_at, confirmation_deadline, game_plan_players(id, position, confirmed, player_id, players(name, photo))')
				.in('cal_week', calWeeks);
			if (pErr) { triggerToast('Fehler: ' + pErr.message); return; }
			plans = (pData ?? []).map(p => ({
				...p,
				game_plan_players: (p.game_plan_players ?? []).sort((a, b) => (a.position ?? 99) - (b.position ?? 99)),
			}));
		} finally {
			loading = false;
		}
	}

	// Matches gefiltert nach aktiver Woche
	let activeRange  = $derived(activeWeek === 0 ? range0 : range1);
	let weekMatches  = $derived(matches.filter(m => m.date >= activeRange.from && m.date <= activeRange.to));

	// game_plan für ein Match finden (via cal_week + league_id)
	function planFor(m) {
		return plans.find(p => p.cal_week === m.cal_week && p.league_id === m.league_id) ?? null;
	}

	function confirmStatus(entry) {
		if (entry.confirmed === true)  return 'confirmed';
		if (entry.confirmed === false) return 'declined';
		return 'pending';
	}

	async function respond(entry, confirmed) {
		if (confirming) return;
		confirming = entry.id;
		// Optimistic update
		plans = plans.map(p => ({
			...p,
			game_plan_players: p.game_plan_players.map(e =>
				e.id === entry.id ? { ...e, confirmed } : e
			),
		}));
		const { error } = await sb.from('game_plan_players').update({ confirmed }).eq('id', entry.id);
		if (error) {
			triggerToast('Fehler: ' + error.message);
			// Rollback
			plans = plans.map(p => ({
				...p,
				game_plan_players: p.game_plan_players.map(e =>
					e.id === entry.id ? { ...e, confirmed: null } : e
				),
			}));
			confirming = null;
			return;
		}

		// Auswärts-Hinweis: Mitfahrgelegenheit prüfen
		if (confirmed === true) {
			const plan  = plans.find(p => p.game_plan_players.some(e => e.id === entry.id));
			const match = plan ? matches.find(m => m.cal_week === plan.cal_week && m.league_id === plan.league_id) : null;
			if (match && match.home_away !== 'HEIM') {
				triggerToast('Auswärtsfahrt – Mitfahrgelegenheit prüfen');
			}
		}

		// Absage → Captains benachrichtigen
		if (confirmed === false) {
			try {
				const plan = plans.find(p => p.game_plan_players.some(e => e.id === entry.id));
				const match = plan ? matches.find(m => m.cal_week === plan.cal_week && m.league_id === plan.league_id) : null;
				const { data: me } = await sb.from('players').select('name').eq('id', $playerId).maybeSingle();
				const { data: captains } = await sb.from('players').select('id').in('role', ['kapitaen','admin']);
				const captainIds = (captains ?? []).map(c => c.id);
				if (captainIds.length && match) {
					await fetch('/api/push/notify', {
						method: 'POST',
						headers: { 'Content-Type': 'application/json' },
						body: JSON.stringify({
							player_ids: captainIds,
							title: `Absage: ${me?.name ?? 'Spieler'}`,
							body:  `${match.leagues?.name ?? ''} vs. ${match.opponent} – Ersatz wählen`,
							url:   '/profil#admin-inbox-aufstellungen',
							pref_key: 'lineup_decline',
						}),
					});
				}
			} catch {}
		}
		confirming = null;
	}

	function tierLabel(tier) {
		return ['BL', 'LL', 'A', 'B'][tier - 1] ?? String(tier);
	}

	function homeAwayLabel(ha) {
		return ha === 'HEIM' ? 'Heim' : 'Auswärts';
	}

	function todayStr() {
		return toDateStr(new Date());
	}

	onMount(load);

	// 30s poll für live-Fortschritt
	$effect(() => {
		const id = setInterval(() => { if (!editOpen && !absenceOpen) load(); }, 30_000);
		return () => clearInterval(id);
	});

	function statsFor(plan) {
		const entries = plan?.game_plan_players ?? [];
		let yes = 0, no = 0, pending = 0;
		for (const e of entries) {
			if (e.confirmed === true) yes++;
			else if (e.confirmed === false) no++;
			else pending++;
		}
		return { yes, no, pending };
	}

	function matchStartMs(m) {
		if (!m?.date || !m?.time) return null;
		return new Date(`${m.date}T${m.time}`).getTime();
	}
	function isShortNotice(m, plan) {
		if (!plan?.confirmation_deadline) return false;
		if (plan.confirmation_deadline >= todayStr()) return false;
		const startMs = matchStartMs(m);
		if (!startMs) return false;
		return Date.now() < startMs;
	}
</script>

<div class="at-wrap">
	<!-- Woche-Toggle -->
	<div class="at-week-toggle">
		<button class="at-week-btn" class:at-week-btn--active={activeWeek === 0} onclick={() => activeWeek = 0}>
			Diese Woche
		</button>
		<button class="at-week-btn" class:at-week-btn--active={activeWeek === 1} onclick={() => activeWeek = 1}>
			Nächste Woche
		</button>
	</div>

	{#if loading}
		<div class="at-loading">
			{#each Array(3) as _}
				<div class="skeleton-card animate-pulse-skeleton" style="height: 140px;"></div>
			{/each}
		</div>

	{:else if weekMatches.length === 0}
		<div class="at-empty">
			<span class="material-symbols-outlined">sports_score</span>
			<p>Keine Spiele diese Woche.</p>
		</div>

	{:else}
		<div class="at-cards">
			{#each weekMatches as m (m.id)}
				{@const plan = planFor(m)}
				{@const published = !!plan?.lineup_published_at}
				{@const deadlinePassed = plan?.confirmation_deadline ? plan.confirmation_deadline < todayStr() : false}
				{@const myEntry = plan?.game_plan_players?.find(e => e.player_id === $playerId) ?? null}
				{@const shortNotice = published && isShortNotice(m, plan)}
				{@const canRespond = myEntry && published && (!deadlinePassed || shortNotice)}
				{@const captainStats = statsFor(plan)}

				<div class="at-card" class:at-card--unpublished={!published}>
					<!-- Card header -->
					<div class="at-card-header">
						<div class="at-league-badge" data-tier={m.leagues?.tier ?? 1}>
							{tierLabel(m.leagues?.tier ?? 1)}
						</div>
						<div class="at-card-meta">
							<span class="at-card-date">
								{DAY_SHORT[(new Date(m.date + 'T12:00')).getDay()]}, {new Date(m.date + 'T12:00').getDate()}. {['Jän', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'][new Date(m.date + 'T12:00').getMonth()]}
								{#if m.time} · {fmtTime(m.time)}{/if}
							</span>
							<span class="at-home-away">{homeAwayLabel(m.home_away)}</span>
						</div>
					</div>
					<p class="at-opponent">vs. {m.opponent}</p>

					{#if $playerRole === 'kapitaen'}
						<div class="at-captain-actions">
							<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={() => openEdit(m.id)}>
								<span class="material-symbols-outlined">{plan ? 'edit' : 'add'}</span>
								{plan ? 'Aufstellung bearbeiten' : 'Aufstellung erstellen'}
							</button>
						</div>
						{#if published}
							<div class="at-captain-strip">
								<span class="at-stat at-stat--yes">
									<span class="material-symbols-outlined">check_circle</span>
									{captainStats.yes} zugesagt
								</span>
								<span class="at-stat at-stat--no">
									<span class="material-symbols-outlined">cancel</span>
									{captainStats.no} abgesagt
								</span>
								<span class="at-stat at-stat--pending">
									<span class="material-symbols-outlined">schedule</span>
									{captainStats.pending} offen
								</span>
							</div>
						{/if}
					{/if}

					{#if !plan || !published}
						<!-- Nicht veröffentlicht -->
						<div class="at-not-published">
							<span class="material-symbols-outlined">schedule</span>
							Aufstellung folgt
						</div>
					{:else}
						<!-- Spielerliste -->
						<div class="at-players">
							{#each plan.game_plan_players as entry (entry.id)}
								{@const name  = entry.players?.name ?? '–'}
								{@const photo = entry.players?.photo ?? null}
								{@const status = confirmStatus(entry)}
								{@const isMe   = entry.player_id === $playerId}
								<div class="at-player-row" class:at-player-row--me={isMe}>
									<span class="at-pos">{entry.position}</span>
									<div class="at-avatar">
										<img src={imgPath(photo, name)} alt={name} onerror={(e) => { e.currentTarget.style.display = 'none'; }} />
										<span class="at-initial">{name.slice(0, 1)}</span>
									</div>
									<span class="at-player-name">{name}{#if isMe} (Du){/if}</span>
									<span class="at-status at-status--{status}" title={status === 'confirmed' ? 'Bestätigt' : status === 'declined' ? 'Abgelehnt' : 'Ausstehend'}>
										{#if status === 'confirmed'}
											<span class="material-symbols-outlined">check_circle</span>
										{:else if status === 'declined'}
											<span class="material-symbols-outlined">cancel</span>
										{:else}
											<span class="material-symbols-outlined">radio_button_unchecked</span>
										{/if}
									</span>
								</div>
							{/each}
						</div>

						<!-- My status -->
						{#if !myEntry}
							<p class="at-my-status at-my-status--out">Du bist nicht dabei</p>
						{:else if myEntry.confirmed === true}
							<p class="at-my-status at-my-status--yes">Du bist dabei</p>
						{:else if myEntry.confirmed === false}
							<p class="at-my-status at-my-status--no">Du hast abgesagt</p>
						{:else}
							<p class="at-my-status at-my-status--pending">Bestätigung offen</p>
						{/if}

						<!-- Frist -->
						{#if plan.confirmation_deadline}
							<p class="at-deadline" class:at-deadline--passed={deadlinePassed}>
								{deadlinePassed ? 'Frist abgelaufen:' : 'Bestätigen bis'} {fmtDate(plan.confirmation_deadline)}
							</p>
						{/if}

						{#if shortNotice}
							<div class="at-urgent-warn">
								<span class="material-symbols-outlined">notifications_active</span>
								Kurzfristige Änderung — Kapitän wird sofort informiert
							</div>
						{/if}

						<!-- Confirm/Decline nur für eigenen Eintrag -->
						{#if canRespond}
							<div class="at-actions">
								<button
									class="lcc-btn lcc-btn--decline"
									onclick={() => respond(myEntry, false)}
									disabled={!!confirming}
								>
									<span class="material-symbols-outlined">close</span>
									Ablehnen
								</button>
								<button
									class="lcc-btn lcc-btn--confirm"
									onclick={() => respond(myEntry, true)}
									disabled={!!confirming}
								>
									<span class="material-symbols-outlined">check</span>
									Bestätigen
								</button>
							</div>
						{/if}
					{/if}
				</div>
			{/each}
		</div>
	{/if}

	<button class="at-absence-link" onclick={() => absenceOpen = true}>
		<span class="material-symbols-outlined">event_busy</span>
		Nicht verfügbar? Abwesenheit eintragen
	</button>
</div>

<AdminAufstellung bind:open={editOpen} preselectedMatchId={editMatchId} />
<AbsenceSheet bind:open={absenceOpen} onReload={load} />

<style>
	.at-wrap {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-4) calc(var(--space-4) + 80px);
	}

	/* Week toggle */
	.at-week-toggle {
		display: flex;
		gap: var(--space-2);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-full);
		padding: 3px;
	}
	.at-week-btn {
		flex: 1;
		padding: var(--space-2) var(--space-3);
		border: none; border-radius: var(--radius-full);
		font-family: var(--font-body); font-size: var(--text-body-sm); font-weight: 600;
		cursor: pointer; color: var(--color-on-surface-variant);
		background: transparent; transition: background 0.15s, color 0.15s;
		-webkit-tap-highlight-color: transparent;
	}
	.at-week-btn--active {
		background: var(--color-surface);
		color: var(--color-on-surface);
		box-shadow: 0 1px 3px rgba(0,0,0,0.12);
	}

	/* Loading / empty */
	.at-loading { display: flex; flex-direction: column; gap: var(--space-3); }
	.at-empty {
		display: flex; flex-direction: column; align-items: center;
		gap: var(--space-2); padding: var(--space-8) 0;
		color: var(--color-on-surface-variant);
	}
	.at-empty .material-symbols-outlined { font-size: 2.5rem; opacity: 0.4; }
	.at-empty p { font-size: var(--text-body-md); }

	/* Cards */
	.at-cards { display: flex; flex-direction: column; gap: var(--space-3); }
	.at-card {
		background: var(--color-surface);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	.at-card--unpublished { opacity: 0.8; }

	/* Card header */
	.at-card-header {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) var(--space-4) var(--space-2);
	}
	.at-league-badge {
		min-width: 2rem; height: 2rem;
		border-radius: var(--radius-sm);
		display: flex; align-items: center; justify-content: center;
		font-family: var(--font-display); font-size: 0.7rem; font-weight: 900;
		letter-spacing: 0.03em; flex-shrink: 0;
	}
	.at-league-badge[data-tier="1"] { background: #7f1d1d; color: #fff; }
	.at-league-badge[data-tier="2"] { background: #1e3a5f; color: #fff; }
	.at-league-badge[data-tier="3"] { background: #14532d; color: #fff; }
	.at-league-badge[data-tier="4"] { background: #4a1d96; color: #fff; }

	.at-card-meta { flex: 1; display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-2); }
	.at-card-date { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); font-weight: 500; }
	.at-home-away { font-size: var(--text-label-sm); color: var(--color-outline); }

	.at-opponent {
		font-family: var(--font-display); font-weight: 700;
		font-size: var(--text-title-sm); color: var(--color-on-surface);
		padding: 0 var(--space-4) var(--space-3);
		margin: 0;
	}

	/* Not published */
	.at-not-published {
		display: flex; align-items: center; gap: var(--space-2);
		margin: 0 var(--space-4) var(--space-3);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		font-size: var(--text-body-sm); color: var(--color-on-surface-variant);
	}
	.at-not-published .material-symbols-outlined { font-size: 1rem; }

	/* Player rows */
	.at-players {
		border-top: 1px solid var(--color-outline-variant);
		display: flex; flex-direction: column;
	}
	.at-player-row {
		display: grid;
		grid-template-columns: 24px 32px 1fr 24px;
		gap: var(--space-2); align-items: center;
		padding: var(--space-2) var(--space-4);
		border-bottom: 1px solid var(--color-outline-variant);
	}
	.at-player-row:last-child { border-bottom: none; }
	.at-player-row--me { background: rgba(var(--color-secondary-rgb, 212, 175, 55), 0.08); }

	.at-pos { font-size: var(--text-body-sm); font-weight: 700; color: var(--color-primary); text-align: center; }
	.at-avatar {
		width: 32px; height: 32px; border-radius: 50%;
		overflow: hidden; background: var(--color-surface-container-highest);
		display: grid; place-items: center; position: relative;
	}
	.at-avatar img { width: 100%; height: 100%; object-fit: cover; position: absolute; inset: 0; }
	.at-initial { font-weight: 700; font-size: 0.7rem; color: var(--color-outline); }
	.at-player-name { font-size: var(--text-body-sm); font-weight: 500; color: var(--color-on-surface); }

	.at-status .material-symbols-outlined { font-size: 1.1rem; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.at-status--confirmed .material-symbols-outlined { color: #2D7A3A; }
	.at-status--declined  .material-symbols-outlined { color: var(--color-error, #b00020); }
	.at-status--pending   .material-symbols-outlined { color: var(--color-outline); }

	/* Deadline */
	.at-deadline {
		margin: var(--space-2) var(--space-4) 0;
		font-size: var(--text-label-sm); color: var(--color-on-surface-variant);
		text-align: center;
	}
	.at-deadline--passed { color: var(--color-error, #b00020); }

	/* Actions */
	.at-actions {
		display: flex; gap: var(--space-3);
		padding: var(--space-3) var(--space-4) var(--space-4);
	}

	/* Captain actions */
	.at-captain-actions {
		padding: 0 var(--space-4) var(--space-3);
	}

	/* My status */
	.at-my-status {
		margin: var(--space-3) var(--space-4) 0;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		font-size: var(--text-label-md);
		font-weight: 600;
		text-align: center;
	}
	.at-my-status--yes { background: rgba(45,122,58,0.12); color: #2D7A3A; }
	.at-my-status--no { background: rgba(176,0,32,0.12); color: var(--color-error, #b00020); }
	.at-my-status--pending { background: var(--color-surface-container-low); color: var(--color-on-surface-variant); }
	.at-my-status--out { background: var(--color-surface-container-low); color: var(--color-on-surface-variant); }

	/* Captain progress-strip */
	.at-captain-strip {
		display: flex; gap: var(--space-2);
		padding: 0 var(--space-4) var(--space-3);
		flex-wrap: wrap;
	}
	.at-stat {
		display: inline-flex; align-items: center; gap: 4px;
		padding: 4px 10px;
		background: var(--color-surface-container-low);
		border-radius: var(--radius-full);
		font-size: var(--text-label-md);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.at-stat .material-symbols-outlined { font-size: 0.9rem; }
	.at-stat--yes     { color: #2D7A3A; }
	.at-stat--no      { color: var(--color-error, #b00020); }
	.at-stat--pending { color: var(--color-on-surface-variant); }

	/* Kurzfristig-Banner */
	.at-urgent-warn {
		display: flex; align-items: center; gap: var(--space-2);
		margin: var(--space-2) var(--space-4) 0;
		padding: var(--space-2) var(--space-3);
		background: rgba(180, 83, 9, 0.1);
		border: 1px solid rgba(180, 83, 9, 0.35);
		border-radius: var(--radius-md);
		color: #b45309;
		font-size: var(--text-label-md);
		font-weight: 600;
	}
	.at-urgent-warn .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}

	/* Abwesenheits-Link */
	.at-absence-link {
		display: flex; align-items: center; justify-content: center; gap: var(--space-2);
		padding: var(--space-3);
		border: 1.5px dashed var(--color-outline-variant);
		border-radius: var(--radius-md);
		background: transparent;
		color: var(--color-on-surface-variant);
		font-family: inherit;
		font-size: var(--text-body-sm);
		font-weight: 600;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		margin-top: var(--space-2);
	}
	.at-absence-link:active {
		background: var(--color-surface-container-low);
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.at-absence-link .material-symbols-outlined { font-size: 1.1rem; }
</style>
