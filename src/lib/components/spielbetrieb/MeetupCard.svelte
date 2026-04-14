<script>
	import MeetupEditSheet from './MeetupEditSheet.svelte';
	import { shortTime } from '$lib/utils/league.js';

	let { match, meetup = null, canEdit = false, onSaved } = $props();
	let sheetOpen = $state(false);

	const isAway = $derived(match?.home_away !== 'HEIM');
</script>

{#if isAway}
	<section class="mw-card">
		<div class="mw-card__head">
			<h3 class="mw-card__title">
				<span class="material-symbols-outlined" style="color: var(--color-primary);">location_on</span>
				Treffpunkt
			</h3>
			{#if canEdit}
				<button class="mw-btn mw-btn--soft" onclick={() => sheetOpen = true}>
					<span class="material-symbols-outlined">edit</span>
					{meetup ? 'Bearbeiten' : 'Festlegen'}
				</button>
			{/if}
		</div>

		{#if meetup}
			<div>
				{#if meetup.location_url}
					<a class="mw-meetup__link" href={meetup.location_url} target="_blank" rel="noopener">
						📍 {meetup.location_name}
					</a>
				{:else}
					<span class="mw-meetup__link" style="text-decoration:none;">📍 {meetup.location_name}</span>
				{/if}
				<div class="mw-meetup__row">
					<span class="mw-meetup__time">
						<span class="material-symbols-outlined" style="font-size:1rem;">schedule</span>
						{shortTime(meetup.meet_time)}
					</span>
				</div>
				{#if meetup.note}
					<p class="mw-card__subtitle" style="margin-top: var(--space-2);">{meetup.note}</p>
				{/if}
			</div>
		{:else}
			<p class="mw-empty">Noch kein Treffpunkt festgelegt.</p>
		{/if}
	</section>

	{#if canEdit}
		<MeetupEditSheet bind:open={sheetOpen} {match} {meetup} {onSaved} />
	{/if}
{/if}
