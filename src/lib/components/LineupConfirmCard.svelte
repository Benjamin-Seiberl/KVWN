<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { user } from '$lib/stores/auth';

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
		setTimeout(() => { dismissed = true; }, 320);
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

{#if !dismissed && !loading && pendingEntry && match}
	<div class="lcc" class:lcc--exit={exiting}>

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

		<!-- Aufstellung -->
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

		<!-- Aktionen -->
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
