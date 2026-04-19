<script>
	import { currentSubtab } from '$lib/stores/subtab.js';
	import { playerRole }    from '$lib/stores/auth';
	import UebersichtTab     from '$lib/components/profil/UebersichtTab.svelte';
	import MeineDatenTab     from '$lib/components/profil/MeineDatenTab.svelte';
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
	{:else if activeTab === 'meine-daten'}
		<MeineDatenTab />
	{:else if activeTab === 'einstellungen'}
		<EinstellungenTab />
	{:else if activeTab === 'admin'}
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

/* ── Performance Card ───────────────────────────────── */
.perf-card {
	background: linear-gradient(160deg, #1a0000 0%, #3d0000 40%, #6b0000 100%);
	border-radius: 20px;
	overflow: hidden;
	box-shadow: 0 8px 32px rgba(204, 0, 0, 0.28);
}

.perf-header {
	display: flex;
	justify-content: space-between;
	align-items: center;
	padding: var(--space-4) var(--space-5) 0;
}

.perf-eyebrow {
	font-family: var(--font-display);
	font-size: 0.7rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.14em;
	color: rgba(212, 175, 55, 0.9);
}

.perf-games {
	font-size: 0.72rem;
	font-weight: 700;
	color: rgba(255, 255, 255, 0.45);
	letter-spacing: 0.04em;
}

.perf-hero {
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: var(--space-5) var(--space-5) var(--space-4);
	gap: var(--space-1);
}

.perf-trophy {
	font-size: 2rem;
	color: var(--color-secondary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 48;
	margin-bottom: var(--space-1);
	filter: drop-shadow(0 0 12px rgba(212,175,55,0.6));
}

.perf-avg-value {
	font-family: var(--font-display);
	font-size: 4rem;
	font-weight: 900;
	color: #fff;
	line-height: 1;
	letter-spacing: -0.02em;
	text-shadow: 0 2px 16px rgba(0,0,0,0.4);
}

.perf-avg-label {
	font-size: 0.78rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255,255,255,0.5);
}

.perf-divider {
	height: 1px;
	background: linear-gradient(90deg, transparent, rgba(212,175,55,0.35), transparent);
	margin: 0 var(--space-5);
}

.perf-stats-row {
	display: flex;
	align-items: stretch;
	padding: var(--space-4) var(--space-5);
	gap: 0;
}

.perf-stat {
	flex: 1;
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 3px;
}

.perf-stat-sep {
	width: 1px;
	background: rgba(255,255,255,0.12);
	margin: 0 var(--space-2);
	align-self: stretch;
}

.perf-stat-value {
	font-family: var(--font-display);
	font-size: 1.45rem;
	font-weight: 900;
	color: #fff;
	line-height: 1;
	display: flex;
	align-items: baseline;
	gap: 4px;
}

.perf-stat-form { color: #fff; }

.perf-trend {
	font-family: var(--font-display);
	font-size: 0.72rem;
	font-weight: 800;
	padding: 1px 5px;
	border-radius: 999px;
}

.perf-trend--up { color: #4ade80; background: rgba(74, 222, 128, 0.15); }
.perf-trend--dn { color: #f87171; background: rgba(248, 113, 113, 0.15); }

.perf-stat-label {
	font-size: 0.65rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255,255,255,0.4);
}

/* ── Profil-Karte (royal) ───────────────────────────── */
.profil-card {
	background: var(--color-surface-container-lowest);
	border-radius: 20px;
	overflow: hidden;
	border: 1px solid var(--color-surface-container);
	box-shadow: 0 4px 24px rgba(0,0,0,0.06);
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
	box-shadow: 0 4px 20px rgba(0,0,0,0.3);
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
	box-shadow: 0 2px 8px rgba(0,0,0,0.12);
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

/* ── Nächstes Spiel ─────────────────────────────────── */
.next-match-card {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-left: 4px solid var(--color-primary);
	border-radius: 16px;
	overflow: hidden;
	display: flex;
	flex-direction: column;
}

.next-match-head {
	display: flex;
	align-items: center;
	justify-content: space-between;
	padding: var(--space-4) var(--space-4) var(--space-2);
}

.days-badge {
	font-size: 0.72rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	padding: 3px 10px;
	border-radius: 999px;
	background: var(--color-surface-container);
	color: var(--color-on-surface-variant);
}

.days-badge--urgent { background: var(--color-primary); color: #fff; }

.next-match-body {
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
	padding: var(--space-2) var(--space-4) var(--space-4);
}

.next-match-info {
	display: flex;
	justify-content: space-between;
	align-items: flex-start;
	gap: var(--space-3);
}

.match-meta-label {
	font-size: 0.68rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.12em;
	color: var(--color-on-surface-variant);
	margin: 0 0 3px;
}

.match-opponent {
	font-family: var(--font-display);
	font-weight: 900;
	font-size: 1.15rem;
	color: var(--color-on-surface);
	margin: 0;
	line-height: 1.1;
}

.match-league {
	font-size: 0.78rem;
	font-weight: 600;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
	text-transform: uppercase;
	letter-spacing: 0.04em;
}

.match-date-block { text-align: right; flex-shrink: 0; }

.match-date {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
}

.match-time {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.95rem;
	color: var(--color-primary);
	margin: 2px 0 0;
}

.match-link-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3);
	background: rgba(204,0,0,0.06);
	border-radius: 12px;
	text-decoration: none;
	border: 1px solid rgba(204,0,0,0.1);
	transition: background 150ms;
}

.match-link-row:active { background: rgba(204,0,0,0.12); }

.match-link-icon {
	width: 36px;
	height: 36px;
	border-radius: 10px;
	background: var(--color-primary);
	display: grid;
	place-items: center;
	flex-shrink: 0;
}

.match-link-icon .material-symbols-outlined {
	color: #fff;
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.match-link-text { flex: 1; }
.match-link-label { font-size: 0.85rem; font-weight: 700; color: var(--color-on-surface); margin: 0; }
.match-link-arrow { color: var(--color-on-surface-variant); font-size: 1.1rem; }

/* ── Agenda ─────────────────────────────────────────── */
.agenda { display: flex; flex-direction: column; gap: 0; }

.agenda-item {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) 0;
	border-top: 1px solid var(--color-surface-container);
}

.agenda-item:first-child { border-top: none; padding-top: 0; }

.agenda-date-col {
	display: flex;
	flex-direction: column;
	align-items: center;
	min-width: 36px;
	flex-shrink: 0;
}

.agenda-day {
	font-family: var(--font-display);
	font-size: 1.3rem;
	font-weight: 900;
	color: var(--color-primary);
	line-height: 1;
}

.agenda-month {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}

.agenda-info { flex: 1; min-width: 0; }

.agenda-title {
	font-weight: 700;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.agenda-sub {
	font-size: 0.78rem;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
}

.agenda-rsvp {
	display: flex;
	gap: var(--space-1);
	flex-shrink: 0;
}

.rsvp-btn {
	width: 32px;
	height: 32px;
	border-radius: 50%;
	border: 1.5px solid var(--color-outline-variant);
	background: transparent;
	cursor: pointer;
	display: grid;
	place-items: center;
	transition: background 150ms, border-color 150ms;
	-webkit-tap-highlight-color: transparent;
}

.rsvp-btn .material-symbols-outlined { font-size: 1rem; color: var(--color-on-surface-variant); }

.rsvp-btn--yes.active { background: #dcfce7; border-color: #16a34a; }
.rsvp-btn--yes.active .material-symbols-outlined { color: #16a34a; }
.rsvp-btn--no.active  { background: #fee2e2; border-color: var(--color-error); }
.rsvp-btn--no.active  .material-symbols-outlined { color: var(--color-error); }

/* ── Meilensteine ───────────────────────────────────── */
.milestones {
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.milestones-scroll {
	display: flex;
	gap: var(--space-3);
	overflow-x: auto;
	scrollbar-width: none;
	padding-bottom: 4px;
}

.milestones-scroll::-webkit-scrollbar { display: none; }

.milestone-card {
	flex-shrink: 0;
	width: 120px;
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 14px;
	padding: var(--space-4) var(--space-3);
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: var(--space-2);
	text-align: center;
}

.milestone-icon {
	font-size: 2rem;
	color: var(--color-secondary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}

.milestone-label {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.85rem;
	color: var(--color-on-surface);
	margin: 0;
	line-height: 1.2;
}

.milestone-sub {
	font-size: 0.72rem;
	color: var(--color-on-surface-variant);
	margin: 0;
}

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
