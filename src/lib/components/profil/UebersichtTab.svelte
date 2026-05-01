<script>
	import { sb }                   from '$lib/supabase';
	import { playerId }             from '$lib/stores/auth.js';
	import { triggerToast }         from '$lib/stores/toast.js';
	import { fmtDate, daysUntil } from '$lib/utils/dates.js';
	import { formatIbanMasked }     from '$lib/utils/players.js';

	import ProfilHeroCard           from './ProfilHeroCard.svelte';
	import ProfilActionCards        from './ProfilActionCards.svelte';
	import ProfilMitgliedschaftCard from './ProfilMitgliedschaftCard.svelte';
	import ProfilDatenAccordion     from './ProfilDatenAccordion.svelte';
	import ProfilDatenSheet         from './ProfilDatenSheet.svelte';
	import ProfilEinwilligungenCard from './ProfilEinwilligungenCard.svelte';
	import ProfilAbwesenheitCard    from './ProfilAbwesenheitCard.svelte';

	// All player columns this tab reads — explicit to tolerate pending migration.
	// See supabase/migrations/20260422_profil_selfservice.sql
	const PLAYER_FIELDS = [
		'id','name','email','phone','address','avatar_url','photo','role',
		'shirt_size','pants_size','spielerpass_nr','medical_exam_expiry',
		'birth_date','push_prefs',
		'iban','account_holder',
		'member_since','membership_status',
		'consent_photo','consent_liga_data','consent_whatsapp','consent_accepted_at',
		'attest_url',
	].join(', ');

	let me        = $state(null);
	let scores    = $state([]);
	let allScores = $state([]);
	let loading   = $state(true);

	let editSheetOpen = $state(false);
	let editSection   = $state('kontakt');
	let editFocus     = $state('');
	let editForm      = $state({});

	$effect(() => { if ($playerId) loadData($playerId); });

	async function loadData(pid) {
		loading = true;
		try {
			const [
				{ data: p,  error: e1 },
				{ data: sc, error: e2 },
				{ data: all },
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
			]);
			if (e1) triggerToast('Fehler: ' + e1.message);
			if (e2) triggerToast('Fehler: ' + e2.message);

			me        = p;
			scores    = (sc ?? []).map(g => Number(g.score));
			allScores = all ?? [];
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

	const missingFields = $derived.by(() => {
		if (!me) return [];
		const m = [];
		if (!me.phone)                   m.push('Telefon');
		if (!me.address)                 m.push('Adresse');
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
			{ key: 'spielerpass_nr',      label: 'Spielerpass-Nr.',  value: me.spielerpass_nr, icon: 'badge' },
			{ key: 'medical_exam_expiry', label: 'Ärztl. Attest gültig bis', value: attest?.text ?? null, valueClass: attest?.cls ?? '', icon: 'medical_information' },
			{ key: 'attest_url',          label: 'Attest-Datei',     value: me.attest_url ? 'Hochgeladen' : null, icon: 'description' },
		];
	});

	const zahlungRows = $derived.by(() => {
		if (!me) return [];
		return [
			{ key: 'iban',           label: 'IBAN',          value: formatIbanMasked(me.iban), icon: 'account_balance' },
			{ key: 'account_holder', label: 'Kontoinhaber',  value: me.account_holder,         icon: 'person' },
		];
	});

	const dataSections = $derived([
		{ key: 'kontakt', title: 'Kontakt & Adresse',  icon: 'contact_page',        rows: kontaktRows },
		{ key: 'sport',   title: 'Sport-Ausrüstung',   icon: 'sports_and_outdoors', rows: sportRows },
		{ key: 'zahlung', title: 'Zahlung',            icon: 'account_balance',     rows: zahlungRows },
	]);

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
				spielerpass_nr:      me.spielerpass_nr ?? '',
				medical_exam_expiry: me.medical_exam_expiry ?? '',
				attest_url:          me.attest_url ?? '',
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
			payload = {
				shirt_size:          editForm.shirt_size || null,
				pants_size:          editForm.pants_size?.trim() || null,
				spielerpass_nr:      editForm.spielerpass_nr?.trim() || null,
				medical_exam_expiry: editForm.medical_exam_expiry || null,
				attest_url:          editForm.attest_url || null,
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

		<ProfilDatenAccordion sections={dataSections} onEdit={openEdit} />

		<ProfilEinwilligungenCard {me} onUpdated={onConsentUpdated} />

		<ProfilAbwesenheitCard />
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
