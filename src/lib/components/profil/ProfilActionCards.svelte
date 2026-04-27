<script>
	let { attestStatus = null, missingFields = [], birthdaySoon = null, onEdit } = $props();

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

	// Profil-unvollständig: max. 3 Felder direkt anzeigen, Rest als "+N weitere".
	const missingPreview = $derived.by(() => {
		if (!missingFields?.length) return '';
		const shown = missingFields.slice(0, 3).join(', ');
		const rest  = missingFields.length - 3;
		return rest > 0 ? `${shown} +${rest} weitere` : shown;
	});

	const missingLabel = $derived(missingFields.length === 1 ? 'Feld' : 'Felder');

	const birthdayTitle = $derived.by(() => {
		if (!birthdaySoon) return '';
		const d = birthdaySoon.days;
		if (d === 0) return 'Heute Geburtstag! 🎉';
		if (d === 1) return 'Geburtstag morgen';
		return `Geburtstag in ${d} Tagen`;
	});

	const hasAnyAlert = $derived(
		!!attestStatus || (missingFields?.length ?? 0) > 0 || !!birthdaySoon
	);

	const hasActionAlert = $derived(
		!!attestStatus || (missingFields?.length ?? 0) > 0
	);
</script>

{#if hasAnyAlert}
	<div class="action-stack">
		{#if hasActionAlert}
			<div class="action-eyebrow">ZU ERLEDIGEN</div>
			<div class="action-hairline"></div>
		{/if}

		<div class="action-cards">

			{#if attestStatus?.kind === 'expired'}
				<button
					type="button"
					class="action-card action-card--warn"
					onclick={() => onEdit?.('sport', 'medical_exam_expiry')}
				>
					<span class="action-strip" aria-hidden="true"></span>
					<span class="material-symbols-outlined action-icon">warning</span>
					<div class="action-body">
						<span class="action-title">Ärztliches Attest abgelaufen</span>
						<span class="action-sub">Seit {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'}</span>
					</div>
					<span class="action-cta">ERNEUERN →</span>
				</button>
			{:else if attestStatus?.kind === 'soon'}
				<button
					type="button"
					class="action-card action-card--gold"
					onclick={() => onEdit?.('sport', 'medical_exam_expiry')}
				>
					<span class="action-strip" aria-hidden="true"></span>
					<span class="material-symbols-outlined action-icon">medical_information</span>
					<div class="action-body">
						<span class="action-title">Attest läuft in {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'} ab</span>
						<span class="action-sub">Untersuchung jetzt planen</span>
					</div>
					<span class="action-cta">VERLÄNGERN →</span>
				</button>
			{/if}

			{#if missingFields.length > 0}
				{@const [sec, key] = firstTarget()}
				<button
					type="button"
					class="action-card action-card--blue"
					onclick={() => onEdit?.(sec, key)}
				>
					<span class="action-strip" aria-hidden="true"></span>
					<span class="material-symbols-outlined action-icon">edit_note</span>
					<div class="action-body">
						<span class="action-title">Profil unvollständig</span>
						<span class="action-sub">{missingFields.length} {missingLabel}: {missingPreview}</span>
					</div>
					<span class="action-cta">ERGÄNZEN →</span>
				</button>
			{/if}

			{#if birthdaySoon}
				<div
					class="action-card action-card--gold action-card--static"
					class:action-card--pulse={birthdaySoon.days === 0}
				>
					<span class="action-strip" aria-hidden="true"></span>
					<span class="material-symbols-outlined action-icon">cake</span>
					<div class="action-body">
						<span class="action-title">{birthdayTitle}</span>
						<span class="action-sub">Du wirst {birthdaySoon.age}</span>
					</div>
					{#if birthdaySoon.days === 0}
						<span class="action-cta">ANSTOSSEN 🍾</span>
					{/if}
				</div>
			{/if}

		</div>
	</div>
{/if}

<style>
	/* ── Action-lokale Tokens ──────────────────────────────────────────── */
	.action-stack {
		--action-gold:      var(--color-secondary);
		--action-gold-glow: rgba(212, 175, 55, 0.25);
		--action-warn:      var(--color-primary);
		--action-hairline:  linear-gradient(90deg, transparent, var(--action-gold) 20%, var(--action-gold) 80%, transparent);

		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	/* ── Eyebrow + Hairline ────────────────────────────────────────────── */
	.action-eyebrow {
		font-size: 0.65rem;
		font-weight: 800;
		letter-spacing: 0.2em;
		text-transform: uppercase;
		color: var(--action-gold);
		text-align: center;
	}
	.action-hairline {
		height: 1px;
		width: 100%;
		background: var(--action-hairline);
		opacity: 0.85;
		margin-bottom: var(--space-1);
	}

	/* ── Card-Stack ────────────────────────────────────────────────────── */
	.action-cards {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	/* ── Card-Basis ────────────────────────────────────────────────────── */
	.action-card {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-4);
		padding-left: calc(var(--space-4) + var(--space-1));
		border-radius: var(--radius-xl);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		box-shadow: var(--shadow-card);
		text-align: left;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: transform 100ms ease;
		width: 100%;
		font-family: inherit;
		overflow: hidden;
	}
	.action-card:active:not(.action-card--static) { transform: scale(0.98); }

	.action-card--static { cursor: default; }

	/* ── Severity-Strip (linke Kante) ──────────────────────────────────── */
	.action-strip {
		position: absolute;
		top: 0;
		left: 0;
		bottom: 0;
		width: 4px;
		border-radius: var(--radius-xl) 0 0 var(--radius-xl);
	}
	.action-card--warn .action-strip { background: var(--action-warn); }
	.action-card--gold .action-strip { background: var(--action-gold); }
	.action-card--blue .action-strip { background: var(--color-info); }

	/* ── Icon ──────────────────────────────────────────────────────────── */
	.action-icon {
		font-size: 1.4rem;
		flex-shrink: 0;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.action-card--warn .action-icon { color: var(--action-warn); }
	.action-card--gold .action-icon { color: var(--action-gold); }
	.action-card--blue .action-icon { color: var(--color-info); }

	/* ── Body ──────────────────────────────────────────────────────────── */
	.action-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.action-title {
		font-weight: 700;
		font-size: 0.95rem;
		color: var(--color-on-surface);
	}
	.action-sub {
		font-size: 0.78rem;
		color: var(--color-on-surface-variant);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	/* ── CTA ───────────────────────────────────────────────────────────── */
	.action-cta {
		flex-shrink: 0;
		font-family: var(--font-display);
		font-size: 0.78rem;
		font-weight: 700;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		transition: transform 120ms ease;
	}
	.action-card--warn .action-cta { color: var(--action-warn); }
	.action-card--gold .action-cta { color: var(--action-gold); }
	.action-card--blue .action-cta { color: var(--color-info); }
	.action-card:hover:not(.action-card--static) .action-cta {
		transform: translateX(2px);
	}

	/* ── Birthday-Today Pulse ──────────────────────────────────────────── */
	.action-card--pulse {
		animation: action-gold-pulse 2.4s ease-in-out infinite;
	}
	@keyframes action-gold-pulse {
		0%, 100% { box-shadow: var(--shadow-card); }
		50%      { box-shadow: var(--shadow-card), 0 0 0 6px var(--action-gold-glow); }
	}

	/* ── Reduced Motion ────────────────────────────────────────────────── */
	@media (prefers-reduced-motion: reduce) {
		.action-card,
		.action-cta,
		.action-card--pulse {
			animation: none !important;
			transition: none !important;
		}
		.action-card:hover:not(.action-card--static) .action-cta {
			transform: none;
		}
	}
</style>
