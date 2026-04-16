<script>
	import { sb } from '$lib/supabase';
	import { onMount } from 'svelte';
	import BottomSheet from '../BottomSheet.svelte';
	import { triggerToast } from '$lib/stores/toast.js';

	let { open = $bindable(false) } = $props();

	let players     = $state([]);
	let loading     = $state(true);
	let search      = $state('');
	let saving      = $state(null);   // player id currently saving
	let inviteMode  = $state(false);
	let inviteEmail = $state('');
	let inviteName  = $state('');
	let inviteRole  = $state('user');
	let sending     = $state(false);

	const ROLE_LABELS = { user: 'Spieler', kapitaen: 'Kapitän', admin: 'Admin' };
	const ROLE_COLORS = { user: 'var(--color-outline)', kapitaen: '#D4AF37', admin: 'var(--color-primary)' };

	async function load() {
		loading = true;
		const { data } = await sb
			.from('players')
			.select('id, name, email, role, active, avatar_url, photo')
			.order('name');
		players = data ?? [];
		loading = false;
	}

	async function setRole(player, role) {
		saving = player.id;
		const { error } = await sb.from('players').update({ role }).eq('id', player.id);
		if (!error) {
			player.role = role;
			toast(`${player.name} → ${ROLE_LABELS[role]}`);
		} else {
			toast('Fehler beim Speichern');
		}
		saving = null;
	}

	async function toggleActive(player) {
		saving = player.id;
		const newActive = !player.active;
		const { error } = await sb.from('players').update({ active: newActive }).eq('id', player.id);
		if (!error) {
			player.active = newActive;
			toast(`${player.name} ${newActive ? 'aktiviert' : 'deaktiviert'}`);
		}
		saving = null;
	}

	async function sendInvite() {
		if (!inviteEmail.trim()) return;
		sending = true;
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
				toast(err.error || 'Einladung fehlgeschlagen');
			} else {
				toast('Einladung gesendet!');
				inviteEmail = ''; inviteName = ''; inviteRole = 'user';
				inviteMode = false;
				await load();
			}
		} catch (e) {
			toast(e.message);
		} finally {
			sending = false;
		}
	}

	function toast(msg) {
		open = false;  // Sheet schließen
		setTimeout(() => triggerToast(msg), 300);  // Delay für Sheet-Animation
	}

	// Filtered players list
	let filtered = $derived.by(() => {
		if (!search.trim()) return players;
		const q = search.toLowerCase();
		return players.filter(p =>
			p.name?.toLowerCase().includes(q) ||
			p.email?.toLowerCase().includes(q)
		);
	});

	// Load when sheet opens
	$effect(() => {
		if (open) {
			load();
			inviteMode = false;
		}
	});
</script>

