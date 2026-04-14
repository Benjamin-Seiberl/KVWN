<script>
	import CarpoolOfferSheet from './CarpoolOfferSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { imgPath, shortName, BLANK_IMG } from '$lib/utils/players.js';

	let { match, meetup, carpools = [], onChanged } = $props();
	let sheetOpen = $state(false);

	const freeSeats = $derived(
		carpools.reduce((acc, c) => acc + Math.max(0, (c.seats_total ?? 0) - (c.seats?.length ?? 0)), 0)
	);

	const myDriving = $derived(carpools.find(c => c.driver_id === $playerId));

	function amIPassenger(c) {
		return (c.seats ?? []).some(s => s.passenger_id === $playerId);
	}

	async function toggleSeat(c) {
		if (c.driver_id === $playerId) return;
		if (amIPassenger(c)) {
			await sb
				.from('match_carpool_seats')
				.delete()
				.eq('carpool_id', c.id)
				.eq('passenger_id', $playerId);
		} else {
			if ((c.seats?.length ?? 0) >= c.seats_total) return;
			// Falls in anderer Fahrt eingetragen → zuerst entfernen
			const others = carpools.filter(x => x.id !== c.id && amIPassenger(x));
			for (const o of others) {
				await sb
					.from('match_carpool_seats')
					.delete()
					.eq('carpool_id', o.id)
					.eq('passenger_id', $playerId);
			}
			await sb
				.from('match_carpool_seats')
				.insert({ carpool_id: c.id, passenger_id: $playerId });
		}
		onChanged?.();
	}

	async function cancelMyOffer() {
		if (!myDriving) return;
		if (!confirm('Fahrt wirklich zurückziehen?')) return;
		await sb.from('match_carpools').delete().eq('id', myDriving.id);
		onChanged?.();
	}
</script>

<section class="mw-card">
	<div class="mw-card__head">
		<h3 class="mw-card__title">
			<span class="material-symbols-outlined" style="color:#2e7d32;">directions_car</span>
			Fahrten
		</h3>
		<span class="mw-badge mw-badge--ok">{freeSeats} freie Plätze</span>
	</div>

	{#if carpools.length === 0}
		<p class="mw-empty">Noch keine Fahrt angeboten.</p>
	{:else}
		<div class="mw-carpool__list">
			{#each carpools as c}
				{@const driverName = c.driver?.name ?? '–'}
				{@const filled = c.seats?.length ?? 0}
				{@const iAmDriver = c.driver_id === $playerId}
				{@const iAmPax = amIPassenger(c)}
				<div class="mw-carpool__row">
					<div class="mw-carpool__driver">
						<img
							class="mw-carpool__avatar"
							src={imgPath(c.driver?.photo, driverName)}
							alt={driverName}
							onerror={(e) => { e.currentTarget.src = BLANK_IMG; }}
						/>
						<div class="mw-carpool__info">
							<span class="mw-carpool__name">{shortName(driverName)}{iAmDriver ? ' (du)' : ''}</span>
							<div class="mw-seat-dots">
								{#each Array.from({ length: c.seats_total }, (_, i) => i) as i}
									{@const isFilled = i < filled}
									{@const isMe = iAmPax && i === filled - 1}
									<span
										class="mw-seat-dot"
										class:mw-seat-dot--filled={isFilled}
										class:mw-seat-dot--me={isMe}
									></span>
								{/each}
							</div>
						</div>
					</div>

					{#if iAmDriver}
						<button class="mw-btn mw-btn--ghost" onclick={cancelMyOffer}>Zurückziehen</button>
					{:else if iAmPax}
						<button class="mw-btn mw-btn--soft" onclick={() => toggleSeat(c)}>Absagen</button>
					{:else if filled >= c.seats_total}
						<button class="mw-btn mw-btn--soft" disabled>Voll</button>
					{:else}
						<button class="mw-btn mw-btn--soft" onclick={() => toggleSeat(c)}>Mitfahren</button>
					{/if}
				</div>
			{/each}
		</div>
	{/if}

	{#if !myDriving}
		<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={() => sheetOpen = true}>
			<span class="material-symbols-outlined">add_circle</span>
			Fahrt anbieten
		</button>
	{/if}
</section>

<CarpoolOfferSheet bind:open={sheetOpen} {match} {meetup} onSaved={() => onChanged?.()} />
