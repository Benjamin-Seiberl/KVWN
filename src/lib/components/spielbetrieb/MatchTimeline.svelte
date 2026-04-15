<script>
	import { leagueTiming, offsetTime, shortTime } from '$lib/utils/league.js';

	let { match, meetup = null } = $props();

	const isAway = $derived(match?.home_away !== 'HEIM');
	const timing = $derived(leagueTiming(match?.leagues?.name));

	const startTime = $derived(shortTime(match?.time));
	const arrivalTime = $derived(offsetTime(match?.time, -timing.arrivalOffsetMin));
	const endTime = $derived(offsetTime(match?.time, timing.matchDurationMin + timing.delayBufferMin));
</script>

<section class="mw-card">
	<div class="mw-card__head">
		<h3 class="mw-card__title">
			<span class="material-symbols-outlined">timeline</span>
			Match-Timeline
		</h3>
	</div>

	<div class="mw-timeline">
		{#if isAway}
			<div class="mw-timeline__item">
				<span class="mw-timeline__pin"></span>
				<div class="mw-timeline__row">
					<span class="mw-timeline__label">Treffpunkt</span>
					<span class="mw-timeline__time">
						{meetup?.meet_time ? shortTime(meetup.meet_time) : 'Offen'}
					</span>
				</div>
			</div>
		{/if}

		<div class="mw-timeline__item">
			<span class="mw-timeline__pin mw-timeline__pin--accent"></span>
			<div class="mw-timeline__row">
				<span class="mw-timeline__label">Ankunft</span>
				<span class="mw-timeline__time">{arrivalTime ?? '–'}</span>
			</div>
		</div>

		<div class="mw-timeline__item">
			<span class="mw-timeline__pin mw-timeline__pin--primary"></span>
			<div class="mw-timeline__row">
				<span class="mw-timeline__label">Spielbeginn</span>
				<span class="mw-timeline__time mw-timeline__time--primary">{startTime || '–'}</span>
			</div>
		</div>

		<div class="mw-timeline__item">
			<span class="mw-timeline__pin mw-timeline__pin--accent"></span>
			<div class="mw-timeline__row">
				<span class="mw-timeline__label">Kulinarik &amp; Party</span>
				<span class="mw-timeline__time">ca. {endTime ?? '–'}</span>
			</div>
		</div>

		{#if isAway}
			<div class="mw-timeline__item">
				<span class="mw-timeline__pin"></span>
				<div class="mw-timeline__row">
					<span class="mw-timeline__label">Rückfahrt</span>
					<span class="mw-timeline__time">Offen</span>
				</div>
			</div>
		{/if}
	</div>
</section>
