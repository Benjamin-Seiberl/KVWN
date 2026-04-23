<script>
	import { goto } from '$app/navigation';
	import { sb } from '$lib/supabase';
	import { setSubtab } from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate } from '$lib/utils/dates.js';
	import { leagueTiming, offsetTime, shortTime } from '$lib/utils/league.js';
	import { imgPath, shortName } from '$lib/utils/players.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import CarpoolCard from '$lib/components/spielbetrieb/CarpoolCard.svelte';

	let { open = $bindable(false), match = null, lineup = [] } = $props();

	function confirmStatus(entry) {
		if (entry?.confirmed === true)  return 'confirmed';
		if (entry?.confirmed === false) return 'declined';
		return 'pending';
	}

	let carpools = $state([]);
	let meetup   = $state(null);
	let loading  = $state(false);

	const isAway    = $derived(match?.home_away && match.home_away !== 'HEIM');
	const isTourney = $derived(!!(match?.is_tournament || match?.is_landesbewerb));
	const timing    = $derived(match ? leagueTiming(match.leagues?.name ?? '') : null);
	const arrival   = $derived(match?.time && timing ? offsetTime(match.time, -timing.arrivalOffsetMin) : null);
	const endTime   = $derived(match?.time && timing ? offsetTime(match.time, timing.matchDurationMin) : null);

	async function loadCarpool() {
		if (!match?.id) return;
		loading = true;
		carpools = [];
		meetup   = null;
		const [{ data: cp, error: e1 }, { data: mu, error: e2 }] = await Promise.all([
			sb.from('match_carpools')
				.select('id, match_id, driver_id, seats_total, depart_time, depart_from, note, driver:players!driver_id(name, photo), match_carpool_seats(passenger_id)')
				.eq('match_id', match.id),
			sb.from('match_meetups').select('*').eq('match_id', match.id).maybeSingle(),
		]);
		const err = e1 ?? e2;
		if (err) { triggerToast('Fehler: ' + err.message); loading = false; return; }
		carpools = (cp ?? []).map(c => ({ ...c, seats: c.match_carpool_seats ?? [] }));
		meetup   = mu;
		loading  = false;
	}

	$effect(() => {
		if (open && match?.id && isAway && !isTourney) loadCarpool();
	});

	function goToAufstellung() {
		open = false;
		setSubtab('/spielbetrieb', 'aufstellungen');
		goto('/spielbetrieb');
	}
</script>

