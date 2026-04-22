<script>
	import { sb }             from '$lib/supabase';
	import { triggerToast }   from '$lib/stores/toast.js';
	import ToggleSwitch       from '$lib/components/ui/ToggleSwitch.svelte';

	/**
	 * Props:
	 *   me: players row (needs id, consent_photo, consent_liga_data, consent_whatsapp, consent_accepted_at).
	 *   onUpdated: (patch) => void — lifts saved fields back into orchestrator `me`.
	 */
	let { me, onUpdated } = $props();

	const CONSENTS = [
		{ key: 'consent_photo',      label: 'Foto-Veröffentlichung', sub: 'Fotos von mir dürfen auf Vereins-Website & Social Media veröffentlicht werden' },
		{ key: 'consent_liga_data',  label: 'Datenweitergabe Liga',  sub: 'Name & Spielerpass-Nr. dürfen an den Landesverband übermittelt werden' },
		{ key: 'consent_whatsapp',   label: 'WhatsApp-Gruppe',       sub: 'Ich möchte in der Vereins-WhatsApp-Gruppe sein' },
	];

	async function updateConsent(key, value) {
		const patch = { [key]: !!value };
		if (!me?.consent_accepted_at) {
			patch.consent_accepted_at = new Date().toISOString();
		}
		const { error } = await sb.from('players').update(patch).eq('id', me.id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		onUpdated?.(patch);
	}
</script>

<section class="cons-card">
	<div class="cons-head">
		<h3 class="section-title">
			<span class="material-symbols-outlined">privacy_tip</span>
			Einwilligungen
		</h3>
	</div>

	<p class="cons-intro">
		Deine Datenschutz-Einstellungen. Änderungen werden sofort gespeichert.
	</p>

	<div class="cons-rows">
		{#each CONSENTS as c (c.key)}
			<label class="toggle">
				<div class="toggle-text">
					<span class="toggle-label">{c.label}</span>
					<span class="toggle-sub">{c.sub}</span>
				</div>
				<ToggleSwitch
					checked={me?.[c.key] ?? false}
					onchange={(e) => updateConsent(c.key, e.target.checked)}
					ariaLabel={c.label}
				/>
			</label>
		{/each}
	</div>
</section>

<style>
	.cons-card {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.cons-head { display: flex; justify-content: space-between; align-items: center; }

	.cons-intro {
		margin: 0;
		font-size: 0.78rem; color: var(--color-on-surface-variant);
	}

	.cons-rows { display: flex; flex-direction: column; }

	.toggle {
		display: flex; align-items: center; justify-content: space-between; gap: var(--space-3);
		padding: var(--space-3) 0;
		border-top: 1px solid var(--color-surface-container);
		cursor: pointer;
	}
	.toggle:first-child { border-top: none; }

	.toggle-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
	.toggle-label {
		font-size: 0.92rem; font-weight: 700; color: var(--color-on-surface);
	}
	.toggle-sub {
		font-size: 0.76rem; color: var(--color-on-surface-variant); line-height: 1.3;
	}
</style>
