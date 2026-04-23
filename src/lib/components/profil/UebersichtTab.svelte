<script>
	import { sb }                   from '$lib/supabase';
	import { playerId }             from '$lib/stores/auth.js';
	import { triggerToast }         from '$lib/stores/toast.js';
	import { fmtDate, toDateStr, daysUntil } from '$lib/utils/dates.js';
	import { formatIbanMasked }     from '$lib/utils/players.js';

	import ProfilHeroCard           from './ProfilHeroCard.svelte';
	import ProfilActionCards        from './ProfilActionCards.svelte';
	import ProfilMitgliedschaftCard from './ProfilMitgliedschaftCard.svelte';
	import ProfilDatenCard          from './ProfilDatenCard.svelte';
	import ProfilDatenSheet         from './ProfilDatenSheet.svelte';
	import ProfilEinwilligungenCard from './ProfilEinwilligungenCard.svelte';
	import ProfilTermineCard        from './ProfilTermineCard.svelte';
	import ProfilAbwesenheitCard    from './ProfilAbwesenheitCard.svelte';
	import ProfilMeilensteineCard   from './ProfilMeilensteineCard.svelte';

	// All player columns this tab reads — explicit to tolerate pending migration.
	// See supabase/migrations/20260422_profil_selfservice.sql
	const PLAYER_FIELDS = [
		'id','name','email','phone','address','avatar_url','photo','role',
		'shirt_size','pants_size','spielerpass_nr','medical_exam_expiry',
		'birth_date','push_prefs',
		// Phase B columns
		'jersey_number','shoe_size',
		'emergency_contact_name','emergency_contact_phone',
		'iban','account_holder',
		'member_since','membership_status',
		'drivers_license','default_car_seats','dietary_notes',
		'consent_photo','consent_liga_data','consent_whatsapp','consent_accepted_at',
		'attest_url',
	].join(', ');

	let me        = $state(null);
	let scores    = $state([]);
	let allScores = $state([]);
	let events    = $state([]);
	let rsvps     = $state([]);
	let loading   = $state(true);

	let editSheetOpen = $state(false);
	let editSection   = $state('kontakt');
	let editFocus     = $state('');
	let editForm      = $state({});

	$effect(() => { if ($playerId) loadData($playerId); });

	async function loadData(pid) {
		loading = true;
		try {
			const today = toDateStr(new Date());
			const [
				{ data: p,  error: e1 },
				{ data: sc, error: e2 },
				{ data: all },
				{ data: ev, error: e4 },
				{ data: rs },
			] = await Promise.all([
				sb.from('players')
					.select(PLAYER_FIELDS)
					.eq('id', pid).maybeSingle(),
				sb.from('game_plan_players')
					.select('score, game_plans!inner(cal_week)')
					.eq('player_id', pid).eq('played', true).not('score', 'is', null)
					.order('cal_week', { referencedTable: 'game_plans', ascending: false }),
				sb.from('game_plan_players')
					.select('player_id, score').eq('played', true).not('score', 'is', null),
				sb.from('events')
					.select('id, title, date, time, location, external_id')
					.gte('date', today).order('date').limit(6),
				sb.from('event_rsvps').select('event_id, response').eq('player_id', pid),
			]);
			if (e1) triggerToast('Fehler: ' + e1.message);
			if (e2) triggerToast('Fehler: ' + e2.message);
			if (e4) triggerToast('Fehler: ' + e4.message);

			me        = p;
			scores    = (sc ?? []).map(g => Number(g.score));
			allScores = all ?? [];
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

	const missingFields = $derived.by(() => {
		if (!me) return [];
		const m = [];
		if (!me.phone)                   m.push('Telefon');
		if (!me.address)                 m.push('Adresse');
		if (!me.emergency_contact_phone) m.push('Notfallkontakt');
		if (!me.shirt_size)              m.push('Trikotgröße');
		if (!me.spielerpass_nr)          m.push('Spielerpass-Nr.');
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

	function fmtAttestValue(d) {
		if (!d) return null;
		const days = daysUntil(d);
		if (days < 0)   return { text: `Abgelaufen seit ${fmtDate(d)}`, cls: 'val-expired' };
		if (days <= 30) return { text: `${fmtDate(d)} (${days}d)`,       cls: 'val-soon' };
		return { text: fmtDate(d), cls: '' };
	}

	// ── Row definitions per section ─────────────────────────────────────────────
	const kontaktRows = $derived.by(() => {
		if (!me) return [];
		return [
			{ key: 'phone',      label: 'Telefon',       value: me.phone,   icon: 'call' },
			{ key: 'email',      label: 'E-Mail',        value: me.email,   icon: 'mail', readonly: true },
			{ key: 'address',    label: 'Adresse',       value: me.address, icon: 'home' },
			{ key: 'birth_date', label: 'Geburtsdatum',  value: me.birth_date ? fmtDate(me.birth_date) : null, icon: 'cake' },
		];
	});

	const sportRows = $derived.by(() => {
		if (!me) return [];
		const attest = fmtAttestValue(me.medical_exam_expiry);
		return [
			{ key: 'shirt_size',          label: 'Trikotgröße',      value: me.shirt_size,    icon: 'apparel' },
			{ key: 'pants_size',          label: 'Hosengröße',       value: me.pants_size,    icon: 'straighten' },
			{ key: 'shoe_size',           label: 'Schuhgröße',       value: me.shoe_size,     icon: 'footprint' },
			{ key: 'jersey_number',       label: 'Trikotnummer',     value: me.jersey_number != null ? String(me.jersey_number) : null, icon: 'tag' },
			{ key: 'spielerpass_nr',      label: 'Spielerpass-Nr.',  value: me.spielerpass_nr, icon: 'badge' },
			{ key: 'medical_exam_expiry', label: 'Ärztl. Attest gültig bis', value: attest?.text ?? null, valueClass: attest?.cls ?? '', icon: 'medical_information' },
			{ key: 'attest_url',          label: 'Attest-Datei',     value: me.attest_url ? 'Hochgeladen' : null, icon: 'description' },
		];
	});

	const notfallRows = $derived.by(() => {
		if (!me) return [];
		return [
			{ key: 'emergency_contact_name',  label: 'Kontaktperson', value: me.emergency_contact_name,  icon: 'person' },
			{ key: 'emergency_contact_phone', label: 'Telefon',       value: me.emergency_contact_phone, icon: 'call' },
		];
	});

	const mobilitaetRows = $derived.by(() => {
		if (!me) return [];
		return [
			{ key: 'drivers_license',   label: 'Führerschein', value: me.drivers_license ? 'Ja' : (me.drivers_license === false ? 'Nein' : null), icon: 'directions_car' },
			{ key: 'default_car_seats', label: 'Plätze im Auto', value: me.default_car_seats != null ? String(me.default_car_seats) : null, icon: 'event_seat' },
			{ key: 'dietary_notes',     label: 'Ernährungshinweise', value: me.dietary_notes, icon: 'restaurant' },
		];
	});

	const zahlungRows = $derived.by(() => {
		if (!me) return [];
		return [
			{ key: 'iban',           label: 'IBAN',          value: formatIbanMasked(me.iban), icon: 'account_balance' },
			{ key: 'account_holder', label: 'Kontoinhaber',  value: me.account_holder,         icon: 'person' },
		];
	});

	// ── Edit orchestration ──────────────────────────────────────────────────────
	function openEdit(section, focus = '') {
		if (!me) return;
		if (section === 'kontakt') {
			editForm = {
				name:       me.name ?? '',
				email:      me.email ?? '',
				phone:      me.phone ?? '',
				address:    me.address ?? '',
				birth_date: me.birth_date ?? '',
			};
		} else if (section === 'sport') {
			editForm = {
				shirt_size:          me.shirt_size ?? '',
				pants_size:          me.pants_size ?? '',
				shoe_size:           me.shoe_size ?? '',
				jersey_number:       me.jersey_number ?? null,
				spielerpass_nr:      me.spielerpass_nr ?? '',
				medical_exam_expiry: me.medical_exam_expiry ?? '',
				attest_url:          me.attest_url ?? '',
			};
		} else if (section === 'notfall') {
			editForm = {
				emergency_contact_name:  me.emergency_contact_name  ?? '',
				emergency_contact_phone: me.emergency_contact_phone ?? '',
			};
		} else if (section === 'mobilitaet') {
			editForm = {
				drivers_license:    !!me.drivers_license,
				default_car_seats:  me.default_car_seats ?? null,
				dietary_notes:      me.dietary_notes ?? '',
			};
		} else if (section === 'zahlung') {
			editForm = {
				iban:           me.iban ?? '',
				account_holder: me.account_holder ?? '',
			};
		} else {
			return;
		}
		editSection   = section;
		editFocus     = focus;
		editSheetOpen = true;
	}

	async function saveEdit(section) {
		let payload = null;
		if (section === 'kontakt') {
			payload = {
				name:       editForm.name?.trim() || null,
				phone:      editForm.phone?.trim() || null,
				address:    editForm.address?.trim() || null,
				birth_date: editForm.birth_date || null,
			};
		} else if (section === 'sport') {
			const jn = editForm.jersey_number;
			payload = {
				shirt_size:          editForm.shirt_size || null,
				pants_size:          editForm.pants_size?.trim() || null,
				shoe_size:           editForm.shoe_size?.trim() || null,
				jersey_number:       jn === '' || jn == null ? null : Number(jn),
				spielerpass_nr:      editForm.spielerpass_nr?.trim() || null,
				medical_exam_expiry: editForm.medical_exam_expiry || null,
				attest_url:          editForm.attest_url || null,
			};
		} else if (section === 'notfall') {
			payload = {
				emergency_contact_name:  editForm.emergency_contact_name?.trim()  || null,
				emergency_contact_phone: editForm.emergency_contact_phone?.trim() || null,
			};
		} else if (section === 'mobilitaet') {
			const cs = editForm.default_car_seats;
			payload = {
				drivers_license:   !!editForm.drivers_license,
				default_car_seats: cs === '' || cs == null ? null : Number(cs),
				dietary_notes:     editForm.dietary_notes?.trim() || null,
			};
		} else if (section === 'zahlung') {
			payload = {
				iban:           editForm.iban?.replace(/\s+/g, '').toUpperCase() || null,
				account_holder: editForm.account_holder?.trim() || null,
			};
		} else {
			return;
		}

		const { error } = await sb.from('players').update(payload).eq('id', me.id);
		if (error) { triggerToast('Fehler: ' + error.message); return; }
		me = { ...me, ...payload };
		editSheetOpen = false;
		triggerToast('Gespeichert');
	}

	function onHeroUpdated(patch) {
		me = { ...me, ...patch };
	}

	function onConsentUpdated(patch) {
		me = { ...me, ...patch };
	}
</script>

{#if loading}
	<div class="ueb-loading">
		<div class="ueb-skeleton shimmer-box"></div>
		<div class="ueb-skeleton ueb-skeleton--short shimmer-box"></div>
		<div class="ueb-skeleton shimmer-box"></div>
	</div>
{:else if me}
	<div class="ueb-page">
		<ProfilHeroCard {me} {stats} {last5} onUpdated={onHeroUpdated} />

		<ProfilActionCards
			{attestStatus}
			{missingFields}
			{birthdaySoon}
			onEdit={openEdit}
		/>

		<ProfilMitgliedschaftCard {me} />

		<ProfilDatenCard
			section="kontakt"
			title="Kontakt & Adresse"
			icon="contact_page"
			rows={kontaktRows}
			onEdit={openEdit}
		/>

		<ProfilDatenCard
			section="notfall"
			title="Notfallkontakt"
			icon="emergency"
			rows={notfallRows}
			onEdit={openEdit}
		/>

		<ProfilDatenCard
			section="sport"
			title="Sport-Ausrüstung"
			icon="sports_and_outdoors"
			rows={sportRows}
			onEdit={openEdit}
		/>

		<ProfilDatenCard
			section="mobilitaet"
			title="Mobilität & Verpflegung"
			icon="directions_car"
			rows={mobilitaetRows}
			onEdit={openEdit}
		/>

		<ProfilDatenCard
			section="zahlung"
			title="Zahlung"
			icon="account_balance"
			rows={zahlungRows}
			onEdit={openEdit}
		/>

		<ProfilEinwilligungenCard {me} onUpdated={onConsentUpdated} />

		<ProfilTermineCard
			{events}
			bind:rsvps
			onReload={() => loadData($playerId)}
		/>

		<ProfilAbwesenheitCard />

		<ProfilMeilensteineCard {milestones} />
	</div>
{/if}

<ProfilDatenSheet
	bind:open={editSheetOpen}
	section={editSection}
	focus={editFocus}
	bind:form={editForm}
	playerId={me?.id ?? null}
	onSave={saveEdit}
	onClose={() => { editSheetOpen = false; }}
/>

<style>
	.ueb-page { padding: var(--space-5) var(--space-5) var(--space-10); display: flex; flex-direction: column; gap: var(--space-5); }
	.ueb-loading { padding: var(--space-5); display: flex; flex-direction: column; gap: var(--space-4); }
	.ueb-skeleton { height: 120px; border-radius: var(--radius-lg); }
	.ueb-skeleton--short { height: 56px; }
</style>