<BottomSheet bind:open title={isTourney ? 'Turnier' : 'Spiel'}>
	{#if match}
		<div class="md">
			<div class="md-head">
				<span class="md-chip md-chip--round">{match.round ?? '—'}</span>
				<span class="md-chip" class:md-chip--home={!isAway} class:md-chip--away={isAway}>
					{match.home_away === 'HEIM' ? 'Heim' : 'Auswärts'}
				</span>
				{#if isTourney}
					<span class="md-chip md-chip--tourney">
						<span class="material-symbols-outlined">military_tech</span>
						{match.is_landesbewerb ? 'Landesbewerb' : 'Turnier'}
					</span>
				{/if}
			</div>

			<h2 class="md-title">
				{#if isTourney}
					{match.tournament_title ?? match.opponent}
				{:else}
					{match.home_away === 'HEIM' ? 'vs. ' : 'bei '}{match.opponent}
				{/if}
			</h2>

			<div class="md-meta">
				<div class="md-meta-row">
					<span class="material-symbols-outlined">calendar_today</span>
					<span>{fmtDate(match.date)}</span>
				</div>
				{#if match.time}
					<div class="md-meta-row">
						<span class="material-symbols-outlined">schedule</span>
						<span>{shortTime(match.time)} Uhr{#if endTime} – {endTime} Uhr{/if}</span>
					</div>
				{/if}
				{#if match.location}
					<div class="md-meta-row">
						<span class="material-symbols-outlined">location_on</span>
						<span>{match.location}</span>
					</div>
				{/if}
				{#if arrival && !isTourney}
					<div class="md-meta-row md-meta-row--hint">
						<span class="material-symbols-outlined">flag</span>
						<span>Treffpunkt ab {arrival} Uhr</span>
					</div>
				{/if}
			</div>

			{#if lineup.length > 0}
				<div class="md-section">
					<h3 class="md-section-title">
						<span class="material-symbols-outlined">format_list_numbered</span>
						Aufstellung
					</h3>
					<div class="md-lineup">
						{#each lineup as entry (entry.id)}
							{@const name  = entry.players?.name ?? entry.player_name ?? '–'}
							{@const photo = entry.players?.photo ?? null}
							{@const status = confirmStatus(entry)}
							<div class="md-lineup-row">
								<span class="md-lineup-pos">{entry.position}</span>
								<div class="md-lineup-avatar">
									<img
										src={imgPath(photo, name)}
										alt=""
										onerror={(e) => { e.currentTarget.style.display = 'none'; }}
									/>
									<span class="md-lineup-initial">{name.slice(0, 1)}</span>
								</div>
								<span class="md-lineup-name">{shortName(name)}</span>
								<span class="md-lineup-status md-lineup-status--{status}" aria-label={status === 'confirmed' ? 'Bestätigt' : status === 'declined' ? 'Abgelehnt' : 'Ausstehend'}>
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
				</div>
			{/if}

			{#if isAway && !isTourney}
				<div class="md-section">
					<h3 class="md-section-title">
						<span class="material-symbols-outlined">directions_car</span>
						Fahrgemeinschaft
					</h3>
					{#if loading}
						<div class="md-loading shimmer-box"></div>
					{:else}
						<CarpoolCard {match} {meetup} {carpools} onChanged={loadCarpool} />
					{/if}
				</div>
			{/if}

			<button class="md-cta" onclick={goToAufstellung}>
				<span class="material-symbols-outlined">format_list_numbered</span>
				Zur Aufstellung
			</button>
		</div>
	{/if}
</BottomSheet>

<style>
	.md { display: flex; flex-direction: column; gap: var(--space-4); padding-bottom: var(--space-4); }

	.md-head { display: flex; flex-wrap: wrap; gap: var(--space-2); }
	.md-chip {
		display: inline-flex; align-items: center; gap: 4px;
		padding: 3px 10px; border-radius: 999px;
		font-size: var(--text-label-sm); font-weight: 700;
		text-transform: uppercase; letter-spacing: 0.05em;
	}
	.md-chip .material-symbols-outlined {
		font-size: 0.9rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.md-chip--round   { background: var(--color-surface-container); color: var(--color-on-surface-variant); }
	.md-chip--home    { background: rgba(30,58,95,0.12); color: #1e3a5f; }
	.md-chip--away    { background: rgba(30,58,95,0.2);  color: #1e3a5f; }
	.md-chip--tourney { background: color-mix(in srgb, var(--color-secondary) 20%, transparent); color: #8a6f1e; }

	.md-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-headline-sm);
		font-weight: 800;
		line-height: 1.2;
		color: var(--color-on-surface);
	}

	.md-meta { display: flex; flex-direction: column; gap: var(--space-2); }
	.md-meta-row {
		display: flex; align-items: center; gap: var(--space-2);
		font-size: var(--text-body-md); color: var(--color-on-surface);
	}
	.md-meta-row .material-symbols-outlined {
		font-size: 1rem; color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.md-meta-row--hint { color: var(--color-on-surface-variant); font-size: var(--text-label-md); }
	.md-meta-row--hint .material-symbols-outlined { color: var(--color-on-surface-variant); }

	.md-section { display: flex; flex-direction: column; gap: var(--space-3); }
	.md-section-title {
		display: flex; align-items: center; gap: var(--space-2);
		font-family: var(--font-display);
		font-size: var(--text-title-sm); font-weight: 800;
		text-transform: uppercase; letter-spacing: 0.04em;
		margin: 0; color: var(--color-on-surface);
	}
	.md-section-title .material-symbols-outlined {
		font-size: 1.1rem; color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.md-loading { height: 90px; border-radius: var(--radius-md); }

	.md-lineup {
		display: flex; flex-direction: column; gap: var(--space-2);
	}
	.md-lineup-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
	}
	.md-lineup-pos {
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 800;
		color: var(--color-primary);
		min-width: 20px;
		text-align: center;
	}
	.md-lineup-avatar {
		position: relative;
		width: 34px; height: 34px;
		border-radius: var(--radius-full);
		background: var(--color-surface-container);
		overflow: hidden;
		flex-shrink: 0;
	}
	.md-lineup-avatar img {
		width: 100%; height: 100%;
		object-fit: cover; object-position: top center;
	}
	.md-lineup-initial {
		position: absolute; inset: 0;
		display: flex; align-items: center; justify-content: center;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 0.85rem;
		color: var(--color-on-surface-variant);
		z-index: -1;
	}
	.md-lineup-name {
		flex: 1;
		font-size: var(--text-body-md);
		font-weight: 600;
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.md-lineup-status .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.md-lineup-status--confirmed { color: var(--color-success); }
	.md-lineup-status--declined  { color: var(--color-primary); }
	.md-lineup-status--pending   { color: var(--color-outline); }

	.md-cta {
		display: flex; align-items: center; justify-content: center; gap: var(--space-2);
		width: 100%; padding: var(--space-4);
		background: var(--color-primary); color: #fff;
		border: none; border-radius: var(--radius-lg);
		font-family: var(--font-body);
		font-size: var(--text-label-md); font-weight: 700;
		text-transform: uppercase; letter-spacing: 0.06em;
		cursor: pointer; -webkit-tap-highlight-color: transparent;
		transition: transform 100ms ease;
	}
	.md-cta:active { transform: scale(0.98); }
	.md-cta .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
</style>
