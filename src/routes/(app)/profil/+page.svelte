<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId, user, signOut, playerRole } from '$lib/stores/auth';
	import { registerPush, unregisterPush, pushStatus } from '$lib/push/register.js';

	let me = $state(null);
	let uploading = $state(false);
	let msg = $state('');
	let pushOn = $state(false);

	async function load() {
		if (!$playerId) return;
		const { data } = await sb.from('players')
			.select('id, name, email, phone, avatar_url, photo, push_prefs, role')
			.eq('id', $playerId).maybeSingle();
		me = data;
		pushOn = await pushStatus();
	}

	async function save() {
		msg = '';
		const { error } = await sb.from('players').update({
			name:  me.name,
			phone: me.phone,
			push_prefs: me.push_prefs,
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
			if (pushOn) {
				await unregisterPush();
				pushOn = false;
			} else {
				await registerPush($playerId);
				pushOn = true;
			}
		} catch (e) {
			msg = `❌ ${e.message}`;
		}
	}

	function updatePref(key, val) {
		me.push_prefs = { ...(me.push_prefs || {}), [key]: val };
	}

	onMount(load);
</script>

<div class="page">
	<h1 class="phdr">
		<span class="material-symbols-outlined">person</span>
		Mein Profil
	</h1>

	{#if me}
		<section class="card">
			<div class="avatar-row">
				<div class="avatar">
					{#if me.avatar_url || me.photo}
						<img src={me.avatar_url || me.photo} alt={me.name} />
					{:else}
						<span>{(me.name || '?').slice(0,1)}</span>
					{/if}
				</div>
				<label class="upload">
					<input type="file" accept="image/*" onchange={uploadAvatar} hidden />
					<span class="material-symbols-outlined">photo_camera</span>
					{uploading ? 'Lädt…' : 'Foto ändern'}
				</label>
			</div>

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

			<button class="btn btn--primary" onclick={save}>
				<span class="material-symbols-outlined">check</span> Speichern
			</button>
			{#if msg}<p class="msg">{msg}</p>{/if}
		</section>

		<section class="card">
			<h2>Benachrichtigungen</h2>
			<button class="btn btn--secondary" onclick={togglePush}>
				<span class="material-symbols-outlined">{pushOn ? 'notifications_active' : 'notifications_off'}</span>
				{pushOn ? 'Push-Benachrichtigungen deaktivieren' : 'Push-Benachrichtigungen aktivieren'}
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

		{#if $playerRole === 'admin'}
			<section class="profil-admin">
				<h3>
					<span class="material-symbols-outlined" style="font-variation-settings:'FILL' 1,'wght' 500,'GRAD' 0,'opsz' 24;font-size:1.1rem">shield_person</span>
					Admin-Bereich
				</h3>
				<div class="admin-tile-grid">
					<a href="/admin/spieler" class="admin-tile">
						<span class="material-symbols-outlined">group</span>
						Spieler
					</a>
					<a href="/admin/teams" class="admin-tile">
						<span class="material-symbols-outlined">shield</span>
						Teams
					</a>
					<a href="/admin/saison" class="admin-tile">
						<span class="material-symbols-outlined">upload_file</span>
						Saison
					</a>
					<a href="/admin/training" class="admin-tile">
						<span class="material-symbols-outlined">fitness_center</span>
						Training
					</a>
					<a href="/admin/news" class="admin-tile">
						<span class="material-symbols-outlined">campaign</span>
						News
					</a>
					<a href="/admin" class="admin-tile">
						<span class="material-symbols-outlined">dashboard</span>
						Übersicht
					</a>
				</div>
			</section>
		{/if}

		<button class="btn btn--ghost" onclick={signOut}>
			<span class="material-symbols-outlined">logout</span> Abmelden
		</button>
	{/if}
</div>

<style>
	.phdr { display: flex; gap: 6px; align-items: center; font-family: 'Lexend'; font-weight: 600; font-size: 1.2rem; color: var(--color-primary, #CC0000); margin: 0 0 var(--space-3); }
	.card { background: var(--color-surface, #fff); border: 1px solid var(--color-border, #eee); border-radius: 14px; padding: var(--space-4); margin-bottom: var(--space-3); display: flex; flex-direction: column; gap: var(--space-2); }
	.avatar-row { display: flex; gap: var(--space-3); align-items: center; }
	.avatar { width: 72px; height: 72px; border-radius: 50%; overflow: hidden; background: #eee; display: grid; place-items: center; font-size: 1.8rem; font-weight: 700; color: #999; border: 3px solid var(--color-secondary, #D4AF37); }
	.avatar img { width: 100%; height: 100%; object-fit: cover; }
	.upload { display: inline-flex; gap: 4px; align-items: center; padding: 8px 14px; border: 1px solid var(--color-border, #ddd); background: #fff; border-radius: 999px; font-size: 0.9rem; cursor: pointer; }
	.field { display: flex; flex-direction: column; gap: 4px; font-size: 0.85rem; color: var(--color-text-soft, #666); }
	.field input { padding: 10px; border: 1px solid var(--color-border, #ddd); border-radius: 8px; font-size: 16px; }
	.field input:disabled { background: #f5f5f5; color: #999; }
	h2 { font-family: 'Lexend'; font-weight: 600; font-size: 1rem; margin: 0; color: var(--color-primary, #CC0000); }
	.btn { display: inline-flex; gap: 4px; align-items: center; justify-content: center; padding: 10px 16px; border: 0; border-radius: 999px; font-size: 0.95rem; cursor: pointer; }
	.btn--primary { background: var(--color-primary, #CC0000); color: #fff; align-self: flex-start; }
	.btn--secondary { background: var(--color-secondary, #D4AF37); color: #fff; }
	.btn--ghost { background: none; border: 1px solid var(--color-border, #ddd); color: var(--color-text-soft, #666); margin: var(--space-3) auto; }
	.msg { margin: 0; font-size: 0.9rem; }
	.prefs { display: flex; flex-direction: column; gap: 6px; margin-top: var(--space-2); }
	.toggle { display: flex; justify-content: space-between; align-items: center; padding: 6px 2px; font-size: 0.9rem; }
</style>
