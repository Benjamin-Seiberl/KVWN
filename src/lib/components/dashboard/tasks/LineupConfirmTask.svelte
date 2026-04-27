<script>
	import { sb } from '$lib/supabase';
	import { goto } from '$app/navigation';
	import { triggerToast } from '$lib/stores/toast.js';
	import { setSubtab } from '$lib/stores/subtab.js';
	import { DAY_SHORT, daysUntil } from '$lib/utils/dates.js';

	/**
	 * @typedef {Object} LineupEntry
	 * @property {string} gamePlanPlayerId
	 * @property {number|null} position
	 * @property {any} match
	 * @property {any[]} teammates
	 */

	let { entry, myName = null, onReload } = $props();

	let busy     = $state(false);
	let done     = $state(null);   // null | 'confirmed' | 'declined'
	let leaving  = $state(false);  // fade-out

	function formatTime(t) { return t ? t.substring(0, 5) : ''; }
	function dateLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return DAY_SHORT[d.getDay()] + ', ' + d.getDate() + '.' + (d.getMonth() + 1) + '.';
	}

	async function notifyCaptainsOnDecline() {
		try {
			const { data: captains } = await sb.from('players')
				.select('id').in('role', ['kapitaen','admin']);
			const ids = (captains ?? []).map(c => c.id);
			if (!ids.length) return;
			await fetch('/api/push/notify', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					player_ids: ids,
					title: `Absage: ${myName ?? 'Spieler'}`,
					body:  `${entry.match.leagues?.name ?? ''} vs. ${entry.match.opponent} – Ersatz wählen`,
					url:   '/profil#admin-inbox-aufstellungen',
					pref_key: 'lineup_decline',
				}),
			});
		} catch {}
	}

	async function respond(confirmed) {
		if (busy || done) return;
		busy = true;

		const { error } = await sb.from('game_plan_players')
			.update({ confirmed })
			.eq('id', entry.gamePlanPlayerId);

		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}

		if (confirmed === false) {
			notifyCaptainsOnDecline();
		}

		done = confirmed ? 'confirmed' : 'declined';
		busy = false;

		// Bei Zusage + Auswärts: Card kurzzeitig stehen lassen, damit der Carpool-CTA sichtbar wird.
		// Sonst: 1.4 s Success-State → Fade-Out → Reload.
		const holdLonger = confirmed && isAway;
		setTimeout(() => {
			leaving = true;
			setTimeout(() => onReload?.(), 280);
		}, holdLonger ? 4200 : 1400);
	}

	function openCarpool() {
		// Push subtab auf "spiele" damit /spielbetrieb direkt SpieleTab rendert,
		// danach Deep-Link mit ?carpool=<id>.
		setSubtab('/spielbetrieb', 'spiele');
		goto(`/spielbetrieb?carpool=${entry.match.id}`);
	}

	let days = $derived(daysUntil(entry.match.date));
	let isAway = $derived(!!entry.match?.home_away && entry.match.home_away !== 'HEIM');
</script>

<div class="lct" class:lct--leaving={leaving} class:lct--done={!!done}>
	<div class="lct-head">
		<span class="lct-icon material-symbols-outlined">sports_score</span>
		<div class="lct-head-text">
			<span class="lct-title">Aufstellung bestätigen</span>
			<span class="lct-sub">
				{entry.match.leagues?.name ?? ''} · vs. {entry.match.opponent}
			</span>
		</div>
		<span class="lct-days">
			{days === 0 ? 'heute' : days === 1 ? 'morgen' : 'in ' + days + ' T'}
		</span>
	</div>

	<div class="lct-meta">
		<span class="material-symbols-outlined lct-meta-icon">schedule</span>
		{dateLabel(entry.match)} · {formatTime(entry.match.time)} Uhr
		{#if entry.position} · Pos. {entry.position}{/if}
	</div>

	{#if done === 'confirmed'}
		<div class="lct-confirmed-row">
			<div class="lct-result lct-result--ok">
				<span class="material-symbols-outlined">check_circle</span>
				Bestätigt
			</div>
			{#if isAway}
				<button
					class="mw-btn mw-btn--soft lct-carpool-btn"
					onclick={openCarpool}
					aria-label="Fahrt organisieren"
				>
					<span class="material-symbols-outlined">directions_car</span>
					Fahrt organisieren
				</button>
			{/if}
		</div>
	{:else if done === 'declined'}
		<div class="lct-result lct-result--off">
			<span class="material-symbols-outlined">cancel</span>
			Abgesagt
		</div>
	{:else}
		<div class="lct-actions">
			<button
				class="mw-btn mw-btn--ghost"
				onclick={() => respond(false)}
				disabled={busy}
				aria-label="Absagen"
			>
				<span class="material-symbols-outlined">close</span>
				Absage
			</button>
			<button
				class="mw-btn mw-btn--primary"
				onclick={() => respond(true)}
				disabled={busy}
				aria-label="Zusagen"
			>
				<span class="material-symbols-outlined">check</span>
				Zusage
			</button>
		</div>
	{/if}
</div>

<style>
	.lct {
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-left: 4px solid var(--color-primary);
		border-radius: var(--radius-lg);
		padding: var(--space-3) var(--space-4);
		box-shadow: var(--shadow-card);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		transition: opacity 260ms ease, transform 260ms ease, max-height 320ms ease, padding 260ms ease, margin 260ms ease;
		max-height: 320px;
		overflow: hidden;
	}
	.lct--done {
		border-left-color: var(--color-success);
	}
	.lct--leaving {
		opacity: 0;
		transform: translateY(-6px);
		max-height: 0;
		padding-top: 0;
		padding-bottom: 0;
		margin-bottom: calc(var(--space-3) * -1);
	}

	.lct-head {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.lct-icon {
		font-size: 1.2rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
		flex-shrink: 0;
	}
	.lct-head-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.lct-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.lct-sub {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.lct-days {
		flex-shrink: 0;
		background: var(--color-primary);
		color: #fff;
		border-radius: var(--radius-full);
		padding: 2px 10px;
		font-family: var(--font-display);
		font-size: 0.7rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.lct-meta {
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.lct-meta-icon {
		font-size: 0.95rem;
	}

	.lct-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}
	.lct-actions :global(.mw-btn) {
		flex: 1;
	}

	.lct-result {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		align-self: flex-start;
		padding: 6px 12px;
		border-radius: var(--radius-full);
		font-family: var(--font-display);
		font-size: 0.78rem;
		font-weight: 800;
		margin-top: var(--space-1);
	}
	.lct-result .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lct-result--ok {
		background: rgba(45, 122, 58, 0.12);
		color: var(--color-success);
	}
	.lct-result--off {
		background: rgba(204, 0, 0, 0.1);
		color: var(--color-primary);
	}

	.lct-confirmed-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		flex-wrap: wrap;
		margin-top: var(--space-1);
	}
	.lct-confirmed-row .lct-result {
		margin-top: 0;
	}
	.lct-carpool-btn {
		margin-left: auto;
	}
</style>
