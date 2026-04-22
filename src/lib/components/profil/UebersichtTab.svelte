<script>
	import { onMount }      from 'svelte';
	import { sb }           from '$lib/supabase';
	import { playerId, playerRole } from '$lib/stores/auth.js';
	import { setSubtab }    from '$lib/stores/subtab.js';
	import { goto }         from '$app/navigation';
	import { triggerToast } from '$lib/stores/toast.js';
	import { fmtDate, fmtTime, toDateStr, daysUntil, MONTH_SHORT } from '$lib/utils/dates.js';
	import BottomSheet      from '$lib/components/BottomSheet.svelte';

	let me         = $state(null);
	let scores     = $state([]);
	let allScores  = $state([]);
	let nextMatch  = $state(null);
	let events     = $state([]);
	let rsvps      = $state([]);
	let loading    = $state(true);
	let uploading  = $state(false);

	let editSheetOpen = $state(false);
	let editFocus     = $state('');
	let editForm      = $state({});

	$effect(() => { if ($playerId) loadData($playerId); });

	function goToComp(pill, extraParams = '') {
		setSubtab('/spielbetrieb', 'uebersicht');
		goto(`/spielbetrieb?pill=${pill}${extraParams}`, { keepFocus: true, noScroll: true });
	}

	async function loadData(pid) {
		loading = true;
		try {
			const today = toDateStr(new Date());
			const [
				{ data: p,  error: e1 },
				{ data: sc, error: e2 },
				{ data: all },
				{ data: nm, error: e3 },
				{ data: ev, error: e4 },
				{ data: rs },
			] = await Promise.all([
				sb.from('players')
					.select('id, name, email, phone, address, avatar_url, photo, role, shirt_size, pants_size, spielerpass_nr, medical_exam_expiry, birth_date, push_prefs')
					.eq('id', pid).maybeSingle(),
				sb.from('game_plan_players')
					.select('score, game_plans!inner(cal_week)')
					.eq('player_id', pid).eq('played', true).not('score', 'is', null)
					.order('cal_week', { referencedTable: 'game_plans', ascending: false }),
				sb.from('game_plan_players')
					.select('player_id, score').eq('played', true).not('score', 'is', null),
				sb.from('matches')
					.select('id, date, time, opponent, home_away, location, leagues(name)')
					.gte('date', today).neq('opponent', 'spielfrei')
					.order('date').limit(1).maybeSingle(),
				sb.from('events')
					.select('id, title, date, time, location')
					.gte('date', today).order('date').limit(6),
				sb.from('event_rsvps').select('event_id, response').eq('player_id', pid),
			]);
			if (e1) triggerToast('Fehler: ' + e1.message);
			if (e2) triggerToast('Fehler: ' + e2.message);
			if (e3) triggerToast('Fehler: ' + e3.message);
			if (e4) triggerToast('Fehler: ' + e4.message);

			me        = p;
			scores    = (sc ?? []).map(g => Number(g.score));
			allScores = all ?? [];
			nextMatch = nm;
			events    = ev ?? [];
			rsvps     = rs ?? [];
		} finally {
			loading = false;
		}
	}

	const stats = $derived.by(() => {
		if (!scores.length) return null;
		const avg  = Math.round(scores.reduce((a,b) => a+b, 0) / scores.length);
		const avg5 = Math.round(scores.slice(0,5).reduce((a,b) => a+b, 0) / Math.min(5, scores.length));
		const best = Math.max(...scores);
		const playerAvgs = {};
		for (const g of allScores) {
			(playerAvgs[g.player_id] ||= []).push(Number(g.score));
		}
		const sorted = Object.entries(playerAvgs).sort((a, b) => {
			const av = a[1].reduce((s,v) => s+v, 0) / a[1].length;
			const bv = b[1].reduce((s,v) => s+v, 0) / b[1].length;
			return bv - av;
		});
		const rank = sorted.findIndex(([id]) => id === me?.id) + 1;
		return { avg, avg5, best, rank, count: scores.length };
	});

	const last5 = $derived(scores.slice(0, 5));

	const milestones = $derived.by(() => {
		if (!scores.length) return [];
		const ms = [];
		const n = scores.length;
		const best = Math.max(...scores);
		const avg = stats?.avg ?? 0;
		if (n >= 1)   ms.push({ icon: 'sports_score',     label: 'Erstes Spiel', sub: `${n} Spiele bisher` });
		if (n >= 10)  ms.push({ icon: 'military_tech',    label: '10 Spiele',    sub: 'Meilenstein' });
		if (n >= 25)  ms.push({ icon: 'military_tech',    label: '25 Spiele',    sub: 'Meilenstein' });
		if (n >= 50)  ms.push({ icon: 'emoji_events',     label: '50 Spiele',    sub: 'Halbes Hundert!' });
		if (n >= 100) ms.push({ icon: 'workspace_premium',label: '100 Spiele',   sub: 'Jahrhundert!' });
		if (n >= 150) ms.push({ icon: 'grade',            label: '150 Spiele',   sub: 'Legende!' });
		if (best >= 500) ms.push({ icon: 'star',    label: '500+ Holz', sub: `Rekord: ${best}` });
		if (best >= 550) ms.push({ icon: 'stars',   label: '550+ Holz', sub: `Rekord: ${best}` });
		if (best >= 600) ms.push({ icon: 'diamond', label: '600+ Holz', sub: `Rekord: ${best}` });
		if (avg >= 500) ms.push({ icon: 'trending_up', label: 'Ø 500+', sub: `Schnitt: ${avg}` });
		return ms.reverse();
	});

	// Action cards
	const missingFields = $derived.by(() => {
		if (!me) return [];
		const m = [];
		if (!me.phone)          m.push('Telefon');
		if (!me.address)        m.push('Adresse');
		if (!me.shirt_size)     m.push('Trikotgröße');
		if (!me.pants_size)     m.push('Hosengröße');
		if (!me.spielerpass_nr) m.push('Spielerpass-Nr.');
		return m;
	});

	const attestStatus = $derived.by(() => {
		if (!me?.medical_exam_expiry) return null;
		const d = daysUntil(me.medical_exam_expiry);
		if (d < 0)   return { kind: 'expired', days: -d };
		if (d <= 30) return { kind: 'soon',    days: d };
		return null;
	});

	const birthdaySoon = $derived.by(() => {
		if (!me?.birth_date) return null;
		const now = new Date(); now.setHours(0,0,0,0);
		const [by, bm, bd] = me.birth_date.split('-').map(Number);
		let next = new Date(now.getFullYear(), bm - 1, bd);
		if (next < now) next = new Date(now.getFullYear() + 1, bm - 1, bd);
		const diff = Math.round((next - now) / 86400000);
		if (diff > 7) return null;
		return { days: diff, age: next.getFullYear() - by };
	});

	function myRsvp(eid) {
		return rsvps.find(r => r.event_id === eid)?.response ?? null;
	}

	async function rsvp(eid, response) {
		const pid = $playerId;
		const existing = myRsvp(eid);
		if (existing === response) {
			rsvps = rsvps.filter(r => r.event_id !== eid);
			const { error } = await sb.from('event_rsvps').delete().eq('event_id', eid).eq('player_id', pid);
			if (error) { triggerToast('Fehler: ' + error.message); loadData(pid); }
		} else {
			rsvps = [...rsvps.filter(r => r.event_id !== eid), { event_id: eid, response }];
			const { error } = await sb.from('event_rsvps').upsert({ event_id: eid, player_id: pid, response });
			if (error) { triggerToast('Fehler: ' + error.message); loadData(pid); }
		}
	}

	function openEdit(field = '') {
		if (!me) return;
		editForm = {
			name:                me.name ?? '',
			phone:               me.phone ?? '',
			address:             me.address ?? '',
			shirt_size:          me.shirt_size ?? '',
			pants_size:          me.pants_size ?? '',
			spielerpass_nr:      me.spielerpass_nr ?? '',
			medical_exam_expiry: me.medical_exam_expiry ?? '',
			birth_date:          me.birth_date ?? '',
		};
		editFocus = field;
		editSheetOpen = true;
	}

	async function saveEdit() {
		const payload = {
			name:                editForm.name?.trim() || null,
			phone:               editForm.phone?.trim() || null,
			address:             editForm.address?.trim() || null,
			shirt_size:          editForm.shirt_size || null,
			pants_size:          editForm.pants_size?.trim() || null,
			spielerpass_nr:      editForm.spielerpass_nr?.trim() || null,
			medical_exam_expiry: editForm.medical_exam_expiry || null,
			birth_date:          editForm.birth_date || null,
		};
		const { error } = await sb.from('players').update(payload).eq('id', me.id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		me = { ...me, ...payload };
		editSheetOpen = false;
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
		const { error } = await sb.from('players').update({ avatar_url: data.publicUrl }).eq('id', me.id);
		uploading = false;
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		me = { ...me, avatar_url: data.publicUrl };
		triggerToast('Foto aktualisiert');
	}

	function initials(name) {
		return (name ?? '?').split(' ').map(w => w[0]).join('').slice(0,2).toUpperCase();
	}

	function daysUntilLabel(dateStr) {
		const d = daysUntil(dateStr);
		if (d === 0) return 'Heute';
		if (d === 1) return 'Morgen';
		if (d === 2) return 'Übermorgen';
		if (d < 0)   return null;
		return `In ${d} Tagen`;
	}

	function fmtAttestValue(d) {
		if (!d) return null;
		const days = daysUntil(d);
		if (days < 0)   return { text: `Abgelaufen seit ${fmtDate(d)}`, cls: 'val-expired' };
		if (days <= 30) return { text: `${fmtDate(d)} (${days}d)`,       cls: 'val-soon' };
		return { text: fmtDate(d), cls: '' };
	}

	const SHIRT_SIZES = ['XS','S','M','L','XL','XXL','XXXL'];

	const dataRows = $derived.by(() => {
		if (!me) return [];
		const attest = fmtAttestValue(me.medical_exam_expiry);
		return [
			{ key: 'phone',          label: 'Telefon',          value: me.phone,          icon: 'call' },
			{ key: 'email',          label: 'E-Mail',           value: me.email,          icon: 'mail',         readonly: true },
			{ key: 'address',        label: 'Adresse',          value: me.address,        icon: 'home' },
			{ key: 'birth_date',     label: 'Geburtsdatum',     value: me.birth_date ? fmtDate(me.birth_date) : null, icon: 'cake' },
			{ key: 'shirt_size',     label: 'Trikotgröße',      value: me.shirt_size,     icon: 'apparel' },
			{ key: 'pants_size',     label: 'Hosengröße',       value: me.pants_size,     icon: 'straighten' },
			{ key: 'spielerpass_nr', label: 'Spielerpass-Nr.',  value: me.spielerpass_nr, icon: 'badge' },
			{ key: 'medical_exam_expiry', label: 'Ärztl. Attest gültig bis', value: attest?.text ?? null, valueClass: attest?.cls ?? '', icon: 'medical_information' },
		];
	});
</script>

{#if loading}
	<div class="ueb-loading">
		<div class="ueb-skeleton shimmer-box"></div>
		<div class="ueb-skeleton ueb-skeleton--short shimmer-box"></div>
		<div class="ueb-skeleton shimmer-box"></div>
	</div>
{:else if me}
<div class="ueb-page">

	<!-- ── Hero player card ──────────────────────────────── -->
	<section class="hero-card">
		<div class="hero-bg"></div>
		<div class="hero-avatar-wrap">
			<div class="hero-avatar-ring">
				<div class="hero-avatar">
					{#if me.avatar_url || me.photo}
						<img src={me.avatar_url || me.photo} alt={me.name} />
					{:else}
						<span>{initials(me.name)}</span>
					{/if}
				</div>
			</div>
			<label class="hero-photo-btn" aria-label="Foto ändern">
				<input type="file" accept="image/*" onchange={uploadAvatar} hidden />
				{#if uploading}
					<span class="material-symbols-outlined hero-spinner">progress_activity</span>
				{:else}
					<span class="material-symbols-outlined">photo_camera</span>
				{/if}
			</label>
		</div>
		<div class="hero-identity">
			<h2 class="hero-name">{me.name ?? '—'}</h2>
			<span class="hero-role" class:hero-role--gold={$playerRole === 'kapitaen'}>
				{$playerRole === 'kapitaen' ? 'Kapitän' : 'Spieler'}
			</span>
		</div>
		{#if stats}
			<div class="hero-stats">
				<div class="hero-stat">
					<span class="hero-stat-val">{stats.avg}</span>
					<span class="hero-stat-lbl">Schnitt</span>
				</div>
				<div class="hero-stat-sep"></div>
				<div class="hero-stat">
					<span class="hero-stat-val">{stats.count}</span>
					<span class="hero-stat-lbl">Spiele</span>
				</div>
				<div class="hero-stat-sep"></div>
				<div class="hero-stat">
					<div class="hero-form-dots">
						{#each last5 as sc}
							{@const isMax = sc === Math.max(...last5)}
							{@const isMin = sc === Math.min(...last5)}
							<span class="hero-form-dot" class:hero-form-dot--hi={isMax && !isMin} class:hero-form-dot--lo={isMin && !isMax}>{sc}</span>
						{/each}
					</div>
					<span class="hero-stat-lbl">Letzte 5</span>
				</div>
			</div>
		{/if}
	</section>

	<!-- ── Action cards ──────────────────────────────────── -->
	{#if attestStatus || missingFields.length > 0 || birthdaySoon}
		<div class="action-cards">

			{#if attestStatus?.kind === 'expired'}
				<button class="action-card action-card--warn" onclick={() => openEdit('medical_exam_expiry')}>
					<span class="material-symbols-outlined action-icon">warning</span>
					<div class="action-body">
						<span class="action-title">Ärztliches Attest abgelaufen</span>
						<span class="action-sub">Seit {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'}</span>
					</div>
					<span class="action-cta">Aktualisieren →</span>
				</button>
			{:else if attestStatus?.kind === 'soon'}
				<button class="action-card action-card--gold" onclick={() => openEdit('medical_exam_expiry')}>
					<span class="material-symbols-outlined action-icon">medical_information</span>
					<div class="action-body">
						<span class="action-title">Attest läuft in {attestStatus.days} {attestStatus.days === 1 ? 'Tag' : 'Tagen'} ab</span>
						<span class="action-sub">Untersuchung jetzt planen</span>
					</div>
					<span class="action-cta">Aktualisieren →</span>
				</button>
			{/if}

			{#if missingFields.length > 0}
				<button class="action-card action-card--blue" onclick={() => openEdit(missingFields[0].toLowerCase())}>
					<span class="material-symbols-outlined action-icon">edit_note</span>
					<div class="action-body">
						<span class="action-title">Profil unvollständig</span>
						<span class="action-sub">{missingFields.length} {missingFields.length === 1 ? 'Feld' : 'Felder'}: {missingFields.join(', ')}</span>
					</div>
					<span class="action-cta">Ergänzen →</span>
				</button>
			{/if}

			{#if birthdaySoon}
				<div class="action-card action-card--gold action-card--static">
					<span class="material-symbols-outlined action-icon">cake</span>
					<div class="action-body">
						<span class="action-title">
							{birthdaySoon.days === 0 ? 'Heute Geburtstag!' : `Geburtstag in ${birthdaySoon.days} ${birthdaySoon.days === 1 ? 'Tag' : 'Tagen'}`}
						</span>
						<span class="action-sub">Du wirst {birthdaySoon.age}</span>
					</div>
				</div>
			{/if}

		</div>
	{/if}

	<!-- ── Performance card ──────────────────────────────── -->
	{#if stats}
		{@const formDiff = stats.avg5 - stats.avg}
		<section class="perf-card">
			<div class="perf-header">
				<span class="perf-eyebrow">Meine Performance</span>
				<span class="perf-games">{stats.count} Spiele</span>
			</div>
			<div class="perf-hero">
				<span class="material-symbols-outlined perf-trophy">emoji_events</span>
				<div class="perf-avg-value">{stats.avg}</div>
				<div class="perf-avg-label">Saison-Schnitt</div>
			</div>
			<div class="perf-divider"></div>
			<div class="perf-stats-row">
				<div class="perf-stat">
					<span class="perf-stat-value">#{stats.rank}</span>
					<span class="perf-stat-label">Vereinsrang</span>
				</div>
				<div class="perf-stat-sep"></div>
				<div class="perf-stat">
					<span class="perf-stat-value perf-stat-form">
						{stats.avg5}
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
					<span class="perf-stat-value">{stats.best}</span>
					<span class="perf-stat-label">Rekord</span>
				</div>
			</div>
		</section>
	{/if}

	<!-- ── Meine Daten ───────────────────────────────────── -->
	<section class="data-card">
		<div class="data-card-head">
			<h3 class="section-title">
				<span class="material-symbols-outlined">person</span>
				Meine Daten
			</h3>
			<button class="data-card-edit" onclick={() => openEdit('')}>
				<span class="material-symbols-outlined">edit</span>
				Bearbeiten
			</button>
		</div>
		<div class="data-rows">
			{#each dataRows as row}
				<button
					class="data-row"
					class:data-row--readonly={row.readonly}
					onclick={() => !row.readonly && openEdit(row.key)}
					disabled={row.readonly}
				>
					<span class="material-symbols-outlined data-row-icon">{row.icon}</span>
					<div class="data-row-text">
						<span class="data-row-label">{row.label}</span>
						{#if row.value}
							<span class="data-row-value {row.valueClass ?? ''}">{row.value}</span>
						{:else}
							<span class="data-row-value data-row-value--empty">Nicht angegeben</span>
						{/if}
					</div>
					{#if !row.readonly}
						<span class="material-symbols-outlined data-row-arrow">chevron_right</span>
					{/if}
				</button>
			{/each}
		</div>
	</section>

	<!-- ── Nächstes Spiel ────────────────────────────────── -->
	{#if nextMatch}
		{@const badge = daysUntilLabel(nextMatch.date)}
		<button class="next-match-card" onclick={() => goToComp('spiele')}>
			<div class="next-match-head">
				<h3 class="section-title">
					<span class="material-symbols-outlined">emoji_events</span>
					Nächstes Spiel
				</h3>
				{#if badge}
					<span class="days-badge" class:days-badge--urgent={badge === 'Heute' || badge === 'Morgen'}>{badge}</span>
				{/if}
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
						{#if nextMatch.time}<p class="match-time">{fmtTime(nextMatch.time)}</p>{/if}
					</div>
				</div>
			</div>
		</button>
	{/if}

	<!-- ── Vereinstermine ────────────────────────────────── -->
	{#if events.length}
		<section class="card">
			<div class="data-card-head">
				<h3 class="section-title">
					<span class="material-symbols-outlined">event</span>
					Vereinstermine
				</h3>
				<button class="data-card-edit" onclick={() => goto('/kalender')}>
					Alle →
				</button>
			</div>
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

	<!-- ── Meilensteine ──────────────────────────────────── -->
	{#if milestones.length}
		<section class="milestones">
			<h3 class="section-title">
				<span class="material-symbols-outlined">workspace_premium</span>
				Karriere-Meilensteine
			</h3>
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

</div>
{/if}

<!-- ── Edit BottomSheet ──────────────────────────────────── -->
<BottomSheet bind:open={editSheetOpen} title="Daten bearbeiten">
	<div class="edit-form">
		<label class="mw-field" class:mw-field--focus={editFocus === 'name'}>
			<span>Name</span>
			<input type="text" bind:value={editForm.name} />
		</label>
		<label class="mw-field" class:mw-field--focus={editFocus === 'phone'}>
			<span>Telefon</span>
			<input type="tel" bind:value={editForm.phone} placeholder="+43 …" />
		</label>
		<label class="mw-field" class:mw-field--focus={editFocus === 'address'}>
			<span>Adresse</span>
			<input type="text" bind:value={editForm.address} placeholder="Straße, PLZ Ort" />
		</label>
		<label class="mw-field" class:mw-field--focus={editFocus === 'birth_date'}>
			<span>Geburtsdatum</span>
			<input type="date" bind:value={editForm.birth_date} />
		</label>
		<div class="edit-row">
			<label class="mw-field" class:mw-field--focus={editFocus === 'shirt_size'}>
				<span>Trikotgröße</span>
				<select bind:value={editForm.shirt_size}>
					<option value="">–</option>
					{#each SHIRT_SIZES as s}<option value={s}>{s}</option>{/each}
				</select>
			</label>
			<label class="mw-field" class:mw-field--focus={editFocus === 'pants_size'}>
				<span>Hosengröße</span>
				<input type="text" bind:value={editForm.pants_size} placeholder="z.B. 32/32" />
			</label>
		</div>
		<label class="mw-field" class:mw-field--focus={editFocus === 'spielerpass_nr'}>
			<span>Spielerpass-Nr.</span>
			<input type="text" bind:value={editForm.spielerpass_nr} />
		</label>
		<label class="mw-field" class:mw-field--focus={editFocus === 'medical_exam_expiry'}>
			<span>Ärztliches Attest gültig bis</span>
			<input type="date" bind:value={editForm.medical_exam_expiry} />
		</label>
		<div class="edit-actions">
			<button class="mw-btn mw-btn--ghost mw-btn--wide" onclick={() => editSheetOpen = false}>Abbrechen</button>
			<button class="mw-btn mw-btn--primary mw-btn--wide" onclick={saveEdit}>
				<span class="material-symbols-outlined">check</span> Speichern
			</button>
		</div>
	</div>
</BottomSheet>

<style>
	.ueb-page { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-5); }
	.ueb-loading { padding: var(--space-5); display: flex; flex-direction: column; gap: var(--space-4); }
	.ueb-skeleton { height: 120px; border-radius: var(--radius-lg); }
	.ueb-skeleton--short { height: 56px; }

	/* Hero */
	.hero-card {
		position: relative; border-radius: 24px; overflow: hidden;
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		display: flex; flex-direction: column; align-items: center;
		padding: 0 var(--space-5) var(--space-4);
		box-shadow: 0 8px 28px rgba(204,0,0,0.12);
	}
	.hero-bg {
		width: calc(100% + var(--space-10)); height: 96px; margin: 0 calc(var(--space-5) * -1);
		background: linear-gradient(160deg, #1a0000 0%, #7f1d1d 60%, #b91c1c 100%);
		position: relative;
	}
	.hero-bg::after {
		content: ''; position: absolute; inset: 0;
		background: radial-gradient(ellipse at 80% 30%, rgba(255,255,255,0.1), transparent 60%);
	}
	.hero-avatar-wrap { position: relative; margin-top: -48px; }
	.hero-avatar-ring {
		width: 96px; height: 96px; border-radius: 50%; padding: 3px;
		background: linear-gradient(135deg, var(--color-secondary), #a07c20);
		box-shadow: 0 4px 20px rgba(0,0,0,0.3);
	}
	.hero-avatar {
		width: 100%; height: 100%; border-radius: 50%; overflow: hidden;
		background: var(--color-surface-container); display: grid; place-items: center;
		font-family: var(--font-display); font-size: 2rem; font-weight: 900; color: var(--color-primary);
		border: 3px solid var(--color-surface-container-lowest);
	}
	.hero-avatar img { width: 100%; height: 100%; object-fit: cover; }
	.hero-photo-btn {
		position: absolute; bottom: -4px; right: -4px;
		width: 32px; height: 32px; border-radius: 50%;
		background: var(--color-surface-container-lowest);
		border: 1.5px solid var(--color-outline-variant);
		display: grid; place-items: center; cursor: pointer;
		box-shadow: 0 2px 8px rgba(0,0,0,0.12);
	}
	.hero-photo-btn .material-symbols-outlined { font-size: 1rem; color: var(--color-on-surface-variant); }
	.hero-spinner { animation: spin 1s linear infinite; }
	@keyframes spin { to { transform: rotate(360deg); } }

	.hero-identity {
		margin-top: var(--space-3); display: flex; flex-direction: column; align-items: center; gap: var(--space-2);
	}
	.hero-name {
		margin: 0; font-family: var(--font-display); font-weight: 900; font-size: 1.35rem; color: var(--color-on-surface); letter-spacing: -0.01em;
	}
	.hero-role {
		font-size: 0.7rem; font-weight: 800; text-transform: uppercase; letter-spacing: 0.1em;
		padding: 3px 12px; border-radius: 999px;
		background: var(--color-surface-container); color: var(--color-on-surface-variant);
	}
	.hero-role--gold {
		background: linear-gradient(135deg, var(--color-secondary), #a07c20); color: #fff;
		box-shadow: 0 2px 8px rgba(212,175,55,0.4);
	}

	.hero-stats {
		margin-top: var(--space-4); width: 100%;
		display: flex; align-items: stretch; gap: 0;
		padding: var(--space-3) 0 0; border-top: 1px solid var(--color-surface-container);
	}
	.hero-stat { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 3px; }
	.hero-stat-sep { width: 1px; background: var(--color-surface-container); margin: 0 var(--space-2); align-self: stretch; }
	.hero-stat-val { font-family: var(--font-display); font-size: 1.5rem; font-weight: 900; color: var(--color-on-surface); line-height: 1; }
	.hero-stat-lbl { font-size: 0.62rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: var(--color-on-surface-variant); }
	.hero-form-dots { display: flex; gap: 3px; align-items: baseline; }
	.hero-form-dot { font-family: var(--font-display); font-size: 0.72rem; font-weight: 800; color: var(--color-on-surface-variant); padding: 1px 3px; border-radius: 4px; }
	.hero-form-dot--hi { color: #16a34a; }
	.hero-form-dot--lo { color: var(--color-primary); }

	/* Action Cards */
	.action-cards { display: flex; flex-direction: column; gap: var(--space-3); }
	.action-card {
		display: flex; align-items: center; gap: var(--space-3); padding: var(--space-4);
		border-radius: var(--radius-lg); border: 1.5px solid transparent; text-align: left;
		cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 100ms ease;
		box-shadow: var(--shadow-card); width: 100%; font-family: inherit;
	}
	.action-card:active:not(.action-card--static) { transform: scale(0.98); }
	.action-card--static { cursor: default; }
	.action-card--warn { background: #fefce8; border-color: #fde047; }
	.action-card--gold { background: #fffbeb; border-color: #fbbf24; }
	.action-card--blue { background: #eff6ff; border-color: #93c5fd; }
	.action-icon { font-size: 1.4rem; flex-shrink: 0; font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; }
	.action-card--warn .action-icon { color: #ca8a04; }
	.action-card--gold .action-icon { color: #b45309; }
	.action-card--blue .action-icon { color: #1d4ed8; }
	.action-body { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
	.action-title { font-weight: 700; font-size: 0.9rem; color: var(--color-on-surface); }
	.action-sub   { font-size: 0.78rem; color: var(--color-on-surface-variant); }
	.action-cta   { font-size: 0.78rem; font-weight: 700; flex-shrink: 0; }
	.action-card--warn .action-cta, .action-card--gold .action-cta { color: #92400e; }
	.action-card--blue .action-cta { color: #1d4ed8; }

	/* Data card */
	.data-card {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.data-card-head { display: flex; justify-content: space-between; align-items: center; }
	.data-card-edit {
		display: inline-flex; align-items: center; gap: 4px;
		background: transparent; border: 1px solid var(--color-outline-variant);
		border-radius: 999px; padding: 4px 10px; font-size: 0.72rem; font-weight: 700;
		color: var(--color-on-surface-variant); cursor: pointer; font-family: inherit;
	}
	.data-card-edit .material-symbols-outlined { font-size: 0.88rem; }
	.data-card-edit:active { background: var(--color-surface-container-low); }

	.data-rows { display: flex; flex-direction: column; }
	.data-row {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) 0; border: none; background: none;
		border-top: 1px solid var(--color-surface-container);
		text-align: left; font-family: inherit; cursor: pointer; width: 100%;
		-webkit-tap-highlight-color: transparent;
	}
	.data-row:first-child { border-top: none; }
	.data-row:active:not(.data-row--readonly) { background: var(--color-surface-container-low); }
	.data-row--readonly { cursor: default; }
	.data-row-icon {
		font-size: 1.1rem; color: var(--color-primary); flex-shrink: 0;
		width: 24px; text-align: center;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.data-row-text { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
	.data-row-label { font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-on-surface-variant); }
	.data-row-value { font-size: 0.92rem; font-weight: 600; color: var(--color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
	.data-row-value--empty { color: var(--color-outline); font-weight: 500; font-style: italic; }
	.data-row-value.val-expired { color: var(--color-primary); font-weight: 800; }
	.data-row-value.val-soon { color: #b45309; font-weight: 700; }
	.data-row-arrow { color: var(--color-on-surface-variant); font-size: 1rem; flex-shrink: 0; }

	/* Next match: turn the card into a button */
	.next-match-card { width: 100%; text-align: left; cursor: pointer; font-family: inherit; -webkit-tap-highlight-color: transparent; }
	.next-match-card:active { transform: scale(0.99); }

	/* Edit sheet */
	.edit-form { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-2) var(--space-4) var(--space-6); }
	.edit-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); }
	.edit-actions { display: flex; gap: var(--space-2); margin-top: var(--space-3); }
	.edit-form :global(.mw-field) { margin-bottom: 0; }
	.edit-form :global(.mw-field > span) {
		font-family: var(--font-display); font-size: 0.7rem; font-weight: 700;
		letter-spacing: 0.06em; text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.edit-form :global(.mw-field input),
	.edit-form :global(.mw-field select) {
		width: 100%; padding: 10px 12px;
		border: 1px solid var(--color-outline-variant); border-radius: 10px;
		background: var(--color-surface-container-lowest); font-family: var(--font-body);
		font-size: 15px; color: var(--color-on-surface);
	}
	.edit-form :global(.mw-field input:focus),
	.edit-form :global(.mw-field select:focus) { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }
	.edit-form :global(.mw-field--focus input),
	.edit-form :global(.mw-field--focus select) { outline: 2px solid var(--color-primary); outline-offset: 1px; border-color: transparent; }
</style>
