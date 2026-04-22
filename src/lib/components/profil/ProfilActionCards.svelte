<script>
	let { attestStatus = null, missingFields = [], birthdaySoon = null, onEdit } = $props();

	// Map the display label → [section, fieldKey] so that tapping an action jumps
	// to the right section sheet with the right focus. Section split per Phase B.
	const FIELD_MAP = {
		'Telefon':         ['kontakt', 'phone'],
		'Adresse':         ['kontakt', 'address'],
		'Notfallkontakt':  ['notfall', 'emergency_contact_phone'],
		'Trikotgröße':     ['sport',   'shirt_size'],
		'Hosengröße':      ['sport',   'pants_size'],
		'Spielerpass-Nr.': ['sport',   'spielerpass_nr'],
	};

	function firstTarget() {
		const label = missingFields[0];
		return FIELD_MAP[label] ?? ['kontakt', ''];
	}
</script>

{#if attestStatus || missingFields.length > 0 || birthdaySoon}
	<div class="action-cards">

		{#if attestStatus?.kind === 'expired'}
			<button class="action-card action-card--warn" onclick={() => onEdit?.('sport', 'medical_exam_expiry')}>
				<span class="material-symbols-outlined action-icon">warning</span>
				<div class="action-body">
					<span class="action-title">Ärztliches Attest abgelaufen</span>
					<span class="action-sub">Seit {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'}</span>
				</div>
				<span class="action-cta">Aktualisieren →</span>
			</button>
		{:else if attestStatus?.kind === 'soon'}
			<button class="action-card action-card--gold" onclick={() => onEdit?.('sport', 'medical_exam_expiry')}>
				<span class="material-symbols-outlined action-icon">medical_information</span>
				<div class="action-body">
					<span class="action-title">Attest läuft in {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'} ab</span>
					<span class="action-sub">Untersuchung jetzt planen</span>
				</div>
				<span class="action-cta">Aktualisieren →</span>
			</button>
		{/if}

		{#if missingFields.length > 0}
			{@const [sec, key] = firstTarget()}
			<button class="action-card action-card--blue" onclick={() => onEdit?.(sec, key)}>
				<span class="material-symbols-outlined action-icon">edit_note</span>
				<div class="action-body">
					<span class="action-title">Profil unvollständig</span>
					<span class="action-sub">{missingFields.length} {missingFields.length === 1 ? 'Feld' : 'Felder'}: {missingFields.join(', ')}</span>
				</div>
				<span class="action-cta">Ergänzen →</span>
			</button>
		{/if}

		{#if birthdaySoon}
			<div class="action-card action-card--gold action-card--static">
				<span class="material-symbols-outlined action-icon">cake</span>
				<div class="action-body">
					<span class="action-title">
						{birthdaySoon.days === 0 ? 'Heute Geburtstag!' : `Geburtstag in ${birthdaySoon.days} ${birthdaySoon.days === 1 ? 'Tag' : 'Tagen'}`}
					</span>
					<span class="action-sub">Du wirst {birthdaySoon.age}</span>
				</div>
			</div>
		{/if}

	</div>
{/if}

<style>
	.action-cards { display: flex; flex-direction: column; gap: var(--space-3); }
	.action-card {
		display: flex; align-items: center; gap: var(--space-3); padding: var(--space-4);
		border-radius: var(--radius-lg); border: 1.5px solid transparent; text-align: left;
		cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease;
		box-shadow: var(--shadow-card); width: 100%; font-family: inherit;
	}
	.action-card:active:not(.action-card--static) { transform: scale(0.98); }
	.action-card--static { cursor: default; }
	.action-card--warn { background: #fefce8; border-color: #fde047; }
	.action-card--gold { background: #fffbeb; border-color: #fbbf24; }
	.action-card--blue { background: #eff6ff; border-color: #93c5fd; }
	.action-icon { font-size: 1.4rem; flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.action-card--warn .action-icon { color: #ca8a04; }
	.action-card--gold .action-icon { color: #b45309; }
	.action-card--blue .action-icon { color: #1d4ed8; }
	.action-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.action-title { font-weight: 700; font-size: 0.9rem; color: var(--color-on-surface); }
	.action-sub   { font-size: 0.78rem; color: var(--color-on-surface-variant); }
	.action-cta   { font-size: 0.78rem; font-weight: 700; flex-shrink: 0; }
	.action-card--warn .action-cta, .action-card--gold .action-cta { color: #92400e; }
	.action-card--blue .action-cta { color: #1d4ed8; }
</style>
