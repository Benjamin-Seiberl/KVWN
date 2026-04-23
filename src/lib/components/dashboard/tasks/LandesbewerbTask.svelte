<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime } from '$lib/utils/dates.js';
	import { BEWERB_LABEL } from '$lib/constants/competitions.js';

	let { lb, onReload } = $props();

	let busy    = $state(false);
	let done    = $state(null);   // null | 'registered' | 'unregistered' | 'dismissed'
	let leaving = $state(false);

	function fmtDeadline(ts) {
		return new Date(ts).toLocaleString('de-AT', { dateStyle: 'short', timeStyle: 'short' });
	}
	function hoursLeft(ts) {
		return Math.max(0, Math.floor((new Date(ts).getTime() - Date.now()) / 3_600_000));
	}

	async function register() {
		if (busy || done || !$playerId) return;
		busy = true;

		const { error } = await sb.from('landesbewerb_registrations').insert({
			landesbewerb_id: lb.id,
			player_id:       $playerId,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}

		done = 'registered';
		busy = false;

		setTimeout(() => {
			leaving = true;
			setTimeout(() => onReload?.(), 280);
		}, 1400);
	}

	async function unregister() {
		if (busy || done || !$playerId) return;
		busy = true;

		const { error } = await sb.from('landesbewerb_registrations')
			.delete()
			.eq('landesbewerb_id', lb.id)
			.eq('player_id', $playerId);
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}

		done = 'unregistered';
		busy = false;

		setTimeout(() => {
			leaving = true;
			setTimeout(() => onReload?.(), 280);
		}, 1400);
	}

	async function dismiss() {
		if (busy || done || !$playerId) return;
		busy = true;

		const { error } = await sb.from('dashboard_task_dismissals').insert({
			player_id:   $playerId,
			task_kind:   'landesbewerb',
			task_ref_id: lb.id,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}

		done = 'dismissed';
		busy = false;
		setTimeout(() => {
			leaving = true;
			setTimeout(() => onReload?.(), 280);
		}, 200);
	}

	let left   = $derived(hoursLeft(lb.registration_deadline));
	let urgent = $derived(left < 24);
</script>

<div class="lbt" class:lbt--leaving={leaving} class:lbt--urgent={urgent} class:lbt--done={!!done}>
	<button
		class="lbt-dismiss"
		onclick={dismiss}
		disabled={busy || !!done}
		aria-label="Aufgabe ausblenden"
	>
		<span class="material-symbols-outlined">close</span>
	</button>

	<div class="lbt-head">
		<div class="lbt-trophy">
			<span class="material-symbols-outlined">workspace_premium</span>
		</div>
		<div class="lbt-head-text">
			<span class="lbt-title">Landesbewerb-Anmeldung</span>
			<span class="lbt-sub">
				{lb.title ?? (BEWERB_LABEL[lb.typ] ?? 'Landesbewerb')}
			</span>
		</div>
	</div>

	<div class="lbt-meta">
		<span class="material-symbols-outlined lbt-meta-icon">event</span>
		{fmtDate(lb.date)}{#if lb.time} · {fmtTime(lb.time)} Uhr{/if}
		{#if lb.location} · {lb.location}{/if}
	</div>

	<div class="lbt-deadline" class:lbt-deadline--urgent={urgent}>
		<span class="material-symbols-outlined">alarm</span>
		bis {fmtDeadline(lb.registration_deadline)}
		{#if urgent} · nur mehr {left} h{/if}
	</div>

	{#if done === 'registered'}
		<div class="lbt-result lbt-result--ok">
			<span class="material-symbols-outlined">check_circle</span>
			Angemeldet
		</div>
	{:else if done === 'unregistered'}
		<div class="lbt-result lbt-result--off">
			<span class="material-symbols-outlined">cancel</span>
			Abgemeldet
		</div>
	{:else if done !== 'dismissed'}
		<div class="lbt-actions">
			<button
				class="mw-btn mw-btn--ghost"
				onclick={unregister}
				disabled={busy}
				aria-label="Abmelden"
			>
				<span class="material-symbols-outlined">close</span>
				Abmelden
			</button>
			<button
				class="mw-btn mw-btn--primary"
				onclick={register}
				disabled={busy}
				aria-label="Anmelden"
			>
				<span class="material-symbols-outlined">check</span>
				Anmelden
			</button>
		</div>
	{/if}
</div>

<style>
	.lbt {
		position: relative;
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-left: 4px solid var(--color-secondary, #D4AF37);
		border-radius: var(--radius-lg);
		padding: var(--space-3) var(--space-4);
		box-shadow: var(--shadow-card);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		transition: opacity 260ms ease, transform 260ms ease, max-height 320ms ease, padding 260ms ease, margin 260ms ease;
		max-height: 280px;
		overflow: hidden;
	}
	.lbt--urgent {
		border-left-color: var(--color-primary);
		background: linear-gradient(135deg, rgba(204,0,0,0.04), var(--color-surface-container-lowest));
	}
	.lbt--done {
		border-left-color: var(--color-success);
	}
	.lbt--leaving {
		opacity: 0;
		transform: translateY(-6px);
		max-height: 0;
		padding-top: 0;
		padding-bottom: 0;
		margin-bottom: calc(var(--space-3) * -1);
	}

	.lbt-dismiss {
		position: absolute;
		top: var(--space-2);
		right: var(--space-2);
		width: 28px;
		height: 28px;
		border-radius: var(--radius-full);
		border: none;
		background: transparent;
		color: var(--color-on-surface-variant);
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.lbt-dismiss:active { opacity: 0.6; }
	.lbt-dismiss .material-symbols-outlined { font-size: 1.1rem; }

	.lbt-head {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding-right: 32px; /* Platz für Dismiss-Button */
	}
	.lbt-trophy {
		width: 36px;
		height: 36px;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-md);
		background: linear-gradient(135deg, color-mix(in srgb, var(--color-secondary) 75%, white), var(--color-secondary));
		color: color-mix(in srgb, var(--color-secondary) 30%, black);
	}
	.lbt-trophy .material-symbols-outlined {
		font-size: 1.2rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lbt-head-text {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.lbt-title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.lbt-sub {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.lbt-meta {
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.lbt-meta-icon { font-size: 0.95rem; }

	.lbt-deadline {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		font-size: 0.73rem;
		font-weight: 600;
		color: var(--color-on-surface-variant);
	}
	.lbt-deadline .material-symbols-outlined { font-size: 0.85rem; }
	.lbt-deadline--urgent { color: var(--color-primary); }

	.lbt-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}
	.lbt-actions :global(.mw-btn) { flex: 1; }

	.lbt-result {
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
	.lbt-result .material-symbols-outlined {
		font-size: 1rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.lbt-result--ok {
		background: rgba(45, 122, 58, 0.12);
		color: var(--color-success);
	}
	.lbt-result--off {
		background: rgba(204, 0, 0, 0.1);
		color: var(--color-primary);
	}
</style>
