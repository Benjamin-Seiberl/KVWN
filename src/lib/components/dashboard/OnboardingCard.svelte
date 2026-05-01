<script>
	import { sb } from '$lib/supabase';
	import { goto } from '$app/navigation';
	import { playerId } from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';

	let me            = $state(null);
	let scoresCount   = $state(0);
	let dismissed     = $state(false);
	let loading       = $state(true);
	let busy          = $state(false);
	let leaving       = $state(false);

	async function load(pid) {
		loading = true;
		try {
			const [meRes, scRes, dmRes] = await Promise.all([
				sb.from('players')
					.select('id, phone, address, shirt_size, spielerpass_nr')
					.eq('id', pid)
					.maybeSingle(),
				sb.from('game_plan_players')
					.select('id', { count: 'exact', head: true })
					.eq('player_id', pid)
					.eq('played', true)
					.not('score', 'is', null),
				sb.from('dashboard_task_dismissals')
					.select('task_ref_id')
					.eq('player_id', pid)
					.eq('task_kind', 'onboarding_welcome')
					.maybeSingle(),
			]);
			if (meRes.error) { triggerToast('Fehler: ' + meRes.error.message); return; }
			if (scRes.error) { triggerToast('Fehler: ' + scRes.error.message); return; }
			if (dmRes.error) { triggerToast('Fehler: ' + dmRes.error.message); return; }

			me          = meRes.data ?? null;
			scoresCount = scRes.count ?? 0;
			dismissed   = !!dmRes.data;
		} finally {
			loading = false;
		}
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			load($playerId);
		}
	});

	const missingFields = $derived.by(() => {
		if (!me) return [];
		const m = [];
		if (!me.phone)          m.push('Telefon');
		if (!me.address)        m.push('Adresse');
		if (!me.shirt_size)     m.push('Trikotgröße');
		if (!me.spielerpass_nr) m.push('Spielerpass-Nr.');
		return m;
	});

	const showCard = $derived(
		!loading && !dismissed && !!me && scoresCount === 0 && missingFields.length > 0
	);

	const missingPreview = $derived.by(() => {
		if (!missingFields.length) return '';
		const shown = missingFields.slice(0, 3).join(', ');
		const rest  = missingFields.length - 3;
		return rest > 0 ? `${shown} +${rest} weitere` : shown;
	});

	function goToProfile() {
		goto('/profil');
	}

	async function dismiss() {
		if (busy || !$playerId) return;
		busy = true;
		// task_ref_id muss UUID sein — wir kennzeichnen die Karte über task_kind und nehmen
		// die Player-ID als Ref (eine Karte pro Spieler).
		const { error } = await sb.from('dashboard_task_dismissals').insert({
			player_id:   $playerId,
			task_kind:   'onboarding_welcome',
			task_ref_id: $playerId,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			busy = false;
			return;
		}
		busy = false;
		leaving = true;
		setTimeout(() => { dismissed = true; }, 280);
	}
</script>

{#if showCard}
	<div class="onb-wrap" class:onb-wrap--leaving={leaving}>
		<div class="onb-card">
			<button
				class="onb-dismiss"
				type="button"
				onclick={dismiss}
				disabled={busy}
				aria-label="Hinweis ausblenden"
			>
				<span class="material-symbols-outlined">close</span>
			</button>

			<div class="onb-head">
				<span class="material-symbols-outlined onb-icon">waving_hand</span>
				<span class="onb-eyebrow">Willkommen bei KVWN</span>
			</div>

			<h3 class="onb-title">Profil vervollständigen</h3>
			<p class="onb-text">
				Vervollständige dein Profil, damit der Kapitän alles für dich vorbereiten kann.
			</p>

			<div class="onb-missing">
				<span class="material-symbols-outlined">edit_note</span>
				<span>
					{missingFields.length} {missingFields.length === 1 ? 'Feld' : 'Felder'} offen: {missingPreview}
				</span>
			</div>

			<button type="button" class="onb-cta" onclick={goToProfile}>
				Zum Profil
				<span class="material-symbols-outlined">arrow_forward</span>
			</button>
		</div>
	</div>
{/if}

<style>
	.onb-wrap {
		padding: 0 var(--space-5);
		transition: opacity 260ms ease, transform 260ms ease, max-height 320ms ease;
		max-height: 360px;
		overflow: hidden;
	}
	.onb-wrap--leaving {
		opacity: 0;
		transform: translateY(-6px);
		max-height: 0;
	}

	.onb-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		width: 100%;
		text-align: left;
		padding: var(--space-4) var(--space-5);
		padding-top: calc(var(--space-4) + var(--space-1));
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		border-left: 4px solid var(--color-secondary);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
	}

	.onb-dismiss {
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
	.onb-dismiss:active { opacity: 0.6; }
	.onb-dismiss .material-symbols-outlined { font-size: 1.1rem; }

	.onb-head {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding-right: 32px;
	}
	.onb-icon {
		font-size: 1.2rem;
		color: var(--color-secondary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.onb-eyebrow {
		font-family: var(--font-display);
		font-size: 0.7rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		color: var(--color-secondary);
	}

	.onb-title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 800;
		color: var(--color-on-surface);
	}
	.onb-text {
		margin: 0;
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		line-height: 1.4;
	}

	.onb-missing {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
		margin-top: var(--space-1);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container);
		border-radius: var(--radius-md);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.onb-missing .material-symbols-outlined {
		font-size: 1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	.onb-cta {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		align-self: flex-start;
		margin-top: var(--space-2);
		padding: var(--space-2) var(--space-3);
		background: var(--color-primary);
		color: var(--color-on-primary);
		border: none;
		border-radius: var(--radius-full);
		font-family: var(--font-display);
		font-size: var(--text-label-sm);
		font-weight: 800;
		letter-spacing: 0.04em;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: transform 100ms ease;
	}
	.onb-cta:active { transform: scale(0.97); }
	.onb-cta:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.onb-cta .material-symbols-outlined {
		font-size: 1rem;
	}
</style>
