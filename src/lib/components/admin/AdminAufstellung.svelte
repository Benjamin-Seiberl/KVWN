<script>
	import { sb } from '$lib/supabase';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false) } = $props();

	let matches         = $state([]);
	let loading         = $state(true);
	let selectedMatch   = $state(null);
	let loadingLineup   = $state(false);
	let gamePlanId      = $state(null);
	let lineup          = $state([]);       // [{position, player_id, player_name, id}]
	let allPlayers      = $state([]);       // alle aktiven Spieler
	let saving          = $state(false);
	let starterCount    = $state(4);

	const DAY_SHORT = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

	// Nächste 3 Wochen Matches laden
	async function loadMatches() {
		loading = true;
		const now = new Date();
		const threeWeeks = new Date(now);
		threeWeeks.setDate(now.getDate() + 21);

		const { data } = await sb
			.from('matches')
			.select('id, date, time, opponent, home_away, cal_week, league_id, leagues(name)')
			.gte('date', fmt(now))
			.lte('date', fmt(threeWeeks))
			.order('date')
			.order('time');

		matches = data ?? [];
		loading = false;
	}

	function fmt(d) {
		return d.getFullYear() + '-' +
			String(d.getMonth() + 1).padStart(2, '0') + '-' +
			String(d.getDate()).padStart(2, '0');
	}

	function matchLabel(m) {
		const d = new Date(m.date + 'T12:00');
		return `${DAY_SHORT[d.getDay()]} ${d.getDate()}.${d.getMonth() + 1}. – ${m.opponent}`;
	}

	function matchSub(m) {
		return `${m.leagues?.name ?? ''} · ${m.home_away === 'HEIM' ? 'Heim' : 'Auswärts'}`;
	}

	// Match auswählen → bestehende Aufstellung laden oder leer anlegen
	async function selectMatch(m) {
		selectedMatch = m;
		loadingLineup = true;
		starterCount = /bundesliga|landesliga/i.test(m.leagues?.name ?? '') ? 6 : 4;

		// Alle aktiven Spieler laden
		const { data: pl } = await sb
			.from('players')
			.select('id, name, photo, avatar_url')
			.eq('active', true)
			.order('name');
		allPlayers = pl ?? [];

		// Bestehende Aufstellung suchen
		const { data: gp } = await sb
			.from('game_plans')
			.select('id, game_plan_players(id, position, player_id, player_name, players(name, photo))')
			.eq('cal_week', m.cal_week)
			.eq('league_id', m.league_id)
			.maybeSingle();

		gamePlanId = gp?.id ?? null;
		lineup = (gp?.game_plan_players ?? [])
			.sort((a, b) => (a.position ?? 99) - (b.position ?? 99));

		loadingLineup = false;
	}

	// Spieler zum nächsten freien Slot hinzufügen
	async function addPlayer(player) {
		if (lineup.length >= starterCount) return;
		if (lineup.some(l => l.player_id === player.id)) return;

		saving = true;

		// Game-Plan erstellen falls noch keiner existiert
		if (!gamePlanId) {
			const { data: newGp, error } = await sb
				.from('game_plans')
				.insert({ cal_week: selectedMatch.cal_week, league_id: selectedMatch.league_id })
				.select('id')
				.single();
			if (error) { saving = false; return; }
			gamePlanId = newGp.id;
		}

		const pos = lineup.length + 1;
		const { data: row, error } = await sb
			.from('game_plan_players')
			.insert({
				game_plan_id: gamePlanId,
				position: pos,
				player_id: player.id,
				player_name: player.name,
			})
			.select('id, position, player_id, player_name')
			.single();

		if (!error && row) {
			lineup = [...lineup, { ...row, players: player }];
		}
		saving = false;
	}

	// Spieler aus Aufstellung entfernen
	async function removePlayer(entry) {
		saving = true;
		const { error } = await sb.from('game_plan_players').delete().eq('id', entry.id);
		if (!error) {
			lineup = lineup.filter(l => l.id !== entry.id);
			// Positionen neu nummerieren
			for (let i = 0; i < lineup.length; i++) {
				if (lineup[i].position !== i + 1) {
					lineup[i].position = i + 1;
					await sb.from('game_plan_players')
						.update({ position: i + 1 })
						.eq('id', lineup[i].id);
				}
			}
		}
		saving = false;
	}

	// Spieler im Pool, die noch nicht aufgestellt sind
	let availablePlayers = $derived.by(() => {
		const usedIds = new Set(lineup.map(l => l.player_id));
		return allPlayers.filter(p => !usedIds.has(p.id));
	});

	function imgPath(player) {
		const photo = player.photo || player.players?.photo;
		const name = player.name || player.players?.name || player.player_name;
		const key = photo || name;
		return key ? '/images/' + encodeURIComponent(key) + '.jpg' : '';
	}

	function done() {
		open = false;
		setTimeout(() => triggerToast(`Aufstellung: ${lineup.length}/${starterCount} Spieler`), 300);
	}

	function back() {
		selectedMatch = null;
		lineup = [];
		gamePlanId = null;
	}

	$effect(() => {
		if (open) {
			loadMatches();
			selectedMatch = null;
			lineup = [];
			gamePlanId = null;
		}
	});
