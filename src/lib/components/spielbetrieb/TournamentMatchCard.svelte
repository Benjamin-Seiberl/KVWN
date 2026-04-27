<script>
	import { onMount }   from 'svelte';
	import { sb }        from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime } from '$lib/utils/dates.js';
	import { imgPath } from '$lib/utils/players.js';

	let { tournament, onReload = () => {} } = $props();

	// ── State ──────────────────────────────────────────────────────
	let dateOptions   = $state([]);
	let votes         = $state([]);
	let dateVotes     = $state([]);
	let rounds        = $state([]);
	let assignments   = $state([]);
	let allPlayers    = $state([]);
	let savingStatus  = $state(false);
	let scoreInputs   = $state({});

	const statusLabels     = { voting:'Abstimmung läuft', voting_closed:'Geschlossen', scheduling:'Spielplan', confirmed:'Bestätigt ✓' };
	const isAdmin          = $derived($playerRole === 'kapitaen');
	const status           = $derived(tournament.status ?? 'voting');
	const votingDeadline   = $derived(tournament.voting_deadline ? new Date(tournament.voting_deadline) : null);
	const deadlinePassed   = $derived(votingDeadline ? votingDeadline < new Date() : false);
	const votingOpen       = $derived(status === 'voting' && !deadlinePassed);
	const myVote           = $derived(votes.find(v => v.player_id === $playerId));
	const myDateVoteIds    = $derived(dateVotes.filter(v => v.player_id === $playerId).map(v => v.date_option_id));
	const yesPlayers       = $derived(votes.filter(v => v.wants_to_play));
	const maxDateVotes     = $derived(Math.max(1, ...dateOptions.map(o => dateVoteCount(o.id))));

	let newTeamName  = $state('');
	let newStartTime = $state('');
	let addingTeam   = $state(false);

	function dateVoteCount(optionId) {
		return dateVotes.filter(v => v.date_option_id === optionId).length;
	}
	function scoreKey(a) { return a.round_id + '_' + a.lane_number; }

	// ── Load ───────────────────────────────────────────────────────
	async function load() {
		const [
			{ data: opts },
			{ data: v },
			{ data: dv },
			{ data: r },
			{ data: p },
		] = await Promise.all([
			sb.from('tournament_date_options').select('*').eq('tournament_id', tournament.id).order('date'),
			sb.from('tournament_votes').select('*, players(name, photo)').eq('tournament_id', tournament.id),
			sb.from('tournament_date_votes').select('*').eq('tournament_id', tournament.id),
			sb.from('tournament_rounds').select('*').eq('tournament_id', tournament.id).order('round_number'),
			sb.from('players').select('id, name, photo').eq('active', true).order('name'),
		]);
		dateOptions = opts ?? [];
		votes       = v   ?? [];
		dateVotes   = dv  ?? [];
		rounds      = r   ?? [];
		allPlayers  = p   ?? [];
		if (rounds.length) {
			const { data: a } = await sb
				.from('tournament_round_players').select('*')
				.in('round_id', rounds.map(x => x.id));
			assignments = a ?? [];
			// Seed score inputs from loaded data
			const next = {};
			for (const asg of (a ?? [])) {
				next[scoreKey(asg)] = asg.score ?? '';
			}
			scoreInputs = next;
		} else {
			assignments = [];
			scoreInputs = {};
		}
	}

	// ── Abstimmung ─────────────────────────────────────────────────
	async function voteParticipation(wants) {
		if (!votingOpen) return;
		await sb.from('tournament_votes').upsert(
			{ tournament_id: tournament.id, player_id: $playerId, wants_to_play: wants },
			{ onConflict: 'tournament_id,player_id' }
		);
		await load();
	}

	async function toggleDateVote(optionId) {
		if (!votingOpen) return;
		if (myDateVoteIds.includes(optionId)) {
			await sb.from('tournament_date_votes').delete()
				.eq('tournament_id', tournament.id).eq('player_id', $playerId).eq('date_option_id', optionId);
		} else {
			await sb.from('tournament_date_votes')
				.insert({ tournament_id: tournament.id, player_id: $playerId, date_option_id: optionId });
		}
		await load();
	}

	// ── Status-Übergänge (Kapitän) ─────────────────────────────────
	async function setStatus(s) {
		savingStatus = true;
		const { error } = await sb.from('tournaments').update({ status: s }).eq('id', tournament.id);
		savingStatus = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		tournament = { ...tournament, status: s };
		triggerToast(s === 'voting_closed' ? 'Abstimmung geschlossen' :
		             s === 'scheduling'    ? 'Spielplan-Phase' :
		             s === 'confirmed'     ? 'Turnier bestätigt!' : '');
		await load();
		onReload();
	}

	// ── Datum bestätigen (nach Voting) ─────────────────────────────
	const sortedDateOptions = $derived.by(() => {
		return [...dateOptions]
			.map(o => ({ ...o, _count: dateVoteCount(o.id) }))
			.sort((a, b) => b._count - a._count || a.date.localeCompare(b.date));
	});

	async function confirmTournamentDate(opt) {
		if (!opt?.date) return;
		savingStatus = true;
		const { error } = await sb.from('tournaments')
			.update({ confirmed_date: opt.date })
			.eq('id', tournament.id);
		savingStatus = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		tournament = { ...tournament, confirmed_date: opt.date };
		triggerToast('Termin bestätigt: ' + fmtDate(opt.date));
		onReload();
	}

	// ── Mannschaft anlegen / entfernen ─────────────────────────────
	async function addTeam() {
		if (!newTeamName || !newStartTime) return;
		addingTeam = true;
		const nextNum = (rounds.at(-1)?.round_number ?? 0) + 1;
		await sb.from('tournament_rounds').insert({
			tournament_id: tournament.id, round_number: nextNum,
			start_time: newStartTime, lane_count: 4, team_name: newTeamName,
		});
		newTeamName = ''; newStartTime = '';
		addingTeam = false;
		await load();
	}

	async function removeTeam(r) {
		await sb.from('tournament_rounds').delete().eq('id', r.id);
		await load();
		triggerToast('Mannschaft entfernt');
	}

	// ── Bahn-Zuweisung ─────────────────────────────────────────────
	function assignmentFor(roundId, lane) {
		return assignments.find(a => a.round_id === roundId && a.lane_number === lane);
	}
	function getPlayer(id) { return allPlayers.find(p => p.id === id); }

	async function setLane(round, lane, pid) {
		const existing = assignmentFor(round.id, lane);
		if (!pid) {
			if (existing) await sb.from('tournament_round_players')
				.delete().eq('round_id', round.id).eq('lane_number', lane);
		} else if (existing) {
			await sb.from('tournament_round_players')
				.update({ player_id: pid }).eq('round_id', round.id).eq('lane_number', lane);
		} else {
			await sb.from('tournament_round_players')
				.insert({ round_id: round.id, lane_number: lane, player_id: pid });
		}
		await load();
	}

	async function selfAssign(round, lane) {
		await setLane(round, lane, $playerId);
		triggerToast('Du bist eingetragen!');
	}

	async function saveScore(a) {
		const val = scoreInputs[scoreKey(a)];
		const n = Number(val);
		if (!Number.isFinite(n)) return;
		await sb.from('tournament_round_players')
			.update({ score: n }).eq('round_id', a.round_id).eq('lane_number', a.lane_number);
		const pl = getPlayer(a.player_id);
		if (pl) triggerToast(`${pl.name}: ${n} Holz`);
		await load();
	}

	onMount(load);
