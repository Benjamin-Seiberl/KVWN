<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';

	let stats = $state({
		players: null, matches: null, news: null, polls: null, events: null, teams: null,
	});

	async function count(table) {
		const { count: c } = await sb.from(table).select('*', { count: 'exact', head: true });
		return c ?? 0;
	}

	onMount(async () => {
		const [players, matches, news, polls, events, teams] = await Promise.all([
			count('players'), count('matches'), count('announcements'), count('polls'), count('events'), count('teams'),
		]);
		stats = { players, matches, news, polls, events, teams };
	});

	const tiles = $derived([
		{ href: '/admin/spieler',  icon: 'group',          label: 'Spieler',     value: stats.players },
		{ href: '/admin/teams',    icon: 'diversity_3',    label: 'Teams',       value: stats.teams },
		{ href: '/admin/saison',   icon: 'event_note',     label: 'Matches',     value: stats.matches },
		{ href: '/admin/news',     icon: 'campaign',       label: 'News',        value: stats.news },
		{ href: '/admin/news',     icon: 'ballot',         label: 'Polls',       value: stats.polls },
		{ href: '/admin/saison',   icon: 'calendar_month', label: 'Events',      value: stats.events },
	]);
</script>

<div class="admin-grid">
	{#each tiles as t}
		<a class="admin-tile" href={t.href}>
			<span class="material-symbols-outlined admin-tile__icon">{t.icon}</span>
			<span class="admin-tile__value">{t.value ?? '–'}</span>
			<span class="admin-tile__label">{t.label}</span>
		</a>
	{/each}
</div>

<style>
	.admin-grid {
		display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-3);
	}
	.admin-tile {
		display: flex; flex-direction: column; gap: 4px;
		padding: var(--space-4);
		background: var(--color-surface, #fff);
		border: 1px solid var(--color-border, #eee);
		border-radius: 14px;
		text-decoration: none;
		color: inherit;
		transition: transform 0.1s;
	}
	.admin-tile:active { transform: scale(0.98); }
	.admin-tile__icon { font-size: 1.6rem; color: var(--color-primary, #CC0000); }
	.admin-tile__value { font-family: 'Lexend', sans-serif; font-weight: 700; font-size: 1.5rem; }
	.admin-tile__label { color: var(--color-text-soft, #666); font-size: 0.9rem; }
	@media (min-width: 600px) {
		.admin-grid { grid-template-columns: repeat(3, 1fr); }
	}
</style>
