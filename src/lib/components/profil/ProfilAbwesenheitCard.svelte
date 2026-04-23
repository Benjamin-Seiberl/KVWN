<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, toDateStr } from '$lib/utils/dates.js';
	import AbsenceSheet from '$lib/components/dashboard/AbsenceSheet.svelte';

	let absences = $state([]);
	let loading  = $state(true);
	let sheetOpen = $state(false);

	async function load() {
		const pid = $playerId;
		if (!pid) { loading = false; return; }
		loading = true;
		const todayStr = toDateStr(new Date());
		const { data, error } = await sb
			.from('absences')
			.select('id, from_date, to_date, reason')
			.eq('player_id', pid)
			.gte('to_date', todayStr)
			.order('from_date');
		if (error) { triggerToast('Fehler: ' + error.message); loading = false; return; }
		absences = data ?? [];
		loading = false;
	}

	let loaded = false;
	$effect(() => {
		if ($playerId && !loaded) {
			loaded = true;
			load();
		}
	});

	async function removeAbsence(id) {
		const { error } = await sb.from('absences').delete().eq('id', id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		absences = absences.filter(a => a.id !== id);
		triggerToast('Abwesenheit entfernt');
	}

	function fmtRange(a) {
		if (a.from_date === a.to_date) return fmtDate(a.from_date);
		return fmtDate(a.from_date) + ' – ' + fmtDate(a.to_date);
	}
</script>

<section class="card">
	<div class="data-card-head">
		<h3 class="section-title">
			<span class="material-symbols-outlined">event_busy</span>
			Meine Abwesenheiten
		</h3>
		<button class="data-card-edit" onclick={() => sheetOpen = true}>
			+ Melden
		</button>
	</div>

	{#if loading}
		<div class="abs-skel shimmer-box"></div>
	{:else if absences.length === 0}
		<p class="abs-empty">Keine Abwesenheiten gemeldet.</p>
	{:else}
		<div class="abs-list">
			{#each absences as a (a.id)}
				<div class="abs-row">
					<div class="abs-body">
						<span class="abs-range">{fmtRange(a)}</span>
						{#if a.reason}
							<span class="abs-reason">{a.reason}</span>
						{/if}
					</div>
					<button
						class="abs-remove"
						onclick={() => removeAbsence(a.id)}
						aria-label="Abwesenheit entfernen"
					>
						<span class="material-symbols-outlined">close</span>
					</button>
				</div>
			{/each}
		</div>
	{/if}
</section>

<AbsenceSheet bind:open={sheetOpen} onReload={load} />

<style>
	.card {
		background: var(--color-surface-container-lowest);
		border-radius: var(--radius-lg);
		padding: var(--space-4);
		box-shadow: var(--shadow-card);
	}
	.data-card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.section-title {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--text-title-sm);
		font-weight: 700;
		color: var(--color-on-surface);
	}
	.section-title .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.data-card-edit {
		background: none;
		border: none;
		font: inherit;
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-primary);
		cursor: pointer;
		padding: 4px 8px;
		border-radius: var(--radius-md);
	}
	.data-card-edit:active { opacity: 0.7; }

	.abs-skel {
		height: 40px;
		border-radius: var(--radius-md);
	}

	.abs-empty {
		margin: 0;
		font-size: var(--text-body-md);
		color: var(--color-on-surface-variant);
	}

	.abs-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.abs-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
	}
	.abs-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.abs-range {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
	}
	.abs-reason {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
	.abs-remove {
		flex-shrink: 0;
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
		-webkit-tap-highlight-color: transparent;
	}
	.abs-remove:active {
		background: var(--color-surface-container);
	}
	.abs-remove .material-symbols-outlined {
		font-size: 1rem;
	}
</style>
