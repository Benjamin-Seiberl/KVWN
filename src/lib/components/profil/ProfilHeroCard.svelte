<script>
	import { sb }           from '$lib/supabase';
	import { playerRole }   from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';

	/**
	 * @typedef {{ id: string, name: string|null, avatar_url: string|null, photo: string|null, member_since: string|null }} Me
	 * @typedef {{ avg: number, count: number }} Stats
	 */
	let { me, stats, last5 = [], onUpdated } = $props();

	let uploading      = $state(false);
	let displayedAvg   = $state(0);
	let displayedCount = $state(0);
	let hasAnimated    = $state(false);

	function initials(name) {
		return (name ?? '?').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
	}

	const nameParts = $derived.by(() => {
		const raw = (me?.name ?? '').trim();
		if (!raw) return { first: '—', last: '' };
		const idx = raw.indexOf(' ');
		if (idx < 0) return { first: raw, last: '' };
		return { first: raw.slice(0, idx), last: raw.slice(idx + 1) };
	});

	const memberYear = $derived.by(() => {
		const ms = me?.member_since;
		if (!ms) return null;
		const m = String(ms).match(/^(\d{4})/);
		return m ? m[1] : null;
	});

	const isCaptain = $derived($playerRole === 'kapitaen');
	const roleLabel = $derived(isCaptain ? 'KAPITÄN' : 'SPIELER');

	const max5 = $derived(last5.length ? Math.max(...last5) : 0);
	const min5 = $derived(last5.length ? Math.min(...last5) : 0);

	// Stat-Count-Up beim Mount — einmalig.
	$effect(() => {
		if (hasAnimated || !stats) return;
		hasAnimated = true;

		const targetAvg   = Number(stats.avg)   || 0;
		const targetCount = Number(stats.count) || 0;

		// prefers-reduced-motion: Endwerte sofort setzen, kein RAF-Loop.
		if (typeof window !== 'undefined'
			&& window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
			displayedAvg   = targetAvg;
			displayedCount = targetCount;
			return;
		}

		const duration    = 1200;
		const start       = performance.now();
		let raf;

		const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

		const tick = (now) => {
			const t = Math.min(1, (now - start) / duration);
			const eased = easeOutCubic(t);
			displayedAvg   = Math.round(targetAvg   * eased);
			displayedCount = Math.round(targetCount * eased);
			if (t < 1) raf = requestAnimationFrame(tick);
		};

		raf = requestAnimationFrame(tick);
		return () => { if (raf) cancelAnimationFrame(raf); };
	});

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
</script>

