<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr } from '$lib/utils/dates.js';
	import { imgPath, shortName, BLANK_IMG } from '$lib/utils/players.js';
	import ResultEntrySheet from '$lib/components/spielbetrieb/ResultEntrySheet.svelte';
	import BottomSheet      from '$lib/components/BottomSheet.svelte';
	import CarpoolCard      from '$lib/components/spielbetrieb/CarpoolCard.svelte';
	import AdminAufstellung from '$lib/components/admin/AdminAufstellung.svelte';
	import FeedbackCard     from '$lib/components/spielbetrieb/FeedbackCard.svelte';

	// ── State ─────────────────────────────────────────────────────────────────
	let pastMatches    = $state([]);                 // last 14 days, scored (or unscored for Kapitän)
	let upcomingMatches = $state([]);                // today … +14 days
	let lineupsByMatch = $state(new Map());          // match_id → { game_plan_id, published, deadline, players[] }
	let carpoolsByMatch = $state(new Map());         // match_id → { seats_total, seats_taken }
	let loading        = $state(true);

	// Result-entry sheet (Kapitän)
	let resultSheetOpen    = $state(false);
	let resultSheetMatchId = $state(null);

	// Carpool sheet
	let carpoolSheetOpen   = $state(false);
	let carpoolSheetMatch  = $state(null);
	let carpoolSheetData   = $state([]);
	let carpoolSheetMeetup = $state(null);
	let carpoolLoading     = $state(false);

	// Lineup-edit sheet (Kapitän)
	let editLineupOpen    = $state(false);
	let editLineupMatchId = $state(null);

	// Feedback sheet (Spieler, via Push-URL)
	let feedbackSheetOpen     = $state(false);
	let feedbackSheetMatch    = $state(null);
	let feedbackQuestions     = $state([]);
	let feedbackExisting      = $state(null);

	// Confirm-mutation guard (per game_plan_player_id)
	let confirming = $state(null);

	// ── Date constants ────────────────────────────────────────────────────────
	const today   = toDateStr(new Date());
	const plus14  = toDateStr(new Date(Date.now() + 14 * 86400000));
	const minus14 = toDateStr(new Date(Date.now() - 14 * 86400000));

	// ── Helpers ───────────────────────────────────────────────────────────────
	function teamTotal(m) {
		return (m.game_plans ?? []).reduce((acc, gp) =>
			acc + (gp.game_plan_players ?? []).reduce((s, p) => s + (Number(p.score) || 0), 0)
		, 0);
	}

	function matchHasScores(m) {
		return (m.game_plans ?? []).some(gp =>
			(gp.game_plan_players ?? []).some(p => p.score != null)
		);
	}

	function matchPublished(m) {
		return (m.game_plans ?? []).some(gp => gp.result_published_at);
	}

	function bewerbBadge(m) {
		// Spec §12 q3: Designer-Empfehlung ist `leagues.name` (max 12 Zeichen) für Liga-Matches.
		// `BEWERB_LABEL` aus `$lib/constants/competitions.js` deckt nur Turnier/Landesbewerb-Keys ab —
		// hier werden ausschließlich Liga-Matches geladen (`.not('league_id', 'is', null)`), daher nicht anwendbar.
		const ligaName = m.leagues?.name?.trim();
		if (ligaName) return ligaName.length > 12 ? ligaName.slice(0, 12) : ligaName;
		return 'Liga';
	}

	// ── Load ──────────────────────────────────────────────────────────────────
	async function loadData() {
		loading = true;
		try {
			// Past matches: last 14 days. Spieler sieht nur scored+published, Kapitän sieht alles für Reminder.
			const { data: pData, error: pErr } = await sb
				.from('matches')
				.select('id, date, time, opponent, home_away, league_id, cal_week, leagues(name), game_plans(id, result_published_at, game_plan_players(score, played))')
				.gte('date', minus14)
				.lt('date', today)
				.not('league_id', 'is', null)
				.order('date', { ascending: false });
			if (pErr) { triggerToast('Fehler: ' + pErr.message); return; }
			pastMatches = pData ?? [];

			// Upcoming league matches: today … +14 days.
			const { data: uData, error: uErr } = await sb
				.from('matches')
				.select('id, date, time, opponent, home_away, league_id, cal_week, leagues(name)')
				.gte('date', today)
				.lte('date', plus14)
				.not('league_id', 'is', null)
				.neq('opponent', 'spielfrei')
				.order('date');
			if (uErr) { triggerToast('Fehler: ' + uErr.message); return; }
			upcomingMatches = uData ?? [];

			// Lineups for upcoming matches (joined via cal_week + league_id, NOT match_id FK).
			const map = new Map();
			if (upcomingMatches.length) {
				const calWeeks  = [...new Set(upcomingMatches.map(m => m.cal_week).filter(Boolean))];
				const leagueIds = [...new Set(upcomingMatches.map(m => m.league_id).filter(Boolean))];
				if (calWeeks.length && leagueIds.length) {
					const { data: gps, error: gErr } = await sb
						.from('game_plans')
						.select('id, cal_week, league_id, lineup_published_at, confirmation_deadline, game_plan_players(id, position, player_id, confirmed, players!game_plan_players_player_id_fkey(id, name, photo))')
						.in('cal_week', calWeeks)
						.in('league_id', leagueIds);
					if (gErr) { triggerToast('Fehler: ' + gErr.message); return; }
					for (const m of upcomingMatches) {
						const gp = (gps ?? []).find(g => g.cal_week === m.cal_week && g.league_id === m.league_id);
						if (gp) {
							map.set(m.id, {
								game_plan_id: gp.id,
								published:    !!gp.lineup_published_at,
								deadline:     gp.confirmation_deadline,
								players:      (gp.game_plan_players ?? []).slice().sort((a, b) => (a.position ?? 99) - (b.position ?? 99)),
							});
						}
					}
				}
			}
			lineupsByMatch = map;

			// Carpools für Auswärts-Matches in den nächsten 14 Tagen (Counter 3/4).
			const awayIds = upcomingMatches.filter(m => m.home_away !== 'HEIM').map(m => m.id);
			const cMap = new Map();
			if (awayIds.length) {
				const { data: cps, error: cErr } = await sb
					.from('match_carpools')
					.select('id, match_id, seats_total, match_carpool_seats(passenger_id)')
					.in('match_id', awayIds);
				if (cErr) { triggerToast('Fehler: ' + cErr.message); return; }
				// Aggregiere pro Match: total Plätze + total besetzt + Anzahl Fahrten.
				for (const c of cps ?? []) {
					const cur = cMap.get(c.match_id) ?? { seats_total: 0, seats_taken: 0, rides: 0 };
					cur.seats_total += Number(c.seats_total) || 0;
					cur.seats_taken += (c.match_carpool_seats ?? []).length;
					cur.rides += 1;
					cMap.set(c.match_id, cur);
				}
			}
			carpoolsByMatch = cMap;
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await loadData();
		// Push-URL ?feedback=<match_id> — Sheet öffnen
		try {
			const params = new URLSearchParams(window.location.search);
			const fbId = params.get('feedback');
			if (fbId) await openFeedbackForMatch(fbId);
			// Deep-Link ?carpool=<match_id> (vom Dashboard nach Lineup-Zusage)
			const cpId = params.get('carpool');
			if (cpId) await openCarpoolForMatchId(cpId);
		} catch {}
	});

	async function openCarpoolForMatchId(matchId) {
		// Match aus den geladenen upcomingMatches nehmen — sonst nachladen.
		let match = upcomingMatches.find(m => m.id === matchId);
		if (!match) {
			const { data, error } = await sb
				.from('matches')
				.select('id, date, time, opponent, home_away, league_id, cal_week, leagues(name)')
				.eq('id', matchId)
				.maybeSingle();
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			if (!data)  { triggerToast('Spiel nicht gefunden'); return; }
			match = data;
		}
		await openCarpoolSheet(match);
	}

	// Close: ?carpool aus URL entfernen, damit Sheet beim Reload nicht wieder aufgeht.
	let wasCarpoolOpen = false;
	$effect(() => {
		if (wasCarpoolOpen && !carpoolSheetOpen) {
			try {
				const url = new URL(window.location.href);
				if (url.searchParams.has('carpool')) {
					url.searchParams.delete('carpool');
					window.history.replaceState(window.history.state, '', url.pathname + url.search);
				}
			} catch {}
		}
		wasCarpoolOpen = carpoolSheetOpen;
	});

	// ── Feedback sheet (vom Push-Link `?feedback=<match_id>`) ─────────────────
	async function openFeedbackForMatch(matchId) {
		const [{ data: m, error: mErr }, { data: qs, error: qErr }, { data: fb, error: fbErr }] = await Promise.all([
			sb.from('matches').select('id, opponent, date, home_away, leagues(name)').eq('id', matchId).maybeSingle(),
			sb.from('feedback_questions').select('id, prompt'),
			sb.from('match_feedback').select('id, answer, question_id').eq('match_id', matchId).eq('player_id', $playerId).maybeSingle(),
		]);
		if (mErr) { triggerToast('Fehler: ' + mErr.message); return; }
		if (qErr) { triggerToast('Fehler: ' + qErr.message); return; }
		if (fbErr && fbErr.code !== 'PGRST116') { triggerToast('Fehler: ' + fbErr.message); return; }
		if (!m) { triggerToast('Spiel nicht gefunden'); return; }
		feedbackSheetMatch = m;
		feedbackQuestions  = qs ?? [];
		feedbackExisting   = fb ?? null;
		feedbackSheetOpen  = true;
	}

	// Close: Param aus URL entfernen damit Sheet bei späterem Reload nicht wieder aufgeht
	let wasFeedbackOpen = false;
	$effect(() => {
		if (wasFeedbackOpen && !feedbackSheetOpen) {
			try {
				const url = new URL(window.location.href);
				if (url.searchParams.has('feedback')) {
					url.searchParams.delete('feedback');
					window.history.replaceState(window.history.state, '', url.pathname + url.search);
				}
			} catch {}
			feedbackSheetMatch = null;
			feedbackExisting   = null;
		}
		wasFeedbackOpen = feedbackSheetOpen;
	});

	// ── Derived ───────────────────────────────────────────────────────────────
	const recentResults = $derived.by(() => {
		// Spieler: nur scored + published. Kapitän: alle (auch unscored) — Reminder zum Eintragen.
		if ($playerRole === 'kapitaen') {
			return pastMatches.slice(0, 3);
		}
		return pastMatches.filter(m => matchPublished(m) && matchHasScores(m)).slice(0, 3);
	});

	// ── Confirm / Decline / Pending — 3-State-Toggle (User-Entscheidung 1) ───
	async function cycleMyConfirmation(match, entry) {
		if (!entry || confirming) return;

		const lu = lineupsByMatch.get(match.id);
		const deadlinePassed = lu?.deadline && lu.deadline < today;
		if (!lu?.published || deadlinePassed) {
			triggerToast('Bestätigung geschlossen');
			return;
		}

		// pending → confirmed → declined → pending
		const current = entry.confirmed; // true | false | null
		const next = current === null ? true : current === true ? false : null;

		confirming = entry.id;

		// Optimistic UI: Map ersetzen damit Svelte rerendert.
		const prevMap = lineupsByMatch;
		const newMap = new Map(prevMap);
		const luNew = newMap.get(match.id);
		if (luNew) {
			newMap.set(match.id, {
				...luNew,
				players: luNew.players.map(p => p.id === entry.id ? { ...p, confirmed: next } : p),
			});
			lineupsByMatch = newMap;
		}

		const { error } = await sb
			.from('game_plan_players')
			.update({ confirmed: next })
			.eq('id', entry.id);

		if (error) {
			triggerToast('Fehler: ' + error.message);
			lineupsByMatch = prevMap; // Rollback
			confirming = null;
			return;
		}

		// Auswärts-Hinweis bei "confirmed".
		if (next === true && match.home_away !== 'HEIM') {
			triggerToast('Auswärtsfahrt – Mitfahrgelegenheit prüfen');
		}

		// Absage → Kapitäne benachrichtigen (analog zu AufstellungenTab).
		if (next === false) {
			try {
				const { data: me } = await sb.from('players').select('name').eq('id', $playerId).maybeSingle();
				const { data: captains } = await sb.from('players').select('id').in('role', ['kapitaen', 'admin']);
				const captainIds = (captains ?? []).map(c => c.id);
				if (captainIds.length) {
					await fetch('/api/push/notify', {
						method:  'POST',
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
			} catch (err) {
				console.warn('[SpieleTab] Push-Notify an Kapitäne fehlgeschlagen:', err);
			}
		}

		confirming = null;
	}

	function handleSlotKey(e, match, entry) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			cycleMyConfirmation(match, entry);
		}
	}

	// ── Result-entry sheet (Kapitän) ──────────────────────────────────────────
	function openResultEntry(matchId) {
		resultSheetMatchId = matchId;
		resultSheetOpen    = true;
	}

	// ── Carpool sheet ─────────────────────────────────────────────────────────
	async function openCarpoolSheet(match, e) {
		e?.stopPropagation?.();
		carpoolSheetMatch  = match;
		carpoolSheetOpen   = true;
		carpoolLoading     = true;
		carpoolSheetData   = [];
		carpoolSheetMeetup = null;
		const [{ data: cp, error: cpErr }, { data: mu, error: muErr }] = await Promise.all([
			sb.from('match_carpools')
				.select('id, match_id, driver_id, seats_total, depart_time, depart_from, note, driver:players!driver_id(name, photo), match_carpool_seats(passenger_id)')
				.eq('match_id', match.id),
			sb.from('match_meetups').select('*').eq('match_id', match.id).maybeSingle(),
		]);
		if (cpErr) { triggerToast('Fehler: ' + cpErr.message); carpoolLoading = false; return; }
		if (muErr && muErr.code !== 'PGRST116') { triggerToast('Fehler: ' + muErr.message); }
		carpoolSheetData   = (cp ?? []).map(c => ({ ...c, seats: c.match_carpool_seats ?? [] }));
		carpoolSheetMeetup = mu ?? null;
		carpoolLoading     = false;
	}

	async function refreshCarpoolSheet() {
		if (!carpoolSheetMatch) return;
		await openCarpoolSheet(carpoolSheetMatch);
		await loadData();
	}

	function handleCarpoolKey(e, match) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			openCarpoolSheet(match);
		}
	}

	// ── Lineup-edit sheet (Kapitän) ───────────────────────────────────────────
	function openLineupEdit(matchId, e) {
		e?.stopPropagation?.();
		editLineupMatchId = matchId;
		editLineupOpen    = true;
	}

	let wasEditOpen = false;
	$effect(() => {
		if (wasEditOpen && !editLineupOpen) {
			editLineupMatchId = null;
			loadData();
		}
		wasEditOpen = editLineupOpen;
	});

	// ── Captain reminder push ─────────────────────────────────────────────────
	let reminderSending = $state(null); // match.id while sending
	async function sendLineupReminder(match) {
		if (reminderSending) return;
		const lu = lineupsByMatch.get(match.id);
		if (!lu?.published) return;
		const pendingIds = (lu.players ?? [])
			.filter(p => p.confirmed === null && p.player_id)
			.map(p => p.player_id);
		if (!pendingIds.length) { triggerToast('Keine offenen Bestätigungen'); return; }

		reminderSending = match.id;
		try {
			const leagueName = match.leagues?.name ?? 'Liga';
			const versus     = match.home_away === 'HEIM' ? 'vs.' : 'bei';
			const fristText  = lu.deadline ? ` – Frist ${fmtDate(lu.deadline)}` : '';
			const res = await fetch('/api/push/notify', {
				method:  'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					player_ids: pendingIds,
					title: 'Bitte Aufstellung bestätigen',
					body:  `${leagueName} ${versus} ${match.opponent}${fristText}`,
					url:   '/',
					pref_key: 'lineup_reminder',
				}),
			});
			if (!res.ok) throw new Error('HTTP ' + res.status);
			triggerToast(`Erinnerung an ${pendingIds.length} Spieler gesendet`);
		} catch (err) {
			triggerToast('Fehler: ' + (err?.message ?? 'Push fehlgeschlagen'));
		} finally {
			reminderSending = null;
		}
	}
