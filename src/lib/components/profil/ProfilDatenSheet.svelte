<script>
	import BottomSheet      from '$lib/components/BottomSheet.svelte';
	import ToggleSwitch     from '$lib/components/ui/ToggleSwitch.svelte';
	import { sb }           from '$lib/supabase';
	import { triggerToast } from '$lib/stores/toast.js';

	/**
	 * Props:
	 *   open:      $bindable(boolean)
	 *   section:   'kontakt' | 'sport' | 'notfall' | 'mobilitaet' | 'zahlung'
	 *   focus:     string — field key to highlight
	 *   form:      $bindable(object) — two-way bound form state owned by orchestrator
	 *   playerId:  string — required for attest storage path
	 *   onSave:    (section) => void|Promise<void>
	 *   onClose:   () => void
	 */
	let {
		open     = $bindable(false),
		section  = 'kontakt',
		focus    = '',
		form     = $bindable({}),
		playerId = null,
		onSave,
		onClose,
	} = $props();

	const SHIRT_SIZES = ['XS','S','M','L','XL','XXL','XXXL'];

	const TITLE = {
		kontakt:    'Kontakt bearbeiten',
		sport:      'Sport-Ausrüstung bearbeiten',
		notfall:    'Notfallkontakt bearbeiten',
		mobilitaet: 'Mobilität & Verpflegung',
		zahlung:    'Zahlung bearbeiten',
	};
	const sheetTitle = $derived(TITLE[section] ?? 'Bearbeiten');

	let uploadingAttest = $state(false);
	let viewingAttest   = $state(false);

	function close() {
		open = false;
		onClose?.();
	}

	function save() {
		onSave?.(section);
	}

	async function uploadAttest(e) {
		const file = e.target.files?.[0];
		if (!file || !playerId) return;
		uploadingAttest = true;
		try {
			const ext  = file.name.split('.').pop();
			const path = `${playerId}/${Date.now()}.${ext}`;
			const { error } = await sb.storage.from('attests').upload(path, file);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			form = { ...form, attest_url: path };
			triggerToast('Attest hochgeladen');
		} finally {
			uploadingAttest = false;
			e.target.value = '';
		}
	}

	async function viewAttest() {
		const path = form?.attest_url;
		if (!path) return;
		viewingAttest = true;
		try {
			const { data, error } = await sb.storage.from('attests').createSignedUrl(path, 3600);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			window.open(data.signedUrl, '_blank', 'noopener');
		} finally {
			viewingAttest = false;
		}
	}
</script>

