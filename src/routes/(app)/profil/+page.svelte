<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, signOut, playerRole } from '$lib/stores/auth';
	import { registerPush, unregisterPush, pushStatus } from '$lib/push/register.js';

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
		return ms.reverse(); // neueste/höchste zuerst
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
			// Toggle off: delete
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
</script>

<div class="profil-page">

	<h1 class="phdr">
		<span class="material-symbols-outlined">person</span>
		Mein Profil
	</h1>

	{#if !me}
		<!-- Loading state -->
		<div class="profil-loading">
			<div class="skeleton-card animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
		</div>
	{:else}

	<!-- ── A) Profil-Karte ─────────────────────────────── -->
	<section class="card">
		<div class="avatar-row">
			<div class="avatar">
				{#if me.avatar_url || me.photo}
					<img src={me.avatar_url || me.photo} alt={me.name} />
				{:else}
					<span>{(me.name || '?').slice(0,1).toUpperCase()}</span>
				{/if}
			</div>
			<div class="avatar-meta">
				<p class="avatar-name">{me.name}</p>
				<p class="avatar-email">{me.email}</p>
				<label class="upload">
					<input type="file" accept="image/*" onchange={uploadAvatar} hidden />
					<span class="material-symbols-outlined">photo_camera</span>
					{uploading ? 'Lädt…' : 'Foto ändern'}
				</label>
			</div>
		</div>

		<div class="fields-grid">
			<label class="field">
				<span>Name</span>
				<input type="text" bind:value={me.name} />
			</label>
			<label class="field">
				<span>E-Mail</span>
				<input type="email" value={me.email} disabled />
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

		<button class="btn btn--primary" onclick={save}>
			<span class="material-symbols-outlined">check</span> Speichern
		</button>
		{#if msg}<p class="msg">{msg}</p>{/if}
	</section>

	<!-- ── B) Meine Stats ────────────────────────────────── -->
	{#if myStats}
	<section class="stats-mini">
		<h2 class="section-title">
			<span class="material-symbols-outlined">bar_chart</span>
			Meine Performance
		</h2>
		<div class="stats-chips">
			<div class="stats-chip stats-chip--primary">
				<span class="stats-chip-label">Schnitt</span>
				<span class="stats-chip-value">{myStats.avg}</span>
			</div>
			<div class="stats-chip">
				<span class="stats-chip-label">Rang</span>
				<span class="stats-chip-value">#{myStats.rank}</span>
			</div>
			<div class="stats-chip">
				<span class="stats-chip-label">Form Ø5</span>
				<span class="stats-chip-value">
					{myStats.avg5}
					{#if myStats.avg5 > myStats.avg}
						<span class="trend-up">▲</span>
					{:else if myStats.avg5 < myStats.avg}
						<span class="trend-dn">▼</span>
					{/if}
				</span>
			</div>
			<div class="stats-chip">
				<span class="stats-chip-label">Rekord</span>
				<span class="stats-chip-value">{myStats.best}</span>
			</div>
		</div>
	</section>
	{/if}

	<!-- ── C) Nächstes Spiel ─────────────────────────────── -->
	{#if nextMatch}
	{@const badge = daysUntil(nextMatch.date)}
	<section class="next-match-card">
		<div class="next-match-head">
			<h3 class="section-title">
				<span class="material-symbols-outlined">emoji_events</span>
				Nächstes Spiel &amp; Logistik
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

	<!-- ── D) Vereinstermine Agenda ──────────────────────── -->
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

	<!-- ── E) Karriere-Meilensteine ─────────────────────── -->
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

	<!-- ── F) Benachrichtigungen ─────────────────────────── -->
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

	<!-- ── G) Abwesenheiten (Placeholder) ────────────────── -->
	<section class="card placeholder-section">
		<h2 class="section-title">
			<span class="material-symbols-outlined">event_busy</span>
			Abwesenheiten
		</h2>
		<p class="placeholder-hint">Demnächst: Abwesenheiten für Spieltermine melden, damit der Kapitän bei der Aufstellung Bescheid weiß.</p>
	</section>

	<!-- ── H) Offene Aktionen (Placeholder) ──────────────── -->
	<section class="card placeholder-section">
		<h2 class="section-title">
			<span class="material-symbols-outlined">pending_actions</span>
			Offene Aktionen
		</h2>
		<p class="placeholder-hint">Hier erscheinen bald Aktionen wie die Bestätigung zur Jahreshauptversammlung oder Abstimmungen zum Vereinsdress.</p>
	</section>

	<!-- ── I) Admin-Bereich ───────────────────────────────── -->
	{#if $playerRole === 'admin'}
		<section class="profil-admin">
			<h3>
				<span class="material-symbols-outlined" style="font-variation-settings:'FILL' 1,'wght' 500,'GRAD' 0,'opsz' 24;font-size:1.1rem">shield_person</span>
				Admin-Bereich
			</h3>
			<div class="admin-tile-grid">
				<a href="/admin/spieler"  class="admin-tile"><span class="material-symbols-outlined">group</span>Spieler</a>
				<a href="/admin/teams"    class="admin-tile"><span class="material-symbols-outlined">shield</span>Teams</a>
				<a href="/admin/saison"   class="admin-tile"><span class="material-symbols-outlined">upload_file</span>Saison</a>
				<a href="/admin/training" class="admin-tile"><span class="material-symbols-outlined">fitness_center</span>Training</a>
				<a href="/admin/news"     class="admin-tile"><span class="material-symbols-outlined">campaign</span>News</a>
				<a href="/admin"          class="admin-tile"><span class="material-symbols-outlined">dashboard</span>Übersicht</a>
			</div>
		</section>
	{/if}

	<button class="btn btn--ghost btn--logout" onclick={signOut}>
		<span class="material-symbols-outlined">logout</span> Abmelden
	</button>

	{/if}<!-- end {#if me} -->
</div>

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

/* ── Header ─────────────────────────────────────────── */
.phdr {
	display: flex;
	gap: 6px;
	align-items: center;
	font-family: var(--font-display);
	font-weight: 700;
	font-size: 1.3rem;
	color: var(--color-primary);
	margin: 0;
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

/* ── Stats Mini ─────────────────────────────────────── */
.stats-mini {
	background: var(--color-surface-container-lowest);
	border: 1px solid var(--color-surface-container);
	border-radius: 16px;
	padding: var(--space-4);
	display: flex;
	flex-direction: column;
	gap: var(--space-3);
}

.stats-chips {
	display: grid;
	grid-template-columns: repeat(4, 1fr);
	gap: var(--space-2);
}

.stats-chip {
	display: flex;
	flex-direction: column;
	gap: 2px;
	padding: var(--space-3);
	background: var(--color-surface-container-low);
	border-radius: 12px;
	text-align: center;
}

.stats-chip--primary {
	background: var(--gradient-primary);
}

.stats-chip-label {
	font-size: 0.65rem;
	font-weight: 700;
	text-transform: uppercase;
	letter-spacing: 0.07em;
	color: var(--color-on-surface-variant);
}

.stats-chip--primary .stats-chip-label { color: rgba(255,255,255,0.75); }

.stats-chip-value {
	font-family: var(--font-display);
	font-size: 1.1rem;
	font-weight: 900;
	color: var(--color-on-surface);
	display: flex;
	align-items: center;
	justify-content: center;
	gap: 2px;
}

.stats-chip--primary .stats-chip-value { color: #fff; }
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
</style>