</script>

<div class="sp-page">
	{#if loading}
		<div class="sp-loading">
			<div class="shimmer-box sp-skel sp-skel--row"></div>
			<div class="shimmer-box sp-skel sp-skel--card"></div>
			<div class="shimmer-box sp-skel sp-skel--card"></div>
		</div>
	{:else}

		<!-- ── Letzte Ergebnisse ─────────────────────────────────────────── -->
		{#if recentResults.length > 0}
			<section class="sp-section">
				<header class="sp-sec-head">
					<span class="material-symbols-outlined sp-sec-icon">sports_score</span>
					<h2 class="sp-sec-title">Letzte Ergebnisse</h2>
				</header>

				<div class="sp-cards">
					{#each recentResults as m (m.id)}
						{@const isPub      = matchPublished(m) && matchHasScores(m)}
						{@const total      = teamTotal(m)}
						{@const isCaptain  = $playerRole === 'kapitaen'}
						{@const showAction = isCaptain && !isPub}

						<article
							class="mw-card sp-result-card"
							class:sp-result-card--unscored={showAction}
							aria-label={showAction
								? `Ergebnis fehlt — Spiel vom ${fmtDate(m.date)} ${m.home_away === 'HEIM' ? 'gegen' : 'bei'} ${m.opponent}`
								: `Spiel vom ${fmtDate(m.date)}: ${total} Holz ${m.home_away === 'HEIM' ? 'gegen' : 'bei'} ${m.opponent}`}
						>
							<div class="sp-result-grid">
								<div class="sp-result-meta">
									<span class="sp-result-eyebrow">
										{fmtDate(m.date)} · {bewerbBadge(m)}
									</span>
									<span class="sp-result-opp">
										{m.home_away === 'HEIM' ? 'vs. ' : 'bei '}{m.opponent}
									</span>
								</div>

								<div class="sp-result-right">
									{#if isPub}
										<span class="sp-result-score">{total}</span>
										<span class="sp-result-unit">HOLZ</span>
									{:else if showAction}
										<span class="sp-result-pending">Kein Ergebnis</span>
										<button
											class="mw-btn mw-btn--primary sp-result-cta"
											onclick={() => openResultEntry(m.id)}
											aria-label="Ergebnis eintragen für Spiel vom {fmtDate(m.date)}"
										>
											<span class="material-symbols-outlined">edit_note</span>
											Ergebnis eintragen
										</button>
									{/if}
								</div>
							</div>
						</article>
					{/each}
				</div>
			</section>
		{/if}

		<!-- ── Diese & nächste Woche ─────────────────────────────────────── -->
		<section class="sp-section">
			<header class="sp-sec-head">
				<span class="material-symbols-outlined sp-sec-icon">event_upcoming</span>
				<h2 class="sp-sec-title">Diese & nächste Woche</h2>
			</header>

			{#if upcomingMatches.length === 0}
				<div class="mw-card sp-empty">
					<span class="material-symbols-outlined sp-empty-icon">event_busy</span>
					<p class="sp-empty-text">Keine Spiele in den nächsten 14 Tagen</p>
				</div>
			{:else}
				<div class="sp-cards">
					{#each upcomingMatches as m (m.id)}
						{@const lu              = lineupsByMatch.get(m.id) ?? null}
						{@const myEntry         = lu?.players?.find(p => p.player_id === $playerId) ?? null}
						{@const deadlinePassed  = lu?.deadline && lu.deadline < today}
						{@const slotsCount      = Math.max(4, lu?.players?.length ?? 4)}
						{@const isHome          = m.home_away === 'HEIM'}
						{@const cp              = carpoolsByMatch.get(m.id) ?? null}
						{@const isCaptain       = $playerRole === 'kapitaen'}

						<article class="mw-card sp-match-card animate-fade-float" aria-label={`Spiel ${fmtDate(m.date)} ${isHome ? 'Heim' : 'Auswärts'} ${m.opponent}`}>
							<!-- Header -->
							<div class="sp-match-head">
								<div class="sp-match-when">
									{fmtDate(m.date)}{m.time ? ' · ' + fmtTime(m.time) : ''}
								</div>
								<div class="sp-match-head-right">
									<span class="mw-badge">{bewerbBadge(m)}</span>
									{#if isCaptain}
										<button
											class="sp-edit-btn"
											type="button"
											aria-label="Aufstellung bearbeiten"
											aria-haspopup="dialog"
											onclick={(e) => openLineupEdit(m.id, e)}
										>
											<span class="material-symbols-outlined">edit</span>
										</button>
									{/if}
								</div>
							</div>

							<!-- Subline: Heim/Auswärts · Gegner -->
							<div class="sp-match-sub">
								<span class="sp-match-where">{isHome ? 'Heim' : 'Auswärts'}</span>
								<span class="sp-match-sep">·</span>
								<span class="sp-match-opp">{m.opponent}</span>
							</div>

							<!-- Trennlinie + Slots -->
							<div class="sp-divider"></div>

							{#if !lu || !lu.published}
								<!-- Aufstellung steht noch nicht -->
								<ul class="sp-slots" role="list" aria-label="Aufstellung">
									{#each Array(slotsCount) as _, i}
										<li class="sp-slot sp-slot--empty" role="listitem" aria-label={`Slot ${i + 1}, frei`}>
											<span class="sp-slot-pos">{i + 1}.</span>
											<span class="sp-slot-avatar sp-slot-avatar--empty" aria-hidden="true"></span>
											<span class="sp-slot-name sp-slot-name--empty">Frei</span>
										</li>
									{/each}
								</ul>
								<p class="sp-slots-hint">
									<span class="material-symbols-outlined">schedule</span>
									Aufstellung folgt
								</p>
							{:else}
								<ul class="sp-slots" role="list" aria-label="Aufstellung">
									{#each lu.players as entry, i (entry.id)}
										{@const pl     = entry.players ?? null}
										{@const name   = pl?.name ?? '–'}
										{@const photo  = pl?.photo ?? null}
										{@const isMe   = entry.player_id === $playerId}
										{@const status = entry.confirmed === true ? 'confirmed' : entry.confirmed === false ? 'declined' : 'pending'}
										{@const statusLabel = status === 'confirmed' ? 'Zugesagt' : status === 'declined' ? 'Abgesagt' : 'Offen'}
										{@const disabled    = deadlinePassed}

										{#if isMe}
											<li
												class="sp-slot sp-slot--me sp-slot--{status}"
												class:sp-slot--disabled={disabled}
												role="button"
												tabindex="0"
												aria-pressed={status === 'confirmed' ? 'true' : status === 'declined' ? 'false' : 'mixed'}
												aria-label={`Slot ${entry.position ?? i + 1}, ${name}, Status: ${statusLabel}${disabled ? '. Bestätigung geschlossen' : '. Antippen zum Wechseln'}`}
												onclick={() => cycleMyConfirmation(m, entry)}
												onkeydown={(e) => handleSlotKey(e, m, entry)}
											>
												<span class="sp-slot-pos">{entry.position ?? i + 1}.</span>
												<img
													class="sp-slot-avatar sp-slot-avatar--me"
													src={imgPath(photo, name)}
													alt={name}
													draggable="false"
													onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}
												/>
												<span class="sp-slot-name">{shortName(name)}</span>
												<span class="sp-slot-du">DU</span>
												<span class="sp-slot-status sp-slot-status--{status}">
													{#if disabled}
														<span class="material-symbols-outlined">lock</span>
														<span>Geschlossen</span>
													{:else if status === 'pending'}
														<span class="material-symbols-outlined">touch_app</span>
														<span>Tippen zum Bestätigen</span>
													{:else if status === 'confirmed'}
														<span class="material-symbols-outlined">check_circle</span>
														<span>Zugesagt</span>
													{:else}
														<span class="material-symbols-outlined">cancel</span>
														<span>Abgesagt</span>
													{/if}
												</span>
											</li>
										{:else}
											<li
												class="sp-slot sp-slot--{status}"
												role="listitem"
												aria-label={`Slot ${entry.position ?? i + 1}, ${name}, ${statusLabel}`}
											>
												<span class="sp-slot-pos">{entry.position ?? i + 1}.</span>
												<img
													class="sp-slot-avatar"
													src={imgPath(photo, name)}
													alt={name}
													draggable="false"
													onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}
												/>
												<span class="sp-slot-name">{shortName(name)}</span>
												<span class="sp-slot-status sp-slot-status--{status}">
													{#if status === 'confirmed'}
														<span class="material-symbols-outlined">check_circle</span>
														<span>Zugesagt</span>
													{:else if status === 'declined'}
														<span class="material-symbols-outlined">cancel</span>
														<span>Abgesagt</span>
													{:else}
														<span class="material-symbols-outlined">radio_button_unchecked</span>
														<span>Offen</span>
													{/if}
												</span>
											</li>
										{/if}
									{/each}
								</ul>
							{/if}

							<!-- Captain-Strip: offene Bestätigungen + Erinnerung -->
							{#if isCaptain && lu?.published}
								{@const pendingPlayers = (lu.players ?? []).filter(p => p.confirmed === null && p.player_id)}
								{#if pendingPlayers.length > 0}
									<div class="sp-cap-strip">
										<div class="sp-cap-strip-info">
											<span class="material-symbols-outlined sp-cap-strip-icon">schedule</span>
											<div class="sp-cap-strip-text">
												<span class="sp-cap-strip-count">{pendingPlayers.length} offen</span>
												<span class="sp-cap-strip-names">
													{pendingPlayers.map(p => shortName(p.players?.name ?? '–')).join(', ')}
												</span>
											</div>
										</div>
										<button
											type="button"
											class="mw-btn mw-btn--soft sp-cap-strip-btn"
											onclick={() => sendLineupReminder(m)}
											disabled={reminderSending === m.id}
											aria-label={`Erinnerung an ${pendingPlayers.length} offene Spieler senden`}
										>
											<span class="material-symbols-outlined">notifications_active</span>
											{reminderSending === m.id ? 'Wird gesendet…' : 'Erinnerung senden'}
										</button>
									</div>
								{/if}
							{/if}

							<!-- Carpool-Footer (nur Auswärts; bei Heim ausblenden, User-Entscheidung 2) -->
							{#if !isHome}
								{@const cpFree     = cp ? Math.max(0, cp.seats_total - cp.seats_taken) : 0}
								{@const cpFull     = !!cp && cp.seats_total > 0 && cp.seats_taken >= cp.seats_total}
								{@const cpMulti    = !!cp && cp.rides > 1}
								{@const cpAriaLbl  = !cp || cp.seats_total === 0
									? 'Mitfahrt anbieten. Antippen zum Öffnen.'
									: cpMulti
										? (cpFull
											? `Mitfahrt: ${cp.rides} Fahrten, alle Plätze voll. Antippen zum Öffnen.`
											: `Mitfahrt: ${cp.rides} Fahrten, ${cpFree} freie Plätze. Antippen zum Öffnen.`)
										: `Mitfahrt: ${cp.seats_taken} von ${cp.seats_total} Plätzen besetzt. Antippen zum Öffnen.`}
								<div
									class="sp-carpool"
									role="button"
									tabindex="0"
									aria-label={cpAriaLbl}
									onclick={(e) => openCarpoolSheet(m, e)}
									onkeydown={(e) => handleCarpoolKey(e, m)}
								>
									<span class="material-symbols-outlined sp-carpool-icon">directions_car</span>
									<span class="sp-carpool-label">
										{#if !cp || cp.seats_total === 0}
											Mitfahrt anbieten
										{:else if cpMulti}
											{#if cpFull}
												{cp.rides} Fahrten · voll
											{:else}
												{cp.rides} Fahrten · {cpFree} freie Plätze
											{/if}
										{:else if cpFull}
											Mitfahrt voll
										{:else}
											Mitfahrt {cp.seats_taken}/{cp.seats_total}
										{/if}
									</span>
									<span class="material-symbols-outlined sp-carpool-chevron">chevron_right</span>
								</div>
							{/if}
						</article>
					{/each}
				</div>
			{/if}
		</section>

	{/if}
</div>

<!-- ── Sheets ───────────────────────────────────────────────────────────── -->
<ResultEntrySheet
	bind:open={resultSheetOpen}
	preselectedMatchId={resultSheetMatchId}
	onPublished={loadData}
/>

<BottomSheet bind:open={carpoolSheetOpen} title="Fahrgemeinschaft">
	{#if carpoolLoading}
		<div class="sp-sheet-loading">
			<span class="material-symbols-outlined sp-sheet-loading-icon">directions_car</span>
			<p>Lädt…</p>
		</div>
	{:else if carpoolSheetMatch}
		<CarpoolCard
			match={carpoolSheetMatch}
			meetup={carpoolSheetMeetup}
			carpools={carpoolSheetData}
			onChanged={refreshCarpoolSheet}
		/>
	{/if}
</BottomSheet>

<AdminAufstellung bind:open={editLineupOpen} preselectedMatchId={editLineupMatchId} />

<BottomSheet bind:open={feedbackSheetOpen} title="Kurzes Feedback">
	{#if feedbackSheetMatch}
		<div class="sp-fb-wrap">
			<FeedbackCard
				match={feedbackSheetMatch}
				questions={feedbackQuestions}
				existingFeedback={feedbackExisting}
				onSaved={() => { setTimeout(() => { feedbackSheetOpen = false; }, 1200); }}
			/>
		</div>
	{/if}
</BottomSheet>

<style>
	/* ── Page-Frame ───────────────────────────────────────────────────────── */
	.sp-page {
		padding: var(--space-4) 0 calc(var(--nav-height) + var(--space-5));
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

	.sp-loading {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding: 0 var(--space-4);
	}
	.sp-skel { border-radius: var(--radius-lg); }
	.sp-skel--row  { height: 80px; }
	.sp-skel--card { height: 240px; }

	/* ── Section-Header (gemeinsam) ──────────────────────────────────────── */
	.sp-section {
		display: flex;
		flex-direction: column;
	}
	.sp-sec-head {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 0 var(--space-5);
		margin-bottom: var(--space-3);
	}
	.sp-sec-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sp-sec-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-md);
		font-weight: 700;
		color: var(--color-on-surface);
	}

	/* ── Card-Listen ─────────────────────────────────────────────────────── */
	.sp-cards {
		display: flex;
		flex-direction: column;
	}
	.sp-cards :global(.mw-card) {
		margin: 0 var(--space-4) var(--space-3);
	}

	/* ── Empty-State (Diese & nächste Woche) ─────────────────────────────── */
	.sp-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-6) var(--space-4);
		text-align: center;
	}
	.sp-empty-icon {
		font-size: 1.4rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sp-empty-text {
		margin: 0;
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
	}

	/* ── Result-Card ─────────────────────────────────────────────────────── */
	.sp-result-card {
		border-left: 4px solid var(--color-outline-variant);
	}
	.sp-result-card--unscored {
		border-left: 4px solid var(--color-secondary);
	}
	.sp-result-grid {
		display: grid;
		grid-template-columns: 1fr auto;
		gap: var(--space-3);
		align-items: center;
	}
	.sp-result-meta {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.sp-result-eyebrow {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.sp-result-opp {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.sp-result-right {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		flex-shrink: 0;
	}
	.sp-result-score {
		font-family: var(--font-display);
		font-size: var(--text-headline-sm);
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.01em;
		color: var(--color-on-surface);
	}
	.sp-result-unit {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
	}
	.sp-result-pending {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--color-secondary);
	}
	.sp-result-cta {
		padding: var(--space-2) var(--space-3);
		font-size: var(--text-label-sm);
	}

	/* ── Match-Card ──────────────────────────────────────────────────────── */
	.sp-match-card {
		display: flex;
		flex-direction: column;
	}
	.sp-match-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.sp-match-when {
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.sp-match-head-right {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		flex-shrink: 0;
	}

	.sp-edit-btn {
		width: 44px;
		height: 44px;
		padding: 10px;
		border: none;
		border-radius: var(--radius-full);
		background: transparent;
		color: var(--color-on-surface-variant);
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		transition: background 150ms ease, color 150ms ease;
		-webkit-tap-highlight-color: transparent;
	}
	.sp-edit-btn:hover,
	.sp-edit-btn:focus-visible {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		color: var(--color-primary);
	}
	.sp-edit-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.sp-edit-btn .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.sp-match-sub {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin-top: 2px;
		min-width: 0;
	}
	.sp-match-where {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
	}
	.sp-match-sep {
		color: var(--color-outline);
		flex-shrink: 0;
	}
	.sp-match-opp {
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		font-weight: 600;
		color: var(--color-on-surface);
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.sp-divider {
		border-top: 1px solid var(--color-outline-variant);
		margin: var(--space-3) 0;
	}

	/* ── Slots ───────────────────────────────────────────────────────────── */
	.sp-slots {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.sp-slot {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-height: 44px;
		padding: 6px 0;
		border-radius: var(--radius-md);
		transition: background 150ms ease;
	}
	.sp-slot-pos {
		min-width: 28px;
		font-family: var(--font-display);
		font-size: var(--text-label-sm);
		font-weight: 800;
		color: var(--color-on-surface-variant);
	}
	.sp-slot-avatar {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-full);
		object-fit: cover;
		object-position: top center;
		background: var(--color-surface-container);
		flex-shrink: 0;
	}
	.sp-slot-avatar--empty {
		display: inline-block;
		border: 1.5px dashed var(--color-outline-variant);
		background: transparent;
	}
	.sp-slot-name {
		font-family: var(--font-display);
		font-size: var(--text-body-md);
		font-weight: 700;
		color: var(--color-on-surface);
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.sp-slot-name--empty {
		color: var(--color-on-surface-variant);
		font-style: italic;
		font-weight: 600;
	}

	/* Status-Indikator (rechts) */
	.sp-slot-status {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		flex-shrink: 0;
		transition: opacity 150ms ease-out;
	}
	.sp-slot-status .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.sp-slot-status--confirmed { color: var(--color-success); }
	.sp-slot-status--pending   { color: var(--color-on-surface-variant); }
	.sp-slot-status--declined  { color: var(--color-primary); }

	/* "Aufstellung folgt"-Hint */
	.sp-slots-hint {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin: var(--space-2) 0 0;
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container);
		border-radius: var(--radius-md);
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.sp-slots-hint .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	/* ── Mein-Slot (hervorgehoben + tap-bar) ─────────────────────────────── */
	.sp-slot--me {
		background: color-mix(in srgb, var(--color-primary) 6%, transparent);
		box-shadow: inset 3px 0 0 var(--color-primary);
		padding-left: var(--space-2);
		padding-right: var(--space-2);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease, transform 80ms ease;
	}
	.sp-slot--me:active {
		transform: scale(0.98);
	}
	.sp-slot--me:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.sp-slot--me.sp-slot--confirmed {
		background: color-mix(in srgb, var(--color-success) 8%, transparent);
		box-shadow: inset 3px 0 0 var(--color-success);
	}
	.sp-slot--me.sp-slot--declined {
		background: color-mix(in srgb, var(--color-primary) 6%, transparent);
		box-shadow: inset 3px 0 0 var(--color-primary);
	}
	.sp-slot--me .sp-slot-avatar {
		border: 2px solid var(--color-primary);
	}
	.sp-slot--me.sp-slot--confirmed .sp-slot-avatar {
		border-color: var(--color-success);
	}
	.sp-slot--me .sp-slot-name {
		flex: 0 1 auto;
		min-width: 0;
	}
	.sp-slot-du {
		font-family: var(--font-display);
		font-size: var(--text-label-sm);
		font-weight: 800;
		letter-spacing: 0.04em;
		color: var(--color-primary);
		padding: 2px var(--space-2);
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
		border-radius: var(--radius-full);
		flex-shrink: 0;
	}
	.sp-slot--me.sp-slot--confirmed .sp-slot-du {
		color: var(--color-success);
		background: color-mix(in srgb, var(--color-success) 10%, transparent);
	}
	.sp-slot--me.sp-slot--pending .sp-slot-status--pending {
		color: var(--color-primary);
	}
	.sp-slot--me.sp-slot--disabled {
		cursor: not-allowed;
		opacity: 0.7;
	}
	.sp-slot--me.sp-slot--disabled:active {
		transform: none;
	}

	/* ── Carpool-Footer ──────────────────────────────────────────────────── */
	.sp-carpool {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-height: 44px;
		margin-top: var(--space-3);
		padding: var(--space-2) var(--space-2) var(--space-2);
		border-top: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease, transform 80ms ease;
	}
	.sp-carpool:active {
		transform: scale(0.98);
	}
	.sp-carpool:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.sp-carpool-icon {
		font-size: 1.1rem;
		color: var(--color-on-surface-variant);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
		flex-shrink: 0;
	}
	.sp-carpool-label {
		flex: 1;
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		font-weight: 600;
		color: var(--color-on-surface);
	}
	.sp-carpool-chevron {
		font-size: 1rem;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
	}

	/* ── Feedback-Sheet-Wrap ─────────────────────────────────────────────── */
	.sp-fb-wrap {
		padding: var(--space-2) 0 var(--space-4);
	}

	/* ── Captain-Strip (offene Bestätigungen + Erinnerung) ───────────────── */
	.sp-cap-strip {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		margin-top: var(--space-3);
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--color-secondary) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-secondary) 35%, transparent);
		border-radius: var(--radius-md);
		flex-wrap: wrap;
	}
	.sp-cap-strip-info {
		display: flex;
		align-items: flex-start;
		gap: var(--space-2);
		flex: 1;
		min-width: 0;
	}
	.sp-cap-strip-icon {
		font-size: 1.1rem;
		color: color-mix(in srgb, var(--color-secondary) 70%, var(--color-on-surface));
		flex-shrink: 0;
		margin-top: 2px;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.sp-cap-strip-text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.sp-cap-strip-count {
		font-family: var(--font-display);
		font-size: var(--text-label-sm);
		font-weight: 800;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: color-mix(in srgb, var(--color-secondary) 70%, var(--color-on-surface));
	}
	.sp-cap-strip-names {
		font-family: var(--font-body);
		font-size: var(--text-label-md);
		font-weight: 600;
		color: var(--color-on-surface);
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.sp-cap-strip-btn {
		flex-shrink: 0;
	}
	.sp-cap-strip-btn .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	/* ── Sheet-Loading ───────────────────────────────────────────────────── */
	.sp-sheet-loading {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-10) var(--space-4);
		color: var(--color-outline);
	}
	.sp-sheet-loading-icon {
		font-size: 2rem;
		opacity: 0.4;
	}
</style>
