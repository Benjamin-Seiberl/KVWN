<script>
	import { onMount }      from 'svelte';
	import { page }         from '$app/stores';
	import { sb }           from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth.js';
	import { setSubtab }    from '$lib/stores/subtab.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr } from '$lib/utils/dates.js';
	import { imgPath, shortName } from '$lib/utils/players.js';

	let player     = $state(null);
	let scores     = $state([]);
	let nextMatch  = $state(null);
	let loading    = $state(true);

	$effect(() => {
		if ($playerId) loadData($playerId);
	});

	async function loadData(pid) {
		loading = true;
		try {
			const today = toDateStr(new Date());
			const [
				{ data: p,  error: e1 },
				{ data: sc, error: e2 },
				{ data: nm, error: e3 },
			] = await Promise.all([
				sb.from('players').select('id, name, avatar_url, photo, email, role').eq('id', pid).maybeSingle(),
				sb.from('game_plan_players')
					.select('score, cal_week, played')
					.eq('player_id', pid)
					.eq('played', true)
					.not('score', 'is', null)
					.order('cal_week', { ascending: false })
					.limit(20),
				sb.from('matches')
					.select('id, date, time, home_away, opponent, location')
					.gte('date', today)
					.neq('opponent', 'spielfrei')
					.order('date', { ascending: true })
					.limit(1)
					.maybeSingle(),
			]);
			if (e1) { triggerToast('Fehler: ' + e1.message); }
			if (e2) { triggerToast('Fehler: ' + e2.message); }
			if (e3) { triggerToast('Fehler: ' + e3.message); }
			player    = p;
			scores    = (sc ?? []).filter(s => s.played && s.score != null);
			nextMatch = nm;
		} finally {
			loading = false;
		}
	}

	const avg = $derived.by(() => {
		if (!scores.length) return null;
		return Math.round(scores.reduce((s, r) => s + r.score, 0) / scores.length);
	});

	const last5 = $derived(scores.slice(0, 5).map(s => s.score));

	function go(key) {
		setSubtab($page.url.pathname, key);
	}

	function initials(name) {
		return (name ?? '?').split(' ').map(w => w[0]).join('').slice(0,2).toUpperCase();
	}
</script>

