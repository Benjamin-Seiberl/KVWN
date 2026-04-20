<script>
	import { onMount }   from 'svelte';
	import { sb }        from '$lib/supabase';
	import { setSubtab } from '$lib/stores/subtab.js';
	import { goto }      from '$app/navigation';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { leagueTiming, offsetTime } from '$lib/utils/league.js';
	import AdminRollen      from '$lib/components/admin/AdminRollen.svelte';
	import AdminTraining    from '$lib/components/admin/AdminTraining.svelte';
	import AdminErgebnis    from '$lib/components/admin/AdminErgebnis.svelte';
	import AdminAufstellung from '$lib/components/admin/AdminAufstellung.svelte';

	let rollenOpen      = $state(false);
	let trainingOpen    = $state(false);
	let ergebnisOpen    = $state(false);
	let aufstellungOpen = $state(false);
	let attestExpanded  = $state(false);

	let openLineups      = $state([]);
	let missingResults   = $state([]);
	let pendingVotes     = $state([]);
	let urgentLbs        = $state([]);
	let expiringAtteste  = $state([]);
	let loading          = $state(true);

	onMount(loadData);

	async function loadData() {
		loading = true;
		const today  = toDateStr(new Date());
		const plus14 = toDateStr(new Date(Date.now() + 14 * 86400000));
		const plus30 = toDateStr(new Date(Date.now() - 0)); // now
		const plus30d = toDateStr(new Date(Date.now() + 30 * 86400000));
		const minus30 = toDateStr(new Date(Date.now() - 30 * 86400000));

		const [
			{ data: lineups },
			{ data: pastMatches },
			{ data: tournaments },
			{ data: lbs },
			{ data: atteste },
		] = await Promise.all([
			sb.from('game_plans')
				.select('id, cal_week, league_id, lineup_published_at, matches!inner(id, date, opponent, home_away, leagues(name))')
				.is('lineup_published_at', null)
				.gte('matches.date', today)
				.order('date', { referencedTable: 'matches' }),
			sb.from('matches')
				.select('id, date, time, opponent, home_away, leagues(name), game_plans(id, game_plan_players(score))')
				.gte('date', minus30).lt('date', today)
				.not('league_id', 'is', null)
				.order('date', { ascending: false }),
			sb.from('tournaments')
				.select('id, title, status, voting_deadline')
				.eq('status', 'voting')
				.gte('voting_deadline', new Date().toISOString())
				.order('voting_deadline'),
			sb.from('landesbewerbe')
				.select('id, title, typ, registration_deadline')
				.gte('registration_deadline', new Date().toISOString())
				.lte('registration_deadline', new Date(Date.now() + 30 * 86400000).toISOString())
				.order('registration_deadline'),
			sb.from('players')
				.select('id, name, medical_exam_expiry')
				.not('medical_exam_expiry', 'is', null)
				.lte('medical_exam_expiry', plus30d)
				.eq('active', true)
				.order('medical_exam_expiry'),
		]);

		openLineups     = lineups ?? [];
		pendingVotes    = tournaments ?? [];
		urgentLbs       = lbs ?? [];
		expiringAtteste = atteste ?? [];

		// Filter past matches: ended + at least one score missing
		missingResults = (pastMatches ?? []).filter(m => {
			if (!matchEnded(m)) return false;
			const gps = m.game_plans ?? [];
			if (!gps.length) return true;
			return gps.some(gp =>
				!gp.game_plan_players?.length ||
				gp.game_plan_players.some(p => p.score == null)
			);
		});

		loading = false;
	}

	function matchEnded(m) {
		if (!m?.time) return false;
		const timing = leagueTiming(m.leagues?.name ?? '');
		const endStr = offsetTime(m.time, timing.matchDurationMin);
		if (!endStr) return false;
		const [eh, em] = endStr.split(':').map(Number);
		const end = new Date(m.date + 'T00:00:00');
		end.setHours(eh, em + 10, 0, 0);
		return new Date() >= end;
	}

	const totalPending = $derived(
		openLineups.length + missingResults.length + pendingVotes.length + urgentLbs.length + expiringAtteste.length,
	);

	// ── Inbox cards ───────────────────────────────────────────────────────────
	const inboxCards = $derived.by(() => {
		const cards = [];
		if (openLineups.length > 0) {
			const n = openLineups.length;
			const next = openLineups[0]?.matches;
			cards.push({
				icon: 'edit_calendar',
				title: `${n} ${n === 1 ? 'Aufstellung' : 'Aufstellungen'} offen`,
				sub: next ? `Nächstes: ${next.opponent} · ${fmtDate(next.date)}` : 'Aufstellung erstellen',
				color: '#CC0000', bg: 'rgba(204,0,0,0.08)',
				action: () => aufstellungOpen = true,
			});
		}
		if (missingResults.length > 0) {
			const n = missingResults.length;
			const next = missingResults[0];
			cards.push({
				icon: 'sports_score',
				title: `${n} ${n === 1 ? 'Ergebnis fehlt' : 'Ergebnisse fehlen'}`,
				sub: next ? `Zuletzt: ${next.opponent} · ${fmtDate(next.date)}` : '',
				color: '#1d4ed8', bg: 'rgba(29,78,216,0.08)',
				action: () => ergebnisOpen = true,
			});
		}
		if (pendingVotes.length > 0) {
			const n = pendingVotes.length;
			const next = pendingVotes[0];
			cards.push({
				icon: 'how_to_vote',
				title: `${n} ${n === 1 ? 'Turnier-Abstimmung' : 'Turnier-Abstimmungen'}`,
				sub: next?.title ? `${next.title} · Frist: ${fmtDate(String(next.voting_deadline).slice(0,10))}` : '',
				color: '#b45309', bg: 'rgba(180,83,9,0.1)',
				action: () => { goto('/spielbetrieb'); setSubtab('/spielbetrieb', 'turnier'); },
			});
		}
		if (urgentLbs.length > 0) {
			const n = urgentLbs.length;
			const next = urgentLbs[0];
			cards.push({
				icon: 'workspace_premium',
				title: `${n} ${n === 1 ? 'Landesbewerb' : 'Landesbewerbe'} ausstehend`,
				sub: next?.title ? `${next.title} · Frist: ${fmtDate(String(next.registration_deadline).slice(0,10))}` : '',
				color: '#b45309', bg: 'rgba(180,83,9,0.1)',
				action: () => { goto('/spielbetrieb'); setSubtab('/spielbetrieb', 'landesbewerb'); },
			});
		}
		if (expiringAtteste.length > 0) {
			const n = expiringAtteste.length;
			cards.push({
				icon: 'medical_information',
				title: `${n} ${n === 1 ? 'Attest läuft ab' : 'Atteste laufen ab'}`,
				sub: 'Innerhalb von 30 Tagen',
				color: '#ca8a04', bg: 'rgba(202,138,4,0.1)',
				action: () => attestExpanded = !attestExpanded,
				expandable: true,
			});
		}
		return cards;
	});

	// ── Grouped tools (live counters injected) ────────────────────────────────
	const sections = $derived.by(() => [
		{
			title: 'Spielbetrieb',
			icon: 'emoji_events',
			color: '#CC0000',
			actions: [
				{ icon: 'edit_calendar', label: 'Aufstellung erstellen', live: true, count: openLineups.length,    countLabel: 'offen',  open: () => aufstellungOpen = true },
				{ icon: 'sports_score',  label: 'Ergebnis eintragen',    live: true, count: missingResults.length, countLabel: 'fehlen', open: () => ergebnisOpen = true },
				{ icon: 'leaderboard',   label: 'Tabelle pflegen' },
			],
		},
		{
			title: 'Spielerverwaltung',
			icon: 'group',
			color: '#3b82f6',
			actions: [
				{ icon: 'shield_person', label: 'Rollen verwalten',      live: true, open: () => rollenOpen = true },
				{ icon: 'person_add',    label: 'Spieler hinzufügen' },
				{ icon: 'person_remove', label: 'Spieler deaktivieren' },
			],
		},
		{
			title: 'Training',
			icon: 'fitness_center',
			color: '#059669',
			actions: [
				{ icon: 'event',     label: 'Training verwalten',  live: true, open: () => trainingOpen = true },
				{ icon: 'how_to_reg', label: 'Anwesenheit erfassen' },
			],
		},
		{
			title: 'Vereinskommunikation',
			icon: 'campaign',
			color: '#ea580c',
			actions: [
				{ icon: 'newspaper',     label: 'News verfassen' },
				{ icon: 'notifications', label: 'Push an alle senden' },
				{ icon: 'poll',          label: 'Umfrage erstellen' },
				{ icon: 'celebration',   label: 'Event anlegen' },
			],
		},
		{
			title: 'Statistiken & Daten',
			icon: 'analytics',
			color: '#0891b2',
			actions: [
				{ icon: 'bar_chart', label: 'Saisonstatistik' },
				{ icon: 'download',  label: 'Export (CSV)' },
			],
		},
		{
			title: 'System',
			icon: 'settings',
			color: '#64748b',
			actions: [
				{ icon: 'manage_accounts', label: 'Admin-Zugänge' },
				{ icon: 'backup',          label: 'Datensicherung' },
				{ icon: 'bug_report',      label: 'Debug-Log' },
			],
		},
	]);

	function adminAction(a) { if (a.live) a.open?.(); }

	function attestDaysLabel(d) {
		const diff = daysUntil(d);
		if (diff < 0) return `Abgelaufen seit ${-diff}d`;
		if (diff === 0) return 'Läuft heute ab';
		return `Noch ${diff} ${diff === 1 ? 'Tag' : 'Tage'}`;
	}
