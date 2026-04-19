<script>
	import { sb }       from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, MONTH_SHORT } from '$lib/utils/dates.js';

	let me         = $state(null);
	let uploading  = $state(false);
	let nextMatch  = $state(null);
	let events     = $state([]);
	let rsvps      = $state([]);
	let myStats    = $state(null);
	let milestones = $state([]);

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
			sb.from('matches')
				.select('id, date, time, opponent, home_away, leagues(name)')
				.gte('date', today).order('date', { ascending: true }).limit(1).maybeSingle(),
			sb.from('events')
				.select('id, title, date, time, location, description')
				.gte('date', today).order('date', { ascending: true }).limit(6),
			sb.from('event_rsvps').select('event_id, response').eq('player_id', pid),
			sb.from('game_plan_players')
				.select('score, game_plans!inner(cal_week)')
				.eq('player_id', pid).eq('played', true).not('score', 'is', null)
				.order('cal_week', { referencedTable: 'game_plans', ascending: false }),
			sb.from('game_plan_players').select('player_id, score').eq('played', true).not('score', 'is', null),
		]);

		me        = playerData;
		nextMatch = matchData;
		events    = eventData ?? [];
		rsvps     = rsvpData ?? [];

		const myScores = (scoreData ?? []).map(g => Number(g.score));
		if (myScores.length) {
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
			milestones = calcMilestones(myScores, myScores.length);
		}
	}

	function calcMilestones(scores, gamesPlayed) {
		const ms = [];
		if (gamesPlayed >= 1)   ms.push({ icon: 'sports_score',     label: 'Erstes Vereinsspiel', sub: `${gamesPlayed} Spiele bisher` });
		if (gamesPlayed >= 10)  ms.push({ icon: 'military_tech',     label: '10 Spiele',           sub: 'Meilenstein erreicht' });
		if (gamesPlayed >= 25)  ms.push({ icon: 'military_tech',     label: '25 Spiele',           sub: 'Meilenstein erreicht' });
		if (gamesPlayed >= 50)  ms.push({ icon: 'emoji_events',      label: '50 Spiele',           sub: 'Halbes Hunderter!' });
		if (gamesPlayed >= 100) ms.push({ icon: 'workspace_premium', label: '100 Spiele',          sub: 'Jahrhundert-Marke!' });
		if (gamesPlayed >= 150) ms.push({ icon: 'grade',             label: '150 Spiele',          sub: 'Legende!' });
		const best = Math.max(...scores);
		if (best >= 500) ms.push({ icon: 'star',    label: '500+ Holz', sub: `Bestleistung: ${best}` });
		if (best >= 550) ms.push({ icon: 'stars',   label: '550+ Holz', sub: `Bestleistung: ${best}` });
		if (best >= 600) ms.push({ icon: 'diamond', label: '600+ Holz', sub: `Bestleistung: ${best}` });
		const avg = Math.round(scores.reduce((a,b) => a+b, 0) / scores.length);
		if (avg >= 500) ms.push({ icon: 'trending_up', label: 'Ø 500+', sub: `Durchschnitt: ${avg}` });
		return ms.reverse();
	}

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

	async function save() {
		const { error } = await sb.from('players').update({
			name:       me.name,
			phone:      me.phone,
			push_prefs: me.push_prefs,
			shirt_size: me.shirt_size,
			pants_size: me.pants_size,
		}).eq('id', me.id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		triggerToast('Gespeichert');
	}

	async function uploadAvatar(e) {
		const file = e.target.files?.[0];
		if (!file) return;
		uploading = true;
		const ext  = file.name.split('.').pop();
		const path = `${me.id}/${Date.now()}.${ext}`;
		const { error: upErr } = await sb.storage.from('avatars').upload(path, file, { upsert: true });
		if (upErr) { triggerToast('Fehler: ' + upErr.message); uploading = false; return; }
		const { data } = sb.storage.from('avatars').getPublicUrl(path);
		const url = data.publicUrl;
		const { error } = await sb.from('players').update({ avatar_url: url }).eq('id', me.id);
		uploading = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		me.avatar_url = url;
		triggerToast('Foto aktualisiert');
	}

	function daysUntilLabel(dateStr) {
		const today = new Date(); today.setHours(0,0,0,0);
		const d     = new Date(dateStr + 'T00:00:00');
		const diff  = Math.round((d - today) / 86400000);
		if (diff === 0) return 'Heute';
		if (diff === 1) return 'Morgen';
		if (diff === 2) return 'Übermorgen';
		return `In ${diff} Tagen`;
	}
</script>

{#if !me}
	<div class="profil-loading">
		<div class="skeleton-card animate-pulse-skeleton"></div>
		<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
	</div>
{:else}

	{#if myStats}
	{@const formDiff = myStats.avg5 - myStats.avg}
	<section class="perf-card">
		<div class="perf-header">
			<span class="perf-eyebrow">Meine Performance</span>
			<span class="perf-games">{myStats.gamesPlayed} Spiele</span>
		</div>
		<div class="perf-hero">
			<span class="material-symbols-outlined perf-trophy">emoji_events</span>
			<div class="perf-avg-value">{myStats.avg}</div>
			<div class="perf-avg-label">Saison-Schnitt</div>
		</div>
		<div class="perf-divider"></div>
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

	{#if nextMatch}
	{@const badge = daysUntilLabel(nextMatch.date)}
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

	<section class="profil-card">
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
		<div class="profil-card-identity">
			<h2 class="profil-card-name">{me.name}</h2>
			<p class="profil-card-email">{me.email}</p>
			<div class="profil-card-gold-line"></div>
		</div>
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
		<div class="profil-card-actions">
			<button class="btn btn--primary" onclick={save}>
				<span class="material-symbols-outlined">check</span> Speichern
			</button>
		</div>
	</section>

	{#if events.length}
	<section class="card">
		<h2 class="section-title">
			<span class="material-symbols-outlined">event</span>
			Vereinstermine
		</h2>
		<div class="agenda">
			{#each events as ev}
			{@const d   = new Date(ev.date + 'T00:00:00')}
			{@const myR = myRsvp(ev.id)}
			<div class="agenda-item">
				<div class="agenda-date-col">
					<span class="agenda-day">{d.getDate()}</span>
					<span class="agenda-month">{MONTH_SHORT[d.getMonth()]}</span>
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
					<button class="rsvp-btn rsvp-btn--yes" class:active={myR === 'yes'} onclick={() => rsvp(ev.id, 'yes')} aria-label="Zusagen">
						<span class="material-symbols-outlined">check</span>
					</button>
					<button class="rsvp-btn rsvp-btn--no" class:active={myR === 'no'} onclick={() => rsvp(ev.id, 'no')} aria-label="Absagen">
						<span class="material-symbols-outlined">close</span>
					</button>
				</div>
			</div>
			{/each}
		</div>
	</section>
	{/if}

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

{/if}