<BottomSheet bind:open title={sheetTitle}>
	{#if section === 'kontakt'}
		<div class="edit-form">
			<label class="mw-field" class:mw-field--focus={focus === 'name'}>
				<span>Name</span>
				<input type="text" bind:value={form.name} />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'email'}>
				<span>E-Mail</span>
				<input type="email" value={form.email ?? ''} disabled />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'phone'}>
				<span>Telefon</span>
				<input type="tel" bind:value={form.phone} placeholder="+43 …" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'address'}>
				<span>Adresse</span>
				<input type="text" bind:value={form.address} placeholder="Straße, PLZ Ort" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'birth_date'}>
				<span>Geburtsdatum</span>
				<input type="date" bind:value={form.birth_date} />
			</label>
			<div class="edit-actions">
				<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={close}>Abbrechen</button>
				<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
			</div>
		</div>
	{:else if section === 'sport'}
		<div class="edit-form">
			<div class="edit-row">
				<label class="mw-field" class:mw-field--focus={focus === 'shirt_size'}>
					<span>Trikotgröße</span>
					<select bind:value={form.shirt_size}>
						<option value="">–</option>
						{#each SHIRT_SIZES as s}<option value={s}>{s}</option>{/each}
					</select>
				</label>
				<label class="mw-field" class:mw-field--focus={focus === 'pants_size'}>
					<span>Hosengröße</span>
					<input type="text" bind:value={form.pants_size} placeholder="z.B. 32/32" />
				</label>
			</div>
			<div class="edit-row">
				<label class="mw-field" class:mw-field--focus={focus === 'shoe_size'}>
					<span>Schuhgröße</span>
					<input type="text" bind:value={form.shoe_size} placeholder="z.B. 43" />
				</label>
				<label class="mw-field" class:mw-field--focus={focus === 'jersey_number'}>
					<span>Trikotnummer</span>
					<input type="number" min="1" max="99" bind:value={form.jersey_number} placeholder="1–99" />
				</label>
			</div>
			<label class="mw-field" class:mw-field--focus={focus === 'spielerpass_nr'}>
				<span>Spielerpass-Nr.</span>
				<input type="text" bind:value={form.spielerpass_nr} />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'medical_exam_expiry'}>
				<span>Ärztliches Attest gültig bis</span>
				<input type="date" bind:value={form.medical_exam_expiry} />
			</label>

			<div class="mw-field mw-field--block" class:mw-field--focus={focus === 'attest_url'}>
				<span>Attest-Datei</span>
				<div class="attest-row">
					{#if form.attest_url}
						<span class="attest-status">
							<span class="material-symbols-outlined">task</span> Hochgeladen
						</span>
						<button
							type="button"
							class="mw-btn mw-btn--ghost"
							onclick={viewAttest}
							disabled={viewingAttest}
							aria-label="Attest anzeigen"
						>
							{viewingAttest ? 'Öffne …' : 'Anzeigen'}
						</button>
					{:else}
						<span class="attest-status attest-status--empty">Nicht hochgeladen</span>
					{/if}
				</div>
				<label class="attest-upload">
					<input
						type="file"
						accept="application/pdf,image/jpeg,image/png"
						onchange={uploadAttest}
						hidden
					/>
					<span class="material-symbols-outlined">
						{uploadingAttest ? 'progress_activity' : 'upload'}
					</span>
					{uploadingAttest ? 'Lädt hoch …' : (form.attest_url ? 'Neues Attest hochladen' : 'Attest hochladen')}
				</label>
				<p class="attest-hint">PDF, JPG oder PNG. Nur du und der Kapitän können es sehen.</p>
			</div>

			<div class="edit-actions">
				<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={close}>Abbrechen</button>
				<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
			</div>
		</div>
	{:else if section === 'notfall'}
		<div class="edit-form">
			<label class="mw-field" class:mw-field--focus={focus === 'emergency_contact_name'}>
				<span>Name der Kontaktperson</span>
				<input type="text" bind:value={form.emergency_contact_name} placeholder="z.B. Maria Müller" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'emergency_contact_phone'}>
				<span>Telefon</span>
				<input type="tel" bind:value={form.emergency_contact_phone} placeholder="+43 …" />
			</label>
			<p class="edit-hint">Wird nur im Notfall bei Turnieren/Spielen verwendet.</p>
			<div class="edit-actions">
				<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={close}>Abbrechen</button>
				<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
			</div>
		</div>
	{:else if section === 'mobilitaet'}
		<div class="edit-form">
			<label class="mw-field mw-field--inline" class:mw-field--focus={focus === 'drivers_license'}>
				<span>Führerschein</span>
				<ToggleSwitch bind:checked={form.drivers_license} ariaLabel="Führerschein" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'default_car_seats'}>
				<span>Plätze im eigenen Auto (inkl. Fahrer)</span>
				<input type="number" min="1" max="9" bind:value={form.default_car_seats} placeholder="z.B. 5" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'dietary_notes'}>
				<span>Ernährungshinweise / Allergien</span>
				<textarea rows="3" bind:value={form.dietary_notes} placeholder="z.B. vegetarisch, Nussallergie, …"></textarea>
			</label>
			<div class="edit-actions">
				<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={close}>Abbrechen</button>
				<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
			</div>
		</div>
	{:else if section === 'zahlung'}
		<div class="edit-form">
			<label class="mw-field" class:mw-field--focus={focus === 'iban'}>
				<span>IBAN</span>
				<input type="text" bind:value={form.iban} placeholder="AT.." autocomplete="off" />
			</label>
			<label class="mw-field" class:mw-field--focus={focus === 'account_holder'}>
				<span>Kontoinhaber</span>
				<input type="text" bind:value={form.account_holder} placeholder="Name wie auf der Karte" />
			</label>
			<p class="edit-hint">Für Rückerstattungen (Reisekosten, Turniere) und Mitgliedsbeitrag.</p>
			<div class="edit-actions">
				<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={close}>Abbrechen</button>
				<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
			</div>
		</div>
	{/if}
