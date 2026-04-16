<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { user } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';

	const DAY_NAMES = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	let loading   = $state(true);
	let exiting   = $state(false);
	let dismissed = $state(false);
	let busy      = $state(false);

	let myPlayer     = $state(null);
	let pendingEntry = $state(null);
	let match        = $state(null);
	let teammates    = $state([]);

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

	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_NAMES[d.getDay()] + ', ' +
			d.getDate() + '.' + (d.getMonth() + 1) + '. \u2022 ' +
			(m.time ? m.time.substring(0, 5) : '') + ' Uhr';
	}

	async function loadPending(email) {
		const { data: player } = await sb
			.from('players').select('id, name').eq('email', email).maybeSingle();
		if (!player) { loading = false; return; }
		myPlayer = player;

		const range = getWeekRange();
		const { data: matches } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', range.from).lte('date', range.to)
			.order('date').order('time');
		if (!matches?.length) { loading = false; return; }

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
				break;
			}
		}
		loading = false;
	}

	async function respond(confirmed) {
		if (busy || !pendingEntry) return;
		busy = true;
		await sb.from('game_plan_players').update({ confirmed }).eq('id', pendingEntry.id);
		exiting = true;
		setTimeout(() => {
			dismissed = true;
			triggerToast(confirmed ? 'Aufstellung bestätigt!' : 'Absage registriert');
		}, 320);
	}

	let loaded = false;
	$effect(() => {
		if ($user?.email && !loaded) {
			loaded = true;
			loadPending($user.email);
		} else if (!$user) {
			loading = false;
		}
	});
</script>

{#if loading}
	<div class="lcc lcc--skeleton">
		<!-- banner bar -->
		<div class="skel-lcc-banner shimmer-box"></div>
		<!-- header -->
		<div class="skel-lcc-header">
			<div class="skel-lcc-col">
				<div class="skel-bar skel-bar--league shimmer-box"></div>
				<div class="skel-bar skel-bar--opponent shimmer-box" style="margin-top:var(--space-2)"></div>
			</div>
			<div class="skel-lcc-col skel-lcc-col--right">
				<div class="skel-lcc-icon shimmer-box"></div>
				<div class="skel-bar skel-bar--date shimmer-box" style="margin-top:var(--space-2)"></div>
			</div>
		</div>
		<!-- avatar row -->
		<div class="skel-avatars" style="padding: var(--space-3) var(--space-4)">
			{#each [0,1,2,3] as _}
				<div class="skel-avatar shimmer-box"></div>
			{/each}
		</div>
		<!-- action buttons -->
		<div class="skel-lcc-actions">
			<div class="skel-lcc-btn shimmer-box"></div>
			<div class="skel-lcc-btn shimmer-box"></div>
		</div>
	</div>
{:else if !dismissed && pendingEntry && match}
	<div class="lcc" class:lcc--exit={exiting}>

		<!-- Urgency banner -->
		<div class="lcc-banner">
			<span class="lcc-pulse-dot"></span>
			<span class="lcc-banner-text">Aufstellungsbestätigung erforderlich</span>
		</div>

		<!-- Header -->
		<div class="lcc-header">
			<div class="lcc-header-left">
				<p class="lcc-league">{match.leagues?.name ?? ''}</p>
				<p class="lcc-opponent">vs. <strong>{match.opponent}</strong></p>
			</div>
			<div class="lcc-header-right">
				<span class="material-symbols-outlined lcc-sport-icon">sports_score</span>
				<p class="lcc-date">{dateLabel(match)}</p>
			</div>
		</div>

		<!-- Avatars -->
		<div class="lcc-avatars">
			{#each teammates as p}
				{@const name  = p.players?.name ?? p.player_name}
				{@const photo = p.players?.photo ?? null}
				{@const isMe  = p.player_id === myPlayer?.id}
				<div class="lcc-player" class:lcc-player--me={isMe}>
					<div class="lcc-avatar-wrap">
						<img
							class="lcc-avatar"
							src={imgPath(photo, name)}
							alt={name ?? ''}
							draggable="false"
							onerror={(e) => e.currentTarget.style.display = 'none'}
						/>
					</div>
					{#if isMe}
						<span class="lcc-you">Du</span>
					{/if}
				</div>
			{/each}
		</div>

		<!-- Actions -->
		<div class="lcc-actions">
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

<style>
	/* ── Skeleton shapes ──────────────────────────────────── */
	.lcc--skeleton { pointer-events: none; }

	.skel-lcc-banner {
		height: 32px;
		border-radius: 0;
	}
	.skel-lcc-header {
		display: flex;
		justify-content: space-between;
		padding: var(--space-3) var(--space-4);
		gap: var(--space-3);
	}
	.skel-lcc-col { display: flex; flex-direction: column; gap: var(--space-1); flex: 1; }
	.skel-lcc-col--right { align-items: flex-end; }
	.skel-lcc-icon {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-md);
	}
	.skel-lcc-actions {
		display: flex;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4) var(--space-4);
	}
	.skel-lcc-btn {
		flex: 1;
		height: 44px;
		border-radius: var(--radius-lg);
	}

	/* Urgency banner */
	.lcc-banner {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 7px var(--space-4);
		background: rgba(204, 0, 0, 0.06);
		border-bottom: 1px solid rgba(204, 0, 0, 0.10);
	}
	.lcc-banner-text {
		font-size: 0.70rem;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--color-primary, #CC0000);
	}
	.lcc-pulse-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--color-primary, #CC0000);
		flex-shrink: 0;
		animation: lcc-pulse 1.8s ease-in-out infinite;
	}
	@keyframes lcc-pulse {
		0%, 100% { transform: scale(1);   opacity: 1;   box-shadow: 0 0 0 0 rgba(204,0,0,0.5); }
		50%       { transform: scale(1.1); opacity: 0.8; box-shadow: 0 0 0 5px rgba(204,0,0,0); }
	}
</style>