</script>

<BottomSheet bind:open title={selectedMatch ? 'Aufstellung' : 'Match wählen'}>

	{#if loading}
		<div class="aa-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
		</div>

	{:else if !selectedMatch}
		<!-- Match-Auswahl -->
		{#if matches.length === 0}
			<p class="aa-empty">Keine anstehenden Matches.</p>
		{:else}
			<p class="aa-hint">Wähle ein Match für die Aufstellung.</p>
			<div class="aa-match-list">
				{#each matches as m (m.id)}
					<button class="aa-match-row" onclick={() => selectMatch(m)}>
						<div class="aa-match-info">
							<span class="aa-match-label">{matchLabel(m)}</span>
							<span class="aa-match-sub">{matchSub(m)}</span>
						</div>
						<span class="material-symbols-outlined aa-chevron">chevron_right</span>
					</button>
				{/each}
			</div>
		{/if}

	{:else}
		<!-- Zurück -->
		<button class="aa-back" onclick={back}>
			<span class="material-symbols-outlined">arrow_back</span>
			Zurück
		</button>

		<!-- Match-Info -->
		<div class="aa-match-hero">
			<span class="aa-match-hero-label">{matchLabel(selectedMatch)}</span>
			<span class="aa-match-hero-sub">{matchSub(selectedMatch)} · {starterCount} Starter</span>
		</div>

		{#if loadingLineup}
			<div class="aa-loading">
				<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			</div>
		{:else}
			<!-- Aktuelle Aufstellung -->
			<p class="aa-section-title">Aufstellung ({lineup.length}/{starterCount})</p>
			<div class="aa-lineup">
				{#each Array(starterCount) as _, i}
					{@const entry = lineup[i]}
					{#if entry}
						{@const name = entry.players?.name ?? entry.player_name ?? '–'}
						<button class="aa-slot aa-slot--filled" onclick={() => removePlayer(entry)} disabled={saving}>
							<span class="aa-slot-pos">{i + 1}</span>
							<div class="aa-slot-avatar">
								<img
									src={imgPath(entry)}
									alt={name}
									onerror={(e) => { e.currentTarget.style.display = 'none'; }}
								/>
								<span class="aa-slot-initial">{name.slice(0, 1)}</span>
							</div>
							<span class="aa-slot-name">{name}</span>
							<span class="material-symbols-outlined aa-slot-remove">close</span>
						</button>
					{:else}
						<div class="aa-slot aa-slot--empty">
							<span class="aa-slot-pos">{i + 1}</span>
							<div class="aa-slot-avatar aa-slot-avatar--empty">
								<span class="material-symbols-outlined">person_add</span>
							</div>
							<span class="aa-slot-name aa-slot-name--empty">Offen</span>
						</div>
					{/if}
				{/each}
			</div>

			<!-- Spieler-Pool -->
			<p class="aa-section-title" style="margin-top: var(--space-4);">Verfügbare Spieler ({availablePlayers.length})</p>
			<div class="aa-pool">
				{#each availablePlayers as p (p.id)}
					<button
						class="aa-pool-player"
						onclick={() => addPlayer(p)}
						disabled={saving || lineup.length >= starterCount}
					>
						<div class="aa-pool-avatar">
							<img
								src={imgPath(p)}
								alt={p.name}
								onerror={(e) => { e.currentTarget.style.display = 'none'; }}
							/>
							<span class="aa-pool-initial">{(p.name || '?').slice(0, 1)}</span>
						</div>
						<span class="aa-pool-name">{p.name}</span>
					</button>
				{/each}
			</div>

			<!-- Fertig -->
			<button class="mw-btn mw-btn--primary mw-btn--wide aa-done" onclick={done}>
				<span class="material-symbols-outlined">check</span>
				Fertig
			</button>
		{/if}
	{/if}

</BottomSheet>

<style>
	/* Shared */
	.aa-loading { display: flex; flex-direction: column; gap: var(--space-2); }
	.aa-empty, .aa-hint {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		margin: 0 0 var(--space-3);
	}

	/* Match list */
	.aa-match-list { display: flex; flex-direction: column; gap: var(--space-2); }
	.aa-match-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: none; cursor: pointer; text-align: left; width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-match-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
	.aa-match-label { font-weight: 600; font-size: var(--text-body-md); color: var(--color-on-surface); }
	.aa-match-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
	.aa-chevron { font-size: 1.2rem; color: var(--color-outline); }

	/* Back */
	.aa-back {
		display: inline-flex; align-items: center; gap: var(--space-1);
		border: none; background: none;
		font-size: var(--text-body-sm); font-weight: 600;
		color: var(--color-primary); cursor: pointer; padding: 0;
		margin-bottom: var(--space-3);
		-webkit-tap-highlight-color: transparent;
	}
	.aa-back .material-symbols-outlined { font-size: 1.1rem; }

	/* Match hero */
	.aa-match-hero {
		display: flex; flex-direction: column; gap: 2px;
		margin-bottom: var(--space-4);
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--color-outline-variant);
	}
	.aa-match-hero-label {
		font-family: var(--font-display); font-weight: 700;
		font-size: var(--text-title-sm); color: var(--color-on-surface);
	}
	.aa-match-hero-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }

	/* Section title */
	.aa-section-title {
		font-size: var(--text-label-sm); font-weight: 700;
		letter-spacing: 0.07em; text-transform: uppercase;
		color: var(--color-outline); margin: 0 0 var(--space-2);
	}

	/* Lineup slots */
	.aa-lineup { display: flex; flex-direction: column; gap: var(--space-2); }
	.aa-slot {
		display: grid;
		grid-template-columns: 28px 36px 1fr 24px;
		gap: var(--space-2); align-items: center;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		border: 1.5px solid transparent;
	}
	.aa-slot--filled {
		background: var(--color-surface-container-low);
		border-color: var(--color-outline-variant);
		cursor: pointer; width: 100%; text-align: left;
		-webkit-tap-highlight-color: transparent;
	}
	.aa-slot--empty {
		background: var(--color-surface-container-low);
		border: 1.5px dashed var(--color-outline-variant);
		opacity: 0.55;
	}

	.aa-slot-pos {
		font-weight: 800; color: var(--color-primary);
		text-align: center; font-size: var(--text-body-sm);
	}
	.aa-slot-avatar {
		width: 36px; height: 36px; border-radius: 50%;
		overflow: hidden; background: var(--color-surface-container-highest);
		display: grid; place-items: center; position: relative;
	}
	.aa-slot-avatar img {
		width: 100%; height: 100%; object-fit: cover;
		position: absolute; inset: 0;
	}
	.aa-slot-initial {
		font-weight: 700; font-size: var(--text-body-sm);
		color: var(--color-outline);
	}
	.aa-slot-avatar--empty {
		background: none;
	}
	.aa-slot-avatar--empty .material-symbols-outlined {
		font-size: 1.3rem; color: var(--color-outline);
	}
	.aa-slot-name {
		font-weight: 600; font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
	}
	.aa-slot-name--empty { color: var(--color-outline); font-weight: 500; }
	.aa-slot-remove {
		font-size: 1rem; color: var(--color-outline);
		transition: color 0.15s;
	}
	.aa-slot--filled:active .aa-slot-remove { color: var(--color-primary); }

	/* Player pool */
	.aa-pool {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
		gap: var(--space-2);
		margin-bottom: var(--space-4);
	}
	.aa-pool-player {
		display: flex; align-items: center; gap: var(--space-2);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-outline-variant);
		cursor: pointer; text-align: left;
		-webkit-tap-highlight-color: transparent;
		transition: background 0.15s;
	}
	.aa-pool-player:active { background: var(--color-surface-container); }
	.aa-pool-player:disabled { opacity: 0.4; pointer-events: none; }

	.aa-pool-avatar {
		width: 28px; height: 28px; border-radius: 50%;
		overflow: hidden; background: var(--color-surface-container-highest);
		display: grid; place-items: center; flex-shrink: 0;
		position: relative;
	}
	.aa-pool-avatar img {
		width: 100%; height: 100%; object-fit: cover;
		position: absolute; inset: 0;
	}
	.aa-pool-initial {
		font-weight: 700; font-size: 0.7rem; color: var(--color-outline);
	}
	.aa-pool-name {
		font-size: var(--text-body-sm); font-weight: 600;
		color: var(--color-on-surface);
		white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
	}

	/* Done */
	.aa-done { margin-top: var(--space-2); }
</style>
