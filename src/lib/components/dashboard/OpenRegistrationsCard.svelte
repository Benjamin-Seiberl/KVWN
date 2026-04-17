<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { goto } from '$app/navigation';

	let items   = $state([]);
	let loading = $state(true);

	const DAY_SHORT = ['So','Mo','Di','Mi','Do','Fr','Sa'];
	const MONTHS    = ['Jän','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];

	function fmtDate(dateStr) {
		if (!dateStr) return '';
		const d = new Date(dateStr + 'T12:00');
		return DAY_SHORT[d.getDay()] + ', ' + d.getDate() + '. ' + MONTHS[d.getMonth()];
	}
	function fmtDeadline(ts) {
		return new Date(ts).toLocaleString('de-AT', { dateStyle: 'short', timeStyle: 'short' });
	}
	function hoursLeft(ts) {
		return Math.max(0, Math.floor((new Date(ts).getTime() - Date.now()) / 3_600_000));
	}

	async function load() {
		loading = true;
		const nowIso   = new Date().toISOString();
		const todayStr = new Date().toISOString().slice(0, 10);
		const { data } = await sb.from('matches')
			.select('id, date, time, tournament_title, tournament_location, registration_deadline, tournament_votes(player_id, wants_to_play)')
			.eq('is_landesbewerb', true)
			.gte('date', todayStr)
			.gt('registration_deadline', nowIso)
			.order('registration_deadline', { ascending: true });
		items = data ?? [];
		loading = false;
	}

	function myRegistered(m) {
		return (m.tournament_votes ?? []).some(v => v.player_id === $playerId && v.wants_to_play);
	}

	async function register(m) {
		if (!$playerId) return;
		const { error } = await sb.from('tournament_votes').upsert({
			tournament_id: m.id,
			player_id: $playerId,
			wants_to_play: true,
		});
		if (error) { triggerToast('Fehler'); return; }
		triggerToast('Angemeldet');
		await load();
	}

	onMount(load);
</script>

{#if loading || items.length > 0}
<div class="orc">
	<div class="orc-header">
		<div class="orc-header-left">
			<span class="material-symbols-outlined orc-icon">workspace_premium</span>
			<h3 class="orc-title">Anmeldungen offen</h3>
		</div>
	</div>

	{#if loading}
		<div class="orc-list">
			<div class="orc-item orc-item--skel">
				<div class="skel-bar shimmer-box" style="width:60%;height:14px;border-radius:5px"></div>
				<div class="skel-bar shimmer-box" style="width:40%;height:10px;border-radius:4px;margin-top:6px"></div>
			</div>
		</div>
	{:else}
		<div class="orc-list">
			{#each items as m}
				{@const registered = myRegistered(m)}
				{@const left = hoursLeft(m.registration_deadline)}
				{@const urgent = left < 24 && !registered}
				<div class="orc-item" class:orc-item--urgent={urgent}>
					<button class="orc-body" onclick={() => goto('/spielbetrieb?tab=landesbewerb&id=' + m.id)}>
						<div class="orc-trophy">
							<span class="material-symbols-outlined">workspace_premium</span>
						</div>
						<div class="orc-info">
							<span class="orc-item-title">{m.tournament_title}</span>
							<span class="orc-item-meta">
								{fmtDate(m.date)}
								{#if m.tournament_location} · {m.tournament_location}{/if}
							</span>
							<span class="orc-deadline" class:orc-deadline--urgent={urgent}>
								<span class="material-symbols-outlined">alarm</span>
								bis {fmtDeadline(m.registration_deadline)}
							</span>
						</div>
					</button>
					{#if registered}
						<div class="orc-state orc-state--done">
							<span class="material-symbols-outlined">check_circle</span>
							<span>Angemeldet</span>
						</div>
					{:else}
						<button class="orc-cta" onclick={() => register(m)}>
							Anmelden
						</button>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>
{/if}

<style>
	.orc {
		padding: 0 var(--space-5);
		margin: var(--space-2) 0;
	}
	.orc-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-3);
	}
	.orc-header-left {
		display: flex;
		align-items: center;
		gap: 7px;
	}
	.orc-icon {
		font-size: 1.1rem;
		color: var(--color-secondary, #D4AF37);
	}
	.orc-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	.orc-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.orc-item {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		background: var(--color-surface-container-lowest, #fff);
		border-radius: var(--radius-lg);
		box-shadow: 0 1px 4px rgba(0,0,0,0.04);
		border: 1.5px solid transparent;
		transition: border-color 200ms ease;
	}
	.orc-item--urgent {
		border-color: rgba(204, 0, 0, 0.35);
		background: linear-gradient(135deg, rgba(204,0,0,0.04), var(--color-surface-container-lowest, #fff));
	}
	.orc-item--skel { pointer-events: none; }

	.orc-body {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		background: none;
		border: 0;
		padding: 0;
		text-align: left;
		cursor: pointer;
		width: 100%;
	}
	.orc-body:active { opacity: 0.7; }

	.orc-trophy {
		width: 42px;
		height: 42px;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 12px;
		background: linear-gradient(135deg, #f4d87a, #c99a2b);
		color: #5a3e00;
	}
	.orc-trophy .material-symbols-outlined { font-size: 1.3rem; font-variation-settings: 'FILL' 1; }

	.orc-info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.orc-item-title {
		font-weight: 600;
		font-size: var(--text-body-md);
		color: var(--color-on-surface);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.orc-item-meta {
		font-size: var(--text-body-sm);
		color: var(--color-on-surface-variant);
	}
	.orc-deadline {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		font-size: 0.73rem;
		font-weight: 600;
		color: var(--color-on-surface-variant);
		margin-top: 2px;
	}
	.orc-deadline .material-symbols-outlined { font-size: 0.85rem; }
	.orc-deadline--urgent {
		color: var(--color-error, #CC0000);
	}

	.orc-cta {
		align-self: stretch;
		padding: 10px;
		border: 0;
		border-radius: 10px;
		background: var(--color-primary, #CC0000);
		color: #fff;
		font-weight: 700;
		font-size: 0.9rem;
		cursor: pointer;
	}
	.orc-cta:active { opacity: 0.8; }

	.orc-state {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		align-self: flex-start;
		padding: 6px 10px;
		background: rgba(30, 150, 80, 0.12);
		color: #1e9650;
		border-radius: 100px;
		font-size: 0.78rem;
		font-weight: 700;
	}
	.orc-state .material-symbols-outlined { font-size: 0.95rem; font-variation-settings: 'FILL' 1; }
</style>