<section class="hero-card">
	<div class="hero-eyebrow">KV · WIENER NEUSTADT</div>
	<div class="hero-hairline"></div>

	<div class="hero-head">
		<div class="hero-avatar-wrap">
			<div class="hero-avatar-ring">
				<div class="hero-avatar">
					{#if me.avatar_url || me.photo}
						<img src={me.avatar_url || me.photo} alt={me.name ?? ''} />
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
			<h2 class="hero-first">{nameParts.first}</h2>
			{#if nameParts.last}
				<div class="hero-last">{nameParts.last}</div>
			{/if}
		</div>
	</div>

	<div class="hero-hairline"></div>
	<div class="hero-meta">
		<span class="hero-meta-role" class:hero-meta-role--gold={isCaptain}>{roleLabel}</span>
		<span class="hero-meta-dot" aria-hidden="true">·</span>
		<span class="hero-meta-since">SEIT {memberYear ?? '—'}</span>
	</div>
	<div class="hero-hairline"></div>

	{#if stats}
		<div class="hero-stats">
			<div class="hero-stat">
				<span class="hero-stat-val">Ø {displayedAvg}</span>
				<span class="hero-stat-lbl">Schnitt</span>
			</div>
			<div class="hero-stat-sep" aria-hidden="true"></div>
			<div class="hero-stat">
				<span class="hero-stat-val">{displayedCount}</span>
				<span class="hero-stat-lbl">Spiele</span>
			</div>
			<div class="hero-stat-sep" aria-hidden="true"></div>
			<div class="hero-stat">
				<div class="hero-form-dots">
					{#if last5.length}
						{#each last5 as sc, i (i)}
							{@const isMax = sc === max5 && max5 !== min5}
							{@const isMin = sc === min5 && max5 !== min5}
							<span
								class="hero-form-dot"
								class:hero-form-dot--hi={isMax}
								class:hero-form-dot--lo={isMin}
							>{sc}</span>
						{/each}
					{:else}
						<span class="hero-form-dot hero-form-dot--empty">—</span>
					{/if}
				</div>
				<span class="hero-stat-lbl">Form</span>
			</div>
		</div>
	{/if}
</section>

<style>
	/* ── Hero-lokale Tokens ─────────────────────────────────────────────── */
	.hero-card {
		--hero-gold: var(--color-secondary);
		--hero-gold-deep: #a07c20;
		--hero-hairline: linear-gradient(90deg, transparent, var(--hero-gold) 20%, var(--hero-gold) 80%, transparent);
		--hero-stat-sep: rgba(212, 175, 55, 0.35);

		position: relative;
		border-radius: var(--radius-xl);
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		box-shadow: var(--shadow-card);
		padding: var(--space-5) var(--space-5) var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		overflow: hidden;
	}

	/* ── Eyebrow ────────────────────────────────────────────────────────── */
	.hero-eyebrow {
		font-size: 0.65rem;
		font-weight: 800;
		letter-spacing: 0.2em;
		text-transform: uppercase;
		color: var(--hero-gold);
		text-align: center;
	}

	/* ── Gold-Hairline ──────────────────────────────────────────────────── */
	.hero-hairline {
		height: 1px;
		width: 100%;
		background: var(--hero-hairline);
		opacity: 0.85;
	}

	/* ── Avatar + Identity ──────────────────────────────────────────────── */
	.hero-head {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		padding: var(--space-2) 0;
	}

	.hero-avatar-wrap {
		position: relative;
		flex-shrink: 0;
	}
	.hero-avatar-ring {
		width: 80px;
		height: 80px;
		border-radius: 50%;
		padding: 2px;
		background: linear-gradient(135deg, var(--hero-gold) 0%, var(--hero-gold-deep) 50%, var(--hero-gold) 100%);
		background-size: 200% 200%;
		background-position: 0% 0%;
		animation: hero-ring-shimmer 6s ease-in-out infinite;
		box-shadow: 0 2px 8px rgba(212, 175, 55, 0.18);
	}
	.hero-avatar {
		width: 100%;
		height: 100%;
		border-radius: 50%;
		overflow: hidden;
		background: var(--color-surface-container);
		display: grid;
		place-items: center;
		font-family: var(--font-display);
		font-size: 1.6rem;
		font-weight: 900;
		color: var(--color-primary);
		border: 2px solid var(--color-surface-container-lowest);
	}
	.hero-avatar img { width: 100%; height: 100%; object-fit: cover; }

	.hero-photo-btn {
		position: absolute;
		bottom: -2px;
		right: -2px;
		width: 28px;
		height: 28px;
		border-radius: 50%;
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--hero-gold);
		display: grid;
		place-items: center;
		cursor: pointer;
		box-shadow: var(--shadow-card);
	}
	.hero-photo-btn .material-symbols-outlined {
		font-size: 0.95rem;
		color: var(--color-on-surface-variant);
	}
	.hero-spinner { animation: hero-spin 1s linear infinite; }

	.hero-identity {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		flex: 1;
	}
	.hero-first {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 900;
		font-size: 2rem;
		line-height: 1;
		letter-spacing: -0.02em;
		color: var(--color-on-surface);
		text-transform: uppercase;
		overflow-wrap: anywhere;
	}
	.hero-last {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.6rem;
		line-height: 1.05;
		letter-spacing: -0.01em;
		color: var(--color-on-surface-variant);
		text-transform: uppercase;
		padding-left: 2px;
		overflow-wrap: anywhere;
	}

	/* ── Meta-Zeile (KAPITÄN · SEIT 2019) ───────────────────────────────── */
	.hero-meta {
		display: flex;
		justify-content: center;
		align-items: center;
		gap: var(--space-2);
		font-size: 0.7rem;
		font-weight: 800;
		letter-spacing: 0.18em;
		text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.hero-meta-role {
		position: relative;
		padding: 2px 0;
	}
	.hero-meta-role--gold {
		color: var(--hero-gold);
		overflow: hidden;
	}
	.hero-meta-role--gold::before {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(110deg, transparent 30%, rgba(255, 255, 255, 0.45) 50%, transparent 70%);
		background-size: 200% 100%;
		background-position: -100% 0;
		animation: hero-captain-shimmer 4s ease-in-out infinite;
		pointer-events: none;
	}
	.hero-meta-dot {
		color: var(--hero-gold);
		font-weight: 900;
	}
	.hero-meta-since { color: var(--color-on-surface-variant); }

	/* ── Stat-Grid ──────────────────────────────────────────────────────── */
	.hero-stats {
		margin-top: var(--space-1);
		display: grid;
		grid-template-columns: 1fr 1px 1fr 1px 1fr;
		align-items: stretch;
		gap: 0;
	}
	.hero-stat {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-1);
		padding: var(--space-1) 2px;
		min-width: 0;
	}
	.hero-stat-sep {
		background: var(--hero-stat-sep);
		width: 1px;
		align-self: center;
		height: 70%;
	}
	.hero-stat-val {
		font-family: var(--font-display);
		font-size: 1.35rem;
		font-weight: 900;
		color: var(--color-on-surface);
		line-height: 1;
		letter-spacing: -0.01em;
	}
	.hero-stat-lbl {
		font-size: 0.6rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.16em;
		color: var(--color-on-surface-variant);
	}

	.hero-form-dots {
		display: flex;
		gap: var(--space-1);
		align-items: center;
		justify-content: center;
		flex-wrap: wrap;
	}
	.hero-form-dot {
		font-family: var(--font-display);
		font-size: 0.7rem;
		font-weight: 800;
		color: var(--color-on-surface-variant);
		padding: 1px 4px;
		border-radius: 4px;
		line-height: 1.1;
	}
	.hero-form-dot--hi {
		color: var(--hero-gold-deep);
		background: rgba(212, 175, 55, 0.12);
		animation: hero-form-pulse 2.4s ease-in-out infinite;
	}
	.hero-form-dot--lo { color: var(--color-primary); }
	.hero-form-dot--empty { color: var(--color-on-surface-variant); opacity: 0.6; }

	/* ── Animationen ────────────────────────────────────────────────────── */
	@keyframes hero-spin {
		to { transform: rotate(360deg); }
	}
	@keyframes hero-ring-shimmer {
		0%, 100% { background-position: 0% 50%; }
		50%      { background-position: 100% 50%; }
	}
	@keyframes hero-captain-shimmer {
		0%   { background-position: -100% 0; }
		60%  { background-position:  200% 0; }
		100% { background-position:  200% 0; }
	}
	@keyframes hero-form-pulse {
		0%, 100% { box-shadow: 0 0 0 0 rgba(212, 175, 55, 0); }
		50%      { box-shadow: 0 0 0 6px rgba(212, 175, 55, 0.3); }
	}

	@media (prefers-reduced-motion: reduce) {
		.hero-avatar-ring,
		.hero-meta-role--gold::before,
		.hero-form-dot--hi,
		.hero-spinner {
			animation: none !important;
		}
	}
</style>
