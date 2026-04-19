<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { user } from '$lib/stores/auth';
	import { DAY_SHORT } from '$lib/utils/dates.js';
	import { imgPath } from '$lib/utils/players.js';

	// --- Lineup state ---
	let loadingLineup = $state(true);
	let myPlayer      = $state(null);
	let pendingEntry  = $state(null);
	let match         = $state(null);
	let teammates     = $state([]);
	let busy          = $state(false);
	let lineupDone    = $state(false);
	let lineupOpen    = $state(false);

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
		return DAY_SHORT[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '. \u2022 ' +
			(m.time ? m.time.substring(0, 5) : '') + ' Uhr';
	}

	async function loadPending(email) {
		const { data: player } = await sb
			.from('players').select('id, name').eq('email', email).maybeSingle();
		if (!player) { loadingLineup = false; return; }
		myPlayer = player;

		const range = getWeekRange();
		const { data: matches } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', range.from).lte('date', range.to)
			.order('date').order('time');
		if (!matches?.length) { loadingLineup = false; return; }

		for (const m of matches) {
			if (!m.cal_week || !m.league_id) continue;
			const { data: gp } = await sb
				.from('game_plans')
				.select('id, game_plan_players(id, confirmed, position, player_id, player_name, players(name, photo))')
				.eq('cal_week', m.cal_week)
				.eq('league_id', m.league_id)
				.maybeSingle();
			if (!gp) continue;
			const myEntry = gp.game_plan_players?.find(p => p.player_id === player.id);
			if (myEntry && myEntry.confirmed === null) {
				pendingEntry = myEntry;
				match        = m;
				teammates    = (gp.game_plan_players ?? [])
					.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));
				lineupOpen   = true;
				break;
			}
		}
		loadingLineup = false;
	}

	async function respond(confirmed) {
		if (busy || !pendingEntry) return;
		busy = true;
		await sb.from('game_plan_players').update({ confirmed }).eq('id', pendingEntry.id);
		lineupDone = true;
		pendingEntry = null;
		lineupOpen   = false;
		busy = false;
	}

	let loaded = false;
	$effect(() => {
		if ($user?.email && !loaded) {
			loaded = true;
			loadPending($user.email);
		} else if (!$user) {
			loadingLineup = false;
		}
	});

	let lineupCount = $derived(!loadingLineup && pendingEntry ? 1 : 0);
</script>

