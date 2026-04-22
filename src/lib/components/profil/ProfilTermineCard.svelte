<script>
	import { goto }         from '$app/navigation';
	import { sb }           from '$lib/supabase';
	import { playerId }     from '$lib/stores/auth.js';
	import { triggerToast } from '$lib/stores/toast.js';
	import { MONTH_SHORT, fmtTime } from '$lib/utils/dates.js';

	/**
	 * Props:
	 *   events:  Array<{ id, title, date, time, location }>
	 *   rsvps:   Array<{ event_id, response }> — $bindable so RSVP taps mutate parent state
	 *   onReload: () => Promise<void>|void — called after failed upsert/delete to resync.
	 */
	let { events = [], rsvps = $bindable([]), onReload } = $props();

	function myRsvp(eid) {
		return rsvps.find(r => r.event_id === eid)?.response ?? null;
	}

	async function rsvp(eid, response) {
		const pid = $playerId;
		const existing = myRsvp(eid);
		if (existing === response) {
			rsvps = rsvps.filter(r => r.event_id !== eid);
			const { error } = await sb.from('event_rsvps').delete().eq('event_id', eid).eq('player_id', pid);
			if (error) { triggerToast('Fehler: ' + error.message); onReload?.(); }
		} else {
			rsvps = [...rsvps.filter(r => r.event_id !== eid), { event_id: eid, response }];
			const { error } = await sb.from('event_rsvps').upsert({ event_id: eid, player_id: pid, response });
			if (error) { triggerToast('Fehler: ' + error.message); onReload?.(); }
		}
	}
</script>

{#if events.length}
	<section class="card">
		<div class="data-card-head">
			<h3 class="section-title">
				<span class="material-symbols-outlined">event</span>
				Vereinstermine
			</h3>
			<button class="data-card-edit" onclick={() => goto('/kalender')}>
				Alle →
			</button>
		</div>
		<div class="agenda">
			{#each events as ev (ev.id)}
				{@const d   = new Date(ev.date + 'T00:00:00')}
				{@const myR = myRsvp(ev.id)}
				<div class="agenda-item">
					<div class="agenda-date-col">
						<span class="agenda-day">{d.getDate()}</span>
						<span class="agenda-month">{MONTH_SHORT[d.getMonth()]}</span>
					</div>
					<div class="agenda-info">
						<p class="agenda-title">{ev.title}</p>
						{#if ev.time || ev.location}
							<p class="agenda-sub">
								{#if ev.time}{fmtTime(ev.time)}{/if}
								{#if ev.time && ev.location} · {/if}
								{#if ev.location}{ev.location}{/if}
							</p>
						{/if}
					</div>
					<div class="agenda-rsvp">
						<button class="rsvp-btn rsvp-btn--yes" class:active={myR === 'yes'} onclick={() => rsvp(ev.id, 'yes')} aria-label="Zusagen">
							<span class="material-symbols-outlined">check</span>
						</button>
						<button class="rsvp-btn rsvp-btn--no" class:active={myR === 'no'} onclick={() => rsvp(ev.id, 'no')} aria-label="Absagen">
							<span class="material-symbols-outlined">close</span>
						</button>
					</div>
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.card {
		background: var(--color-surface-container-lowest);
		border: 1px solid var(--color-surface-container);
		border-radius: 16px; padding: var(--space-4);
		display: flex; flex-direction: column; gap: var(--space-3);
	}
	.data-card-head { display: flex; justify-content: space-between; align-items: center; }

	.data-card-edit {
		display: inline-flex; align-items: center; gap: 4px;
		background: transparent; border: 1px solid var(--color-outline-variant);
		border-radius: 999px; padding: 4px 10px; font-size: 0.72rem; font-weight: 700;
		color: var(--color-on-surface-variant); cursor: pointer; font-family: inherit;
	}
	.data-card-edit:active { background: var(--color-surface-container-low); }

	.agenda { display: flex; flex-direction: column; gap: 0; }
	.agenda-item {
		display: flex; align-items: center; gap: var(--space-3);
		padding: var(--space-3) 0;
		border-top: 1px solid var(--color-surface-container);
	}
	.agenda-item:first-child { border-top: none; padding-top: 0; }

	.agenda-date-col {
		display: flex; flex-direction: column; align-items: center;
		min-width: 36px; flex-shrink: 0;
	}
	.agenda-day {
		font-family: var(--font-display); font-size: 1.3rem; font-weight: 900;
		color: var(--color-primary); line-height: 1;
	}
	.agenda-month {
		font-size: 0.68rem; font-weight: 700; text-transform: uppercase;
		color: var(--color-on-surface-variant);
	}
	.agenda-info { flex: 1; min-width: 0; }
	.agenda-title {
		font-weight: 700; font-size: 0.9rem; color: var(--color-on-surface);
		margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
	}
	.agenda-sub { font-size: 0.78rem; color: var(--color-on-surface-variant); margin: 2px 0 0; }
	.agenda-rsvp { display: flex; gap: var(--space-1); flex-shrink: 0; }
	.rsvp-btn {
		width: 32px; height: 32px; border-radius: 50%;
		border: 1.5px solid var(--color-outline-variant);
		background: transparent; cursor: pointer;
		display: grid; place-items: center;
		transition: background 150ms, border-color 150ms;
		-webkit-tap-highlight-color: transparent;
	}
	.rsvp-btn .material-symbols-outlined { font-size: 1rem; color: var(--color-on-surface-variant); }
	.rsvp-btn--yes.active { background: #dcfce7; border-color: #16a34a; }
	.rsvp-btn--yes.active .material-symbols-outlined { color: #16a34a; }
	.rsvp-btn--no.active  { background: #fee2e2; border-color: var(--color-error); }
	.rsvp-btn--no.active  .material-symbols-outlined { color: var(--color-error); }
</style>
