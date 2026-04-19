<script>
	import AdminRollen      from '$lib/components/admin/AdminRollen.svelte';
	import AdminTraining    from '$lib/components/admin/AdminTraining.svelte';
	import AdminErgebnis    from '$lib/components/admin/AdminErgebnis.svelte';
	import AdminAufstellung from '$lib/components/admin/AdminAufstellung.svelte';

	let rollenOpen      = $state(false);
	let trainingOpen    = $state(false);
	let ergebnisOpen    = $state(false);
	let aufstellungOpen = $state(false);

	function adminAction(action) {
		if (!action.live) return;
		action.open?.();
	}

	const ADMIN_SECTIONS = [
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
			title: 'Spielbetrieb',
			icon: 'emoji_events',
			color: '#CC0000',
			actions: [
				{ icon: 'edit_calendar', label: 'Aufstellung erstellen', live: true, open: () => aufstellungOpen = true },
				{ icon: 'sports_score',  label: 'Ergebnis eintragen',    live: true, open: () => ergebnisOpen = true },
				{ icon: 'leaderboard',   label: 'Tabelle pflegen' },
			],
		},
		{
			title: 'Training',
			icon: 'fitness_center',
			color: '#059669',
			actions: [
				{ icon: 'event',     label: 'Training verwalten',    live: true, open: () => trainingOpen = true },
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
	];
</script>

<div class="admin-header">
	<span class="material-symbols-outlined admin-header-icon">shield_person</span>
	<div>
		<h2 class="admin-header-title">Kapitäns-Panel</h2>
		<p class="admin-header-sub">Verwaltung · KV Wiener Neustadt</p>
	</div>
</div>

{#each ADMIN_SECTIONS as section}
<section class="admin-section">
	<div class="admin-section-head">
		<div class="admin-section-icon" style="background: {section.color}20; color: {section.color}">
			<span class="material-symbols-outlined">{section.icon}</span>
		</div>
		<h3 class="admin-section-title">{section.title}</h3>
	</div>
	<div class="admin-action-grid">
		{#each section.actions as action}
		<button
			class="admin-action"
			class:admin-action--live={action.live}
			class:admin-action--disabled={!action.live}
			onclick={() => adminAction(action)}
		>
			<span class="material-symbols-outlined admin-action-icon" style="color: {action.live ? section.color : ''}">{action.icon}</span>
			<span class="admin-action-label">{action.label}</span>
			{#if !action.live}
				<span class="admin-action-badge">Bald</span>
			{/if}
		</button>
		{/each}
	</div>
</section>
{/each}

<div class="admin-version">
	<span class="material-symbols-outlined">info</span>
	Admin-Panel v0.2
</div>

<AdminRollen bind:open={rollenOpen} />
<AdminTraining bind:open={trainingOpen} />
<AdminErgebnis bind:open={ergebnisOpen} />
<AdminAufstellung bind:open={aufstellungOpen} />
