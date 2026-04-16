<script>
	import { goto } from '$app/navigation';
	import { sb } from '$lib/supabase';
	import { tick } from 'svelte';
	import { browser } from '$app/environment';
	import BottomSheet from './BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast';

	let { open = $bindable(false) } = $props();

	// ── All available shortcuts ──────────────────────────────
	const ALL_SHORTCUTS = [
		{ id: 's1',  label: 'Spielbetrieb', emoji: '🎳', grad: 'linear-gradient(160deg,#E53E3E,#9E0000)',  path: '/spielbetrieb' },
		{ id: 's2',  label: 'Kalender',     emoji: '📅', grad: 'linear-gradient(160deg,#4299E1,#1A56DB)',  path: '/kalender'     },
		{ id: 's3',  label: 'Statistiken',  emoji: '📊', grad: 'linear-gradient(160deg,#ECC94B,#B7791F)',  path: '/statistiken'  },
		{ id: 's4',  label: 'Training',     emoji: '🎯', grad: 'linear-gradient(160deg,#48BB78,#276749)',  path: '/kalender'     },
		{ id: 's5',  label: 'Aufstellung',  emoji: '🏅', grad: 'linear-gradient(160deg,#9F7AEA,#553C9A)',  path: '/spielbetrieb' },
		{ id: 's6',  label: 'Neuigkeiten',  emoji: '📰', grad: 'linear-gradient(160deg,#F6AD55,#C05621)',  path: '/'             },
		{ id: 's7',  label: 'Profil',       emoji: '🪪',  grad: 'linear-gradient(160deg,#4FD1C5,#285E61)',  path: '/profil'       },
		{ id: 's8',  label: 'Events',       emoji: '🎉', grad: 'linear-gradient(160deg,#F687B3,#97266D)',  path: '/'             },
		{ id: 's9',  label: 'Ergebnisse',   emoji: '🏆', grad: 'linear-gradient(160deg,#F6E05E,#975A16)',  path: '/spielbetrieb' },
		{ id: 's10', label: 'Tabelle',      emoji: '📋', grad: 'linear-gradient(160deg,#63B3ED,#2C5282)',  path: '/statistiken'  },
		{ id: 's11', label: 'Mitglieder',   emoji: '👥', grad: 'linear-gradient(160deg,#76E4F7,#0987A0)',  path: '/mehr'         },
		{ id: 's12', label: 'Absenz',       emoji: '📵', grad: 'linear-gradient(160deg,#FC8181,#9B2C2C)',  path: '/'             },
	];

	const DEFAULT_IDS   = ['s1','s2','s3','s4','s5','s6','s7','s8'];
	const STORAGE_KEY   = 'kvwn_active_shortcuts';
	const MAX_SHORTCUTS = 8;

	function loadActive() {
		if (!browser) return [...DEFAULT_IDS];
		try {
			const raw = localStorage.getItem(STORAGE_KEY);
			if (raw) {
				const ids = JSON.parse(raw);
				if (Array.isArray(ids) && ids.length > 0) return ids.slice(0, MAX_SHORTCUTS);
			}
		} catch {}
		return [...DEFAULT_IDS];
	}

	let activeShortcuts = $state(loadActive());

	$effect(() => {
		if (browser) localStorage.setItem(STORAGE_KEY, JSON.stringify(activeShortcuts));
	});

	let suggestions = $derived(
		activeShortcuts
			.map(id => ALL_SHORTCUTS.find(s => s.id === id))
			.filter(Boolean)
	);

	function toggleShortcut(id, isSelected) {
		if (isSelected) {
			activeShortcuts = activeShortcuts.filter(i => i !== id);
		} else {
			if (activeShortcuts.length >= MAX_SHORTCUTS) {
				triggerToast('Maximal 8 Vorschläge möglich');
				return;
			}
			activeShortcuts = [...activeShortcuts, id];
		}
	}

	// ── Search state ─────────────────────────────────────────
	let query        = $state('');
	let inputEl      = $state(null);
	let playerRes    = $state([]);
	let matchRes     = $state([]);
	let searching    = $state(false);
	let active       = $state(false);
	let resActive    = $state(false);
	let shouldRender = $state(false);
	let editOpen     = $state(false);
	let searchTimer  = null;

	// ── Portal ───────────────────────────────────────────────
	function portal(node) {
		document.body.appendChild(node);
		return { destroy() { node.remove(); } };
	}

	// ── Open / close lifecycle ────────────────────────────────
	$effect(() => {
		if (open) {
			shouldRender = true;
			tick().then(() => {
				active = true;
				setTimeout(() => inputEl?.focus(), 60);
			});
		} else {
			active    = false;
			resActive = false;
			editOpen  = false;
			setTimeout(() => {
				shouldRender = false;
				query     = '';
				playerRes = [];
				matchRes  = [];
			}, 250);
			clearTimeout(searchTimer);
		}
	});

	function close() { open = false; }

	function navigateTo(path) {
		close();
		goto(path);
	}

	// ── Search ───────────────────────────────────────────────
	async function doSearch(q) {
		resActive = false;
		if (!q.trim()) { playerRes = []; matchRes = []; return; }
		searching = true;
		const term = `%${q.trim()}%`;
		const [pr, mr] = await Promise.all([
			sb.from('players').select('id,name,photo').ilike('name', term).eq('active', true).limit(5),
			sb.from('matches').select('id,date,opponent,home_away,leagues(name)').ilike('opponent', term).order('date', { ascending: false }).limit(4),
		]);
		playerRes = pr.data ?? [];
		matchRes  = mr.data ?? [];
		searching = false;
		await tick();
		resActive = true;
	}

	function onInput(e) {
		query = e.target.value;
		clearTimeout(searchTimer);
		searchTimer = setTimeout(() => doSearch(query), 220);
	}

	function onKeydown(e) { if (e.key === 'Escape') close(); }

	// ── Helpers ───────────────────────────────────────────────
	function imgPath(photo, name) {
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function fmtDate(d) {
		if (!d) return '';
		const dt = new Date(d + 'T12:00');
		return ['So','Mo','Di','Mi','Do','Fr','Sa'][dt.getDay()] + ' ' + dt.getDate() + '.' + (dt.getMonth() + 1) + '.';
	}

	let showSugg    = $derived(!query.trim());
	let showResults = $derived(!!query.trim());
	let noResults   = $derived(showResults && !searching && !playerRes.length && !matchRes.length);
</script>

{#if shouldRender}
<div
	use:portal
	class="spot-overlay"
	class:spot-overlay--active={active}
	onkeydown={onKeydown}
	role="dialog"
	aria-modal="true"
	aria-label="Spotlight Suche"
>
	<!-- ── Search bar ──────────────────────────────────────── -->
	<div class="spot-header">
		<div class="spot-input-wrap" class:spot-input-wrap--focused={false}>
			<span class="material-symbols-outlined spot-search-icon">search</span>
			<input
				bind:this={inputEl}
				class="spot-input"
				type="search"
				placeholder="Suchen…"
				autocomplete="off"
				autocorrect="off"
				spellcheck="false"
				value={query}
				oninput={onInput}
				onkeydown={onKeydown}
			/>
			{#if query}
				<button
					class="spot-input-clear"
					type="button"
					onclick={() => { query = ''; playerRes = []; matchRes = []; inputEl?.focus(); }}
					aria-label="Löschen"
				>
					<span class="material-symbols-outlined">cancel</span>
				</button>
			{/if}
		</div>
		<button class="spot-cancel-btn" onclick={close}>Abbrechen</button>
	</div>

	<!-- ── Siri-Vorschläge ────────────────────────────────── -->
	{#if showSugg}
	<div class="spot-sugg-section">
		<div class="spot-sugg-header">
			<p class="spot-section-label">Siri-Vorschläge</p>
			<button class="spot-edit-btn" onclick={() => editOpen = true}>Bearbeiten</button>
		</div>
		<div class="spot-grid">
			{#each suggestions as s, i}
				<button
					class="spot-app-cell"
					onclick={() => navigateTo(s.path)}
					style="
						opacity:          {active ? 1 : 0};
						transform:        {active ? 'translateY(0) scale(1)' : 'translateY(20px) scale(0.9)'};
						transition:       opacity 400ms cubic-bezier(0.34,1.3,0.64,1),
						                  transform 400ms cubic-bezier(0.34,1.3,0.64,1);
						transition-delay: {active ? i * 30 : 0}ms;
					"
				>
					<div class="spot-app-icon" style="background:{s.grad}">
						<span class="spot-app-emoji">{s.emoji}</span>
					</div>
					<span class="spot-app-label">{s.label}</span>
				</button>
			{/each}
		</div>
	</div>
	{/if}

	<!-- ── Suchergebnisse ─────────────────────────────────── -->
	{#if showResults}
	<div class="spot-results-section">
		{#if searching}
			<div class="spot-glass-box">
				{#each [0,1,2] as _}
					<div class="spot-result-row spot-result-row--skel">
						<div class="skel-row-avatar shimmer-box"></div>
						<div class="skel-row-info">
							<div class="skel-row-name shimmer-box"></div>
							<div class="skel-row-avg  shimmer-box"></div>
						</div>
					</div>
				{/each}
			</div>
		{:else if noResults}
			<div class="spot-empty">
				<span class="material-symbols-outlined spot-empty-icon">search_off</span>
				<p class="spot-empty-text">Keine Ergebnisse für „{query}"</p>
			</div>
		{:else}
			{#if playerRes.length}
				<p class="spot-result-label">Spieler</p>
				<div class="spot-glass-box">
					{#each playerRes as p, i}
						<button
							class="spot-result-row"
							onclick={() => navigateTo('/spielbetrieb')}
							style="
								opacity:          {resActive ? 1 : 0};
								transform:        {resActive ? 'translateY(0)' : 'translateY(16px)'};
								transition:       opacity 400ms cubic-bezier(0.34,1.3,0.64,1),
								                  transform 400ms cubic-bezier(0.34,1.3,0.64,1);
								transition-delay: {resActive ? 250 + i * 40 : 0}ms;
							"
						>
							<div class="spot-result-avatar">
								<img src={imgPath(p.photo, p.name)} alt={p.name} onerror={(e) => e.currentTarget.style.display = 'none'} />
								<span class="spot-result-initial">{(p.name ?? '?')[0]}</span>
							</div>
							<div class="spot-result-text">
								<span class="spot-result-title">{p.name}</span>
								<span class="spot-result-sub">Spieler</span>
							</div>
							<span class="material-symbols-outlined spot-result-chevron">chevron_right</span>
						</button>
					{/each}
				</div>
			{/if}
			{#if matchRes.length}
				<p class="spot-result-label" style="margin-top: var(--space-4)">Spiele</p>
				<div class="spot-glass-box">
					{#each matchRes as m, i}
						<button
							class="spot-result-row"
							onclick={() => navigateTo('/spielbetrieb')}
							style="
								opacity:          {resActive ? 1 : 0};
								transform:        {resActive ? 'translateY(0)' : 'translateY(16px)'};
								transition:       opacity 400ms cubic-bezier(0.34,1.3,0.64,1),
								                  transform 400ms cubic-bezier(0.34,1.3,0.64,1);
								transition-delay: {resActive ? 250 + (playerRes.length + i) * 40 : 0}ms;
							"
						>
							<div class="spot-result-icon-box">
								<span class="material-symbols-outlined">emoji_events</span>
							</div>
							<div class="spot-result-text">
								<span class="spot-result-title">{m.opponent}</span>
								<span class="spot-result-sub">
									{m.home_away === 'HEIM' ? 'Heim' : 'Auswärts'} · {fmtDate(m.date)}
									{#if m.leagues?.name} · {m.leagues.name}{/if}
								</span>
							</div>
							<span class="material-symbols-outlined spot-result-chevron">chevron_right</span>
						</button>
					{/each}
				</div>
			{/if}
		{/if}
	</div>
	{/if}
</div>
{/if}

<!-- ── Editor Sheet (z > spotlight) ──────────────────────── -->
<BottomSheet bind:open={editOpen} title="Vorschläge anpassen" zIndex={600}>
	<div class="ec-hint">
		<span class="material-symbols-outlined ec-hint-icon">info</span>
		<p>Wähle bis zu {MAX_SHORTCUTS} Vorschläge aus.</p>
	</div>
	<div class="ec-list">
		{#each ALL_SHORTCUTS as s}
			{@const isSelected = activeShortcuts.includes(s.id)}
			<button
				class="ec-row"
				class:ec-row--selected={isSelected}
				onclick={() => toggleShortcut(s.id, isSelected)}
				aria-pressed={isSelected}
			>
				<div class="ec-icon-wrap" style="background:{s.grad}">
					<span class="ec-emoji">{s.emoji}</span>
				</div>
				<span class="ec-label">{s.label}</span>
				<div class="ec-check" class:ec-check--on={isSelected}>
					{#if isSelected}
						<span class="material-symbols-outlined">check</span>
					{/if}
				</div>
			</button>
		{/each}
	</div>
</BottomSheet>

<style>
/* ── Overlay ─────────────────────────────────────────────── */
.spot-overlay {
	opacity: 0;
	transition: opacity 250ms ease;
}
.spot-overlay--active { opacity: 1; }

/* ── Search bar ──────────────────────────────────────────── */
.spot-header {
	display: flex;
	align-items: center;
	gap: 12px;
	padding: 0 var(--space-4) var(--space-4);
	flex-shrink: 0;
}

.spot-input-wrap {
	flex: 1;
	display: flex;
	align-items: center;
	gap: 8px;
	background: rgba(255, 255, 255, 0.13);
	border-radius: 14px;
	padding: 0 12px;
	height: 44px;
	border: 1.5px solid rgba(255, 255, 255, 0.1);
	transition: background 200ms ease, border-color 200ms ease, box-shadow 200ms ease;
}
.spot-input-wrap:focus-within {
	background: rgba(255, 255, 255, 0.2);
	border-color: rgba(204, 0, 0, 0.6);
	box-shadow: 0 0 0 3px rgba(204, 0, 0, 0.18);
}

.spot-search-icon {
	font-size: 1.05rem;
	color: rgba(255, 255, 255, 0.5);
	flex-shrink: 0;
	pointer-events: none;
	font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
	transition: color 200ms ease;
}
.spot-input-wrap:focus-within .spot-search-icon {
	color: rgba(255, 100, 100, 0.85);
}

.spot-input {
	flex: 1;
	background: none;
	border: none;
	outline: none;
	font-family: inherit;
	font-size: 1rem;
	font-weight: 500;
	color: #fff;
	caret-color: #ff6666;
	min-width: 0;
	-webkit-appearance: none;
}
.spot-input::placeholder { color: rgba(255, 255, 255, 0.4); }
.spot-input::-webkit-search-cancel-button,
.spot-input::-webkit-search-decoration { display: none; }

.spot-input-clear {
	display: flex;
	align-items: center;
	justify-content: center;
	background: none;
	border: none;
	padding: 0;
	cursor: pointer;
	color: rgba(255, 255, 255, 0.45);
	flex-shrink: 0;
	-webkit-tap-highlight-color: transparent;
	transition: opacity 150ms ease;
}
.spot-input-clear:active { opacity: 0.6; }
.spot-input-clear .material-symbols-outlined {
	font-size: 1rem;
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}

.spot-cancel-btn {
	background: none;
	border: none;
	font-family: inherit;
	font-size: 0.95rem;
	font-weight: 600;
	color: rgba(255, 255, 255, 0.85);
	cursor: pointer;
	white-space: nowrap;
	padding: 4px 0;
	flex-shrink: 0;
	-webkit-tap-highlight-color: transparent;
	transition: opacity 150ms ease;
}
.spot-cancel-btn:active { opacity: 0.6; }

/* ── Siri-Vorschläge header row ──────────────────────────── */
.spot-sugg-section { padding: 0 var(--space-4); }

.spot-sugg-header {
	display: flex;
	align-items: center;
	justify-content: space-between;
	margin-bottom: var(--space-3);
}

.spot-section-label {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255, 255, 255, 0.5);
	margin: 0 0 0 var(--space-1);
}

.spot-edit-btn {
	background: rgba(255, 255, 255, 0.1);
	border: none;
	border-radius: var(--radius-full);
	padding: 4px 12px;
	font-family: inherit;
	font-size: 0.72rem;
	font-weight: 600;
	color: rgba(255, 255, 255, 0.8);
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
	transition: background 150ms ease, opacity 150ms ease;
}
.spot-edit-btn:active {
	background: rgba(255, 255, 255, 0.18);
	opacity: 0.8;
}

/* ── Grid ────────────────────────────────────────────────── */
.spot-grid {
	display: grid;
	grid-template-columns: repeat(4, 1fr);
	gap: var(--space-5) var(--space-2);
}

.spot-app-cell {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 6px;
	background: none;
	border: none;
	padding: 4px 2px;
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
}
.spot-app-cell:active .spot-app-icon { transform: scale(0.88); }

.spot-app-icon {
	width: 56px;
	height: 56px;
	border-radius: 14px;
	display: flex;
	align-items: center;
	justify-content: center;
	box-shadow: 0 4px 16px rgba(0,0,0,0.35), 0 1px 4px rgba(0,0,0,0.2);
	transition: transform 150ms cubic-bezier(0.34, 1.3, 0.64, 1);
}
.spot-app-emoji {
	font-size: 1.75rem;
	line-height: 1;
	display: block;
	filter: drop-shadow(0 1px 3px rgba(0,0,0,0.35));
}
.spot-app-label {
	font-size: 0.68rem;
	font-weight: 600;
	color: rgba(255,255,255,0.9);
	text-align: center;
	line-height: 1.2;
	max-width: 64px;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
	text-shadow: 0 1px 4px rgba(0,0,0,0.4);
}

/* ── Results ─────────────────────────────────────────────── */
.spot-results-section { padding: var(--space-2) var(--space-4) 0; }

.spot-result-label {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255,255,255,0.5);
	margin: 0 0 var(--space-2) var(--space-1);
}

.spot-glass-box {
	background: rgba(255,255,255,0.09);
	backdrop-filter: blur(24px);
	-webkit-backdrop-filter: blur(24px);
	border-radius: 20px;
	border: 1px solid rgba(255,255,255,0.14);
	overflow: hidden;
}

.spot-result-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: 13px var(--space-4);
	background: none;
	border: none;
	width: 100%;
	text-align: left;
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
	border-top: 1px solid rgba(255,255,255,0.07);
	transition: background 150ms ease;
}
.spot-result-row:first-child { border-top: none; }
.spot-result-row:active { background: rgba(255,255,255,0.18); }
.spot-result-row--skel { opacity: 1 !important; transform: none !important; }

.spot-result-avatar {
	width: 36px; height: 36px;
	border-radius: 50%;
	background: rgba(255,255,255,0.1);
	flex-shrink: 0;
	overflow: hidden;
	display: grid;
	place-items: center;
	position: relative;
}
.spot-result-avatar img {
	position: absolute; inset: 0;
	width: 100%; height: 100%;
	object-fit: cover;
}
.spot-result-initial {
	font-family: var(--font-display);
	font-size: 0.85rem;
	font-weight: 700;
	color: rgba(255,255,255,0.7);
	text-transform: uppercase;
}

.spot-result-icon-box {
	width: 36px; height: 36px;
	border-radius: 10px;
	background: rgba(255,255,255,0.12);
	flex-shrink: 0;
	display: flex;
	align-items: center;
	justify-content: center;
}
.spot-result-icon-box .material-symbols-outlined {
	font-size: 1.1rem;
	color: rgba(255,255,255,0.75);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}

.spot-result-text {
	flex: 1; min-width: 0;
	display: flex; flex-direction: column; gap: 1px;
}
.spot-result-title {
	font-size: 0.9rem; font-weight: 600; color: #fff;
	white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.spot-result-sub {
	font-size: 0.72rem; font-weight: 500;
	color: rgba(255,255,255,0.55);
	white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.spot-result-chevron {
	font-size: 1.1rem;
	color: rgba(255,255,255,0.35);
	flex-shrink: 0;
	font-variation-settings: 'FILL' 0, 'wght' 300, 'GRAD' 0, 'opsz' 20;
}

.spot-empty {
	display: flex; flex-direction: column;
	align-items: center; gap: var(--space-3);
	padding: var(--space-10) 0;
	color: rgba(255,255,255,0.45);
}
.spot-empty-icon {
	font-size: 2.5rem;
	font-variation-settings: 'FILL' 0, 'wght' 300, 'GRAD' 0, 'opsz' 48;
}
.spot-empty-text { font-size: 0.9rem; font-weight: 500; text-align: center; }

/* ── Editor configurator (inside BottomSheet) ────────────── */
.ec-hint {
	display: flex;
	align-items: center;
	gap: var(--space-2);
	padding: 0 var(--space-5) var(--space-4);
	color: var(--color-on-surface-variant);
}
.ec-hint-icon {
	font-size: 1rem;
	flex-shrink: 0;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 20;
}
.ec-hint p {
	margin: 0;
	font-size: var(--text-label-sm);
	font-weight: 500;
}

.ec-list {
	background: var(--color-surface-container-lowest);
	border-radius: var(--radius-lg);
	overflow: hidden;
	margin: 0 var(--space-4) var(--space-6);
	box-shadow: var(--shadow-card);
}

.ec-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: 13px var(--space-4);
	background: none;
	border: none;
	border-top: 1px solid var(--color-outline-variant);
	width: 100%;
	text-align: left;
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms ease;
	font: inherit;
}
.ec-row:first-child { border-top: none; }
.ec-row:active { background: var(--color-surface-container-low); }

.ec-icon-wrap {
	width: 40px;
	height: 40px;
	border-radius: 11px;
	display: flex;
	align-items: center;
	justify-content: center;
	flex-shrink: 0;
	box-shadow: 0 2px 8px rgba(0,0,0,0.18);
}
.ec-emoji {
	font-size: 1.35rem;
	line-height: 1;
	filter: drop-shadow(0 1px 2px rgba(0,0,0,0.25));
}

.ec-label {
	flex: 1;
	font-family: var(--font-body);
	font-size: var(--text-body-md);
	font-weight: 500;
	color: var(--color-on-surface);
}

/* iOS-style checkbox */
.ec-check {
	width: 24px;
	height: 24px;
	border-radius: var(--radius-full);
	border: 2px solid var(--color-outline-variant);
	display: flex;
	align-items: center;
	justify-content: center;
	flex-shrink: 0;
	transition: background 200ms ease, border-color 200ms ease;
}
.ec-check--on {
	background: #34C759;
	border-color: #34C759;
}
.ec-check--on .material-symbols-outlined {
	font-size: 0.9rem;
	color: #fff;
	font-variation-settings: 'FILL' 0, 'wght' 600, 'GRAD' 0, 'opsz' 20;
}
</style>
