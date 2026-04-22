<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { toDateStr } from '$lib/utils/dates.js';
	import { matchEnded } from '$lib/utils/matchTiming.js';
	import AdminAufstellung from '$lib/components/admin/AdminAufstellung.svelte';
	import ResultEntrySheet from '$lib/components/spielbetrieb/ResultEntrySheet.svelte';
	import TournamentManageSheet from '$lib/components/spielbetrieb/TournamentManageSheet.svelte';
	import LandesbewerbManageSheet from '$lib/components/spielbetrieb/LandesbewerbManageSheet.svelte';

	// ── Sheet flags ─────────────────────────────────────────────
	let aufstellungOpen        = $state(false);
	let preselectedMatchId     = $state(null);
	let resultEntryOpen        = $state(false);
	let tournamentMgrOpen      = $state(false);
	let landesMgrOpen          = $state(false);

	// ── Inbox counts ────────────────────────────────────────────
	let openLineupsCount       = $state(0);
	let missingResultsCount    = $state(0);
	let pendingVotesCount      = $state(0);
	let urgentLbsCount         = $state(0);
	let firstOpenLineupMatchId = $state(null);
	let loading                = $state(true);

	onMount(loadCounts);

	async function loadCounts() {
		loading = true;
		const today    = toDateStr(new Date());
		const minus30  = toDateStr(new Date(Date.now() - 30 * 86400000));
		const nowIso   = new Date().toISOString();
		const plus7Iso = new Date(Date.now() + 7 * 86400000).toISOString();

		const [
			{ data: lineups, error: lineupsErr },
			{ data: pastMatches, error: pastErr },
			{ count: votesCount, error: votesErr },
			{ count: lbsCount, error: lbsErr },
		] = await Promise.all([
			sb.from('game_plans')
				.select('id, matches!inner(id, date)')
				.is('lineup_published_at', null)
				.gte('matches.date', today)
				.order('date', { referencedTable: 'matches' }),
			sb.from('matches')
				.select('id, date, time, leagues(name), game_plans(id, result_published_at)')
				.gte('date', minus30).lt('date', today)
				.not('league_id', 'is', null)
				.eq('is_tournament', false)
				.eq('is_landesbewerb', false)
				.eq('is_friendly', false)
				.order('date', { ascending: false }),
			sb.from('tournaments')
				.select('id', { count: 'exact', head: true })
				.eq('status', 'voting')
				.gte('voting_deadline', nowIso),
			sb.from('landesbewerbe')
				.select('id', { count: 'exact', head: true })
				.gte('registration_deadline', nowIso)
				.lte('registration_deadline', plus7Iso),
		]);

		if (lineupsErr) triggerToast('Fehler: ' + lineupsErr.message);
		if (pastErr)    triggerToast('Fehler: ' + pastErr.message);
		if (votesErr)   triggerToast('Fehler: ' + votesErr.message);
		if (lbsErr)     triggerToast('Fehler: ' + lbsErr.message);

		const lineupRows           = lineups ?? [];
		openLineupsCount           = lineupRows.length;
		firstOpenLineupMatchId     = lineupRows[0]?.matches?.id ?? null;

		// Past matches that ended and have no published result on any game_plan
		const missing = (pastMatches ?? []).filter(m => {
			if (!matchEnded(m)) return false;
			const gps = m.game_plans ?? [];
			if (!gps.length) return true;
			return gps.every(gp => !gp.result_published_at);
		});
		missingResultsCount = missing.length;
		pendingVotesCount   = votesCount ?? 0;
		urgentLbsCount      = lbsCount ?? 0;

		loading = false;
	}

	// Refresh counts whenever any sheet flips back to closed
	$effect(() => {
		const anyOpen = aufstellungOpen || resultEntryOpen || tournamentMgrOpen || landesMgrOpen;
		if (!anyOpen && !loading) loadCounts();
	});
</script>