</script>

<!-- ═══════════════════════════════════════ TURNIER-DETAIL ════ -->
<div class="twd">

	<!-- Header -->
	<div class="twd-header">
		<div class="twd-trophy">
			<span class="material-symbols-outlined">military_tech</span>
		</div>
		<div class="twd-header-info">
			<h2 class="twd-title">{tournament.title ?? 'Turnier'}</h2>
			{#if tournament.location}
				<p class="twd-location">
					<span class="material-symbols-outlined twd-location-icon">location_on</span>
					{tournament.location}
				</p>
			{/if}
		</div>
		<span class="twd-status-badge twd-status-badge--{status}">{statusLabels[status] ?? status}</span>
	</div>

	<!-- ═══ PHASE: VOTING / VOTING_CLOSED ═══ -->
	{#if status === 'voting' || status === 'voting_closed'}

		<!-- Deadline-Info -->
		{#if votingDeadline}
			<div class="twd-deadline-banner" class:twd-deadline-banner--closed={deadlinePassed}>
				<span class="material-symbols-outlined">alarm</span>
				{#if deadlinePassed}
					Abstimmung beendet am {votingDeadline.toLocaleString('de-AT', { dateStyle: 'medium', timeStyle: 'short' })}
				{:else}
					Abstimmung bis {votingDeadline.toLocaleString('de-AT', { dateStyle: 'medium', timeStyle: 'short' })}
				{/if}
			</div>
		{/if}

		<!-- Teilnahme -->
		<div class="twd-section">
			<h3 class="twd-sec-title">
				<span class="material-symbols-outlined">how_to_vote</span>
				Nimmst du teil?
			</h3>
			{#if votingOpen}
				<div class="twd-vote-row">
					<button
						class="twd-vote-btn twd-vote-btn--yes"
						class:twd-vote-btn--active={myVote?.wants_to_play === true}
						onclick={() => voteParticipation(true)}
					>
						<span class="material-symbols-outlined">check_circle</span>
						Ich bin dabei
					</button>
					<button
						class="twd-vote-btn twd-vote-btn--no"
						class:twd-vote-btn--active={myVote?.wants_to_play === false}
						onclick={() => voteParticipation(false)}
					>
						<span class="material-symbols-outlined">cancel</span>
						Nicht dabei
					</button>
				</div>
			{:else}
				<p class="twd-muted">
					{deadlinePassed ? 'Abstimmungsfrist ist abgelaufen.' : 'Abstimmung ist geschlossen.'}
				</p>
			{/if}
		</div>

		<!-- Terminstimmung -->
		{#if dateOptions.length > 0}
			<div class="twd-section">
				<h3 class="twd-sec-title">
					<span class="material-symbols-outlined">calendar_month</span>
					{votingOpen ? 'Welche Tage passen dir?' : 'Terminauswertung'}
				</h3>
				<div class="twd-dates">
					{#each dateOptions as opt}
						{@const count   = dateVoteCount(opt.id)}
						{@const myVoted = myDateVoteIds.includes(opt.id)}
						{@const barPct  = Math.round((count / maxDateVotes) * 100)}
						<div class="twd-date-row">
							{#if votingOpen}
								<button
									class="twd-date-toggle"
									class:twd-date-toggle--on={myVoted}
									onclick={() => toggleDateVote(opt.id)}
								>
									<span class="material-symbols-outlined">
										{myVoted ? 'check_box' : 'check_box_outline_blank'}
									</span>
								</button>
							{/if}
							<span class="twd-date-label">{fmtDate(opt.date)}</span>
							<div class="twd-bar-wrap">
								<div class="twd-bar" style="width:{barPct}%"></div>
							</div>
							<span class="twd-date-count">{count}</span>
						</div>
					{/each}
				</div>
			</div>
		{/if}

		<!-- Zusagen -->
		<div class="twd-section">
			<h3 class="twd-sec-title">
				<span class="material-symbols-outlined">group</span>
				Zusagen ({yesPlayers.length})
			</h3>
			{#if yesPlayers.length === 0}
				<p class="twd-muted">Noch keine Zusagen</p>
			{:else}
				<div class="twd-yes-chips">
					{#each yesPlayers as v}
						{@const pl = v.players}
						<div class="twd-yes-chip">
							<img class="twd-yes-photo"
								src={imgPath(pl?.photo, pl?.name)} alt={pl?.name ?? ''}
								onerror={(e) => { e.currentTarget.src='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
							/>
							<span class="twd-yes-name">{pl?.name?.split(' ')[0] ?? '?'}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Kapitän-Zone -->
		{#if isAdmin}
			<div class="twd-section twd-admin-zone">
				{#if status === 'voting'}
					<button class="twd-btn twd-btn--warn" onclick={() => setStatus('voting_closed')} disabled={savingStatus}>
						<span class="material-symbols-outlined">lock</span>
						Abstimmung schließen
					</button>

				{:else if !tournament.confirmed_date && dateOptions.length > 0}
					<!-- Termin bestätigen (nach geschlossener Abstimmung) -->
					<h3 class="twd-sec-title" style="margin-bottom:var(--space-3)">
						<span class="material-symbols-outlined">event_available</span>
						Termin bestätigen
					</h3>
					<p class="twd-muted" style="margin-bottom:var(--space-3)">
						Wähle den endgültigen Termin. Nach Vote-Stimmen sortiert.
					</p>
					<div class="twd-confirm-list">
						{#each sortedDateOptions as opt, i (opt.id)}
							{@const isWinner = i === 0 && opt._count > 0}
							<button
								class="twd-confirm-row"
								class:twd-confirm-row--winner={isWinner}
								onclick={() => confirmTournamentDate(opt)}
								disabled={savingStatus}
							>
								<span class="twd-confirm-date">{fmtDate(opt.date)}</span>
								<span class="twd-confirm-count">
									<span class="material-symbols-outlined">how_to_vote</span>
									{opt._count}
								</span>
								<span class="material-symbols-outlined twd-confirm-cta">check</span>
							</button>
						{/each}
					</div>

				{:else}
					<!-- Mannschaften anlegen -->
					<h3 class="twd-sec-title" style="margin-bottom:var(--space-3)">
						<span class="material-symbols-outlined">group_add</span>
						Mannschaften anlegen
					</h3>

					{#each rounds as r}
						<div class="twd-team-row">
							<span class="material-symbols-outlined twd-team-icon">shield</span>
							<span class="twd-team-rowname">{r.team_name} — {fmtTime(r.start_time)}</span>
							<button class="twd-icon-btn" onclick={() => removeTeam(r)}>
								<span class="material-symbols-outlined">delete</span>
							</button>
						</div>
					{/each}

					<div class="twd-add-row">
						<input class="tp-input" type="text" placeholder="z.B. KV WN 1" bind:value={newTeamName} />
						<input class="tp-input twd-time-inp" type="time" bind:value={newStartTime} />
						<button class="twd-btn twd-btn--add" onclick={addTeam} disabled={!newTeamName || !newStartTime || addingTeam}>
							<span class="material-symbols-outlined">add</span>
						</button>
					</div>

					{#if rounds.length > 0}
						<button class="twd-btn twd-btn--primary" onclick={() => setStatus('scheduling')} disabled={savingStatus} style="margin-top:var(--space-3)">
							<span class="material-symbols-outlined">arrow_forward</span>
							Zur Spielplan-Phase
						</button>
					{/if}
				{/if}
			</div>
		{/if}

	<!-- ═══ PHASE: SCHEDULING / CONFIRMED ═══ -->
	{:else if status === 'scheduling' || status === 'confirmed'}
		{@const locked = status === 'confirmed'}

		<!-- Bestätigter Termin -->
		{#if tournament.confirmed_date}
			<div class="twd-deadline-banner">
				<span class="material-symbols-outlined">event</span>
				{fmtDate(tournament.confirmed_date)}
				{#if tournament.confirmed_time} · {fmtTime(tournament.confirmed_time)}{/if}
			</div>
		{/if}

		<div class="twd-section">
			<h3 class="twd-sec-title">
				<span class="material-symbols-outlined">schedule</span>
				Spielplan
			</h3>

			{#if rounds.length === 0}
				<p class="twd-muted">Noch keine Mannschaften eingetragen.</p>
			{/if}

			{#each rounds as r}
				<div class="twd-round-card">
					<div class="twd-round-head">
						<span class="material-symbols-outlined twd-round-icon">shield</span>
						<strong class="twd-round-name">{r.team_name ?? 'Mannschaft ' + r.round_number}</strong>
						<span class="twd-round-time">{fmtTime(r.start_time)}</span>
						{#if isAdmin && !locked}
							<button class="mini-del" onclick={() => removeTeam(r)}>
								<span class="material-symbols-outlined">close</span>
							</button>
						{/if}
					</div>

					<div class="twd-lanes">
						{#each Array(r.lane_count) as _, i}
							{@const lane  = i + 1}
							{@const a     = assignmentFor(r.id, lane)}
							{@const pl    = a ? getPlayer(a.player_id) : null}
							{@const isMe  = a?.player_id === $playerId}

							<div class="twd-lane" class:twd-lane--me={isMe}>
								<span class="twd-lane-num">Bahn {lane}</span>

								{#if pl}
									<div class="twd-lane-player">
										<img class="twd-lane-photo"
											src={imgPath(pl.photo, pl.name)} alt={pl.name}
											onerror={(e) => { e.currentTarget.src='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
										/>
										<span class="twd-lane-name">{pl.name.split(' ')[0]}</span>
									</div>
									{#if !locked}
										{#if isAdmin}
											<select class="twd-lane-sel" value={a.player_id}
												onchange={(e) => setLane(r, lane, e.target.value || null)}>
												<option value="">— frei —</option>
												{#each allPlayers as p}<option value={p.id}>{p.name}</option>{/each}
											</select>
											<div class="twd-score-wrap">
												<input class="twd-lane-score" type="number" min="0" max="999"
													inputmode="numeric" placeholder="Holz"
													bind:value={scoreInputs[scoreKey(a)]}
												/>
												<button class="twd-score-save-btn" onclick={() => saveScore(a)}
													disabled={scoreInputs[scoreKey(a)] === '' || scoreInputs[scoreKey(a)] == null}>
													<span class="material-symbols-outlined">check</span>
												</button>
											</div>
										{:else if isMe}
											<button class="twd-icon-btn" onclick={() => setLane(r, lane, null)}>
												<span class="material-symbols-outlined">close</span>
											</button>
										{/if}
									{:else if a.score != null}
										<span class="twd-score-display">{a.score} Holz</span>
									{/if}
								{:else}
									<!-- Freie Bahn -->
									{#if !locked}
										{#if isAdmin}
											<select class="twd-lane-sel" value=""
												onchange={(e) => setLane(r, lane, e.target.value || null)}>
												<option value="">— frei —</option>
												{#each allPlayers as p}<option value={p.id}>{p.name}</option>{/each}
											</select>
										{:else}
											<button class="twd-self-assign" onclick={() => selfAssign(r, lane)}>
												<span class="material-symbols-outlined">add_circle</span>
												Ich trage mich ein
											</button>
										{/if}
									{:else}
										<span class="twd-muted">Frei</span>
									{/if}
								{/if}
							</div>
						{/each}
					</div>
				</div>
			{/each}
		</div>

		<!-- Kapitän: Mannschaft + Bestätigen -->
		{#if isAdmin && !locked}
			<div class="twd-section twd-admin-zone">
				<h3 class="twd-sec-title" style="margin-bottom:var(--space-3)">
					<span class="material-symbols-outlined">add_circle</span>
					Mannschaft hinzufügen
				</h3>
				<div class="twd-add-row">
					<input class="tp-input" type="text" placeholder="z.B. KV WN 2" bind:value={newTeamName} />
					<input class="tp-input twd-time-inp" type="time" bind:value={newStartTime} />
					<button class="twd-btn twd-btn--add" onclick={addTeam} disabled={!newTeamName || !newStartTime || addingTeam}>
						<span class="material-symbols-outlined">add</span>
					</button>
				</div>

				<button class="twd-btn twd-btn--primary" onclick={() => setStatus('confirmed')} disabled={savingStatus} style="margin-top:var(--space-4)">
					<span class="material-symbols-outlined">check_circle</span>
					Turnier bestätigen &amp; Zeiten fixieren
				</button>
			</div>
		{/if}
	{/if}

</div>

<style>
	.twd { padding: var(--space-3) var(--space-3) var(--space-8); display: flex; flex-direction: column; gap: var(--space-3); }

	/* Header */
	.twd-header { background: var(--color-surface-container-lowest); border: 1px solid var(--color-outline-variant); border-radius: var(--radius-xl); padding: var(--space-4); display: flex; align-items: flex-start; gap: var(--space-3); }
	.twd-trophy { width: 44px; height: 44px; border-radius: var(--radius-full); background: linear-gradient(135deg,#d4af37,#fef3a0); display:flex; align-items:center; justify-content:center; flex-shrink:0; }
	.twd-trophy .material-symbols-outlined { font-size:1.4rem; color:#6b4c00; font-variation-settings:'FILL' 1; }
	.twd-header-info { flex:1; min-width:0; }
	.twd-title { font-family:var(--font-display); font-size:var(--text-title-md); font-weight:800; color:var(--color-on-surface); margin:0 0 2px; }
	.twd-location { display:flex; align-items:center; gap:3px; font-size:var(--text-body-sm); color:var(--color-on-surface-variant); margin:0; }
	.twd-location-icon { font-size:0.8rem; }

	.twd-status-badge { flex-shrink:0; font-family:var(--font-display); font-size:0.6rem; font-weight:800; letter-spacing:0.05em; text-transform:uppercase; padding:3px 8px; border-radius:var(--radius-full); white-space:nowrap; }
	.twd-status-badge--voting        { background:rgba(204,0,0,0.1);   color:var(--color-primary); }
	.twd-status-badge--voting_closed { background:rgba(0,0,0,0.08);    color:var(--color-on-surface-variant); }
	.twd-status-badge--scheduling    { background:rgba(25,118,210,0.1); color:#1976d2; }
	.twd-status-badge--confirmed     { background:rgba(46,125,50,0.12); color:#2e7d32; }

	/* Deadline-Banner */
	.twd-deadline-banner { display:flex; align-items:center; gap:8px; padding:10px 14px; border-radius:12px; font-size:0.85rem; font-weight:600; background:rgba(212,175,55,0.12); color:#7a5a00; border:1px solid rgba(212,175,55,0.3); }
	.twd-deadline-banner .material-symbols-outlined { font-size:1.1rem; font-variation-settings:'FILL' 1; }
	.twd-deadline-banner--closed { background:rgba(0,0,0,0.06); color:var(--color-on-surface-variant); border-color:rgba(0,0,0,0.1); }

	/* Sections */
	.twd-section { background:var(--color-surface-container-lowest); border:1px solid var(--color-outline-variant); border-radius:var(--radius-xl); padding:var(--space-4); }
	.twd-sec-title { display:flex; align-items:center; gap:var(--space-2); font-family:var(--font-display); font-size:var(--text-label-lg); font-weight:800; color:var(--color-on-surface); margin:0 0 var(--space-3); }
	.twd-sec-title .material-symbols-outlined { font-size:1.1rem; color:var(--color-primary); font-variation-settings:'FILL' 1; }
	.twd-muted { font-size:var(--text-body-sm); color:var(--color-on-surface-variant); margin:0; }
	.twd-admin-zone { border-color:rgba(204,0,0,0.2); background:rgba(204,0,0,0.02); }

	/* Teilnahme-Buttons */
	.twd-vote-row { display:flex; gap:var(--space-2); }
	.twd-vote-btn { flex:1; display:flex; align-items:center; justify-content:center; gap:var(--space-2); padding:var(--space-3); border-radius:var(--radius-lg); border:2px solid var(--color-outline-variant); background:var(--color-surface-container); font-family:var(--font-display); font-size:var(--text-label-lg); font-weight:700; color:var(--color-on-surface-variant); cursor:pointer; transition:border-color 150ms,background 150ms,color 150ms; -webkit-tap-highlight-color:transparent; }
	.twd-vote-btn .material-symbols-outlined { font-size:1.1rem; font-variation-settings:'FILL' 1; }
	.twd-vote-btn--yes.twd-vote-btn--active { border-color:#2e7d32; background:rgba(46,125,50,0.1); color:#2e7d32; }
	.twd-vote-btn--no.twd-vote-btn--active  { border-color:var(--color-primary); background:rgba(204,0,0,0.08); color:var(--color-primary); }

	/* Datums-Reihen */
	.twd-dates { display:flex; flex-direction:column; gap:var(--space-2); }
	.twd-date-row { display:flex; align-items:center; gap:var(--space-2); }
	.twd-date-toggle { background:none; border:none; padding:0; cursor:pointer; color:var(--color-on-surface-variant); -webkit-tap-highlight-color:transparent; }
	.twd-date-toggle--on { color:var(--color-primary); }
	.twd-date-toggle .material-symbols-outlined { font-size:1.3rem; font-variation-settings:'FILL' 1; }
	.twd-date-label { min-width:110px; font-family:var(--font-display); font-size:var(--text-body-sm); font-weight:700; color:var(--color-on-surface); }
	.twd-bar-wrap { flex:1; height:6px; background:var(--color-surface-container); border-radius:var(--radius-full); overflow:hidden; }
	.twd-bar { height:100%; background:var(--color-primary); border-radius:var(--radius-full); transition:width 400ms ease; min-width:4px; }
	.twd-date-count { font-family:var(--font-display); font-size:var(--text-label-md); font-weight:700; color:var(--color-on-surface-variant); min-width:20px; text-align:right; }

	/* Zusagen-Chips */
	.twd-yes-chips { display:flex; flex-wrap:wrap; gap:var(--space-2); }
	.twd-yes-chip { display:flex; flex-direction:column; align-items:center; gap:3px; }
	.twd-yes-photo { width:40px; height:40px; border-radius:var(--radius-full); object-fit:cover; object-position:top center; background:var(--color-surface-container); border:2px solid var(--color-outline-variant); }
	.twd-yes-name { font-family:var(--font-display); font-size:0.6rem; font-weight:700; color:var(--color-on-surface-variant); }

	/* Aktions-Buttons */
	.twd-btn { width:100%; display:flex; align-items:center; justify-content:center; gap:var(--space-2); padding:var(--space-3) var(--space-4); border-radius:var(--radius-full); border:none; cursor:pointer; font-family:var(--font-display); font-size:var(--text-label-lg); font-weight:800; transition:opacity 150ms; -webkit-tap-highlight-color:transparent; }
	.twd-btn:disabled { opacity:0.5; cursor:default; }
	.twd-btn .material-symbols-outlined { font-size:1.1rem; font-variation-settings:'FILL' 1; }
	.twd-btn--primary { background:var(--color-primary); color:#fff; }
	.twd-btn--warn    { background:rgba(204,0,0,0.1); color:var(--color-primary); }
	.twd-btn--add     { width:auto; padding:var(--space-2) var(--space-3); background:var(--color-primary); color:#fff; flex-shrink:0; }
	.twd-icon-btn     { background:none; border:none; cursor:pointer; padding:4px; color:var(--color-on-surface-variant); }
	.twd-icon-btn .material-symbols-outlined { font-size:1.1rem; }

	/* Mannschafts-Zeile (Entwurf) */
	.twd-team-row { display:flex; align-items:center; gap:var(--space-2); padding:var(--space-2) var(--space-3); background:var(--color-surface-container); border-radius:var(--radius-lg); margin-bottom:var(--space-2); }
	.twd-team-icon { font-size:1rem; color:var(--color-primary); font-variation-settings:'FILL' 1; }
	.twd-team-rowname { flex:1; font-family:var(--font-display); font-weight:700; font-size:var(--text-body-sm); }
	.twd-add-row { display:flex; gap:var(--space-2); align-items:center; margin-top:var(--space-2); }
	.twd-add-row .tp-input { flex:1; }
	.twd-time-inp { flex:0 0 110px !important; }

	/* Runden-Karten (Scheduling) */
	.twd-round-card { background:var(--color-surface-container); border-radius:var(--radius-lg); overflow:hidden; margin-bottom:var(--space-3); }
	.twd-round-head { display:flex; align-items:center; gap:var(--space-2); padding:var(--space-3); background:var(--color-surface-container-high); }
	.twd-round-icon { font-size:1rem; color:var(--color-primary); font-variation-settings:'FILL' 1; }
	.twd-round-name { font-family:var(--font-display); font-weight:800; font-size:var(--text-body-sm); flex:1; }
	.twd-round-time { font-size:var(--text-body-sm); color:var(--color-on-surface-variant); }
	.mini-del { margin-left:auto; background:none; border:0; color:var(--color-on-surface-variant); cursor:pointer; }
	.mini-del .material-symbols-outlined { font-size:1.1rem; }

	.twd-lanes { display:flex; flex-direction:column; }
	.twd-lane { display:flex; align-items:center; gap:var(--space-2); padding:var(--space-2) var(--space-3); border-top:1px solid var(--color-outline-variant); }
	.twd-lane--me { background:rgba(204,0,0,0.04); }
	.twd-lane-num { min-width:52px; font-family:var(--font-display); font-size:0.7rem; font-weight:700; color:var(--color-on-surface-variant); text-transform:uppercase; letter-spacing:0.04em; }
	.twd-lane-player { display:flex; align-items:center; gap:var(--space-2); flex:1; min-width:0; }
	.twd-lane-photo { width:28px; height:28px; border-radius:var(--radius-full); object-fit:cover; object-position:top center; background:var(--color-surface-container); flex-shrink:0; }
	.twd-lane-name { font-family:var(--font-display); font-weight:700; font-size:var(--text-body-sm); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
	.twd-lane-sel { flex:1; max-width:130px; padding:4px 6px; font-size:13px; border:1px solid var(--color-outline-variant); border-radius:var(--radius-md); background:var(--color-surface); }
	.twd-score-wrap { display:flex; align-items:center; gap:4px; }
	.twd-lane-score { width:60px; text-align:right; padding:4px 6px; font-size:14px; border:1px solid var(--color-outline-variant); border-radius:var(--radius-md); background:var(--color-surface); }
	.twd-score-save-btn { display:flex; align-items:center; justify-content:center; width:30px; height:30px; border-radius:var(--radius-full); border:none; background:var(--color-primary); color:#fff; cursor:pointer; flex-shrink:0; }
	.twd-score-save-btn:disabled { opacity:0.4; cursor:default; }
	.twd-score-save-btn .material-symbols-outlined { font-size:0.95rem; font-variation-settings:'FILL' 1; }
	.twd-score-display { font-family:var(--font-display); font-weight:700; font-size:var(--text-body-sm); color:var(--color-on-surface); margin-left:auto; }
	.twd-self-assign { display:flex; align-items:center; gap:4px; padding:4px 10px; border-radius:var(--radius-full); border:1.5px dashed var(--color-primary); background:rgba(204,0,0,0.05); color:var(--color-primary); font-family:var(--font-display); font-size:var(--text-label-md); font-weight:700; cursor:pointer; -webkit-tap-highlight-color:transparent; }
	.twd-self-assign .material-symbols-outlined { font-size:0.95rem; font-variation-settings:'FILL' 1; }

	/* Termin bestätigen — nach Voting */
	.twd-confirm-list { display:flex; flex-direction:column; gap:var(--space-2); }
	.twd-confirm-row {
		display:flex; align-items:center; gap:var(--space-3);
		width:100%; padding:var(--space-3) var(--space-4);
		background:var(--color-surface-container);
		border:1.5px solid var(--color-outline-variant);
		border-radius:var(--radius-lg);
		cursor:pointer; font:inherit;
		-webkit-tap-highlight-color:transparent;
		transition:transform 100ms ease, border-color 150ms ease, background 150ms ease;
	}
	.twd-confirm-row:active { transform:scale(0.98); }
	.twd-confirm-row:disabled { opacity:0.5; cursor:default; }
	.twd-confirm-row--winner {
		border-color:var(--color-success);
		background:color-mix(in srgb, var(--color-success) 8%, transparent);
	}
	.twd-confirm-date {
		flex:1; font-family:var(--font-display);
		font-size:var(--text-body-md); font-weight:700;
		color:var(--color-on-surface); text-align:left;
	}
	.twd-confirm-count {
		display:inline-flex; align-items:center; gap:4px;
		font-family:var(--font-display);
		font-size:var(--text-label-md); font-weight:700;
		color:var(--color-on-surface-variant);
	}
	.twd-confirm-count .material-symbols-outlined {
		font-size:0.95rem;
		font-variation-settings:'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.twd-confirm-cta {
		font-size:1.1rem;
		color:var(--color-success);
		font-variation-settings:'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.twd-confirm-row--winner .twd-confirm-date { color:var(--color-success); }
</style>
