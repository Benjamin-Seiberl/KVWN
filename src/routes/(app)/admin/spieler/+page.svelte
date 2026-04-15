<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import BottomSheet from '$lib/components/BottomSheet.svelte';

	let players = $state([]);
	let inviteOpen = $state(false);
	let inviteEmail = $state('');
	let inviteName  = $state('');
	let inviteRole  = $state('user');
	let sending     = $state(false);
	let inviteMsg   = $state('');

	async function load() {
		const { data } = await sb
			.from('players')
			.select('id, name, email, role, active, avatar_url, phone')
			.order('name');
		players = data ?? [];
	}

	async function setRole(p, role) {
		const { error } = await sb.from('players').update({ role }).eq('id', p.id);
		if (!error) load();
	}

	async function toggleActive(p) {
		const { error } = await sb.from('players').update({ active: !p.active }).eq('id', p.id);
		if (!error) load();
	}

	async function sendInvite() {
		if (!inviteEmail.trim()) return;
		sending = true; inviteMsg = '';
		try {
			const { data: { session } } = await sb.auth.getSession();
			const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/invite-player`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
					Authorization: `Bearer ${session?.access_token ?? ''}`,
				},
				body: JSON.stringify({
					email: inviteEmail.trim(),
					name:  inviteName.trim() || null,
					role:  inviteRole,
				}),
			});
			if (!res.ok) {
				const err = await res.json().catch(() => ({}));
				inviteMsg = `❌ ${err.error || 'Einladung fehlgeschlagen'}`;
			} else {
				inviteMsg = '✅ Einladung gesendet';
				inviteEmail = ''; inviteName = '';
				load();
			}
		} catch (e) {
			inviteMsg = `❌ ${e.message}`;
		} finally {
			sending = false;
		}
	}

	onMount(load);
</script>

<div class="page">
	<header class="page-head">
		<h2>Spieler ({players.length})</h2>
		<button class="btn btn--primary" onclick={() => { inviteOpen = true; inviteMsg = ''; }}>
			<span class="material-symbols-outlined">person_add</span>
			Einladen
		</button>
	</header>

	<ul class="plist">
		{#each players as p}
			<li class="p-item">
				<div class="p-avatar">
					{#if p.avatar_url}<img src={p.avatar_url} alt={p.name} />{:else}<span>{(p.name || '?').slice(0,1)}</span>{/if}
				</div>
				<div class="p-info">
					<div class="p-name">{p.name}</div>
					<div class="p-meta">{p.email ?? 'kein Login'}{p.phone ? ' · ' + p.phone : ''}</div>
				</div>
				<select class="p-role" value={p.role} onchange={(e) => setRole(p, e.target.value)}>
					<option value="user">Spieler</option>
					<option value="kapitaen">Kapitän</option>
					<option value="admin">Admin</option>
				</select>
				<button
					class="p-toggle"
					class:p-toggle--off={!p.active}
					aria-label={p.active ? 'Deaktivieren' : 'Aktivieren'}
					onclick={() => toggleActive(p)}
				>
					<span class="material-symbols-outlined">{p.active ? 'check_circle' : 'block'}</span>
				</button>
			</li>
		{/each}
	</ul>
</div>

<BottomSheet bind:open={inviteOpen} title="Spieler einladen">
	<div class="mw-field">
		<label class="mw-field__label" for="inv-name">Name</label>
		<input id="inv-name" type="text" bind:value={inviteName} placeholder="Vorname Nachname" />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="inv-email">E-Mail</label>
		<input id="inv-email" type="email" bind:value={inviteEmail} placeholder="spieler@example.at" />
	</div>
	<div class="mw-field">
		<label class="mw-field__label" for="inv-role">Rolle</label>
		<select id="inv-role" bind:value={inviteRole}>
			<option value="user">Spieler</option>
			<option value="kapitaen">Kapitän</option>
			<option value="admin">Admin</option>
		</select>
	</div>
	{#if inviteMsg}<p class="inv-msg">{inviteMsg}</p>{/if}
	<button class="mw-btn mw-btn--primary mw-btn--wide" disabled={sending || !inviteEmail} onclick={sendInvite}>
		<span class="material-symbols-outlined">send</span>
		{sending ? 'Senden…' : 'Magic-Link senden'}
	</button>
</BottomSheet>

<style>
	.page-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: var(--space-3); }
	.page-head h2 { font-family: 'Lexend', sans-serif; font-weight: 600; margin: 0; font-size: 1.15rem; }
	.btn { display: inline-flex; gap: 4px; align-items: center; padding: 8px 14px; border: 0; border-radius: 999px; font-size: 0.9rem; cursor: pointer; }
	.btn--primary { background: var(--color-primary, #CC0000); color: #fff; }
	.btn :global(.material-symbols-outlined) { font-size: 1rem; }
	.plist { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: var(--space-2); }
	.p-item {
		display: grid;
		grid-template-columns: 44px 1fr auto auto;
		gap: var(--space-2); align-items: center;
		padding: 10px 12px;
		background: var(--color-surface, #fff);
		border: 1px solid var(--color-border, #eee);
		border-radius: 12px;
	}
	.p-avatar { width: 44px; height: 44px; border-radius: 50%; overflow: hidden; background: #eee; display: grid; place-items: center; font-weight: 600; color: #999; }
	.p-avatar img { width: 100%; height: 100%; object-fit: cover; }
	.p-name { font-weight: 500; }
	.p-meta { font-size: 0.78rem; color: var(--color-text-soft, #888); }
	.p-role { padding: 4px 6px; border-radius: 6px; border: 1px solid var(--color-border, #ddd); font-size: 0.85rem; background: #fff; }
	.p-toggle { background: none; border: 0; padding: 4px; cursor: pointer; color: var(--color-success, #2a9d57); }
	.p-toggle--off { color: var(--color-text-soft, #aaa); }
	.inv-msg { margin: var(--space-2) 0; font-size: 0.9rem; }
</style>
