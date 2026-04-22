<script>
	import { imgPath, shortName } from '$lib/utils/players.js';

	let { player, mode = 'gesamt', lanes = [], score = null, published = false, onScore, onLane } = $props();

	// Local drafts — bound to inputs, committed onblur.
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

	function commitScore() {
		const v = draft;
		if (v === '' || v === null) {
			onScore?.(player.id, null);
			return;
		}
		const n = Number(v);
		if (!Number.isFinite(n)) return;
		onScore?.(player.id, n);
	}

	function commitLane(bahn, field) {
		const v = laneDraft[bahn][field === 'volle' ? 'v' : 'a'];
		if (v === '' || v === null) {
			onLane?.(player.id, bahn, field, null);
			return;
		}
		const n = Number(v);
		if (!Number.isFinite(n)) return;
		onLane?.(player.id, bahn, field, n);
	}

	// Derived sum for detailed mode
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

<div class="sir-card mw-card" class:sir-card--published={published}>
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

		{#if mode === 'gesamt'}
			<div class="sir-input-wrap" class:sir-input-wrap--warn={gesamtWarn}>
				<input
					class="sir-input"
					type="number"
					inputmode="numeric"
					min="0"
					max="999"
					placeholder="Holz"
					bind:value={draft}
					onblur={commitScore}
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

	{#if mode === 'detailliert'}
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
						onblur={() => commitLane(b, 'volle')}
					/>
					<input
						class="sir-lane-input"
						type="number"
						inputmode="numeric"
						min="0"
						max="999"
						placeholder="Abräumen"
						bind:value={laneDraft[b].a}
						onblur={() => commitLane(b, 'abraeumen')}
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
</div>

<style>
	.sir-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		transition: border-color 160ms ease;
	}
	.sir-card--published {
		border-color: color-mix(in srgb, var(--color-secondary) 40%, transparent);
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
</style>
