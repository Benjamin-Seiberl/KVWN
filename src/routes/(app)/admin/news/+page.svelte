<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';

	let news  = $state([]);
	let polls = $state([]);

	// News Form
	let nTitle = $state('');
	let nBody  = $state('');
	let nImage = $state('');
	let nPinned = $state(false);

	// Poll Form
	let pQuestion = $state('');
	let pMulti    = $state(false);
	let pDeadline = $state('');
	let pOptions  = $state(['', '']);

	async function load() {
		const [{ data: n }, { data: p }] = await Promise.all([
			sb.from('announcements').select('*').order('created_at', { ascending: false }).limit(30),
			sb.from('polls').select('*, poll_options(id, label, order_index)').order('created_at', { ascending: false }).limit(30),
		]);
		news = n ?? [];
		polls = p ?? [];
	}

	async function createNews() {
		if (!nTitle || !nBody) return;
		await sb.from('announcements').insert({
			title: nTitle, body: nBody, image_url: nImage || null,
			pinned: nPinned, created_by: $playerId,
		});
		nTitle = ''; nBody = ''; nImage = ''; nPinned = false;
		load();
	}

	async function deleteNews(n) {
		if (!confirm('News löschen?')) return;
		await sb.from('announcements').delete().eq('id', n.id);
		load();
	}

	async function togglePin(n) {
		await sb.from('announcements').update({ pinned: !n.pinned }).eq('id', n.id);
		load();
	}

	async function createPoll() {
		const opts = pOptions.filter(o => o.trim()).map((o, i) => ({ label: o.trim(), order_index: i }));
		if (!pQuestion || opts.length < 2) return;
		const { data: poll } = await sb.from('polls').insert({
			question: pQuestion,
			multi_select: pMulti,
			deadline: pDeadline || null,
			created_by: $playerId,
		}).select().maybeSingle();
		if (!poll) return;
		await sb.from('poll_options').insert(opts.map(o => ({ ...o, poll_id: poll.id })));
		pQuestion = ''; pMulti = false; pDeadline = ''; pOptions = ['', ''];
		load();
	}

	async function deletePoll(p) {
		if (!confirm('Poll löschen?')) return;
		await sb.from('polls').delete().eq('id', p.id);
		load();
	}

	onMount(load);
</script>

<div class="page">
	<section class="admin-card">
		<h2>Neue Ankündigung</h2>
		<input placeholder="Titel" bind:value={nTitle} />
		<textarea placeholder="Text" rows="3" bind:value={nBody}></textarea>
		<input placeholder="Bild-URL (optional)" bind:value={nImage} />
		<label class="cbx"><input type="checkbox" bind:checked={nPinned} /> Anpinnen</label>
		<button class="btn btn--primary" onclick={createNews} disabled={!nTitle || !nBody}>
			<span class="material-symbols-outlined">campaign</span> Veröffentlichen
		</button>

		<h3>Aktuelle News</h3>
		<ul class="nlist">
			{#each news as n}
				<li>
					<div>
						<strong>{n.title}</strong>{#if n.pinned}<span class="pin">📌</span>{/if}
						<p class="sm">{n.body?.slice(0, 100)}{n.body?.length > 100 ? '…' : ''}</p>
					</div>
					<div class="actions">
						<button class="mini" onclick={() => togglePin(n)}>
							<span class="material-symbols-outlined">{n.pinned ? 'keep_off' : 'keep'}</span>
						</button>
						<button class="mini mini--danger" onclick={() => deleteNews(n)}>
							<span class="material-symbols-outlined">delete</span>
						</button>
					</div>
				</li>
			{/each}
		</ul>
	</section>

	<section class="admin-card">
		<h2>Neue Umfrage</h2>
		<input placeholder="Frage" bind:value={pQuestion} />
		<div class="opts">
			{#each pOptions as _, i}
				<input placeholder="Option {i + 1}" bind:value={pOptions[i]} />
			{/each}
			<button class="mini" type="button" onclick={() => pOptions = [...pOptions, '']}>
				<span class="material-symbols-outlined">add</span> Option
			</button>
		</div>
		<label class="cbx"><input type="checkbox" bind:checked={pMulti} /> Mehrfachauswahl</label>
		<label class="field">
			<span>Deadline (optional)</span>
			<input type="datetime-local" bind:value={pDeadline} />
		</label>
		<button class="btn btn--primary" onclick={createPoll} disabled={!pQuestion}>
			<span class="material-symbols-outlined">ballot</span> Umfrage starten
		</button>

		<h3>Laufende Umfragen</h3>
		<ul class="nlist">
			{#each polls as p}
				<li>
					<div>
						<strong>{p.question}</strong>
						<p class="sm">{p.poll_options?.length ?? 0} Optionen{p.multi_select ? ' · Multi' : ''}</p>
					</div>
					<button class="mini mini--danger" onclick={() => deletePoll(p)}>
						<span class="material-symbols-outlined">delete</span>
					</button>
				</li>
			{/each}
		</ul>
	</section>
</div>

<style>
	.admin-card { background: var(--color-surface, #fff); border: 1px solid var(--color-border, #eee); border-radius: 14px; padding: var(--space-4); margin-bottom: var(--space-4); display: flex; flex-direction: column; gap: 8px; }
	h2 { font-family: 'Lexend'; font-weight: 600; font-size: 1rem; margin: 0; color: var(--color-primary, #CC0000); }
	h3 { font-family: 'Lexend'; font-weight: 500; font-size: 0.9rem; margin: var(--space-3) 0 var(--space-1); }
	input, textarea { padding: 8px; border: 1px solid var(--color-border, #ddd); border-radius: 8px; font-size: 16px; width: 100%; box-sizing: border-box; }
	.cbx { display: inline-flex; gap: 6px; align-items: center; font-size: 0.9rem; }
	.field { display: flex; flex-direction: column; gap: 2px; font-size: 0.85rem; color: var(--color-text-soft, #666); }
	.btn { display: inline-flex; gap: 4px; align-items: center; justify-content: center; padding: 10px 16px; border: 0; border-radius: 999px; font-size: 0.95rem; cursor: pointer; align-self: flex-start; }
	.btn--primary { background: var(--color-primary, #CC0000); color: #fff; }
	.nlist { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 6px; }
	.nlist li { display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; padding: 8px; border: 1px solid var(--color-border, #eee); border-radius: 8px; }
	.sm { margin: 2px 0 0; font-size: 0.8rem; color: var(--color-text-soft, #888); }
	.pin { margin-left: 4px; font-size: 0.8rem; }
	.actions { display: flex; gap: 4px; }
	.mini { padding: 4px 8px; font-size: 0.8rem; background: var(--color-surface, #f5f5f5); border: 1px solid var(--color-border, #eee); border-radius: 999px; cursor: pointer; display: inline-flex; align-items: center; gap: 2px; }
	.mini--danger { color: var(--color-primary, #CC0000); }
	.opts { display: flex; flex-direction: column; gap: 6px; }
</style>
