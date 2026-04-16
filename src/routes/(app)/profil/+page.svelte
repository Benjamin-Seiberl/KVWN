<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, signOut, playerRole } from '$lib/stores/auth';
	import { currentSubtab } from '$lib/stores/subtab.js';
	import { registerPush, unregisterPush, pushStatus } from '$lib/push/register.js';
	import AdminRollen from '$lib/components/admin/AdminRollen.svelte';
	import AdminTraining from '$lib/components/admin/AdminTraining.svelte';
	import AdminErgebnis from '$lib/components/admin/AdminErgebnis.svelte';
	import AdminAufstellung from '$lib/components/admin/AdminAufstellung.svelte';

	// ── Active Tab ──────────────────────────────────────────
	// Fall back to meine-daten if admin tab is active but user is no longer admin
	let activeTab = $derived.by(() => {
		const t = $currentSubtab;
		if (t === 'admin' && $playerRole !== 'kapitaen') return 'meine-daten';
		return t ?? 'meine-daten';
	});

	// ── State ────────────────────────────────────────────────
	let me          = $state(null);
	let uploading   = $state(false);
	let msg         = $state('');
	let pushOn      = $state(false);
	let nextMatch   = $state(null);
	let events      = $state([]);
	let rsvps       = $state([]);   // { event_id, response }[]
	let myStats     = $state(null); // { avg, avg5, best, gamesPlayed, rank }
	let milestones  = $state([]);

	const MONTHS = ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
	const DAYS   = ['So','Mo','Di','Mi','Do','Fr','Sa'];

	// ── Bug-Fix: reaktiv wenn $playerId verfügbar wird ──────
	$effect(() => {
		if ($playerId) load();
	});

	async function load() {
		const pid = $playerId;
		if (!pid) return;

		const today = new Date().toISOString().slice(0, 10);

		const [
			{ data: playerData },
			{ data: matchData },
			{ data: eventData },
			{ data: rsvpData },
			{ data: scoreData },
			{ data: allPlayers },
		] = await Promise.all([
			sb.from('players')
				.select('id, name, email, phone, avatar_url, photo, push_prefs, role, shirt_size, pants_size')
				.eq('id', pid).maybeSingle(),
			// Nächstes Match
			sb.from('matches')
				.select('id, date, time, opponent, home_away, leagues(name)')
				.gte('date', today)
				.order('date', { ascending: true })
				.limit(1)
				.maybeSingle(),
			// Kommende Events
			sb.from('events')
				.select('id, title, date, time, location, description')
				.gte('date', today)
				.order('date', { ascending: true })
				.limit(6),
			// Meine RSVPs
			sb.from('event_rsvps')
				.select('event_id, response')
				.eq('player_id', pid),
			// Meine Spielergebnisse
			sb.from('game_plan_players')
				.select('score, game_plans!inner(cal_week)')
				.eq('player_id', pid)
				.eq('played', true)
				.not('score', 'is', null)
				.order('cal_week', { referencedTable: 'game_plans', ascending: false }),
			// Alle Spieler für Rang-Berechnung
			sb.from('game_plan_players')
				.select('player_id, score')
				.eq('played', true)
				.not('score', 'is', null),
		]);

		me      = playerData;
		nextMatch = matchData;
		events  = eventData ?? [];
		rsvps   = rsvpData ?? [];
		pushOn  = await pushStatus();

		// Stats berechnen
		const myScores = (scoreData ?? []).map(g => Number(g.score));
		if (myScores.length) {
			// Rang: alle Spieler Schnitt berechnen
			const playerAvgs = {};
			for (const g of allPlayers ?? []) {
				if (!playerAvgs[g.player_id]) playerAvgs[g.player_id] = [];
				playerAvgs[g.player_id].push(Number(g.score));
			}
			const avgOf = (arr) => arr.length ? Math.round(arr.reduce((a,b) => a+b, 0) / arr.length) : 0;
			const sorted = Object.entries(playerAvgs).sort((a, b) => avgOf(b[1]) - avgOf(a[1]));
			const rank = sorted.findIndex(([id]) => id === pid) + 1;
			const avg  = avgOf(myScores);
			const avg5 = avgOf(myScores.slice(0, 5));
			const best = Math.max(...myScores);
			myStats = { avg, avg5, best, gamesPlayed: myScores.length, rank };
			milestones = calcMilestones(myScores, myScores.length, me);
		}
	}

	// ── Milestones ──────────────────────────────────────────
	function calcMilestones(scores, gamesPlayed) {
		const ms = [];
		if (gamesPlayed >= 1)   ms.push({ icon: 'sports_score',      label: 'Erstes Vereinsspiel',           sub: `${gamesPlayed} Spiele bisher` });
		if (gamesPlayed >= 10)  ms.push({ icon: 'military_tech',      label: '10 Spiele',                     sub: 'Meilenstein erreicht' });
		if (gamesPlayed >= 25)  ms.push({ icon: 'military_tech',      label: '25 Spiele',                     sub: 'Meilenstein erreicht' });
		if (gamesPlayed >= 50)  ms.push({ icon: 'emoji_events',       label: '50 Spiele',                     sub: 'Halbes Hunderter!' });
		if (gamesPlayed >= 100) ms.push({ icon: 'workspace_premium',  label: '100 Spiele',                    sub: 'Jahrhundert-Marke!' });
		if (gamesPlayed >= 150) ms.push({ icon: 'grade',              label: '150 Spiele',                    sub: 'Legende!' });
		const best = Math.max(...scores);
		if (best >= 500) ms.push({ icon: 'star',                       label: '500+ Holz',                    sub: `Bestleistung: ${best}` });
		if (best >= 550) ms.push({ icon: 'stars',                      label: '550+ Holz',                    sub: `Bestleistung: ${best}` });
		if (best >= 600) ms.push({ icon: 'diamond',                    label: '600+ Holz',                    sub: `Bestleistung: ${best}` });
		const avg = Math.round(scores.reduce((a,b) => a+b,0) / scores.length);
		if (avg >= 500) ms.push({ icon: 'trending_up',                 label: 'Ø 500+',                       sub: `Durchschnitt: ${avg}` });
		return ms.reverse();
	}

	// ── RSVP ────────────────────────────────────────────────
	function myRsvp(eventId) {
		return rsvps.find(r => r.event_id === eventId)?.response ?? null;
	}

	async function rsvp(eventId, response) {
		const pid = $playerId;
		if (!pid) return;
		const existing = myRsvp(eventId);
		if (existing === response) {
			await sb.from('event_rsvps').delete().eq('event_id', eventId).eq('player_id', pid);
			rsvps = rsvps.filter(r => r.event_id !== eventId);
		} else {
			await sb.from('event_rsvps').upsert({ event_id: eventId, player_id: pid, response });
			rsvps = [...rsvps.filter(r => r.event_id !== eventId), { event_id: eventId, response }];
		}
	}

	// ── Profil speichern ────────────────────────────────────
	async function save() {
		msg = '';
		const { error } = await sb.from('players').update({
			name:       me.name,
			phone:      me.phone,
			push_prefs: me.push_prefs,
			shirt_size: me.shirt_size,
			pants_size: me.pants_size,
		}).eq('id', me.id);
		msg = error ? `❌ ${error.message}` : '✅ Gespeichert';
	}

	async function uploadAvatar(e) {
		const file = e.target.files?.[0];
		if (!file) return;
		uploading = true; msg = '';
		const ext = file.name.split('.').pop();
		const path = `${me.id}/${Date.now()}.${ext}`;
		const { error: upErr } = await sb.storage.from('avatars').upload(path, file, { upsert: true });
		if (upErr) { msg = `❌ ${upErr.message}`; uploading = false; return; }
		const { data } = sb.storage.from('avatars').getPublicUrl(path);
		const url = data.publicUrl;
		const { error } = await sb.from('players').update({ avatar_url: url }).eq('id', me.id);
		uploading = false;
		if (error) msg = `❌ ${error.message}`;
		else { me.avatar_url = url; msg = '✅ Foto aktualisiert'; }
	}

	async function togglePush() {
		try {
			if (pushOn) { await unregisterPush(); pushOn = false; }
			else        { await registerPush($playerId); pushOn = true; }
		} catch (e) { msg = `❌ ${e.message}`; }
	}

	function updatePref(key, val) {
		me.push_prefs = { ...(me.push_prefs || {}), [key]: val };
	}

	// ── Datum-Hilfsfunktionen ───────────────────────────────
	function daysUntil(dateStr) {
		const today = new Date(); today.setHours(0,0,0,0);
		const d     = new Date(dateStr + 'T00:00:00');
		const diff  = Math.round((d - today) / 86400000);
		if (diff === 0) return 'Heute';
		if (diff === 1) return 'Morgen';
		if (diff === 2) return 'Übermorgen';
		return `In ${diff} Tagen`;
	}

	function fmtDate(dateStr) {
		const d = new Date(dateStr + 'T00:00:00');
		return `${DAYS[d.getDay()]}, ${d.getDate()}. ${MONTHS[d.getMonth()]}`;
	}

	// ── Admin: Sheet-State ──────────────────────────────────
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
				{ icon: 'event',         label: 'Training verwalten',    live: true, open: () => trainingOpen = true },
				{ icon: 'how_to_reg',    label: 'Anwesenheit erfassen' },
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
				{ icon: 'bar_chart',     label: 'Saisonstatistik' },
				{ icon: 'download',      label: 'Export (CSV)' },
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

