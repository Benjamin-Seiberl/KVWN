<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import BottomSheet from '../BottomSheet.svelte';
	import { onMount } from 'svelte';

	let { open = $bindable(false) } = $props();

	const MONTHS = ['Jänner','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
	const DAY_SHORT = ['So','Mo','Di','Mi','Do','Fr','Sa'];

	let fromDate = $state('');
	let toDate   = $state('');
	let reason   = $state('');
	let busy     = $state(false);

	let absences    = $state([]);
	let loadingList = $state(true);

	// Set default from/to to today
	$effect(() => {
		if (open && !fromDate) {
			const today = new Date().toISOString().split('T')[0];
			fromDate = today;
			toDate   = today;
		}
	});

	async function loadAbsences() {
		const pid = $playerId;
		if (!pid) { loadingList = false; return; }
		const todayStr = new Date().toISOString().split('T')[0];
		const { data } = await sb
			.from('absences')
			.select('id, from_date, to_date, reason, created_at')
			.eq('player_id', pid)
			.gte('to_date', todayStr)
			.order('from_date');
		absences = data ?? [];
		loadingList = false;
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			loadAbsences();
		}
	});

	async function submit() {
		if (busy || !fromDate || !toDate) return;
		const pid = $playerId;
		if (!pid) return;

		busy = true;
		const { error } = await sb.from('absences').insert({
			player_id: pid,
			from_date: fromDate,
			to_date: toDate,
			reason: reason.trim() || null,
		});
		busy = false;

		if (error) {
			triggerToast('Fehler beim Speichern');
			return;
		}

		triggerToast('Abwesenheit gemeldet');
		fromDate = '';
		toDate = '';
		reason = '';
		await loadAbsences();
	}

	async function removeAbsence(id) {
		await sb.from('absences').delete().eq('id', id);
		absences = absences.filter(a => a.id !== id);
		triggerToast('Abwesenheit entfernt');
	}

	function fmtDate(d) {
		const dt = new Date(d + 'T12:00');
		return DAY_SHORT[dt.getDay()] + ', ' + dt.getDate() + '. ' + MONTHS[dt.getMonth()];
	}

	function fmtRange(a) {
		if (a.from_date === a.to_date) return fmtDate(a.from_date);
		return fmtDate(a.from_date) + ' – ' + fmtDate(a.to_date);
	}
</script>

<BottomSheet bind:open title="Abwesenheit melden">
	<!-- Form -->
	<div class="abs-form">
		<div class="abs-row">
			<label class="abs-label" for="abs-from">Von</label>
			<input class="abs-input" type="date" id="abs-from" bind:value={fromDate} />
		</div>
		<div class="abs-row">
			<label class="abs-label" for="abs-to">Bis</label>
			<input class="abs-input" type="date" id="abs-to" bind:value={toDate} min={fromDate} />
		</div>
		<div class="abs-row">
			<label class="abs-label" for="abs-reason">Grund (optional)</label>
			<input class="abs-input" type="text" id="abs-reason" bind:value={reason}
				placeholder="z.B. Urlaub, Verletzung…" maxlength="120" />
		</div>
		<button class="abs-submit" onclick={submit} disabled={busy || !fromDate || !toDate}>
			{#if busy}
				<span class="abs-spinner"></span>
			{:else}
				<span class="material-symbols-outlined" style="font-size:1.1rem">event_busy</span>
			{/if}
			Abwesenheit melden
		</button>
	</div>

	<!-- Existing absences -->
	{#if absences.length > 0}
		<p class="abs-section-title">Deine gemeldeten Abwesenheiten</p>
		<div class="abs-list">
			{#each absences as a}
				<div class="abs-item">
					<div class="abs-item-body">
						<span class="abs-item-range">{fmtRange(a)}</span>
						{#if a.reason}
							<span class="abs-item-reason">{a.reason}</span>
						{/if}
					</div>
					<button class="abs-item-remove" onclick={() => removeAbsence(a.id)} aria-label="Entfernen">
						<span class="material-symbols-outlined">close</span>
					</button>
				</div>
			{/each}
		</div>
	{:else if !loadingList}
		<p class="abs-empty">Keine Abwesenheiten gemeldet.</p>
	{/if}
</BottomSheet>

<style>
	.abs-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.abs-row {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.abs-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.abs-input {
		width: 100%;
		padding: 10px 12px;
		border: 1.5px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		font-size: var(--text-body-md);
		font-family: inherit;
		color: var(--color-on-surface);
		background: var(--color-surface-container-low);
		transition: border-color 0.15s ease;
		box-sizing: border-box;
	}
	.abs-input:focus {
		outline: none;
		border-color: var(--color-primary);
	}

	.abs-submit {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		width: 100%;
		padding: 12px;
		border: none;
		border-radius: var(--radius-lg);
		background: var(--color-primary);
		color: #fff;
		font-family: var(--font-display);
		font-size: var(--text-body-md);
		font-weight: 700;
		cursor: pointer;
		transition: opacity 0.15s ease, transform 0.1s ease;
		margin-top: var(--space-1);
	}
	.abs-submit:active { transform: scale(0.97); }
	.abs-submit:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.abs-spinner {
		width: 16px;
		height: 16px;
		border: 2px solid rgba(255,255,255,0.3);
		border-top-color: #fff;
		border-radius: 50%;
		animation: spin 0.6s linear infinite;
	}
	@keyframes spin { to { transform: rotate(360deg); } }

	.abs-section-title {
		font-size: var(--text-label-sm);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
		margin: var(--space-5) 0 var(--space-2);
	}

	.abs-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.abs-item {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
	}
	.abs-item-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.abs-item-range {
		font-weight: 600;
		font-size: var(--text-body-sm);
		color: var(--color-on-surface);
	}
	.abs-item-reason {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.abs-item-remove {
		width: 32px;
		height: 32px;
		border: none;
		border-radius: var(--radius-full);
		background: transparent;
		color: var(--color-outline);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		transition: background 0.15s;
	}
	.abs-item-remove:active {
		background: var(--color-surface-container);
	}
	.abs-item-remove .material-symbols-outlined {
		font-size: 1rem;
	}

	.abs-empty {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: var(--space-4) 0 0;
	}
</style>
