<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false), onCreated } = $props();

	const MAX_BODY = 500;

	let title    = $state('');
	let body     = $state('');
	let pinned   = $state(false);
	let sendPush = $state(false);
	let saving   = $state(false);

	const titleTrim    = $derived(title.trim());
	const bodyTrim     = $derived(body.trim());
	const bodyOverflow = $derived(bodyTrim.length > MAX_BODY);
	const canSubmit    = $derived(!!titleTrim && !!bodyTrim && !bodyOverflow && !saving);

	function resetForm() {
		title    = '';
		body     = '';
		pinned   = false;
		sendPush = false;
	}

	$effect(() => {
		if (!open) resetForm();
	});

	async function notifyAllPlayers(t, b) {
		try {
			const { data: players, error } = await sb
				.from('players')
				.select('id')
				.eq('active', true);
			if (error || !players?.length) return;
			const ids = players.map(p => p.id);
			const truncated = b.length > 80 ? b.slice(0, 79) + '…' : b;
			await fetch('/api/push/notify', {
				method:  'POST',
				headers: { 'Content-Type': 'application/json' },
				body:    JSON.stringify({
					player_ids: ids,
					title:      `Neuigkeit: ${t}`,
					body:       truncated,
					url:        '/',
					pref_key:   'news',
				}),
			});
		} catch {}
	}

	async function save() {
		if (!canSubmit) return;
		saving = true;
		const { error } = await sb.from('announcements').insert({
			title: titleTrim,
			body:  bodyTrim,
			pinned,
		});
		if (error) {
			triggerToast('Fehler: ' + error.message);
			saving = false;
			return;
		}
		if (sendPush) {
			await notifyAllPlayers(titleTrim, bodyTrim);
			triggerToast('News veröffentlicht – Push gesendet');
		} else {
			triggerToast('News veröffentlicht');
		}
		saving   = false;
		open     = false;
		onCreated?.();
	}
</script>

<BottomSheet bind:open title="News verfassen">
	<div class="news-form">
		<label class="mw-field">
			<span class="mw-field__label">Titel</span>
			<input
				type="text"
				bind:value={title}
				placeholder="z.B. Neue Bahnordnung"
				maxlength="80"
				required
			/>
		</label>

		<label class="mw-field">
			<span class="mw-field__label">Text</span>
			<textarea
				bind:value={body}
				rows="6"
				placeholder="Was möchtest du dem Team mitteilen?"
				required
			></textarea>
			<span class="news-counter" class:news-counter--over={bodyOverflow}>
				{bodyTrim.length} / {MAX_BODY}
			</span>
		</label>

		<div class="news-toggles">
			<label class="news-toggle">
				<span class="news-toggle__icon material-symbols-outlined">keep</span>
				<span class="news-toggle__body">
					<span class="news-toggle__title">Anheften</span>
					<span class="news-toggle__sub">Beitrag bleibt oben in den Neuigkeiten</span>
				</span>
				<input type="checkbox" bind:checked={pinned} />
			</label>

			<label class="news-toggle">
				<span class="news-toggle__icon material-symbols-outlined">notifications</span>
				<span class="news-toggle__body">
					<span class="news-toggle__title">Push senden</span>
					<span class="news-toggle__sub">Alle aktiven Spieler benachrichtigen</span>
				</span>
				<input type="checkbox" bind:checked={sendPush} />
			</label>
		</div>

		<div class="news-actions">
			<button
				type="button"
				class="mw-btn mw-btn--ghost"
				onclick={() => open = false}
				disabled={saving}
			>
				Abbrechen
			</button>
			<button
				type="button"
				class="mw-btn mw-btn--primary mw-btn--wide"
				onclick={save}
				disabled={!canSubmit}
			>
				<span class="material-symbols-outlined">send</span>
				{saving ? 'Speichert…' : 'Veröffentlichen'}
			</button>
		</div>
	</div>
</BottomSheet>

<style>
	.news-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		padding: var(--space-2) 0 var(--space-6);
	}

	.news-counter {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		text-align: right;
	}
	.news-counter--over { color: var(--color-primary); font-weight: 700; }

	.news-toggles {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.news-toggle {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.news-toggle__icon {
		font-size: 1.2rem;
		color: var(--color-primary);
		flex-shrink: 0;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}
	.news-toggle__body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.news-toggle__title {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-label-md);
		color: var(--color-on-surface);
	}
	.news-toggle__sub {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.news-toggle input[type="checkbox"] {
		width: 22px;
		height: 22px;
		accent-color: var(--color-primary);
		flex-shrink: 0;
		cursor: pointer;
	}

	.news-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}
</style>