</BottomSheet>

<style>
	.edit-form { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-2) var(--space-4) var(--space-6); }
	.edit-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); }
	.edit-actions { display: flex; gap: var(--space-2); margin-top: var(--space-3); }
	.edit-hint {
		margin: 0; font-size: 0.76rem; color: var(--color-on-surface-variant);
	}

	.edit-form :global(.mw-field) { margin-bottom: 0; }
	.edit-form :global(.mw-field > span) {
		font-family: var(--font-display); font-size: 0.7rem; font-weight: 700;
		letter-spacing: 0.06em; text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.edit-form :global(.mw-field input:not([type="checkbox"])),
	.edit-form :global(.mw-field select),
	.edit-form :global(.mw-field textarea) {
		width: 100%; padding: 10px 12px;
		border: 1px solid var(--color-outline-variant); border-radius: 10px;
		background: var(--color-surface-container-lowest); font-family: var(--font-body);
		font-size: 15px; color: var(--color-on-surface);
	}
	.edit-form :global(.mw-field textarea) { resize: vertical; min-height: 72px; }
	.edit-form :global(.mw-field input:focus),
	.edit-form :global(.mw-field select:focus),
	.edit-form :global(.mw-field textarea:focus) { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }
	.edit-form :global(.mw-field--focus input:not([type="checkbox"])),
	.edit-form :global(.mw-field--focus select),
	.edit-form :global(.mw-field--focus textarea) { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }

	.edit-form :global(.mw-field--inline) {
		flex-direction: row; align-items: center; justify-content: space-between;
		padding: 10px 12px; border: 1px solid var(--color-outline-variant);
		border-radius: 10px; background: var(--color-surface-container-lowest);
	}
	.edit-form :global(.mw-field--inline > span) { margin: 0; }

	.edit-form :global(.mw-field--block) {
		display: flex; flex-direction: column; gap: var(--space-2);
	}

	.attest-row {
		display: flex; align-items: center; justify-content: space-between; gap: var(--space-2);
		padding: 10px 12px;
		border: 1px solid var(--color-outline-variant); border-radius: 10px;
		background: var(--color-surface-container-lowest);
	}
	.attest-status {
		display: inline-flex; align-items: center; gap: 6px;
		font-size: 0.88rem; font-weight: 700; color: var(--color-on-surface);
	}
	.attest-status .material-symbols-outlined {
		font-size: 1.1rem; color: #16a34a;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}
	.attest-status--empty {
		color: var(--color-outline); font-style: italic; font-weight: 500;
	}

	.attest-upload {
		display: inline-flex; align-items: center; justify-content: center; gap: 6px;
		padding: 10px 12px; cursor: pointer;
		border: 1px dashed var(--color-outline-variant); border-radius: 10px;
		background: transparent;
		font-size: 0.88rem; font-weight: 700; color: var(--color-primary);
	}
	.attest-upload .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 0, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}
	.attest-upload:active { background: var(--color-surface-container-low); }
	.attest-hint {
		margin: 0; font-size: 0.74rem; color: var(--color-on-surface-variant);
	}
</style>