</script>

<div class="admin-wrap">

	<!-- Header -->
	<section class="ad-header">
		<span class="material-symbols-outlined ad-header-icon">shield_person</span>
		<div>
			<h2 class="ad-header-title">Kapitän-Werkbank</h2>
			<p class="ad-header-sub">
				{#if loading}Lädt…{:else if totalPending === 0}Alles erledigt{:else}{totalPending} offene {totalPending === 1 ? 'Aufgabe' : 'Aufgaben'}{/if}
			</p>
		</div>
	</section>

	<!-- Inbox -->
	{#if loading}
		<div class="inbox-skeleton shimmer-box"></div>
		<div class="inbox-skeleton shimmer-box" style="animation-delay:80ms"></div>
	{:else if inboxCards.length === 0}
		<div class="inbox-empty">
			<span class="material-symbols-outlined">task_alt</span>
			<p class="inbox-empty-title">Alles erledigt!</p>
			<p class="inbox-empty-sub">Keine offenen Aufgaben.</p>
		</div>
	{:else}
		<div class="inbox">
			{#each inboxCards as card}
				<button
					class="inbox-card"
					style="--ic-color:{card.color}; --ic-bg:{card.bg}"
					onclick={card.action}
				>
					<div class="inbox-icon">
						<span class="material-symbols-outlined">{card.icon}</span>
					</div>
					<div class="inbox-body">
						<span class="inbox-title">{card.title}</span>
						{#if card.sub}<span class="inbox-sub">{card.sub}</span>{/if}
					</div>
					<span class="material-symbols-outlined inbox-arrow">
						{card.expandable ? (attestExpanded ? 'expand_less' : 'expand_more') : 'chevron_right'}
					</span>
				</button>
			{/each}

			{#if attestExpanded && expiringAtteste.length > 0}
				<div class="attest-list">
					{#each expiringAtteste as p}
						<div class="attest-row">
							<span class="attest-name">{p.name}</span>
							<span class="attest-date" class:attest-date--warn={daysUntil(p.medical_exam_expiry) < 0}>
								{fmtDate(p.medical_exam_expiry)} · {attestDaysLabel(p.medical_exam_expiry)}
							</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>
	{/if}

	<!-- Grouped tools -->
	<div class="tools-head">
		<span class="material-symbols-outlined tools-head-icon">construction</span>
		<span class="tools-head-title">Werkzeuge</span>
	</div>

	{#each sections as section}
		{@const liveActions  = section.actions.filter(a => a.live)}
		{@const laterActions = section.actions.filter(a => !a.live)}
		<section class="ad-section">
			<div class="ad-section-head">
				<div class="ad-section-icon" style="background: {section.color}20; color: {section.color}">
					<span class="material-symbols-outlined">{section.icon}</span>
				</div>
				<h3 class="ad-section-title">{section.title}</h3>
			</div>

			{#if liveActions.length === 0}
				<p class="ad-section-empty">Bald verfügbar</p>
			{:else}
				<div class="ad-action-grid">
					{#each liveActions as action}
						<button class="ad-action" onclick={() => adminAction(action)}>
							<span class="material-symbols-outlined ad-action-icon" style="color: {section.color}">{action.icon}</span>
							<span class="ad-action-label">{action.label}</span>
							{#if action.count > 0}
								<span class="ad-action-count" style="background: {section.color}20; color: {section.color}">
									{action.count} {action.countLabel ?? ''}
								</span>
							{/if}
							<span class="material-symbols-outlined ad-action-arrow">chevron_right</span>
						</button>
					{/each}
				</div>
			{/if}

			{#if laterActions.length > 0}
				<p class="ad-later">+ {laterActions.length} geplant: {laterActions.map(a => a.label).join(' · ')}</p>
			{/if}
		</section>
	{/each}

	<div class="ad-version">
		<span class="material-symbols-outlined">info</span>
		Admin-Panel v0.3
	</div>
</div>

<AdminRollen      bind:open={rollenOpen} />
<AdminTraining    bind:open={trainingOpen} />
<AdminErgebnis    bind:open={ergebnisOpen} />
<AdminAufstellung bind:open={aufstellungOpen} />

<style>
	.admin-wrap { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-4); }

	/* Header */
	.ad-header {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-4);
		background: linear-gradient(135deg, rgba(204,0,0,0.08) 0%, rgba(204,0,0,0.04) 100%);
		border: 1px solid rgba(204,0,0,0.15);
		border-radius: 16px;
	}
	.ad-header-icon {
		font-size: 2rem; color: var(--color-primary); flex-shrink: 0;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 48;
	}
	.ad-header-title { font-family: var(--font-display); font-weight: 900; font-size: 1.15rem; color: var(--color-on-surface); margin: 0; }
	.ad-header-sub   { font-size: 0.78rem; color: var(--color-on-surface-variant); margin: 2px 0 0; }

	/* Inbox */
	.inbox { display: flex; flex-direction: column; gap: var(--space-2); }
	.inbox-skeleton { height: 72px; border-radius: var(--radius-lg); }
	.inbox-empty {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-6) var(--space-4);
		display: flex; flex-direction: column; align-items: center; gap: var(--space-2);
		text-align: center;
	}
	.inbox-empty .material-symbols-outlined { font-size: 2.5rem; color: #16a34a; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 48; }
	.inbox-empty-title { font-family: var(--font-display); font-weight: 800; color: var(--color-on-surface); margin: 0; }
	.inbox-empty-sub { font-size: 0.82rem; color: var(--color-on-surface-variant); margin: 0; }

	.inbox-card {
		display: flex; align-items: center; gap: var(--space-3);
		background: var(--ic-bg); border: 1.5px solid color-mix(in srgb, var(--ic-color) 35%, transparent);
		border-radius: 14px; padding: var(--space-3) var(--space-4);
		cursor: pointer; text-align: left; font-family: inherit; width: 100%;
		-webkit-tap-highlight-color: transparent; transition: transform 100ms ease;
		box-shadow: var(--shadow-card);
	}
	.inbox-card:active { transform: scale(0.98); }
	.inbox-icon {
		width: 36px; height: 36px; border-radius: 10px;
		background: color-mix(in srgb, var(--ic-color) 15%, transparent);
		display: grid; place-items: center; flex-shrink: 0;
	}
	.inbox-icon .material-symbols-outlined {
		color: var(--ic-color); font-size: 1.2rem;
		font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}
	.inbox-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.inbox-title { font-weight: 800; font-size: 0.92rem; color: var(--color-on-surface); }
	.inbox-sub   { font-size: 0.75rem; color: var(--color-on-surface-variant); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.inbox-arrow { color: var(--ic-color); flex-shrink: 0; font-size: 1.2rem; }

	.attest-list {
		margin-top: var(--space-1); padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 12px; display: flex; flex-direction: column;
	}
	.attest-row {
		display: flex; justify-content: space-between; align-items: center; gap: var(--space-2);
		padding: var(--space-2) 0; border-top: 1px solid var(--color-surface-container);
	}
	.attest-row:first-child { border-top: none; }
	.attest-name { font-size: 0.88rem; font-weight: 600; color: var(--color-on-surface); }
	.attest-date { font-size: 0.75rem; color: var(--color-on-surface-variant); }
	.attest-date--warn { color: var(--color-primary); font-weight: 700; }

	/* Tools */
	.tools-head {
		display: flex; align-items: center; gap: var(--space-2);
		margin-top: var(--space-3); padding: 0 var(--space-1);
	}
	.tools-head-icon { font-size: 1rem; color: var(--color-primary); font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24; }
	.tools-head-title {
		font-family: var(--font-display); font-weight: 700; font-size: 0.82rem;
		text-transform: uppercase; letter-spacing: 0.08em; color: var(--color-primary);
	}

	.ad-section {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.ad-section-head { display: flex; align-items: center; gap: var(--space-3); }
	.ad-section-icon {
		width: 36px; height: 36px; border-radius: 10px;
		display: grid; place-items: center; flex-shrink: 0;
	}
	.ad-section-icon .material-symbols-outlined {
		font-size: 1.2rem; font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
	}
	.ad-section-title { font-family: var(--font-display); font-weight: 800; font-size: 0.9rem; color: var(--color-on-surface); margin: 0; }
	.ad-section-empty { font-size: 0.8rem; color: var(--color-outline); margin: 0; font-style: italic; }

	.ad-action-grid { display: flex; flex-direction: column; gap: 2px; }
	.ad-action {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) var(--space-2); border: none; background: none;
		border-radius: 10px; cursor: pointer; text-align: left;
		font-family: inherit; -webkit-tap-highlight-color: transparent; width: 100%;
		transition: background 120ms;
	}
	.ad-action:active { background: var(--color-surface-container-low); }
	.ad-action-icon {
		font-size: 1.2rem; flex-shrink: 0; width: 24px; text-align: center;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.ad-action-label { flex: 1; font-size: 0.88rem; font-weight: 600; color: var(--color-on-surface); }
	.ad-action-count {
		font-size: 0.68rem; font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em;
		padding: 2px 8px; border-radius: 999px; flex-shrink: 0;
	}
	.ad-action-arrow { color: var(--color-on-surface-variant); font-size: 1rem; flex-shrink: 0; }

	.ad-later {
		margin: 0; padding-top: var(--space-2); border-top: 1px dashed var(--color-surface-container);
		font-size: 0.72rem; color: var(--color-outline); font-style: italic;
	}

	.ad-version {
		display: flex; align-items: center; justify-content: center; gap: var(--space-2);
		font-size: 0.72rem; color: var(--color-outline); padding: var(--space-3);
	}
	.ad-version .material-symbols-outlined { font-size: 0.9rem; }
</style>
