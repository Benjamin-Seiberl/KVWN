<script>
	import { fmtDate } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerRole } from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';

	let {
		open = $bindable(false),
		event = null,
		onEdited,
		onDeleted,
	} = $props();

	let editing = $state(false);
	let saving  = $state(false);
	let deleting = $state(false);

	// Edit-Form-State (wird beim Betreten des Edit-Mode befüllt)
	let editTitle       = $state('');
	let editDate        = $state('');
	let editTime        = $state('');
	let editLocation    = $state('');
	let editDescription = $state('');

	// Sheet schließt → Edit-Mode verlassen
	$effect(() => {
		if (!open) editing = false;
	});

	const isGcal = $derived(!!event?.external_id);
	const canEdit = $derived($playerRole === 'kapitaen' && isGcal);

	function startEdit() {
		if (!event) return;
		editTitle       = event.title       ?? '';
		editDate        = event.date        ?? '';
		editTime        = event.time ? String(event.time).slice(0, 5) : '';
		editLocation    = event.location    ?? '';
		editDescription = event.description ?? '';
		editing = true;
	}

	function cancelEdit() {
		editing = false;
	}

	async function saveEdit() {
		if (!event) return;
		const t = editTitle.trim();
		if (!t) { triggerToast('Bitte Titel eintragen'); return; }
		if (!editDate) { triggerToast('Bitte Datum wählen'); return; }

		saving = true;
		try {
			const { data: { session } } = await sb.auth.getSession();
			if (!session?.access_token) {
				triggerToast('Fehler: Nicht angemeldet');
				return;
			}

			const res = await fetch('/api/gcal/events', {
				method: 'PATCH',
				headers: {
					Authorization:  'Bearer ' + session.access_token,
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({
					id: event.id,
					patch: {
						title:       t,
						date:        editDate,
						time:        editTime || null,
						location:    editLocation.trim() || null,
						description: editDescription.trim() || null,
					},
				}),
			});

			if (!res.ok) {
				const err = await res.json().catch(() => ({ error: 'Unbekannter Fehler' }));
				triggerToast('Fehler: ' + (err.error ?? res.statusText));
				return;
			}

			triggerToast('Gespeichert');
			editing = false;
			open = false;
			onEdited?.();
		} catch (err) {
			triggerToast('Fehler: ' + (err?.message ?? 'Speichern fehlgeschlagen'));
		} finally {
			saving = false;
		}
	}

	async function doDelete() {
		if (!event) return;
		if (!confirm(`Termin "${event.title}" wirklich löschen?`)) return;

		deleting = true;
		try {
			const { data: { session } } = await sb.auth.getSession();
			if (!session?.access_token) {
				triggerToast('Fehler: Nicht angemeldet');
				return;
			}

			const res = await fetch('/api/gcal/events', {
				method: 'DELETE',
				headers: {
					Authorization:  'Bearer ' + session.access_token,
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({ id: event.id }),
			});

			if (!res.ok) {
				const err = await res.json().catch(() => ({ error: 'Unbekannter Fehler' }));
				triggerToast('Fehler: ' + (err.error ?? res.statusText));
				return;
			}

			triggerToast('Termin gelöscht');
			open = false;
			onDeleted?.();
		} catch (err) {
			triggerToast('Fehler: ' + (err?.message ?? 'Löschen fehlgeschlagen'));
		} finally {
			deleting = false;
		}
	}
</script>

<BottomSheet bind:open title="Termin">
	{#if event}
		{#if editing}
			<div class="ed ed--edit">
				<label class="mw-field">
					<span class="mw-field__label">Titel</span>
					<input type="text" bind:value={editTitle} required />
				</label>

				<label class="mw-field">
					<span class="mw-field__label">Datum</span>
					<input type="date" bind:value={editDate} required />
				</label>

				<label class="mw-field">
					<span class="mw-field__label">Uhrzeit (optional)</span>
					<input type="time" bind:value={editTime} />
				</label>

				<label class="mw-field">
					<span class="mw-field__label">Ort</span>
					<input type="text" bind:value={editLocation} />
				</label>

				<label class="mw-field">
					<span class="mw-field__label">Beschreibung</span>
					<textarea bind:value={editDescription} rows="3"></textarea>
				</label>

				<div class="ed-actions">
					<button type="button" class="mw-btn mw-btn--ghost mw-btn--wide" onclick={cancelEdit} disabled={saving}>
						Abbrechen
					</button>
					<button type="button" class="mw-btn mw-btn--primary mw-btn--wide" onclick={saveEdit} disabled={saving}>
						{saving ? 'Speichern…' : 'Speichern'}
					</button>
				</div>
			</div>
		{:else}
			<div class="ed">
				<h2 class="ed-title">{event.title}</h2>

				<div class="ed-meta">
					<div class="ed-meta-row">
						<span class="material-symbols-outlined">calendar_today</span>
						<span>{fmtDate(event.date)}</span>
					</div>
					{#if event.time}
						<div class="ed-meta-row">
							<span class="material-symbols-outlined">schedule</span>
							<span>{shortTime(event.time)} Uhr</span>
						</div>
					{/if}
					{#if event.location}
						<div class="ed-meta-row">
							<span class="material-symbols-outlined">location_on</span>
							<span>{event.location}</span>
						</div>
					{/if}
				</div>

				{#if event.description}
					<p class="ed-desc">{event.description}</p>
				{/if}

				{#if isGcal}
					<p class="ed-gcal-hint">
						<span class="material-symbols-outlined">sync</span>
						Synchronisiert mit Google Calendar
					</p>
				{/if}

				{#if canEdit}
					<div class="ed-actions">
						<button
							type="button"
							class="mw-btn mw-btn--soft mw-btn--wide"
							onclick={startEdit}
							disabled={deleting}
						>
							<span class="material-symbols-outlined">edit</span>
							Bearbeiten
						</button>
						<button
							type="button"
							class="mw-btn mw-btn--wide ed-btn-danger"
							onclick={doDelete}
							disabled={deleting}
						>
							<span class="material-symbols-outlined">delete</span>
							{deleting ? 'Löschen…' : 'Löschen'}
						</button>
					</div>
				{/if}
			</div>
		{/if}
	{/if}
</BottomSheet>

<style>
	.ed { display: flex; flex-direction: column; gap: var(--space-4); padding-bottom: var(--space-4); }
	.ed--edit { gap: var(--space-3); }

	.ed-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-headline-sm);
		font-weight: 800;
		line-height: 1.2;
		color: var(--color-on-surface);
	}

	.ed-meta { display: flex; flex-direction: column; gap: var(--space-2); }
	.ed-meta-row {
		display: flex; align-items: center; gap: var(--space-2);
		font-size: var(--text-body-md); color: var(--color-on-surface);
	}
	.ed-meta-row .material-symbols-outlined {
		font-size: 1rem; color: #2a78b4;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}

	.ed-desc {
		margin: 0;
		padding: var(--space-4);
		background: var(--color-surface-container);
		border-radius: var(--radius-md);
		font-size: var(--text-body-md);
		line-height: 1.5;
		color: var(--color-on-surface);
		white-space: pre-wrap;
	}

	.ed-gcal-hint {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin: 0;
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		opacity: 0.8;
	}
	.ed-gcal-hint .material-symbols-outlined {
		font-size: 0.95rem;
		color: var(--color-on-surface-variant);
	}

	.ed-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}

	.ed-btn-danger {
		background: var(--color-error-container);
		color: var(--color-error);
	}
</style>
