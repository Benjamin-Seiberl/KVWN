<script>
	import { imgPath, shortName } from '$lib/utils/players.js';

	/**
	 * @prop {object}  player              game_plan_players row joined with players()
	 * @prop {string}  mode                'gesamt' | 'detailliert'
	 * @prop {Array}   lanes               existing lane rows for this player
	 * @prop {number|null} score           current persisted score (sum or gesamt)
	 * @prop {boolean} played              whether the player participated (DNF when false)
	 * @prop {boolean} published           result_published_at != null
	 * @prop {Function} onRowChange        called per-row when user edits — debounced upstream
	 * @prop {Function} onPlayedChange     called when DNF toggle flips
	 */
	let {
		player,
		mode = 'gesamt',
		lanes = [],
		score = null,
		played = true,
		published = false,
		onRowChange,
		onPlayedChange,
	} = $props();

	// Local drafts — bound to inputs.
	let draft = $state(score ?? '');
	$effect(() => { draft = score ?? ''; });

	// Per-bahn local drafts for detail mode
	let laneDraft = $state({ 1: { v: '', a: '' }, 2: { v: '', a: '' }, 3: { v: '', a: '' }, 4: { v: '', a: '' } });

	$effect(() => {
		const map = { 1: { v: '', a: '' }, 2: { v: '', a: '' }, 3: { v: '', a: '' }, 4: { v: '', a: '' } };
		for (const l of lanes ?? []) {
			if (l.bahn >= 1 && l.bahn <= 4) {
				map[l.bahn] = { v: l.volle ?? '', a: l.abraeumen ?? '' };
			}
		}
		laneDraft = map;
	});

	const name  = $derived(player.players?.name ?? player.player_name ?? '–');
	const photo = $derived(player.players?.photo ?? null);

	// Build a snapshot for the parent
	function snapshot() {
		if (mode === 'gesamt') {
			const v = draft;
			const n = (v === '' || v === null) ? null : (Number.isFinite(Number(v)) ? Number(v) : null);
			return { mode, score: n, lanes: null };
		}
		const lanesOut = [];
		for (let b = 1; b <= 4; b++) {
			const v = laneDraft[b]?.v;
			const a = laneDraft[b]?.a;
			const volle     = (v === '' || v === null) ? null : (Number.isFinite(Number(v)) ? Number(v) : null);
			const abraeumen = (a === '' || a === null) ? null : (Number.isFinite(Number(a)) ? Number(a) : null);
			lanesOut.push({ bahn: b, volle, abraeumen });
		}
		return { mode, score: null, lanes: lanesOut };
	}

	// Debounced per-row commit (500ms after last keystroke)
	let timer = null;
	function scheduleCommit() {
		if (played === false) return; // DNF active — ignore lane/score edits
		if (timer) clearTimeout(timer);
		timer = setTimeout(() => {
			timer = null;
			onRowChange?.(player.id, snapshot());
		}, 500);
	}

	// Commit pending edits immediately (e.g. before publish or before DNF flip)
	function flushNow() {
		if (timer) {
			clearTimeout(timer);
			timer = null;
			onRowChange?.(player.id, snapshot());
		}
	}

	// Pending debounce-Timer beim Unmount canceln — sonst feuert onRowChange
	// auf einer ausgehängten Komponente und schreibt stale Daten zurück.
	$effect(() => () => {
		if (timer) {
			clearTimeout(timer);
			timer = null;
		}
	});

	function toggleDnf() {
		// Bei DNF-Wechsel: pending edits zuerst flushen
		flushNow();
		const next = !played;
		onPlayedChange?.(player.id, next);
	}

	// Derived sum for detailed mode (UI-only, persistierter Wert kommt via `score`)
	const laneSum = $derived.by(() => {
		let sum = 0;
		let any = false;
		for (let i = 1; i <= 4; i++) {
			const v = Number(laneDraft[i]?.v);
			const a = Number(laneDraft[i]?.a);
			if (Number.isFinite(v)) { sum += v; any = true; }
			if (Number.isFinite(a)) { sum += a; any = true; }
		}
		return any ? sum : null;
	});

	// Soft validation: warn on unusually low/high totals
	const gesamtWarn = $derived.by(() => {
		const n = Number(draft);
		if (!Number.isFinite(n) || draft === '') return null;
		if (n > 0 && n < 100) return 'low';
		if (n > 700) return 'high';
		return null;
	});

	const sumWarn = $derived.by(() => {
		if (laneSum == null) return null;
		if (laneSum > 0 && laneSum < 100) return 'low';
		if (laneSum > 700) return 'high';
		return null;
	});