<BottomSheet bind:open title="Spieler & Rollen">

	<!-- Header mit Suche + Einladen-Button -->
	<div class="ar-toolbar">
		<div class="ar-search">
			<span class="material-symbols-outlined">search</span>
			<input
				type="text"
				placeholder="Spieler suchen…"
				bind:value={search}
			/>
		</div>
		<button class="ar-invite-btn" onclick={() => { inviteMode = !inviteMode; }}>
			<span class="material-symbols-outlined">{inviteMode ? 'close' : 'person_add'}</span>
		</button>
	</div>

	<!-- Einladen-Formular (aufklappbar) -->
	{#if inviteMode}
		<div class="ar-invite-form">
			<div class="mw-field">
				<label class="mw-field__label" for="ar-inv-name">Name</label>
				<input id="ar-inv-name" type="text" bind:value={inviteName} placeholder="Vorname Nachname" />
			</div>
			<div class="mw-field">
				<label class="mw-field__label" for="ar-inv-email">E-Mail</label>
				<input id="ar-inv-email" type="text" bind:value={inviteEmail} placeholder="spieler@example.at" />
			</div>
			<div class="mw-field">
				<label class="mw-field__label" for="ar-inv-role">Rolle</label>
				<select id="ar-inv-role" bind:value={inviteRole} class="ar-role-select">
					<option value="user">Spieler</option>
					<option value="kapitaen">Kapitän</option>
					<option value="admin">Admin</option>
				</select>
			</div>
			<button
				class="mw-btn mw-btn--primary mw-btn--wide"
				disabled={sending || !inviteEmail.trim()}
				onclick={sendInvite}
			>
				<span class="material-symbols-outlined">send</span>
				{sending ? 'Senden…' : 'Magic-Link senden'}
			</button>
		</div>
	{/if}

	<!-- Spieler-Liste -->
	{#if loading}
		<div class="ar-loading">
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:80ms"></div>
			<div class="skeleton-card skeleton-card--short animate-pulse-skeleton" style="animation-delay:160ms"></div>
		</div>
	{:else}
		<div class="ar-count">{filtered.length} Spieler</div>
		<div class="ar-list">
			{#each filtered as p (p.id)}
				<div class="ar-player" class:ar-player--inactive={!p.active} class:ar-player--saving={saving === p.id}>
					<!-- Avatar -->
					<div class="ar-avatar">
						{#if p.avatar_url || p.photo}
							<img src={p.avatar_url || '/images/' + encodeURIComponent(p.photo || p.name) + '.jpg'} alt={p.name} />
						{:else}
							<span>{(p.name || '?').slice(0, 1).toUpperCase()}</span>
						{/if}
					</div>

					<!-- Info -->
					<div class="ar-info">
						<span class="ar-name">{p.name}</span>
						<span class="ar-email">{p.email ?? 'kein Login'}</span>
					</div>

					<!-- Rolle -->
					<select
						class="ar-role-select"
						value={p.role}
						style="color: {ROLE_COLORS[p.role]}"
						onchange={(e) => setRole(p, e.target.value)}
					>
						<option value="user">Spieler</option>
						<option value="kapitaen">Kapitän</option>
						<option value="admin">Admin</option>
					</select>

					<!-- Aktiv/Inaktiv-Toggle -->
					<button
						class="ar-toggle"
						class:ar-toggle--off={!p.active}
						aria-label={p.active ? 'Deaktivieren' : 'Aktivieren'}
						onclick={() => toggleActive(p)}
					>
						<span class="material-symbols-outlined">{p.active ? 'check_circle' : 'block'}</span>
					</button>
				</div>
			{/each}
		</div>
	{/if}

</BottomSheet>

<style>
	/* Toolbar */
	.ar-toolbar {
		display: flex;
		gap: var(--space-2);
		align-items: center;
		margin-bottom: var(--space-3);
	}
	.ar-search {
		flex: 1;
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-2) var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
	}
	.ar-search .material-symbols-outlined {
		font-size: 1.1rem;
		color: var(--color-outline);
		flex-shrink: 0;
	}
	.ar-search input {
		flex: 1;
		border: none;
		background: none;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		outline: none;
		font-family: var(--font-body);
		min-width: 0;
	}
	.ar-search input::placeholder {
		color: var(--color-outline);
	}
	.ar-invite-btn {
		width: 40px; height: 40px;
		border-radius: var(--radius-md);
		border: 1.5px solid var(--color-outline-variant);
		background: var(--color-surface-container-low);
		display: grid;
		place-items: center;
		cursor: pointer;
		color: var(--color-primary);
		flex-shrink: 0;
		-webkit-tap-highlight-color: transparent;
	}
	.ar-invite-btn .material-symbols-outlined { font-size: 1.2rem; }

	/* Invite form */
	.ar-invite-form {
		padding: var(--space-4);
		margin-bottom: var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-lg);
		border: 1.5px solid var(--color-outline-variant);
		animation: ar-toast-in 0.2s ease-out;
	}

	/* Count */
	.ar-count {
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-outline);
		margin-bottom: var(--space-2);
	}

	/* Player list */
	.ar-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.ar-player {
		display: grid;
		grid-template-columns: 40px 1fr auto auto;
		gap: var(--space-2);
		align-items: center;
		padding: var(--space-3);
		background: var(--color-surface-container-low);
		border-radius: var(--radius-md);
		transition: opacity 0.15s;
	}
	.ar-player--inactive { opacity: 0.45; }
	.ar-player--saving { opacity: 0.6; pointer-events: none; }

	/* Avatar */
	.ar-avatar {
		width: 40px; height: 40px;
		border-radius: 50%;
		overflow: hidden;
		background: var(--color-surface-container-highest);
		display: grid;
		place-items: center;
		font-weight: 700;
		font-size: var(--text-body-sm);
		color: var(--color-outline);
	}
	.ar-avatar img {
		width: 100%; height: 100%;
		object-fit: cover;
	}

	/* Info */
	.ar-info {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.ar-name {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.ar-email {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* Role select */
	.ar-role-select {
		padding: 4px 6px;
		border-radius: 6px;
		border: 1px solid var(--color-outline-variant);
		font-size: var(--text-body-sm);
		font-weight: 600;
		background: var(--color-surface-container-lowest);
		cursor: pointer;
		min-width: 0;
	}

	/* Active toggle */
	.ar-toggle {
		background: none;
		border: none;
		padding: 4px;
		cursor: pointer;
		color: #2a9d57;
		-webkit-tap-highlight-color: transparent;
	}
	.ar-toggle .material-symbols-outlined {
		font-size: 1.3rem;
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.ar-toggle--off { color: var(--color-outline); }

	/* Loading */
	.ar-loading {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
</style>
