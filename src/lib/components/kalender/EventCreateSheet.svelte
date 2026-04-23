<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false), onCreated } = $props();

	let titel        = $state('');
	let datum        = $state('');
	let uhrzeit      = $state('');
	let ort          = $state('');
	let beschreibung = $state('');
	let saving       = $state(false);

	function resetForm() {
		titel        = '';
		datum        = '';
		uhrzeit      = '';
		ort          = '';
		beschreibung = '';
	}

	$effect(() => {
		if (!open) resetForm();
	});

	async function save() {
		const t = titel.trim();
		if (!t) { triggerToast('Bitte Titel eintragen'); return; }
		if (!datum) { triggerToast('Bitte Datum wählen'); return; }

		saving = true;
		try {
			const { data: { session } } = await sb.auth.getSession();
			if (!session?.access_token) {
				triggerToast('Fehler: Nicht angemeldet');
				return;
			}

			const res = await fetch('/api/gcal/events', {
				method: 'POST',
				headers: {
					Authorization:  'Bearer ' + session.access_token,
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({
					title:       t,
					date:        datum,
					time:        uhrzeit || null,
					location:    ort.trim() || null,
					description: beschreibung.trim() || null,
				}),
			});

			if (!res.ok) {
				const err = await res.json().catch(() => ({ error: 'Unbekannter Fehler' }));
				triggerToast('Fehler: ' + (err.error ?? res.statusText));
				return;
			}

			triggerToast('Termin angelegt');
			open = false;
			onCreated?.();
		} catch (err) {
			triggerToast('Fehler: ' + (err?.message ?? 'Speichern fehlgeschlagen'));
		} finally {
			saving = false;
		}
	}

	function cancel() {
		open = false;
	}
</script>

<BottomSheet bind:open title="Termin anlegen">
	<div class="ec">
		<label class="mw-field">
			<span class="mw-field__label">Titel</span>
			<input type="text" bind:value={titel} placeholder="z.B. Weihnachtsfeier" required />
		</label>

		<label class="mw-field">
			<span class="mw-field__label">Datum</span>
			<input type="date" bind:value={datum} required />
		</label>

		<label class="mw-field">
			<span class="mw-field__label">Uhrzeit (optional)</span>
			<input type="time" bind:value={uhrzeit} />
		</label>

		<label class="mw-field">
			<span class="mw-field__label">Ort</span>
			<input type="text" bind:value={ort} placeholder="z.B. Vereinsheim" />
		</label>

		<label class="mw-field">
			<span class="mw-field__label">Beschreibung</span>
			<textarea bind:value={beschreibung} rows="3" placeholder="Optionale Notizen…"></textarea>
		</label>

		<div class="ec-actions">
			<button type="button" class="mw-btn mw-btn--ghost mw-btn--wide" onclick={cancel} disabled={saving}>
				Abbrechen
			</button>
			<button type="button" class="mw-btn mw-btn--primary mw-btn--wide" onclick={save} disabled={saving}>
				{saving ? 'Speichern…' : 'Speichern'}
			</button>
		</div>
	</div>
</BottomSheet>

<style>
	.ec {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding-bottom: var(--space-4);
	}
	.ec-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}
</style>
