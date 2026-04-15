<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { parseMatchesCsv } from '$lib/utils/csvParser.js';
	import { playerId } from '$lib/stores/auth';

	let seasons = $state([]);
	let events = $state([]);
	let leagues = $state([]);

	// CSV-Import
	let csvText = $state('');
	let csvPreview = $state([]);
	let csvErrors  = $state([]);
	let importing  = $state(false);
	let importMsg  = $state('');

	// Event-Erstellung
	let evTitle = $state('');
	let evDate  = $state('');
	let evTime  = $state('');
	let evLoc   = $state('');
	let evDesc  = $state('');

	// Saison
	let newSeasonName  = $state('');
	let newSeasonStart = $state('');
	let newSeasonEnd   = $state('');

	async function load() {
		const [{ data: s }, { data: e }, { data: l }] = await Promise.all([
			sb.from('seasons').select('*').order('start_date', { ascending: false }),
			sb.from('events').select('*').order('date', { ascending: false }).limit(30),
			sb.from('leagues').select('*').order('tier'),
		]);
		seasons = s ?? [];
		events  = e ?? [];
		leagues = l ?? [];
	}

	function parseFile(e) {
		const file = e.target.files?.[0];
		if (!file) return;
		const reader = new FileReader();
		reader.onload = () => {
			csvText = String(reader.result);
			const { rows, errors } = parseMatchesCsv(csvText);
			csvPreview = rows;
			csvErrors  = errors;
		};
		reader.readAsText(file);
	}

	async function confirmImport() {
		if (!csvPreview.length) return;
		importing = true; importMsg = '';
		const payload = csvPreview.map(r => {
			const league = leagues.find(l => l.name.toLowerCase() === (r.league || '').toLowerCase());
			return {
				date: r.date,
				time: r.time,
				league_id: league?.id ?? null,
				home_away: r.home_away,
				opponent:  r.opponent,
				location:  r.location,
				round:     r.round,
				season:    seasons.find(x => x.is_current)?.name ?? null,
			};
		});
		const { error } = await sb.from('matches').insert(payload);
		importing = false;
		if (error) importMsg = `❌ ${error.message}`;
		else { importMsg = `✅ ${payload.length} Matches importiert`; csvPreview = []; csvText = ''; }
	}

	async function createEvent() {
		if (!evTitle || !evDate) return;
		const { error } = await sb.from('events').insert({
			title: evTitle, date: evDate, time: evTime || null,
			location: evLoc || null, description: evDesc || null,
			created_by: $playerId,
		});
		if (!error) {
			evTitle = ''; evDate = ''; evTime = ''; evLoc = ''; evDesc = '';
			load();
		}
	}

	async function deleteEvent(e) {
		if (!confirm(`Event „${e.title}" löschen?`)) return;
		await sb.from('events').delete().eq('id', e.id);
		load();
	}

	async function createSeason() {
		if (!newSeasonName || !newSeasonStart || !newSeasonEnd) return;
		await sb.from('seasons').insert({
			name: newSeasonName, start_date: newSeasonStart, end_date: newSeasonEnd,
		});
		newSeasonName = ''; newSeasonStart = ''; newSeasonEnd = '';
		load();
	}

	async function setCurrent(s) {
		await sb.from('seasons').update({ is_current: false }).neq('id', s.id);
		await sb.from('seasons').update({ is_current: true }).eq('id', s.id);
		load();
	}

	onMount(load);
</script>