<div class="widget widget--card ah">
	<!-- Aufstellungsbestätigung -->
	<div
		class="ah-item"
		class:ah-item--active={lineupCount > 0}
		class:ah-item--done={lineupDone && lineupCount === 0}
		role="button"
		tabindex="0"
		onclick={() => { if (lineupCount > 0) lineupOpen = !lineupOpen; }}
		onkeydown={(e) => { if ((e.key === 'Enter' || e.key === ' ') && lineupCount > 0) lineupOpen = !lineupOpen; }}
	>
		<div class="ah-item-icon-wrap" class:ah-item-icon-wrap--accent={lineupCount > 0}>
			<span class="material-symbols-outlined">sports_score</span>
		</div>
		<div class="ah-item-text">
			<span class="ah-item-label">Aufstellungsbestätigung</span>
			<span class="ah-item-sub">
				{#if loadingLineup}
					Lade…
				{:else if lineupDone}
					Erledigt
				{:else if lineupCount > 0}
					{match?.leagues?.name ?? ''} · {match?.opponent ?? ''}
				{:else}
					Keine offen
				{/if}
			</span>
		</div>
		{#if lineupCount > 0}
			<span class="ah-badge">{lineupCount}</span>
			<span class="material-symbols-outlined ah-expand-icon" class:ah-expand-icon--open={lineupOpen}>
				expand_more
			</span>
		{:else if lineupDone}
			<span class="material-symbols-outlined ah-done-icon">check_circle</span>
		{/if}
	</div>

	<!-- Inline Lineup Confirm -->
	{#if lineupOpen && pendingEntry && match}
		<div class="ah-lineup">
			<div class="ah-lineup-meta">
				<span class="ah-lineup-league">{match.leagues?.name ?? ''}</span>
				<span class="ah-lineup-date">{dateLabel(match)}</span>
			</div>
			<div class="ah-lineup-avatars">
				{#each teammates as p}
					{@const name  = p.players?.name ?? p.player_name}
					{@const photo = p.players?.photo ?? null}
					{@const isMe  = p.player_id === myPlayer?.id}
					<div class="ah-avatar-wrap" class:ah-avatar-wrap--me={isMe}>
						<img
							class="ah-avatar"
							src={imgPath(photo, name)}
							alt={name ?? ''}
							draggable="false"
							onerror={(e) => e.currentTarget.style.display = 'none'}
						/>
						{#if isMe}
							<span class="ah-you">Du</span>
						{/if}
					</div>
				{/each}
			</div>
			<div class="ah-lineup-actions">
				<button class="lcc-btn lcc-btn--decline" onclick={() => respond(false)} disabled={busy}>
					<span class="material-symbols-outlined">close</span>
					Ablehnen
				</button>
				<button class="lcc-btn lcc-btn--confirm" onclick={() => respond(true)} disabled={busy}>
					<span class="material-symbols-outlined">check</span>
					Bestätigen
				</button>
			</div>
		</div>
	{/if}

	<!-- Abstimmungen (placeholder) -->
	<div class="ah-item ah-item--placeholder">
		<div class="ah-item-icon-wrap">
			<span class="material-symbols-outlined">how_to_vote</span>
		</div>
		<div class="ah-item-text">
			<span class="ah-item-label">Abstimmungen</span>
			<span class="ah-item-sub">Keine offen</span>
		</div>
		<span class="ah-badge ah-badge--soon">bald</span>
	</div>

	<!-- Event-Anmeldungen (placeholder) -->
	<div class="ah-item ah-item--placeholder">
		<div class="ah-item-icon-wrap">
			<span class="material-symbols-outlined">event</span>
		</div>
		<div class="ah-item-text">
			<span class="ah-item-label">Event-Anmeldungen</span>
			<span class="ah-item-sub">Keine offen</span>
		</div>
		<span class="ah-badge ah-badge--soon">bald</span>
	</div>

	<!-- Turnier-Anmeldungen (placeholder) -->
	<div class="ah-item ah-item--placeholder">
		<div class="ah-item-icon-wrap">
			<span class="material-symbols-outlined">emoji_events</span>
		</div>
		<div class="ah-item-text">
			<span class="ah-item-label">Turnier-Anmeldungen</span>
			<span class="ah-item-sub">Keine offen</span>
		</div>
		<span class="ah-badge ah-badge--soon">bald</span>
	</div>

	<!-- Landesmeisterschaften (placeholder) -->
	<div class="ah-item ah-item--placeholder">
		<div class="ah-item-icon-wrap">
			<span class="material-symbols-outlined">military_tech</span>
		</div>
		<div class="ah-item-text">
			<span class="ah-item-label">Landesmeisterschaften</span>
			<span class="ah-item-sub">Keine offen</span>
		</div>
		<span class="ah-badge ah-badge--soon">bald</span>
	</div>
</div>

<style>
	/* Action Hub container – gap override: items have own spacing */
	.ah {
		gap: 0;
	}

	/* --- Item row --- */
	.ah-item {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) 0;
		border-bottom: 1px solid var(--color-outline-variant);
		cursor: default;
	}

	.ah-item:last-child {
		border-bottom: none;
		padding-bottom: 0;
	}

	.ah-item--active {
		cursor: pointer;
	}

	.ah-item--active:active {
		opacity: 0.75;
	}

	.ah-item--placeholder {
		opacity: 0.55;
	}

	.ah-item--done .ah-item-label {
		color: var(--color-on-surface-variant);
	}

	/* Icon wrap */
	.ah-item-icon-wrap {
		width: 2.25rem;
		height: 2.25rem;
		border-radius: var(--radius-md);
		background: var(--color-surface-container-low);
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		color: var(--color-on-surface-variant);
	}

	.ah-item-icon-wrap .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	.ah-item-icon-wrap--accent {
		background: var(--color-primary-container, rgba(158, 0, 0, 0.12));
		color: var(--color-primary);
	}

	/* Text */
	.ah-item-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.ah-item-label {
		font-family: var(--font-body);
		font-size: var(--text-body-md);
		font-weight: 500;
		color: var(--color-on-surface);
	}

	.ah-item-sub {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* Badges */
	.ah-badge {
		min-width: 1.4rem;
		height: 1.4rem;
		padding: 0 var(--space-2);
		background: var(--color-primary);
		color: #fff;
		border-radius: var(--radius-full);
		font-family: var(--font-display);
		font-size: 0.72rem;
		font-weight: 700;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.ah-badge--soon {
		background: var(--color-surface-container);
		color: var(--color-on-surface-variant);
		font-family: var(--font-body);
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.ah-done-icon {
		font-size: 1.2rem;
		color: #2D7A3A;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
		flex-shrink: 0;
	}

	.ah-expand-icon {
		font-size: 1.2rem;
		color: var(--color-on-surface-variant);
		flex-shrink: 0;
		transition: transform 0.2s ease;
	}

	.ah-expand-icon--open {
		transform: rotate(180deg);
	}

	/* --- Inline Lineup Confirm --- */
	.ah-lineup {
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		overflow: hidden;
		margin-bottom: var(--space-1);
		animation: ah-lineup-in 0.25s cubic-bezier(0.22, 1, 0.36, 1) both;
	}

	@keyframes ah-lineup-in {
		from { opacity: 0; transform: translateY(-6px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	.ah-lineup-meta {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-3) var(--space-4) var(--space-2);
		gap: var(--space-2);
	}

	.ah-lineup-league {
		font-family: var(--font-display);
		font-size: 0.8rem;
		font-weight: 800;
		color: var(--color-primary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.ah-lineup-date {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}

	.ah-lineup-avatars {
		display: flex;
		gap: var(--space-2);
		padding: 0 var(--space-4) var(--space-3);
		overflow-x: auto;
		scrollbar-width: none;
	}

	.ah-lineup-avatars::-webkit-scrollbar { display: none; }

	.ah-avatar-wrap {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		flex-shrink: 0;
	}

	.ah-avatar {
		width: 38px;
		height: 38px;
		border-radius: var(--radius-full);
		object-fit: cover;
		background: var(--color-surface-container);
		border: 2px solid transparent;
	}

	.ah-avatar-wrap--me .ah-avatar {
		border-color: var(--color-secondary);
		box-shadow: 0 0 0 2px rgba(212, 175, 55, 0.3);
	}

	.ah-you {
		font-family: var(--font-display);
		font-size: 0.58rem;
		font-weight: 800;
		color: var(--color-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.ah-lineup-actions {
		display: flex;
		gap: var(--space-3);
		padding: 0 var(--space-4) var(--space-4);
	}
</style>