<section class="admin-sb">
	<h2 class="admin-sb-title">
		<span class="material-symbols-outlined">admin_panel_settings</span>
		Admin Spielbetrieb
	</h2>

	<!-- Inbox -->
	<div class="inbox">
		{#if loading}
			<div class="inbox-row inbox-row--muted">
				<span>Lädt…</span>
			</div>
		{:else if openLineupsCount === 0 && missingResultsCount === 0 && pendingVotesCount === 0 && urgentLbsCount === 0}
			<div class="inbox-row inbox-row--ok">
				<span class="material-symbols-outlined">check_circle</span>
				<span>Alles erledigt</span>
			</div>
		{:else}
			{#if openLineupsCount > 0}
				<button
					class="inbox-row"
					onclick={() => { preselectedMatchId = firstOpenLineupMatchId; aufstellungOpen = true; }}
				>
					<span class="material-symbols-outlined">format_list_numbered</span>
					<span class="inbox-row-text">Offene Aufstellungen</span>
					<span class="inbox-badge">{openLineupsCount}</span>
				</button>
			{/if}
			{#if missingResultsCount > 0}
				<button class="inbox-row" onclick={() => resultEntryOpen = true}>
					<span class="material-symbols-outlined">edit_note</span>
					<span class="inbox-row-text">Fehlende Ergebnisse</span>
					<span class="inbox-badge">{missingResultsCount}</span>
				</button>
			{/if}
			{#if pendingVotesCount > 0}
				<button class="inbox-row" onclick={() => tournamentMgrOpen = true}>
					<span class="material-symbols-outlined">how_to_vote</span>
					<span class="inbox-row-text">Turnier-Abstimmungen</span>
					<span class="inbox-badge">{pendingVotesCount}</span>
				</button>
			{/if}
			{#if urgentLbsCount > 0}
				<button class="inbox-row" onclick={() => landesMgrOpen = true}>
					<span class="material-symbols-outlined">workspace_premium</span>
					<span class="inbox-row-text">Landesbewerb-Anmeldungen</span>
					<span class="inbox-badge">{urgentLbsCount}</span>
				</button>
			{/if}
		{/if}
	</div>

	<!-- Tools -->
	<h3 class="tools-title">Werkzeuge</h3>
	<div class="tools">
		<button
			class="tool-card"
			onclick={() => { preselectedMatchId = firstOpenLineupMatchId; aufstellungOpen = true; }}
		>
			<span class="material-symbols-outlined tool-icon">format_list_numbered</span>
			<div class="tool-body">
				<span class="tool-name">Aufstellung erstellen</span>
				<span class="tool-sub">Lineup für nächstes Spiel</span>
			</div>
		</button>
		<button class="tool-card" onclick={() => resultEntryOpen = true}>
			<span class="material-symbols-outlined tool-icon">edit_note</span>
			<div class="tool-body">
				<span class="tool-name">Ergebnis eintragen</span>
				<span class="tool-sub">Ergebnis für gespieltes Match</span>
			</div>
		</button>
		<button class="tool-card" onclick={() => tournamentMgrOpen = true}>
			<span class="material-symbols-outlined tool-icon">military_tech</span>
			<div class="tool-body">
				<span class="tool-name">Turnier verwalten</span>
				<span class="tool-sub">Anlegen, bearbeiten, Voting</span>
			</div>
		</button>
		<button class="tool-card" onclick={() => landesMgrOpen = true}>
			<span class="material-symbols-outlined tool-icon">workspace_premium</span>
			<div class="tool-body">
				<span class="tool-name">Landesbewerb verwalten</span>
				<span class="tool-sub">Anlegen, Anmeldungen prüfen</span>
			</div>
		</button>
	</div>
</section>

<AdminAufstellung bind:open={aufstellungOpen} preselectedMatchId={preselectedMatchId} />
<ResultEntrySheet bind:open={resultEntryOpen} onPublished={loadCounts} />
<TournamentManageSheet bind:open={tournamentMgrOpen} />
<LandesbewerbManageSheet bind:open={landesMgrOpen} />

<style>
	.admin-sb {
		padding: var(--space-4);
		max-width: 720px;
		margin: 0 auto;
	}

	.admin-sb-title {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin: 0 0 var(--space-4);
		font-family: var(--font-display);
		font-weight: 800;
		font-size: var(--text-headline-sm);
		color: var(--color-on-surface);
	}

	.admin-sb-title .material-symbols-outlined {
		color: var(--color-primary);
		font-size: 1.5rem;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}

	/* Inbox */
	.inbox {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		margin-bottom: var(--space-6);
	}

	.inbox-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		color: var(--color-on-surface);
		-webkit-tap-highlight-color: transparent;
	}

	.inbox-row .material-symbols-outlined {
		color: var(--color-primary);
		font-size: 1.25rem;
		flex-shrink: 0;
	}

	.inbox-row--ok {
		background: var(--color-surface-container);
		cursor: default;
	}

	.inbox-row--ok .material-symbols-outlined {
		color: var(--color-secondary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	.inbox-row--muted {
		color: var(--color-on-surface-variant);
		cursor: default;
	}

	.inbox-row-text {
		flex: 1;
		text-align: left;
		font-size: var(--text-body-md);
		font-weight: 600;
	}

	.inbox-badge {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 1.5rem;
		padding: var(--space-1) var(--space-2);
		background: var(--color-primary);
		color: #fff;
		border-radius: var(--radius-full);
		font-size: var(--text-label-sm);
		font-weight: 800;
	}

	/* Tools */
	.tools-title {
		margin: 0 0 var(--space-3);
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
	}

	.tools {
		display: grid;
		grid-template-columns: 1fr;
		gap: var(--space-3);
	}

	@media (min-width: 480px) {
		.tools {
			grid-template-columns: 1fr 1fr;
		}
	}

	.tool-card {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2);
		width: 100%;
		padding: var(--space-4);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-card);
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		-webkit-tap-highlight-color: transparent;
		transition: transform 120ms ease;
	}

	.tool-card:active {
		transform: scale(0.98);
	}

	.tool-icon {
		font-size: 32px;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}

	.tool-body {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.tool-name {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
	}

	.tool-sub {
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
	}
</style>
