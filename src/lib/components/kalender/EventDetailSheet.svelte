<script>
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';
	import { shortTime } from '$lib/utils/league.js';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth.js';
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

	// RSVP state — null = keine Antwort, 'yes' | 'no' = gewählt
	let myRsvp        = $state(null);
	let rsvpLoading   = $state(false);
	let rsvpSaving    = $state(false);

	// Sheet schließt → Edit-Mode verlassen
	$effect(() => {
		if (!open) editing = false;
	});

	// Beim Öffnen / Wechsel des Events RSVP laden
	$effect(() => {
		if (open && event?.id && $playerId) {
			loadMyRsvp();
		} else {
			myRsvp = null;
		}
	});

	const isGcal = $derived(!!event?.external_id);
	const canEdit = $derived($playerRole === 'kapitaen' && isGcal);
	const isPast  = $derived(!!event?.date && event.date < toDateStr(new Date()));

	async function loadMyRsvp() {
		rsvpLoading = true;
		try {
			const { data, error } = await sb
				.from('event_rsvps')
				.select('response')
				.eq('event_id', event.id)
				.eq('player_id', $playerId)
				.maybeSingle();
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			myRsvp = data?.response ?? null;
		} finally {
			rsvpLoading = false;
		}
	}

	async function setRsvp(response) {
		if (!event?.id || !$playerId || rsvpSaving) return;
		const previous = myRsvp;
		// Optimistic: Toggle (gleiche Antwort nochmal = Abmeldung)
		const next = previous === response ? null : response;
		myRsvp = next;
		rsvpSaving = true;
		try {
			if (next === null) {
				const { error } = await sb.from('event_rsvps')
					.delete()
					.eq('event_id', event.id)
					.eq('player_id', $playerId);
				if (error) {
					myRsvp = previous;
					triggerToast('Fehler: ' + error.message);
					return;
				}
				triggerToast('Antwort entfernt');
			} else {
				const { error } = await sb.from('event_rsvps').upsert({
					event_id:  event.id,
					player_id: $playerId,
					response:  next,
				});
				if (error) {
					myRsvp = previous;
					triggerToast('Fehler: ' + error.message);
					return;
				}
				triggerToast(next === 'yes' ? 'Zugesagt' : 'Abgesagt');
			}
		} finally {
			rsvpSaving = false;
		}
	}

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

				{#if !isPast}
					<div class="ed-rsvp">
						<span class="ed-rsvp-label">Bist du dabei?</span>
						<div class="ed-rsvp-row">
							<button
								type="button"
								class="ed-rsvp-btn ed-rsvp-btn--yes"
								class:ed-rsvp-btn--active={myRsvp === 'yes'}
								onclick={() => setRsvp('yes')}
								disabled={rsvpSaving || rsvpLoading || !$playerId}
								aria-label="Zusagen"
								aria-pressed={myRsvp === 'yes'}
							>
								<span class="material-symbols-outlined">check_circle</span>
								Zusagen
							</button>
							<button
								type="button"
								class="ed-rsvp-btn ed-rsvp-btn--no"
								class:ed-rsvp-btn--active={myRsvp === 'no'}
								onclick={() => setRsvp('no')}
								disabled={rsvpSaving || rsvpLoading || !$playerId}
								aria-label="Absagen"
								aria-pressed={myRsvp === 'no'}
							>
								<span class="material-symbols-outlined">cancel</span>
								Absagen
							</button>
						</div>
					</div>
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

	.ed-rsvp {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		background: var(--color-surface-container);
		border-radius: var(--radius-md);
	}
	.ed-rsvp-label {
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.ed-rsvp-row {
		display: flex;
		gap: var(--space-2);
	}
	.ed-rsvp-btn {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		min-height: 44px;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-lowest);
		font-family: var(--font-display);
		font-size: var(--text-label-md);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 150ms ease, border-color 150ms ease, color 150ms ease, transform 80ms ease;
	}
	.ed-rsvp-btn:active { transform: scale(0.97); }
	.ed-rsvp-btn:disabled { opacity: 0.5; cursor: default; }
	.ed-rsvp-btn .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	}
	.ed-rsvp-btn--yes.ed-rsvp-btn--active {
		background: color-mix(in srgb, var(--color-success) 12%, transparent);
		border-color: var(--color-success);
		color: var(--color-success);
	}
	.ed-rsvp-btn--no.ed-rsvp-btn--active {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
</style>
