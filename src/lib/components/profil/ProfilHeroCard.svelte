<script>
	import { sb }           from '$lib/supabase';
	import { playerRole }   from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';

	/**
	 * @typedef {{ id: string, name: string|null, avatar_url: string|null, photo: string|null }} Me
	 * @typedef {{ avg: number, count: number }} Stats
	 */
	let { me, stats, last5 = [], onUpdated } = $props();

	let uploading = $state(false);

	function initials(name) {
		return (name ?? '?').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
	}

	async function uploadAvatar(e) {
		const file = e.target.files?.[0];
		if (!file) return;
		uploading = true;
		try {
			const ext  = file.name.split('.').pop();
			const path = `${me.id}/${Date.now()}.${ext}`;
			const { error: upErr } = await sb.storage.from('avatars').upload(path, file, { upsert: true });
			if (upErr) { triggerToast('Fehler: ' + upErr.message); return; }
			const { data } = sb.storage.from('avatars').getPublicUrl(path);
			const { error } = await sb.from('players').update({ avatar_url: data.publicUrl }).eq('id', me.id);
			if (error) { triggerToast('Fehler: ' + error.message); return; }
			onUpdated?.({ avatar_url: data.publicUrl });
			triggerToast('Foto aktualisiert');
		} finally {
			uploading = false;
		}
	}

	const max5 = $derived(last5.length ? Math.max(...last5) : 0);
	const min5 = $derived(last5.length ? Math.min(...last5) : 0);
</script>

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
						{@const isMax = sc === max5}
						{@const isMin = sc === min5}
						<span class="hero-form-dot" class:hero-form-dot--hi={isMax && !isMin} class:hero-form-dot--lo={isMin && !isMax}>{sc}</span>
					{/each}
				</div>
				<span class="hero-stat-lbl">Letzte 5</span>
			</div>
		</div>
	{/if}
</section>

<style>
	.hero-card {
		position: relative; border-radius: 24px; overflow: hidden;
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		display: flex; flex-direction: column; align-items: center;
		padding: 0 var(--space-5) var(--space-4);
		box-shadow: var(--shadow-card);
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
		box-shadow: var(--shadow-float);
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
		box-shadow: var(--shadow-card);
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
		box-shadow: var(--shadow-card);
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
</style>