</script>

<div class="sir-card mw-card" class:sir-card--published={published} class:sir-card--dnf={played === false}>
	<div class="sir-head">
		<span class="sir-pos">{player.position ?? '–'}</span>
		<img
			class="sir-avatar"
			src={imgPath(photo, name)}
			alt={name}
			draggable="false"
			onerror={(e) => { e.currentTarget.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'; }}
		/>
		<span class="sir-name">{shortName(name)}</span>

		{#if played === false}
			<span class="sir-dnf-tag">Nicht gespielt</span>
			<span class="sir-status"></span>
		{:else if mode === 'gesamt'}
			<div class="sir-input-wrap" class:sir-input-wrap--warn={gesamtWarn}>
				<input
					class="sir-input"
					type="number"
					inputmode="numeric"
					min="0"
					max="999"
					placeholder="Holz"
					bind:value={draft}
					oninput={scheduleCommit}
					onblur={flushNow}
				/>
				<span class="sir-unit">Holz</span>
			</div>
			<span class="sir-status">
				{#if score != null}
					<span class="material-symbols-outlined sir-status-icon" class:sir-status-icon--pub={published}>
						{published ? 'check_circle' : 'edit_note'}
					</span>
				{/if}
			</span>
		{:else}
			<span class="sir-sum" class:sir-sum--warn={sumWarn}>
				{laneSum ?? '–'}
				<span class="sir-sum-unit">Holz</span>
			</span>
			<span class="sir-status">
				{#if score != null}
					<span class="material-symbols-outlined sir-status-icon" class:sir-status-icon--pub={published}>
						{published ? 'check_circle' : 'edit_note'}
					</span>
				{/if}
			</span>
		{/if}
	</div>

	{#if mode === 'detailliert' && played !== false}
		<div class="sir-lanes">
			{#each [1, 2, 3, 4] as b}
				<div class="sir-lane-row">
					<span class="sir-lane-label">Bahn {b}</span>
					<input
						class="sir-lane-input"
						type="number"
						inputmode="numeric"
						min="0"
						max="999"
						placeholder="Volle"
						bind:value={laneDraft[b].v}
						oninput={scheduleCommit}
						onblur={flushNow}
					/>
					<input
						class="sir-lane-input"
						type="number"
						inputmode="numeric"
						min="0"
						max="999"
						placeholder="Abräumen"
						bind:value={laneDraft[b].a}
						oninput={scheduleCommit}
						onblur={flushNow}
					/>
				</div>
			{/each}
			<div class="sir-lane-total">
				<span class="sir-lane-total-label">Gesamt</span>
				<span class="sir-lane-total-val" class:sir-lane-total-val--warn={sumWarn}>
					{laneSum ?? '–'}
				</span>
				<span class="sir-lane-total-unit">Holz</span>
			</div>
		</div>
	{/if}

	<!-- DNF-Toggle (immer sichtbar, ausgenommen veröffentlicht) -->
	{#if !published}
		<button
			type="button"
			class="sir-dnf-btn"
			class:sir-dnf-btn--active={played === false}
			onclick={toggleDnf}
			aria-pressed={played === false}
			aria-label={played === false ? `${shortName(name)}: Nicht-gespielt-Status zurücksetzen` : `${shortName(name)} als nicht gespielt markieren`}
		>
			<span class="material-symbols-outlined">
				{played === false ? 'check_box' : 'check_box_outline_blank'}
			</span>
			Nicht gespielt
		</button>
	{/if}
</div>

<style>
	.sir-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		transition: border-color 160ms ease, opacity 160ms ease;
	}
	.sir-card--published {
		border-color: color-mix(in srgb, var(--color-secondary) 40%, transparent);
	}
	.sir-card--dnf {
		opacity: 0.7;
		background: color-mix(in srgb, var(--color-outline-variant) 18%, transparent);
	}
	.sir-head {
		display: grid;
		grid-template-columns: 1.8rem 2rem 1fr auto auto;
		align-items: center;
		gap: var(--space-2);
	}
	.sir-pos {
		font-family: var(--font-display);
		font-weight: 800;
		color: var(--color-primary);
		text-align: center;
		font-size: var(--text-label-md);
	}
	.sir-avatar {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		object-fit: cover;
		object-position: top center;
		background: var(--color-surface-container);
	}
	.sir-name {
		font-family: var(--font-display);
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.sir-input-wrap {
		display: flex;
		align-items: center;
		gap: 4px;
	}
	.sir-input {
		width: 5rem;
		padding: 6px 10px;
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		background: var(--color-surface-container-lowest);
		color: var(--color-on-surface);
		font-family: inherit;
		text-align: right;
		font-weight: 700;
		font-size: var(--text-body-md);
	}
	.sir-input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	.sir-input-wrap--warn .sir-input {
		border-color: color-mix(in srgb, var(--color-secondary) 70%, transparent);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-secondary) 20%, transparent);
	}
	.sir-unit {
		font-size: var(--text-label-sm);
		color: var(--color-outline);
	}
	.sir-sum {
		font-family: var(--font-display);
		font-weight: 800;
		color: var(--color-on-surface);
		font-size: var(--text-title-sm);
	}
	.sir-sum--warn { color: color-mix(in srgb, var(--color-secondary) 85%, var(--color-on-surface)); }
	.sir-sum-unit {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 400;
		color: var(--color-outline);
		margin-left: 3px;
	}
	.sir-status {
		display: flex;
		align-items: center;
		width: 1.3rem;
		justify-content: center;
	}
	.sir-status-icon {
		font-size: 1.1rem;
		color: var(--color-outline);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sir-status-icon--pub { color: var(--color-secondary); }

	.sir-dnf-tag {
		font-family: var(--font-body);
		font-size: var(--text-label-sm);
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-on-surface-variant);
		padding: 2px var(--space-2);
		background: color-mix(in srgb, var(--color-outline-variant) 50%, transparent);
		border-radius: var(--radius-full);
	}

	.sir-lanes {
		margin-top: var(--space-1);
		padding-top: var(--space-2);
		border-top: 1px dashed var(--color-outline-variant);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.sir-lane-row {
		display: grid;
		grid-template-columns: 4rem 1fr 1fr;
		gap: var(--space-2);
		align-items: center;
	}
	.sir-lane-label {
		font-size: var(--text-label-sm);
		font-weight: 700;
		color: var(--color-on-surface-variant);
	}
	.sir-lane-input {
		padding: 6px 10px;
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-md);
		background: var(--color-surface-container-lowest);
		color: var(--color-on-surface);
		font-family: inherit;
		text-align: right;
		font-weight: 600;
		font-size: var(--text-body-md);
		min-width: 0;
	}
	.sir-lane-input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	.sir-lane-total {
		display: grid;
		grid-template-columns: 4rem 1fr auto;
		gap: var(--space-2);
		align-items: center;
		padding-top: var(--space-2);
		border-top: 1px solid var(--color-outline-variant);
	}
	.sir-lane-total-label {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: var(--text-label-sm);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
	}
	.sir-lane-total-val {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: var(--text-title-sm);
		color: var(--color-on-surface);
		text-align: right;
	}
	.sir-lane-total-val--warn { color: color-mix(in srgb, var(--color-secondary) 85%, var(--color-on-surface)); }
	.sir-lane-total-unit {
		font-size: var(--text-label-sm);
		color: var(--color-outline);
	}

	.sir-dnf-btn {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 6px 10px;
		border: 1px solid var(--color-outline-variant);
		border-radius: var(--radius-full);
		background: transparent;
		color: var(--color-on-surface-variant);
		font-family: inherit;
		font-size: var(--text-label-sm);
		font-weight: 600;
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background 120ms ease, color 120ms ease, border-color 120ms ease;
	}
	.sir-dnf-btn:hover,
	.sir-dnf-btn:focus-visible {
		background: var(--color-surface-container);
		color: var(--color-on-surface);
		border-color: var(--color-outline);
	}
	.sir-dnf-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.sir-dnf-btn--active {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.sir-dnf-btn .material-symbols-outlined {
		font-size: 1.1rem;
		font-variation-settings: 'FILL' 0, 'wght' 500, 'GRAD' 0, 'opsz' 20;
	}
</style>