<div class="profil-page">

	{#if !me}
		<!-- Loading state -->
		<div class="profil-loading">
			<div class="skeleton-card animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
		</div>
	{:else}

	<!-- ════════════════════════════════════════════════════ -->
	<!-- TAB: MEINE DATEN                                     -->
	<!-- ════════════════════════════════════════════════════ -->
	{#if activeTab === 'meine-daten'}

		<!-- 1) Performance -->
		{#if myStats}
		{@const formDiff = myStats.avg5 - myStats.avg}
		<section class="perf-card">
			<!-- Header -->
			<div class="perf-header">
				<span class="perf-eyebrow">Meine Performance</span>
				<span class="perf-games">{myStats.gamesPlayed} Spiele</span>
			</div>

			<!-- Hero: Saison-Schnitt -->
			<div class="perf-hero">
				<span class="material-symbols-outlined perf-trophy">emoji_events</span>
				<div class="perf-avg-value">{myStats.avg}</div>
				<div class="perf-avg-label">Saison-Schnitt</div>
			</div>

			<!-- Divider -->
			<div class="perf-divider"></div>

			<!-- Supporting stats -->
			<div class="perf-stats-row">
				<div class="perf-stat">
					<span class="perf-stat-value">#{myStats.rank}</span>
					<span class="perf-stat-label">Vereinsrang</span>
				</div>
				<div class="perf-stat-sep"></div>
				<div class="perf-stat">
					<span class="perf-stat-value perf-stat-form">
						{myStats.avg5}
						{#if formDiff > 0}
							<span class="perf-trend perf-trend--up">+{formDiff}</span>
						{:else if formDiff < 0}
							<span class="perf-trend perf-trend--dn">{formDiff}</span>
						{/if}
					</span>
					<span class="perf-stat-label">Form Ø5</span>
				</div>
				<div class="perf-stat-sep"></div>
				<div class="perf-stat">
					<span class="perf-stat-value">{myStats.best}</span>
					<span class="perf-stat-label">Rekord</span>
				</div>
			</div>
		</section>
		{/if}

		<!-- 2) Nächstes Spiel -->
		{#if nextMatch}
		{@const badge = daysUntil(nextMatch.date)}
		<section class="next-match-card">
			<div class="next-match-head">
				<h3 class="section-title">
					<span class="material-symbols-outlined">emoji_events</span>
					Nächstes Spiel
				</h3>
				<span class="days-badge" class:days-badge--urgent={badge === 'Heute' || badge === 'Morgen'}>{badge}</span>
			</div>
			<div class="next-match-body">
				<div class="next-match-info">
					<div>
						<p class="match-meta-label">Gegner / Liga</p>
						<h4 class="match-opponent">{nextMatch.opponent}</h4>
						<p class="match-league">{nextMatch.leagues?.name ?? ''} · {nextMatch.home_away === 'HEIM' ? 'Heimspiel' : 'Auswärts'}</p>
					</div>
					<div class="match-date-block">
						<p class="match-meta-label">Termin</p>
						<p class="match-date">{fmtDate(nextMatch.date)}</p>
						{#if nextMatch.time}
							<p class="match-time">{String(nextMatch.time).slice(0,5)} Uhr</p>
						{/if}
					</div>
				</div>
				<a href="/spielbetrieb" class="match-link-row">
					<div class="match-link-icon">
						<span class="material-symbols-outlined">sports_score</span>
					</div>
					<div class="match-link-text">
						<p class="match-meta-label">Spielbetrieb</p>
						<p class="match-link-label">Aufstellung &amp; Treffpunkt ansehen</p>
					</div>
					<span class="material-symbols-outlined match-link-arrow">open_in_new</span>
				</a>
			</div>
		</section>
		{/if}

		<!-- 3) Meine Infos (royal) -->
		<section class="profil-card">
			<!-- Gradient header mit großem Avatar -->
			<div class="profil-card-hero">
				<div class="profil-avatar-ring">
					<div class="profil-avatar">
						{#if me.avatar_url || me.photo}
							<img src={me.avatar_url || me.photo} alt={me.name} />
						{:else}
							<span>{(me.name || '?').slice(0,1).toUpperCase()}</span>
						{/if}
					</div>
				</div>
				<label class="profil-photo-btn">
					<input type="file" accept="image/*" onchange={uploadAvatar} hidden />
					<span class="material-symbols-outlined">photo_camera</span>
				</label>
			</div>

			<!-- Name + E-Mail -->
			<div class="profil-card-identity">
				<h2 class="profil-card-name">{me.name}</h2>
				<p class="profil-card-email">{me.email}</p>
				<div class="profil-card-gold-line"></div>
			</div>

			<!-- Felder -->
			<div class="profil-card-fields">
				<label class="field">
					<span>Name</span>
					<input type="text" bind:value={me.name} />
				</label>
				<label class="field">
					<span>Telefon</span>
					<input type="tel" bind:value={me.phone} placeholder="+43 …" />
				</label>
				<div class="fields-row">
					<label class="field">
						<span>Trikotgröße</span>
						<select bind:value={me.shirt_size}>
							<option value="">–</option>
							{#each ['XS','S','M','L','XL','XXL','XXXL'] as s}
								<option value={s}>{s}</option>
							{/each}
						</select>
					</label>
					<label class="field">
						<span>Hosengröße</span>
						<input type="text" bind:value={me.pants_size} placeholder="z.B. 32/32" />
					</label>
				</div>
			</div>

			<!-- Speichern -->
			<div class="profil-card-actions">
				<button class="btn btn--primary" onclick={save}>
					<span class="material-symbols-outlined">check</span> Speichern
				</button>
				{#if msg}<p class="msg">{msg}</p>{/if}
			</div>
		</section>

		<!-- 4) Vereinstermine Agenda -->
		{#if events.length}
		<section class="card">
			<h2 class="section-title">
				<span class="material-symbols-outlined">event</span>
				Vereinstermine
			</h2>
			<div class="agenda">
				{#each events as ev}
				{@const d = new Date(ev.date + 'T00:00:00')}
				{@const myR = myRsvp(ev.id)}
				<div class="agenda-item">
					<div class="agenda-date-col">
						<span class="agenda-day">{d.getDate()}</span>
						<span class="agenda-month">{MONTHS[d.getMonth()]}</span>
					</div>
					<div class="agenda-info">
						<p class="agenda-title">{ev.title}</p>
						{#if ev.time || ev.location}
							<p class="agenda-sub">
								{#if ev.time}{String(ev.time).slice(0,5)} Uhr{/if}
								{#if ev.time && ev.location} · {/if}
								{#if ev.location}{ev.location}{/if}
							</p>
						{/if}
					</div>
					<div class="agenda-rsvp">
						<button
							class="rsvp-btn rsvp-btn--yes"
							class:active={myR === 'yes'}
							onclick={() => rsvp(ev.id, 'yes')}
							aria-label="Zusagen"
						>
							<span class="material-symbols-outlined">check</span>
						</button>
						<button
							class="rsvp-btn rsvp-btn--no"
							class:active={myR === 'no'}
							onclick={() => rsvp(ev.id, 'no')}
							aria-label="Absagen"
						>
							<span class="material-symbols-outlined">close</span>
						</button>
					</div>
				</div>
				{/each}
			</div>
		</section>
		{/if}

		<!-- E) Karriere-Meilensteine -->
		{#if milestones.length}
		<section class="milestones">
			<h2 class="section-title">
				<span class="material-symbols-outlined">workspace_premium</span>
				Karriere-Meilensteine
			</h2>
			<div class="milestones-scroll">
				{#each milestones as m}
				<div class="milestone-card">
					<span class="milestone-icon material-symbols-outlined">{m.icon}</span>
					<p class="milestone-label">{m.label}</p>
					<p class="milestone-sub">{m.sub}</p>
				</div>
				{/each}
			</div>
		</section>
		{/if}

	<!-- ════════════════════════════════════════════════════ -->
	<!-- TAB: EINSTELLUNGEN                                   -->
	<!-- ════════════════════════════════════════════════════ -->
	{:else if activeTab === 'einstellungen'}

		<!-- F) Benachrichtigungen -->
		<section class="card">
			<h2 class="section-title">
				<span class="material-symbols-outlined">notifications</span>
				Benachrichtigungen
			</h2>
			<button class="btn btn--outline btn--push" onclick={togglePush}>
				<span class="material-symbols-outlined">{pushOn ? 'notifications_active' : 'notifications_off'}</span>
				{pushOn ? 'Push deaktivieren' : 'Push aktivieren'}
			</button>
			<div class="prefs">
				{#each [
					{ k: 'lineup',  label: 'Aufstellung' },
					{ k: 'meetup',  label: 'Treffpunkt'  },
					{ k: 'news',    label: 'News'        },
					{ k: 'poll',    label: 'Umfragen'    },
				] as p}
					<label class="toggle">
						<span>{p.label}</span>
						<input
							type="checkbox"
							checked={me.push_prefs?.[p.k] ?? true}
							onchange={(e) => updatePref(p.k, e.target.checked)}
						/>
					</label>
				{/each}
			</div>
		</section>

		<!-- G) Abwesenheiten (Placeholder) -->
		<section class="card placeholder-section">
			<h2 class="section-title">
				<span class="material-symbols-outlined">event_busy</span>
				Abwesenheiten
			</h2>
			<p class="placeholder-hint">Demnächst: Abwesenheiten für Spieltermine melden, damit der Kapitän bei der Aufstellung Bescheid weiß.</p>
		</section>

		<!-- H) Offene Aktionen (Placeholder) -->
		<section class="card placeholder-section">
			<h2 class="section-title">
				<span class="material-symbols-outlined">pending_actions</span>
				Offene Aktionen
			</h2>
			<p class="placeholder-hint">Hier erscheinen bald Aktionen wie die Bestätigung zur Jahreshauptversammlung oder Abstimmungen zum Vereinsdress.</p>
		</section>

		<!-- Abmelden -->
		<button class="btn btn--ghost btn--logout" onclick={signOut}>
			<span class="material-symbols-outlined">logout</span> Abmelden
		</button>

	<!-- ════════════════════════════════════════════════════ -->
	<!-- TAB: ADMIN                                           -->
	<!-- ════════════════════════════════════════════════════ -->
	{:else if activeTab === 'admin' && $playerRole === 'kapitaen'}

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

	{/if}
	<!-- end tab conditionals -->

	{/if}<!-- end {#if me} -->
</div>

<!-- Admin Bottom Sheets (außerhalb des Layout-Flows) -->
{#if $playerRole === 'kapitaen'}
	<AdminRollen bind:open={rollenOpen} />
	<AdminTraining bind:open={trainingOpen} />
	<AdminErgebnis bind:open={ergebnisOpen} />
	<AdminAufstellung bind:open={aufstellungOpen} />
{/if}

<style>
/* ── Seiten-Wrapper ─────────────────────────────────── */
.profil-page {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
	padding: var(--space-5);
}

.profil-loading {
	display: flex;
	flex-direction: column;
	gap: var(--space-4);
}

/* ── Sektion-Titel ──────────────────────────────────── */
.section-title {
	display: flex;
	gap: var(--space-2);
	align-items: center;
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 0.875rem;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	color: var(--color-primary);
	margin: 0;
}

.section-title .material-symbols-outlined {
	font-size: 1rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

/* ── Karte (universal) ──────────────────────────────── */
.card {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

/* ── Avatar-Row ─────────────────────────────────────── */
.avatar-row {
	display: flex;
	gap: var(--space-4);
	align-items: center;
}

.avatar {
	width: 80px;
	height: 80px;
	border-radius: 50%;
	overflow: hidden;
	background: var(--color-surface-container);
	display: grid;
	place-items: center;
	font-family: var(--font-display);
	font-size: 2rem;
	font-weight: 800;
	color: var(--color-on-surface-variant);
	border: 3px solid var(--color-secondary);
	flex-shrink: 0;
}

.avatar img { width: 100%; height: 100%; object-fit: cover; }

.avatar-meta { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.avatar-name { font-family: var(--font-display); font-weight: 700; font-size: 1rem; color: var(--color-on-surface); margin: 0; }
.avatar-email { font-size: 0.8rem; color: var(--color-on-surface-variant); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.upload {
	display: inline-flex;
	gap: 4px;
	align-items: center;
	padding: 6px 12px;
	border: 1px solid var(--color-outline-variant);
	background: transparent;
	border-radius: 999px;
	font-size: 0.82rem;
	cursor: pointer;
	margin-top: 4px;
	color: var(--color-on-surface-variant);
	width: fit-content;
}

.upload .material-symbols-outlined { font-size: 1rem; }

/* ── Felder ─────────────────────────────────────────── */
.fields-grid { display: flex; flex-direction: column; gap: var(--space-2); }
.fields-row  { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); }

.field {
	display: flex;
	flex-direction: column;
	gap: 3px;
	font-size: 0.82rem;
	font-weight: 600;
	color: var(--color-on-surface-variant);
}

.field input,
.field select {
	padding: 10px 12px;
	border: 1px solid var(--color-outline-variant);
	border-radius: 10px;
	font-size: 15px;
	background: var(--color-surface-container-lowest);
	color: var(--color-on-surface);
	font-family: inherit;
}

.field input:disabled { background: var(--color-surface-container-low); color: var(--color-on-surface-variant); }
.field input:focus,
.field select:focus { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }

/* ── Buttons ────────────────────────────────────────── */
.btn {
	display: inline-flex;
	gap: var(--space-2);
	align-items: center;
	justify-content: center;
	padding: 10px 20px;
	border: 0;
	border-radius: 999px;
	font-size: 0.9rem;
	font-weight: 600;
	font-family: inherit;
	cursor: pointer;
	-webkit-tap-highlight-color: transparent;
}

.btn--primary  { background: var(--color-primary); color: #fff; align-self: flex-start; }
.btn--outline  { background: transparent; border: 1.5px solid var(--color-outline-variant); color: var(--color-on-surface-variant); }
.btn--push     { width: 100%; }
.btn--ghost    { background: none; border: 1px solid var(--color-outline-variant); color: var(--color-on-surface-variant); }
.btn--logout   { align-self: center; margin-top: var(--space-2); }
.btn:active    { opacity: 0.75; transform: scale(0.98); }

.msg { margin: 0; font-size: 0.88rem; color: var(--color-on-surface-variant); }

/* ── Performance Card ───────────────────────────────── */
.perf-card {
	background: linear-gradient(160deg, #1a0000 0%, #3d0000 40%, #6b0000 100%);
	border-radius: 20px;
	overflow: hidden;
	box-shadow: 0 8px 32px rgba(204, 0, 0, 0.28);
}

.perf-header {
	display: flex;
	justify-content: space-between;
	align-items: center;
	padding: var(--space-4) var(--space-5) 0;
}

.perf-eyebrow {
	font-family: var(--font-display);
	font-size: 0.7rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.14em;
	color: rgba(212, 175, 55, 0.9);
}

.perf-games {
	font-size: 0.72rem;
	font-weight: 700;
	color: rgba(255, 255, 255, 0.45);
	letter-spacing: 0.04em;
}

.perf-hero {
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: var(--space-5) var(--space-5) var(--space-4);
	gap: var(--space-1);
}

.perf-trophy {
	font-size: 2rem;
	color: var(--color-secondary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 48;
	margin-bottom: var(--space-1);
	filter: drop-shadow(0 0 12px rgba(212,175,55,0.6));
}

.perf-avg-value {
	font-family: var(--font-display);
	font-size: 4rem;
	font-weight: 900;
	color: #fff;
	line-height: 1;
	letter-spacing: -0.02em;
	text-shadow: 0 2px 16px rgba(0,0,0,0.4);
}

.perf-avg-label {
	font-size: 0.78rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255,255,255,0.5);
}

.perf-divider {
	height: 1px;
	background: linear-gradient(90deg, transparent, rgba(212,175,55,0.35), transparent);
	margin: 0 var(--space-5);
}

.perf-stats-row {
	display: flex;
	align-items: stretch;
	padding: var(--space-4) var(--space-5);
	gap: 0;
}

.perf-stat {
	flex: 1;
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 3px;
}

.perf-stat-sep {
	width: 1px;
	background: rgba(255,255,255,0.12);
	margin: 0 var(--space-2);
	align-self: stretch;
}

.perf-stat-value {
	font-family: var(--font-display);
	font-size: 1.45rem;
	font-weight: 900;
	color: #fff;
	line-height: 1;
	display: flex;
	align-items: baseline;
	gap: 4px;
}

.perf-stat-form { /* override color for form when same */
	color: #fff;
}

.perf-trend {
	font-family: var(--font-display);
	font-size: 0.72rem;
	font-weight: 800;
	padding: 1px 5px;
	border-radius: 999px;
}

.perf-trend--up {
	color: #4ade80;
	background: rgba(74, 222, 128, 0.15);
}

.perf-trend--dn {
	color: #f87171;
	background: rgba(248, 113, 113, 0.15);
}

.perf-stat-label {
	font-size: 0.65rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.1em;
	color: rgba(255,255,255,0.4);
}

/* ── Profil-Karte (royal) ───────────────────────────── */
.profil-card {
	background: var(--color-surface-container-lowest);
	border-radius: 20px;
	overflow: hidden;
	border: 1px solid var(--color-surface-container);
	box-shadow: 0 4px 24px rgba(0,0,0,0.06);
}

.profil-card-hero {
	position: relative;
	background: linear-gradient(160deg, #1a0000 0%, #850000 100%);
	height: 88px;
	display: flex;
	justify-content: center;
}

.profil-avatar-ring {
	position: absolute;
	bottom: -36px;
	width: 84px;
	height: 84px;
	border-radius: 50%;
	padding: 3px;
	background: linear-gradient(135deg, var(--color-secondary), #a07c20);
	box-shadow: 0 4px 20px rgba(0,0,0,0.3);
}

.profil-avatar {
	width: 100%;
	height: 100%;
	border-radius: 50%;
	overflow: hidden;
	background: var(--color-surface-container);
	display: grid;
	place-items: center;
	font-family: var(--font-display);
	font-size: 2.2rem;
	font-weight: 900;
	color: var(--color-primary);
	border: 3px solid var(--color-surface-container-lowest);
}

.profil-avatar img { width: 100%; height: 100%; object-fit: cover; }

.profil-photo-btn {
	position: absolute;
	bottom: -28px;
	left: calc(50% + 26px);
	width: 32px;
	height: 32px;
	border-radius: 50%;
	background: var(--color-surface-container-lowest);
	border: 1.5px solid var(--color-outline-variant);
	display: grid;
	place-items: center;
	cursor: pointer;
	box-shadow: 0 2px 8px rgba(0,0,0,0.12);
	transition: background 120ms;
}

.profil-photo-btn:active { background: var(--color-surface-container); }

.profil-photo-btn .material-symbols-outlined {
	font-size: 1rem;
	color: var(--color-on-surface-variant);
}

.profil-card-identity {
	display: flex;
	flex-direction: column;
	align-items: center;
	padding: calc(36px + var(--space-4)) var(--space-5) var(--space-4);
	text-align: center;
	gap: var(--space-1);
}

.profil-card-name {
	font-family: var(--font-display);
	font-size: 1.35rem;
	font-weight: 900;
	color: var(--color-on-surface);
	margin: 0;
	letter-spacing: -0.01em;
}

.profil-card-email {
	font-size: 0.8rem;
	color: var(--color-on-surface-variant);
	margin: 0;
}

.profil-card-gold-line {
	width: 40px;
	height: 2px;
	border-radius: 999px;
	background: linear-gradient(90deg, var(--color-secondary), #a07c20);
	margin-top: var(--space-2);
}

.profil-card-fields {
	padding: 0 var(--space-4) var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.profil-card-actions {
	padding: var(--space-3) var(--space-4) var(--space-4);
	border-top: 1px solid var(--color-surface-container);
	display: flex;
	flex-direction: column;
	gap: var(--space-2);
}

/* keep old stats classes for milestone/etc sections that still use them */
.trend-up { font-size: 0.7rem; color: #16a34a; }
.trend-dn { font-size: 0.7rem; color: var(--color-error); }

/* ── Nächstes Spiel ─────────────────────────────────── */
.next-match-card {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-left: 4px solid var(--color-primary);
	border-radius: 16px;
	overflow: hidden;
	display: flex;
	flex-direction: column;
}

.next-match-head {
	display: flex;
	align-items: center;
	justify-content: space-between;
	padding: var(--space-4) var(--space-4) var(--space-2);
}

.days-badge {
	font-size: 0.72rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.08em;
	padding: 3px 10px;
	border-radius: 999px;
	background: var(--color-surface-container);
	color: var(--color-on-surface-variant);
}

.days-badge--urgent {
	background: var(--color-primary);
	color: #fff;
}

.next-match-body {
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
	padding: var(--space-2) var(--space-4) var(--space-4);
}

.next-match-info {
	display: flex;
	justify-content: space-between;
	align-items: flex-start;
	gap: var(--space-3);
}

.match-meta-label {
	font-size: 0.68rem;
	font-weight: 800;
	text-transform: uppercase;
	letter-spacing: 0.12em;
	color: var(--color-on-surface-variant);
	margin: 0 0 3px;
}

.match-opponent {
	font-family: var(--font-display);
	font-weight: 900;
	font-size: 1.15rem;
	color: var(--color-on-surface);
	margin: 0;
	line-height: 1.1;
}

.match-league {
	font-size: 0.78rem;
	font-weight: 600;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
	text-transform: uppercase;
	letter-spacing: 0.04em;
}

.match-date-block { text-align: right; flex-shrink: 0; }

.match-date {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
}

.match-time {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.95rem;
	color: var(--color-primary);
	margin: 2px 0 0;
}

.match-link-row {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3);
	background: rgba(204,0,0,0.06);
	border-radius: 12px;
	text-decoration: none;
	border: 1px solid rgba(204,0,0,0.1);
	transition: background 150ms;
}

.match-link-row:active { background: rgba(204,0,0,0.12); }

.match-link-icon {
	width: 36px;
	height: 36px;
	border-radius: 10px;
	background: var(--color-primary);
	display: grid;
	place-items: center;
	flex-shrink: 0;
}

.match-link-icon .material-symbols-outlined {
	color: #fff;
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.match-link-text { flex: 1; }
.match-link-label { font-size: 0.85rem; font-weight: 700; color: var(--color-on-surface); margin: 0; }
.match-link-arrow { color: var(--color-on-surface-variant); font-size: 1.1rem; }

/* ── Agenda ─────────────────────────────────────────── */
.agenda { display: flex; flex-direction: column; gap: 0; }

.agenda-item {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) 0;
	border-top: 1px solid var(--color-surface-container);
}

.agenda-item:first-child { border-top: none; padding-top: 0; }

.agenda-date-col {
	display: flex;
	flex-direction: column;
	align-items: center;
	min-width: 36px;
	flex-shrink: 0;
}

.agenda-day {
	font-family: var(--font-display);
	font-size: 1.3rem;
	font-weight: 900;
	color: var(--color-primary);
	line-height: 1;
}

.agenda-month {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	color: var(--color-on-surface-variant);
}

.agenda-info { flex: 1; min-width: 0; }

.agenda-title {
	font-weight: 700;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.agenda-sub {
	font-size: 0.78rem;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
}

.agenda-rsvp {
	display: flex;
	gap: var(--space-1);
	flex-shrink: 0;
}

.rsvp-btn {
	width: 32px;
	height: 32px;
	border-radius: 50%;
	border: 1.5px solid var(--color-outline-variant);
	background: transparent;
	cursor: pointer;
	display: grid;
	place-items: center;
	transition: background 150ms, border-color 150ms;
	-webkit-tap-highlight-color: transparent;
}

.rsvp-btn .material-symbols-outlined { font-size: 1rem; color: var(--color-on-surface-variant); }

.rsvp-btn--yes.active { background: #dcfce7; border-color: #16a34a; }
.rsvp-btn--yes.active .material-symbols-outlined { color: #16a34a; }
.rsvp-btn--no.active  { background: #fee2e2; border-color: var(--color-error); }
.rsvp-btn--no.active  .material-symbols-outlined { color: var(--color-error); }

/* ── Meilensteine ───────────────────────────────────── */
.milestones {
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.milestones-scroll {
	display: flex;
	gap: var(--space-3);
	overflow-x: auto;
	scrollbar-width: none;
	padding-bottom: 4px;
}

.milestones-scroll::-webkit-scrollbar { display: none; }

.milestone-card {
	flex-shrink: 0;
	width: 120px;
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 14px;
	padding: var(--space-4) var(--space-3);
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: var(--space-2);
	text-align: center;
}

.milestone-icon {
	font-size: 2rem;
	color: var(--color-secondary);
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}

.milestone-label {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.85rem;
	color: var(--color-on-surface);
	margin: 0;
	line-height: 1.2;
}

.milestone-sub {
	font-size: 0.72rem;
	color: var(--color-on-surface-variant);
	margin: 0;
}

/* ── Push Prefs ─────────────────────────────────────── */
.prefs { display: flex; flex-direction: column; gap: 2px; }

.toggle {
	display: flex;
	justify-content: space-between;
	align-items: center;
	padding: 8px 0;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	border-top: 1px solid var(--color-surface-container);
	cursor: pointer;
}

.toggle:first-child { border-top: none; }

/* ── Placeholder Sections ───────────────────────────── */
.placeholder-section {
	border-style: dashed;
	border-color: var(--color-outline-variant);
	background: transparent;
}

.placeholder-hint {
	font-size: 0.85rem;
	color: var(--color-on-surface-variant);
	margin: 0;
	line-height: 1.5;
}

/* ── Admin Panel ────────────────────────────────────── */
.admin-header {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-4);
	background: linear-gradient(135deg, rgba(204,0,0,0.08) 0%, rgba(204,0,0,0.04) 100%);
	border: 1px solid rgba(204,0,0,0.15);
	border-radius: 16px;
}

.admin-header-icon {
	font-size: 2rem;
	color: var(--color-primary);
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 48;
	flex-shrink: 0;
}

.admin-header-title {
	font-family: var(--font-display);
	font-weight: 900;
	font-size: 1.15rem;
	color: var(--color-on-surface);
	margin: 0;
}

.admin-header-sub {
	font-size: 0.78rem;
	color: var(--color-on-surface-variant);
	margin: 2px 0 0;
}

.admin-section {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.admin-section-head {
	display: flex;
	align-items: center;
	gap: var(--space-3);
}

.admin-section-icon {
	width: 36px;
	height: 36px;
	border-radius: 10px;
	display: grid;
	place-items: center;
	flex-shrink: 0;
}

.admin-section-icon .material-symbols-outlined {
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24;
}

.admin-section-title {
	font-family: var(--font-display);
	font-weight: 800;
	font-size: 0.9rem;
	color: var(--color-on-surface);
	margin: 0;
}

.admin-action-grid {
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.admin-action {
	display: flex;
	align-items: center;
	gap: var(--space-3);
	padding: var(--space-3) var(--space-2);
	border: none;
	background: none;
	border-radius: 10px;
	cursor: pointer;
	text-align: left;
	font-family: inherit;
	-webkit-tap-highlight-color: transparent;
	transition: background 120ms;
	width: 100%;
}

.admin-action--live:active {
	background: var(--color-surface-container-low);
}
.admin-action--disabled {
	opacity: 0.45;
	cursor: default;
}

.admin-action-icon {
	font-size: 1.2rem;
	font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	flex-shrink: 0;
	width: 24px;
	text-align: center;
}

.admin-action-label {
	flex: 1;
	font-size: 0.88rem;
	font-weight: 600;
	color: var(--color-on-surface);
}

.admin-action-badge {
	font-size: 0.68rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.06em;
	padding: 2px 8px;
	border-radius: 999px;
	background: var(--color-surface-container-high);
	color: var(--color-on-surface-variant);
}

.admin-version {
	display: flex;
	align-items: center;
	justify-content: center;
	gap: var(--space-2);
	font-size: 0.75rem;
	color: var(--color-on-surface-variant);
	padding: var(--space-3);
}

.admin-version .material-symbols-outlined {
	font-size: 1rem;
}
</style>
