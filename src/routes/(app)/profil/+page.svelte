<script>
	import { currentSubtab } from '$lib/stores/subtab.js';
	import { playerRole }    from '$lib/stores/auth';
	import UebersichtTab     from '$lib/components/profil/UebersichtTab.svelte';
	import EinstellungenTab  from '$lib/components/profil/EinstellungenTab.svelte';
	import AdminTab          from '$lib/components/profil/AdminTab.svelte';

	const activeTab = $derived.by(() => {
		const t = $currentSubtab;
		if (t === 'admin' && $playerRole !== 'kapitaen') return 'uebersicht';
		return t ?? 'uebersicht';
	});
</script>

<div class="profil-page">
	{#if activeTab === 'uebersicht'}
		<UebersichtTab />
	{/if}
	{#if activeTab === 'einstellungen'}
		<EinstellungenTab />
	{/if}
	{#if activeTab === 'admin'}
		<AdminTab />
	{/if}
</div>

<style>
:global {
/* ── Seiten-Wrapper ─────────────────────────────────── */
.profil-page {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
	padding: var(--space-5);
}

.profil-loading {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
}

/* ── Sektion-Titel ──────────────────────────────────── */
.section-title {
	display: flex;
	gap: var(--space-2);
	align-items: center;
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.875rem;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-primary);
	margin: 0;
}

.section-title .material-symbols-outlined {
	font-size: 1rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

/* ── Karte (universal) ──────────────────────────────── */
.card {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

/* ── Avatar-Row ─────────────────────────────────────── */
.avatar-row {
	display: flex;
	gap: var(--space-4);
	align-items: center;
}

.avatar {
	width: 80px;
	height: 80px;
	border-radius: 50%;
	overflow: hidden;
	background: var(--color-surface-container);
	display: grid;
	place-items: center;
	font-family: var(--font-display);
	font-size: 2rem;
	font-weight: 800;
	color: var(--color-on-surface-variant);
	border: 3px solid var(--color-secondary);
	flex-shrink: 0;
}

.avatar img { width: 100%; height: 100%; object-fit: cover; }

.avatar-meta { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.avatar-name { font-family: var(--font-display); font-weight: 700; font-size: 1rem; color: var(--color-on-surface); margin: 0; }
.avatar-email { font-size: 0.8rem; color: var(--color-on-surface-variant); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.upload {
	display: inline-flex;
	gap: 4px;
	align-items: center;
	padding: 6px 12px;
	border: 1px solid var(--color-outline-variant);
	background: transparent;
	border-radius: 999px;
	font-size: 0.82rem;
	cursor: pointer;
	margin-top: 4px;
	color: var(--color-on-surface-variant);
	width: fit-content;
}

.upload .material-symbols-outlined { font-size: 1rem; }

/* ── Felder ─────────────────────────────────────────── */
.fields-grid { display: flex; flex-direction: column; gap: var(--space-2); }
.fields-row  { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); }

.field {
	display: flex;
	flex-direction: column;
	gap: 3px;
	font-size: 0.82rem;
	font-weight: 600;
	color: var(--color-on-surface-variant);
}

.field input,
.field select {
	padding: 10px 12px;
	border: 1px solid var(--color-outline-variant);
	border-radius: 10px;
	font-size: 15px;
	background: var(--color-surface-container-lowest);
	color: var(--color-on-surface);
	font-family: inherit;
}

.field input:disabled { background: var(--color-surface-container-low); color: var(--color-on-surface-variant); }
.field input:focus,
.field select:focus { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }

/* ── Buttons ────────────────────────────────────────── */
.btn {
	display: inline-flex;
	gap: var(--space-2);
	align-items: center;
	justify-content: center;
	padding: 10px 20px;
	border: 0;
	border-radius: 999px;
	font-size: 0.9rem;
	font-weight: 600;
	font-family: inherit;
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
}

.btn--primary  { background: var(--color-primary); color: #fff; align-self: flex-start; }
.btn--outline  { background: transparent; border: 1.5px solid var(--color-outline-variant); color: var(--color-on-surface-variant); }
.btn--push     { width: 100%; }
.btn--ghost    { background: none; border: 1px solid var(--color-outline-variant); color: var(--color-on-surface-variant); }
.btn--logout   { align-self: center; margin-top: var(--space-2); }
.btn:active    { opacity: 0.75; transform: scale(0.98); }

.msg { margin: 0; font-size: 0.88rem; color: var(--color-on-surface-variant); }

/* ── Profil-Karte (royal) ───────────────────────────── */
.profil-card {
	background: var(--color-surface-container-lowest);
	border-radius: 20px;
	overflow: hidden;
	border: 1px solid var(--color-surface-container);
	box-shadow: var(--shadow-card);
}

.profil-card-hero {
	position: relative;
	background: linear-gradient(160deg, #1a0000 0%, #850000 100%);
	height: 88px;
	display: flex;
	justify-content: center;
}

.profil-avatar-ring {
	position: absolute;
	bottom: -36px;
	width: 84px;
	height: 84px;
	border-radius: 50%;
	padding: 3px;
	background: linear-gradient(135deg, var(--color-secondary), #a07c20);
	box-shadow: var(--shadow-float);
}

.profil-avatar {
	width: 100%;
	height: 100%;
	border-radius: 50%;
	overflow: hidden;
	background: var(--color-surface-container);
	display: grid;
	place-items: center;
	font-family: var(--font-display);
	font-size: 2.2rem;
	font-weight: 900;
	color: var(--color-primary);
	border: 3px solid var(--color-surface-container-lowest);
}

.profil-avatar img { width: 100%; height: 100%; object-fit: cover; }

.profil-photo-btn {
	position: absolute;
	bottom: -28px;
	left: calc(50% + 26px);
	width: 32px;
	height: 32px;
	border-radius: 50%;
	background: var(--color-surface-container-lowest);
	border: 1.5px solid var(--color-outline-variant);
	display: grid;
	place-items: center;
	cursor: pointer;
	box-shadow: var(--shadow-card);
	transition: background 120ms;
}

.profil-photo-btn:active { background: var(--color-surface-container); }

.profil-photo-btn .material-symbols-outlined {
	font-size: 1rem;
	color: var(--color-on-surface-variant);
}

.profil-card-identity {
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: calc(36px + var(--space-4)) var(--space-5) var(--space-4);
	text-align: center;
	gap: var(--space-1);
}

.profil-card-name {
	font-family: var(--font-display);
	font-size: 1.35rem;
	font-weight: 900;
	color: var(--color-on-surface);
	margin: 0;
	letter-spacing: -0.01em;
}

.profil-card-email {
	font-size: 0.8rem;
	color: var(--color-on-surface-variant);
	margin: 0;
}

.profil-card-gold-line {
	width: 40px;
	height: 2px;
	border-radius: 999px;
	background: linear-gradient(90deg, var(--color-secondary), #a07c20);
	margin-top: var(--space-2);
}

.profil-card-fields {
	padding: 0 var(--space-4) var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.profil-card-actions {
	padding: var(--space-3) var(--space-4) var(--space-4);
	border-top: 1px solid var(--color-surface-container);
	display: flex;
	flex-direction: column;
	gap: var(--space-2);
}

.trend-up { font-size: 0.7rem; color: #16a34a; }
.trend-dn { font-size: 0.7rem; color: var(--color-error); }


/* ── Push Prefs ─────────────────────────────────────── */
.prefs { display: flex; flex-direction: column; gap: 2px; }

.toggle {
	display: flex;
	justify-content: space-between;
	align-items: center;
	padding: 8px 0;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	border-top: 1px solid var(--color-surface-container);
	cursor: pointer;
}

.toggle:first-child { border-top: none; }

/* ── Admin Panel ────────────────────────────────────── */
.admin-header {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-4);
	background: linear-gradient(135deg, rgba(204,0,0,0.08) 0%, rgba(204,0,0,0.04) 100%);
	border: 1px solid rgba(204,0,0,0.15);
	border-radius: 16px;
}

.admin-header-icon {
	font-size: 2rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 48;
	flex-shrink: 0;
}

.admin-header-title {
	font-family: var(--font-display);
	font-weight: 900;
	font-size: 1.15rem;
	color: var(--color-on-surface);
	margin: 0;
}

.admin-header-sub {
	font-size: 0.78rem;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
}

.admin-section {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.admin-section-head {
	display: flex;
	align-items: center;
	gap: var(--space-3);
}

.admin-section-icon {
	width: 36px;
	height: 36px;
	border-radius: 10px;
	display: grid;
	place-items: center;
	flex-shrink: 0;
}

.admin-section-icon .material-symbols-outlined {
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.admin-section-title {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
}

.admin-action-grid {
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.admin-action {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) var(--space-2);
	border: none;
	background: none;
	border-radius: 10px;
	cursor: pointer;
	text-align: left;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms;
	width: 100%;
}

.admin-action--live:active { background: var(--color-surface-container-low); }
.admin-action--disabled    { opacity: 0.45; cursor: default; }

.admin-action-icon {
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	flex-shrink: 0;
	width: 24px;
	text-align: center;
}

.admin-action-label {
	flex: 1;
	font-size: 0.88rem;
	font-weight: 600;
	color: var(--color-on-surface);
}

.admin-action-badge {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	padding: 2px 8px;
	border-radius: 999px;
	background: var(--color-surface-container-high);
	color: var(--color-on-surface-variant);
}

.admin-version {
	display: flex;
	align-items: center;
	justify-content: center;
	gap: var(--space-2);
	font-size: 0.75rem;
	color: var(--color-on-surface-variant);
	padding: var(--space-3);
}

.admin-version .material-symbols-outlined { font-size: 1rem; }
} /* end :global */
</style>