<div class="page">
	<section class="admin-card">
		<h2>Saisonen</h2>
		<ul class="sublist">
			{#each seasons as s}
				<li>
					<strong>{s.name}</strong> ({s.start_date} – {s.end_date})
					{#if s.is_current}<span class="pill">aktuell</span>{:else}
						<button class="mini" onclick={() => setCurrent(s)}>als aktuell setzen</button>
					{/if}
				</li>
			{/each}
		</ul>
		<div class="row">
			<input placeholder="Name (z.B. 2026/27)" bind:value={newSeasonName} />
			<input type="date" bind:value={newSeasonStart} />
			<input type="date" bind:value={newSeasonEnd} />
			<button class="btn btn--primary" onclick={createSeason}>
				<span class="material-symbols-outlined">add</span>
			</button>
		</div>
	</section>

	<section class="admin-card">
		<h2>Match-CSV-Import</h2>
		<p class="hint">Spalten: <code>date,time,league,home_away,opponent,location,round</code> (Semikolon oder Komma)</p>
		<input type="file" accept=".csv,text/csv" onchange={parseFile} />
		{#if csvPreview.length}
			<div class="preview">
				<p><strong>{csvPreview.length} Zeilen bereit:</strong></p>
				<ul class="small">
					{#each csvPreview.slice(0, 8) as r}
						<li>{r.date} {r.time ?? ''} {r.league ?? ''} {r.home_away ?? ''} vs {r.opponent} @{r.location ?? ''}</li>
					{/each}
					{#if csvPreview.length > 8}<li>… +{csvPreview.length - 8}</li>{/if}
				</ul>
				{#each csvErrors as err}<p class="err">⚠ {err}</p>{/each}
				<button class="btn btn--primary" onclick={confirmImport} disabled={importing}>
					<span class="material-symbols-outlined">upload</span>
					{importing ? 'Importieren…' : 'Bestätigen & importieren'}
				</button>
			</div>
		{/if}
		{#if importMsg}<p class="msg">{importMsg}</p>{/if}
	</section>

	<section class="admin-card">
		<h2>Neues Event</h2>
		<div class="col">
			<input placeholder="Titel (z.B. Jahreshauptversammlung)" bind:value={evTitle} />
			<div class="row">
				<input type="date" bind:value={evDate} />
				<input type="time" bind:value={evTime} />
			</div>
			<input placeholder="Ort" bind:value={evLoc} />
			<textarea rows="2" placeholder="Beschreibung" bind:value={evDesc}></textarea>
			<button class="btn btn--primary" onclick={createEvent} disabled={!evTitle || !evDate}>
				<span class="material-symbols-outlined">event</span>
				Event erstellen
			</button>
		</div>
		<h3>Bestehende</h3>
		<ul class="sublist">
			{#each events as e}
				<li>
					<strong>{e.date}{e.time ? ' ' + String(e.time).slice(0,5) : ''}</strong> — {e.title}
					<button class="mini mini--danger" onclick={() => deleteEvent(e)}>
						<span class="material-symbols-outlined">delete</span>
					</button>
				</li>
			{/each}
		</ul>
	</section>
</div>

<style>
	.admin-card {
		background: var(--color-surface, #fff);
		border: 1px solid var(--color-border, #eee);
		border-radius: 14px;
		padding: var(--space-4);
		margin-bottom: var(--space-4);
	}
	h2 { font-family: 'Lexend'; font-weight: 600; font-size: 1rem; margin: 0 0 var(--space-2); color: var(--color-primary, #CC0000); }
	h3 { font-family: 'Lexend'; font-weight: 500; font-size: 0.9rem; margin: var(--space-3) 0 var(--space-1); }
	.sublist { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 6px; font-size: 0.9rem; }
	.sublist li { display: flex; align-items: center; gap: 8px; }
	.pill { padding: 2px 8px; border-radius: 999px; background: var(--color-secondary, #D4AF37); color: #fff; font-size: 0.75rem; font-weight: 600; }
	.row { display: flex; gap: 6px; margin-top: var(--space-2); flex-wrap: wrap; }
	.col { display: flex; flex-direction: column; gap: 6px; }
	.row input, .col input, .col textarea { flex: 1; min-width: 0; padding: 8px; border: 1px solid var(--color-border, #ddd); border-radius: 8px; font-size: 16px; }
	.btn { display: inline-flex; gap: 4px; align-items: center; padding: 8px 14px; border: 0; border-radius: 999px; font-size: 0.9rem; cursor: pointer; }
	.btn--primary { background: var(--color-primary, #CC0000); color: #fff; }
	.mini { padding: 2px 8px; font-size: 0.72rem; background: var(--color-surface, #f5f5f5); border: 1px solid var(--color-border, #eee); border-radius: 999px; cursor: pointer; }
	.mini--danger { color: var(--color-primary, #CC0000); border: 0; background: none; }
	.hint { font-size: 0.8rem; color: var(--color-text-soft, #888); margin: 0 0 var(--space-2); }
	.hint code { background: #f3f3f3; padding: 1px 5px; border-radius: 4px; font-size: 0.75rem; }
	.preview { margin-top: var(--space-2); }
	.small { font-size: 0.78rem; color: var(--color-text-soft, #666); }
	.err { color: var(--color-primary, #CC0000); font-size: 0.82rem; margin: 2px 0; }
	.msg { margin-top: var(--space-2); font-size: 0.9rem; }
</style>
