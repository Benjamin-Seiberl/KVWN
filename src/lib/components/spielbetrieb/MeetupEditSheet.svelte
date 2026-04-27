<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';

	/**
	 * @prop {boolean} open               two-way bindable, controls sheet visibility
	 * @prop {object}  match              match row { id, opponent, ... }
	 * @prop {object}  meetup             existing match_meetups row, or null
	 * @prop {string[]} confirmedPlayerIds  player_ids of bestätigte Spieler — empfangen Push nach Save
	 * @prop {Function} onSaved            called with the saved meetup row
	 */
	let { open = $bindable(false), match, meetup = null, confirmedPlayerIds = [], onSaved } = $props();

	let locationName = $state('');
	let locationUrl  = $state('');
	let meetTime     = $state('');
	let note         = $state('');
	let saving       = $state(false);

	$effect(() => {
		if (open) {
			locationName = meetup?.location_name ?? '';
			locationUrl  = meetup?.location_url ?? '';
			meetTime     = meetup?.meet_time?.slice(0, 5) ?? '';
			note         = meetup?.note ?? '';
		}
	});

	async function save() {
		if (!locationName.trim() || !meetTime) return;
		saving = true;
		const payload = {
			match_id:      match.id,
			location_name: locationName.trim(),
			location_url:  locationUrl.trim() || null,
			meet_time:     meetTime,
			note:          note.trim() || null,
			updated_by:    $playerId,
			updated_at:    new Date().toISOString(),
		};
		const { data, error } = await sb
			.from('match_meetups')
			.upsert(payload, { onConflict: 'match_id' })
			.select()
			.maybeSingle();
		saving = false;
		if (error) {
			triggerToast('Fehler: ' + error.message);
			return;
		}

		// Push an alle bestätigten Spieler des Lineups (Best-Effort, blockiert Save nicht).
		const recipients = (confirmedPlayerIds ?? []).filter(Boolean);
		if (recipients.length) {
			try {
				await fetch('/api/push/notify', {
					method:  'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({
						player_ids: recipients,
						title: 'Treffpunkt festgelegt',
						body:  `${locationName.trim()}, ${meetTime} Uhr`,
						url:   '/spielbetrieb',
						pref_key: 'meetup',
					}),
				});
			} catch (err) {
				console.warn('[MeetupEditSheet] Push-Notify fehlgeschlagen:', err);
			}
		}

		onSaved?.(data);
		open = false;
	}
</script>

<BottomSheet bind:open title="Treffpunkt festlegen">
	<div class="mw-field">
		<label class="mw-field__label" for="mw-loc">Ort</label>
		<input id="mw-loc" type="text" bind:value={locationName} placeholder="z.B. Sportzentrum St. Pölten" />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="mw-url">Google-Maps-Link (optional)</label>
		<input id="mw-url" type="url" bind:value={locationUrl} placeholder="https://maps.google.com/…" />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="mw-time">Uhrzeit</label>
		<input id="mw-time" type="time" bind:value={meetTime} />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="mw-note">Notiz (optional)</label>
		<textarea id="mw-note" bind:value={note} rows="2" placeholder="z.B. Parkplatz hinter der Halle"></textarea>
	</div>
	<button class="mw-btn mw-btn--primary mw-btn--wide" disabled={saving || !locationName.trim() || !meetTime} onclick={save}>
		<span class="material-symbols-outlined">check</span>
		{saving ? 'Wird gespeichert…' : 'Speichern'}
	</button>
</BottomSheet>
