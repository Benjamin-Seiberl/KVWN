<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { shortTime } from '$lib/utils/league.js';

	let { open = $bindable(false), match, meetup, onSaved } = $props();

	let seats = $state(3); // default passenger seats (without driver)
	let departTime = $state('');
	let note = $state('');
	let saving = $state(false);

	const maxSeats = 5; // driver + 5 passengers max in our grid
	const presetTime = $derived(meetup?.meet_time ? shortTime(meetup.meet_time) : shortTime(match?.time));

	$effect(() => {
		if (open) {
			seats = 3;
			departTime = presetTime;
			note = '';
		}
	});

	async function save() {
		if (seats < 1) return;
		saving = true;
		const { data, error } = await sb
			.from('match_carpools')
			.insert({
				match_id:    match.id,
				driver_id:   $playerId,
				seats_total: seats,
				depart_time: departTime || null,
				note:        note.trim() || null,
			})
			.select()
			.maybeSingle();
		saving = false;
		if (!error) {
			onSaved?.(data);
			open = false;
		}
	}
</script>

<BottomSheet bind:open title="Fahrt anbieten">
	<p class="mw-card__subtitle" style="text-align:center; margin-bottom: var(--space-3);">
		Konfiguration: <strong>{seats} {seats === 1 ? 'Platz' : 'Plätze'}</strong> für Mitfahrer:innen
	</p>

	<div class="mw-car-grid" style="margin-bottom: var(--space-4);">
		<!-- Driver -->
		<div class="mw-car-slot">
			<div class="mw-car-slot__tile mw-car-slot__tile--driver">
				<span class="material-symbols-outlined">person</span>
			</div>
			<span class="mw-car-slot__label">Fahrer</span>
		</div>
		<div></div>
		<div></div>
		{#each Array.from({ length: maxSeats }, (_, i) => i) as i}
			{@const on = i < seats}
			<button
				type="button"
				class="mw-car-slot"
				onclick={() => seats = on ? i : i + 1}
				style="background:none;border:none;padding:0;"
			>
				<span class="mw-car-slot__tile" class:mw-car-slot__tile--on={on}>
					<span class="material-symbols-outlined">{on ? 'person' : 'add'}</span>
				</span>
				<span class="mw-car-slot__label">{on ? 'Frei' : 'Hinzu'}</span>
			</button>
		{/each}
	</div>

	<div class="mw-field">
		<label class="mw-field__label" for="mw-depart">Abfahrt</label>
		<input id="mw-depart" type="time" bind:value={departTime} />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="mw-note">Notiz (optional)</label>
		<input id="mw-note" type="text" bind:value={note} placeholder="z.B. Treffen vor meinem Haus" />
	</div>

	<button class="mw-btn mw-btn--primary mw-btn--wide" disabled={saving || seats < 1} onclick={save}>
		Fahrt bestätigen
	</button>
</BottomSheet>
