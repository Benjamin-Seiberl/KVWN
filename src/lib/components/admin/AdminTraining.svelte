<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';
	import { playerId } from '$lib/stores/auth';
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';

	let { open = $bindable(false) } = $props();

	const DAYS  = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
	const HOURS = Array.from({ length: 10 }, (_, i) => 14 + i); // 14..23

	let templates = $state([]);
	let specials  = $state([]);
	let loading   = $state(true);
	let lanes     = $state(4);

	const today = toDateStr(new Date());

	// Sonder-Training form
	let spDate  = $state('');
	let spStart = $state('18:00');
	let spEnd   = $state('19:00');
	let spCap   = $state(4);
	let spNote  = $state('');
	let spSaving = $state(false);

	async function load() {
		loading = true;
		const [{ data: t }, { data: s }] = await Promise.all([
			sb.from('training_templates').select('*'),
			sb.from('training_specials').select('*').gte('date', today).order('date'),
		]);
		templates = t ?? [];
		specials  = s ?? [];
		loading = false;
	}

	async function addSpecial() {
		if (!spDate || !spStart || !spEnd) {
			triggerToast('Datum und Zeiten erforderlich');
			return;
		}
		if (spEnd <= spStart) {
			triggerToast('Ende muss nach Start liegen');
			return;
		}
		spSaving = true;
		const { error } = await sb.from('training_specials').insert({
			date: spDate,
			start_time: spStart,
			end_time: spEnd,
			capacity: spCap,
			note: spNote || null,
			created_by: $playerId,
		});
		spSaving = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		spDate = ''; spNote = '';
		triggerToast('Sonder-Training angelegt');
		await load();
	}

	async function deleteSpecial(id) {
		const { error } = await sb.from('training_specials').delete().eq('id', id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		triggerToast('Sonder-Training entfernt');
		await load();
	}

	// day_of_week mapping: grid index Mo=0..So=6 → DB: 0=So, 1=Mo..6=Sa
	function toDow(dayIdx) {
		return dayIdx === 6 ? 0 : dayIdx + 1;
	}

	function isActive(dayIdx, hour) {
		const dow = toDow(dayIdx);
		return templates.some(t =>
			t.active && t.day_of_week === dow &&
			Number(String(t.start_time).slice(0, 2)) === hour
		);
	}

	function activeCount() {
		return templates.filter(t => t.active).length;
	}

	async function toggle(dayIdx, hour) {
		const dow = toDow(dayIdx);
		const startTime = `${String(hour).padStart(2, '0')}:00`;
		const existing = templates.find(t =>
			t.day_of_week === dow &&
			Number(String(t.start_time).slice(0, 2)) === hour
		);

		if (existing) {
			await sb.from('training_templates')
				.update({ active: !existing.active, lane_count: lanes })
				.eq('id', existing.id);
		} else {
			await sb.from('training_templates').insert({
				day_of_week: dow,
				start_time: startTime,
				end_time: `${String(hour + 1).padStart(2, '0')}:00`,
				lane_count: lanes,
				active: true,
			});
		}
		await load();
	}

	function save() {
		open = false;
		setTimeout(() => triggerToast(`${activeCount()} Trainings-Slots aktiv`), 300);
	}

	// Load when sheet opens
	$effect(() => {
		if (open) load();
	});
</script>

<BottomSheet bind:open title="Training verwalten">
	{#if loading}
		<div class="at-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
		</div>
	{:else}
		<!-- Bahnen-Auswahl -->
		<div class="at-lanes">
			<span class="at-lanes-label">Bahnen pro Block</span>
			<div class="at-lanes-options">
				{#each [4, 6, 8] as n}
					<button
						class="at-lane-btn"
						class:at-lane-btn--active={lanes === n}
						onclick={() => { lanes = n; }}
					>{n}</button>
				{/each}
			</div>
		</div>

		<!-- Wochenplan-Grid -->
		<p class="at-hint">Tippe auf eine Zelle um 1h-Blöcke zu aktivieren.</p>
		<div class="at-grid" style="grid-template-columns: 48px repeat(7, 1fr)">
			<!-- Header -->
			<div class="at-cell at-cell--head"></div>
			{#each DAYS as d}
				<div class="at-cell at-cell--head">{d}</div>
			{/each}

			<!-- Stunden-Zeilen -->
			{#each HOURS as h}
				<div class="at-cell at-cell--time">{h}:00</div>
				{#each DAYS as _, dayIdx}
					{@const active = isActive(dayIdx, h)}
					<button
						class="at-cell at-cell--slot"
						class:at-cell--active={active}
						onclick={() => toggle(dayIdx, h)}
						aria-label="{DAYS[dayIdx]} {h}:00 {active ? 'aktiv' : 'inaktiv'}"
					>
						{#if active}
							<span class="material-symbols-outlined at-check">check</span>
						{/if}
					</button>
				{/each}
			{/each}
		</div>

		<!-- ── Sonder-Trainings ───────────────────────────────────────────── -->
		<div class="at-section-head">
			<span class="material-symbols-outlined">event_available</span>
			<span>Sonder-Trainings</span>
		</div>

		{#if specials.length === 0}
			<p class="at-hint">Noch keine Sonder-Trainings geplant.</p>
		{:else}
			<ul class="at-sp-list">
				{#each specials as sp (sp.id)}
					<li class="at-sp-item">
						<div class="at-sp-body">
							<span class="at-sp-date">{fmtDate(sp.date)}</span>
							<span class="at-sp-time">{String(sp.start_time).slice(0,5)}–{String(sp.end_time).slice(0,5)} Uhr · {sp.capacity} Plätze</span>
							{#if sp.note}<span class="at-sp-note">{sp.note}</span>{/if}
						</div>
						<button class="at-sp-del" onclick={() => deleteSpecial(sp.id)} aria-label="Entfernen">
							<span class="material-symbols-outlined">close</span>
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		<div class="at-sp-form">
			<div class="at-sp-row">
				<label class="at-sp-field">
					<span>Datum</span>
					<input type="date" bind:value={spDate} min={today} />
				</label>
				<label class="at-sp-field at-sp-field--cap">
					<span>Plätze</span>
					<input type="number" min="1" max="20" bind:value={spCap} />
				</label>
			</div>
			<div class="at-sp-row">
				<label class="at-sp-field">
					<span>Start</span>
					<input type="time" bind:value={spStart} />
				</label>
				<label class="at-sp-field">
					<span>Ende</span>
					<input type="time" bind:value={spEnd} />
				</label>
			</div>
			<label class="at-sp-field">
				<span>Notiz (optional)</span>
				<input type="text" bind:value={spNote} placeholder="z. B. Mannschaftstraining" />
			</label>
			<button class="mw-btn mw-btn--soft mw-btn--wide" onclick={addSpecial} disabled={spSaving}>
				<span class="material-symbols-outlined">add</span>
				Sonder-Training anlegen
			</button>
		</div>

		<!-- Fertig-Button -->
		<button class="mw-btn mw-btn--primary mw-btn--wide at-done" onclick={save}>
			<span class="material-symbols-outlined">check</span>
			Fertig
		</button>
	{/if}
</BottomSheet>

<style>
	/* Bahnen-Auswahl */
	.at-lanes {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.at-lanes-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-outline);
	}
	.at-lanes-options {
		display: flex;
		gap: var(--space-1);
	}
	.at-lane-btn {
		width: 36px; height: 36px;
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-low);
		font-weight: 700;
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
	}
	.at-lane-btn--active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: #fff;
	}

	/* Hinweis */
	.at-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-3);
	}

	/* Grid */
	.at-grid {
		display: grid;
		gap: 3px;
		margin-bottom: var(--space-4);
	}
	.at-cell {
		text-align: center;
		font-size: 0.72rem;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.at-cell--head {
		font-weight: 700;
		color: var(--color-outline);
		padding: 4px 0;
		font-size: var(--text-label-sm);
	}
	.at-cell--time {
		color: var(--color-on-surface-variant);
		font-size: 0.7rem;
		padding: 2px 0;
	}
	.at-cell--slot {
		min-height: 28px;
		background: var(--color-surface-container-low);
		border: 1px solid var(--color-outline-variant);
		border-radius: 6px;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 0.15s, border-color 0.15s;
		padding: 0;
	}
	.at-cell--active {
		background: var(--color-primary);
		border-color: var(--color-primary);
	}
	.at-check {
		font-size: 0.85rem;
		color: #fff;
		font-variation-settings: 'FILL' 1, 'wght' 600;
	}

	/* Fertig */
	.at-done {
		margin-top: var(--space-4);
	}

	/* Loading */
	.at-loading {
		padding: var(--space-4) 0;
	}

	/* Sonder-Trainings section */
	.at-section-head {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-family: var(--font-display);
		font-weight: 800;
		font-size: var(--text-label-md);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-on-surface);
		margin: var(--space-4) 0 var(--space-3);
		padding-top: var(--space-3);
		border-top: 1px solid var(--color-outline-variant);
	}
	.at-section-head .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	.at-sp-list {
		list-style: none;
		padding: 0;
		margin: 0 0 var(--space-3);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.at-sp-item {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		background: var(--color-surface-container-low, #f7f7f7);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--color-outline-variant);
	}
	.at-sp-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.at-sp-date {
		font-weight: 700;
		font-size: var(--text-label-md);
		color: var(--color-on-surface);
	}
	.at-sp-time {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.at-sp-note {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		font-style: italic;
	}
	.at-sp-del {
		width: 32px; height: 32px;
		border-radius: var(--radius-md);
		border: none;
		background: transparent;
		color: var(--color-on-surface-variant);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		-webkit-tap-highlight-color: transparent;
	}
	.at-sp-del:active { background: var(--color-surface-container); }
	.at-sp-del .material-symbols-outlined { font-size: 1.1rem; }

	.at-sp-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		background: var(--color-surface-container-low, #f7f7f7);
		border-radius: var(--radius-md);
		padding: var(--space-3);
		border: 1px solid var(--color-outline-variant);
	}
	.at-sp-row {
		display: flex;
		gap: var(--space-2);
	}
	.at-sp-field {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex: 1;
		min-width: 0;
	}
	.at-sp-field--cap { flex: 0 0 90px; }
	.at-sp-field > span {
		font-size: var(--text-label-sm);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-outline);
	}
	.at-sp-field input {
		padding: 8px 10px;
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-lowest, #fff);
		font-size: var(--text-body-md);
		font-family: inherit;
		color: var(--color-on-surface);
	}
	.at-sp-field input:focus {
		outline: none;
		border-color: var(--color-primary);
	}
</style>
