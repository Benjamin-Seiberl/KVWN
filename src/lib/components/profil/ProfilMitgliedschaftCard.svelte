<script>
	import { playerRole } from '$lib/stores/auth.js';
	import { MONTH_FULL, formatYearsSince } from '$lib/utils/dates.js';

	/**
	 * Props:
	 *   me: { member_since: string|null, membership_status: string|null }
	 * Read-only only — member_since / membership_status are captain-editable via admin flows.
	 */
	let { me } = $props();

	const STATUS_LABEL = {
		aktiv:         'Aktiv',
		passiv:        'Passiv',
		nachwuchs:     'Nachwuchs',
		ehrenmitglied: 'Ehrenmitglied',
		ruhend:        'Ruhend',
	};

	const statusKey   = $derived(me?.membership_status || 'aktiv');
	const statusLabel = $derived(STATUS_LABEL[statusKey] ?? 'Aktiv');

	const sinceText = $derived.by(() => {
		if (!me?.member_since) return null;
		const d = new Date(me.member_since + 'T12:00');
		if (Number.isNaN(d.getTime())) return null;
		const y = formatYearsSince(me.member_since);
		return 'Mitglied seit ' + MONTH_FULL[d.getMonth()] + ' ' + d.getFullYear() + (y ? ' (' + y + ')' : '');
	});
</script>

<section class="mem-card">
	<div class="mem-head">
		<h3 class="section-title">
			<span class="material-symbols-outlined">workspace_premium</span>
			Mitgliedschaft
		</h3>
	</div>

	<div class="mem-rows">
		<div class="mem-row">
			<span class="mem-label">Status</span>
			<span class="mem-badge mem-badge--{statusKey}">{statusLabel}</span>
		</div>

		<div class="mem-row">
			<span class="mem-label">Rolle</span>
			<span
				class="mem-badge"
				class:mem-badge--gold={$playerRole === 'kapitaen'}
			>
				{$playerRole === 'kapitaen' ? 'Kapitän' : 'Spieler'}
			</span>
		</div>

		<div class="mem-row mem-row--since">
			{#if sinceText}
				<span class="mem-since">{sinceText}</span>
			{:else}
				<span class="mem-since mem-since--empty">Eintrittsdatum nicht erfasst</span>
			{/if}
		</div>
	</div>
</section>

<style>
	.mem-card {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.mem-head { display: flex; justify-content: space-between; align-items: center; }

	.mem-rows { display: flex; flex-direction: column; }
	.mem-row {
		display: flex; align-items: center; justify-content: space-between;
		padding: var(--space-3) 0;
		border-top: 1px solid var(--color-surface-container);
	}
	.mem-row:first-child { border-top: none; }
	.mem-row--since { justify-content: flex-start; }

	.mem-label {
		font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em;
		color: var(--color-on-surface-variant);
	}
	.mem-since {
		font-size: 0.92rem; font-weight: 600; color: var(--color-on-surface);
	}
	.mem-since--empty {
		color: var(--color-outline); font-style: italic; font-weight: 500;
	}

	.mem-badge {
		font-size: 0.72rem; font-weight: 800; text-transform: uppercase; letter-spacing: 0.08em;
		padding: 4px 10px; border-radius: 999px;
		background: var(--color-surface-container); color: var(--color-on-surface-variant);
	}
	.mem-badge--aktiv         { background: var(--color-primary); color: #fff; }
	.mem-badge--passiv        { background: var(--color-surface-container); color: var(--color-on-surface-variant); }
	.mem-badge--nachwuchs     { background: #eff6ff; color: #1d4ed8; }
	.mem-badge--ehrenmitglied { background: linear-gradient(135deg, var(--color-secondary), #a07c20); color: #fff; }
	.mem-badge--ruhend        { background: var(--color-surface-container); color: var(--color-outline); }
	.mem-badge--gold {
		background: linear-gradient(135deg, var(--color-secondary), #a07c20); color: #fff;
	}
</style>