<div class="pueb-page">
	<!-- Player header card -->
	{#if loading}
		<div class="pueb-header-skeleton"></div>
	{:else if player}
		<div class="pueb-player-card">
			<div class="pueb-card-hero"></div>
			<div class="pueb-avatar-ring">
				<div class="pueb-avatar">
					{#if imgPath(player)}
						<img src={imgPath(player)} alt={player.name} />
					{:else}
						{initials(player.name)}
					{/if}
				</div>
			</div>
			<div class="pueb-identity">
				<span class="pueb-name">{player.name ?? '—'}</span>
				{#if $playerRole === 'kapitaen'}
					<span class="pueb-role-badge">Kapitän</span>
				{/if}
			</div>
		</div>
	{/if}

	<!-- Nav hub -->
	<div class="pueb-hub-grid">
		{#each [
			{ key: 'meine-daten',   label: 'Meine Daten',   icon: 'person',        desc: 'Profil & Statistiken'  },
			{ key: 'einstellungen', label: 'Einstellungen',  icon: 'settings',      desc: 'Benachrichtigungen'    },
		] as h}
			<button class="pueb-hub-tile" onclick={() => go(h.key)}>
				<span class="material-symbols-outlined pueb-hub-icon">{h.icon}</span>
				<div class="pueb-hub-text">
					<span class="pueb-hub-label">{h.label}</span>
					<span class="pueb-hub-desc">{h.desc}</span>
				</div>
				<span class="material-symbols-outlined pueb-hub-arrow">chevron_right</span>
			</button>
		{/each}
		{#if $playerRole === 'kapitaen'}
			<button class="pueb-hub-tile pueb-hub-tile--admin" onclick={() => go('admin')}>
				<span class="material-symbols-outlined pueb-hub-icon">shield_person</span>
				<div class="pueb-hub-text">
					<span class="pueb-hub-label">Kapitän</span>
					<span class="pueb-hub-desc">Admin-Panel</span>
				</div>
				<span class="material-symbols-outlined pueb-hub-arrow">chevron_right</span>
			</button>
		{/if}
	</div>

	<!-- Quick stats -->
	{#if loading || scores.length > 0}
		<div class="pueb-section">
			<div class="pueb-sec-head">
				<span class="material-symbols-outlined pueb-sec-icon">bar_chart</span>
				<span class="pueb-sec-title">Meine Saison</span>
			</div>
			{#if loading}
				<div class="pueb-skeleton"></div>
			{:else}
				<div class="pueb-stats-row">
					<div class="pueb-stat">
						<span class="pueb-stat-value">{avg ?? '—'}</span>
						<span class="pueb-stat-label">Schnitt</span>
					</div>
					<div class="pueb-stat-sep"></div>
					<div class="pueb-stat">
						<span class="pueb-stat-value">{scores.length}</span>
						<span class="pueb-stat-label">Spiele</span>
					</div>
					<div class="pueb-stat-sep"></div>
					<div class="pueb-stat">
						<div class="pueb-form-dots">
							{#each last5 as sc, i}
								{@const isMax = sc === Math.max(...last5)}
								{@const isMin = sc === Math.min(...last5)}
								<span class="pueb-form-dot" class:pueb-form-dot--hi={isMax && !isMin} class:pueb-form-dot--lo={isMin && !isMax}>
									{sc}
								</span>
							{/each}
						</div>
						<span class="pueb-stat-label">Letzte 5</span>
					</div>
				</div>
			{/if}
		</div>
	{/if}

	<!-- Nächstes Spiel -->
	{#if loading || nextMatch}
		<div class="pueb-section">
			<div class="pueb-sec-head">
				<span class="material-symbols-outlined pueb-sec-icon">emoji_events</span>
				<span class="pueb-sec-title">Nächstes Spiel</span>
			</div>
			{#if loading}
				<div class="pueb-skeleton"></div>
			{:else if nextMatch}
				<div class="pueb-match-row">
					<div class="pueb-match-date">
						<span class="pueb-match-date-str">{fmtDate(nextMatch.date)}</span>
						{#if nextMatch.time}<span class="pueb-match-time">{fmtTime(nextMatch.time)}</span>{/if}
					</div>
					<div class="pueb-match-info">
						<span class="pueb-match-opp">{nextMatch.opponent}</span>
						<span class="pueb-match-badge" class:pueb-match-badge--heim={nextMatch.home_away === 'heim'}>
							{nextMatch.home_away === 'heim' ? 'Heim' : 'Auswärts'}
						</span>
					</div>
				</div>
			{/if}
		</div>
	{/if}
</div>

<style>
.pueb-page {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
	padding: var(--space-5);
}

/* Player card */
.pueb-header-skeleton {
	height: 140px;
	background: var(--color-surface-container-low);
	border-radius: 20px;
	animation: ppulse 1.4s ease-in-out infinite;
}

@keyframes ppulse {
	0%, 100% { opacity: 1; }
	50%       { opacity: 0.5; }
}

.pueb-player-card {
	border-radius: 20px;
	overflow: hidden;
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	display: flex;
	flex-direction: column;
	align-items: center;
	padding-bottom: var(--space-4);
	position: relative;
}

.pueb-card-hero {
	width: 100%;
	height: 72px;
	background: linear-gradient(160deg, #1a0000 0%, #850000 100%);
}

.pueb-avatar-ring {
	position: relative;
	margin-top: -36px;
	width: 80px;
	height: 80px;
	border-radius: 50%;
	padding: 3px;
	background: linear-gradient(135deg, var(--color-secondary), #a07c20);
	box-shadow: 0 4px 20px rgba(0,0,0,0.3);
	z-index: 1;
}

.pueb-avatar {
	width: 100%;
	height: 100%;
	border-radius: 50%;
	overflow: hidden;
	background: var(--color-surface-container);
	display: grid;
	place-items: center;
	font-family: var(--font-display);
	font-size: 1.8rem;
	font-weight: 900;
	color: var(--color-primary);
	border: 3px solid var(--color-surface-container-lowest);
}

.pueb-avatar img { width: 100%; height: 100%; object-fit: cover; }

.pueb-identity {
	margin-top: var(--space-3);
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: var(--space-2);
}

.pueb-name {
	font-family: var(--font-display);
	font-weight: 900;
	font-size: 1.15rem;
	color: var(--color-on-surface);
}

.pueb-role-badge {
	font-size: 0.72rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	padding: 3px 10px;
	border-radius: 999px;
	background: rgba(204,0,0,0.12);
	color: var(--color-primary);
}

/* Hub */
.pueb-hub-grid {
	display: flex;
	flex-direction: column;
	gap: var(--space-2);
}

.pueb-hub-tile {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) var(--space-4);
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 14px;
	cursor: pointer;
	text-align: left;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms;
}

.pueb-hub-tile:active { background: var(--color-surface-container-low); }

.pueb-hub-tile--admin {
	border-color: rgba(204,0,0,0.2);
	background: rgba(204,0,0,0.04);
}

.pueb-hub-icon {
	font-size: 1.4rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	flex-shrink: 0;
}

.pueb-hub-text {
	flex: 1;
	display: flex;
	flex-direction: column;
	gap: 1px;
}

.pueb-hub-label {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.9rem;
	color: var(--color-on-surface);
}

.pueb-hub-desc {
	font-size: 0.75rem;
	color: var(--color-on-surface-variant);
}

.pueb-hub-arrow {
	color: var(--color-on-surface-variant);
	font-size: 1.1rem;
	flex-shrink: 0;
}

/* Sections */
.pueb-section {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.pueb-sec-head {
	display: flex;
	align-items: center;
	gap: var(--space-2);
}

.pueb-sec-icon {
	font-size: 1rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.pueb-sec-title {
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.875rem;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-primary);
}

.pueb-skeleton {
	height: 48px;
	background: var(--color-surface-container-low);
	border-radius: 10px;
	animation: ppulse 1.4s ease-in-out infinite;
}

/* Stats row */
.pueb-stats-row {
	display: flex;
	align-items: stretch;
	gap: 0;
}

.pueb-stat {
	flex: 1;
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 3px;
}

.pueb-stat-sep {
	width: 1px;
	background: var(--color-surface-container);
	margin: 0 var(--space-2);
	align-self: stretch;
}

.pueb-stat-value {
	font-family: var(--font-display);
	font-size: 1.6rem;
	font-weight: 900;
	color: var(--color-on-surface);
	line-height: 1;
}

.pueb-stat-label {
	font-size: 0.65rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: var(--color-on-surface-variant);
}

.pueb-form-dots {
	display: flex;
	gap: 3px;
	align-items: baseline;
}

.pueb-form-dot {
	font-family: var(--font-display);
	font-size: 0.75rem;
	font-weight: 800;
	color: var(--color-on-surface-variant);
	padding: 1px 3px;
	border-radius: 4px;
}

.pueb-form-dot--hi { color: #16a34a; }
.pueb-form-dot--lo { color: var(--color-primary); }

/* Match */
.pueb-match-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
}

.pueb-match-date {
	display: flex;
	flex-direction: column;
	align-items: center;
	min-width: 72px;
	padding: 4px 8px;
	border-radius: 8px;
	background: var(--color-surface-container-low);
	flex-shrink: 0;
}

.pueb-match-date-str {
	font-family: var(--font-display);
	font-size: 0.72rem;
	font-weight: 800;
	color: var(--color-on-surface);
}

.pueb-match-time {
	font-size: 0.68rem;
	font-weight: 700;
	color: var(--color-on-surface-variant);
}

.pueb-match-info {
	flex: 1;
	min-width: 0;
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.pueb-match-opp {
	font-weight: 700;
	font-size: 0.88rem;
	color: var(--color-on-surface);
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.pueb-match-badge {
	font-size: 0.68rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	padding: 1px 7px;
	border-radius: 999px;
	background: var(--color-surface-container);
	color: var(--color-on-surface-variant);
	width: fit-content;
}

.pueb-match-badge--heim {
	background: rgba(204,0,0,0.12);
	color: var(--color-primary);
}
</style>
