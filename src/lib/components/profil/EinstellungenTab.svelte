<script>
	import { sb }       from '$lib/supabase';
	import { playerId, signOut } from '$lib/stores/auth';
	import { triggerToast }      from '$lib/stores/toast.js';
	import { registerPush, unregisterPush, pushStatus } from '$lib/push/register.js';

	let pushPrefs = $state({});
	let pushOn    = $state(false);
	let playerId_ = $state(null);

	$effect(() => {
		if ($playerId) {
			playerId_ = $playerId;
			loadPrefs();
		}
	});

	async function loadPrefs() {
		const { data } = await sb.from('players').select('id, push_prefs').eq('id', playerId_).maybeSingle();
		if (data) pushPrefs = data.push_prefs ?? {};
		pushOn = await pushStatus();
	}

	async function togglePush() {
		try {
			if (pushOn) { await unregisterPush(); pushOn = false; }
			else        { await registerPush(playerId_); pushOn = true; }
		} catch (e) { triggerToast('Fehler: ' + e.message); }
	}

	async function updatePref(key, val) {
		pushPrefs = { ...pushPrefs, [key]: val };
		const { error } = await sb.from('players').update({ push_prefs: pushPrefs }).eq('id', playerId_);
		if (error) triggerToast('Fehler: ' + error.message);
	}
</script>

<section class="card">
	<h2 class="section-title">
		<span class="material-symbols-outlined">notifications</span>
		Benachrichtigungen
	</h2>
	<button class="btn btn--outline btn--push" onclick={togglePush}>
		<span class="material-symbols-outlined">{pushOn ? 'notifications_active' : 'notifications_off'}</span>
		{pushOn ? 'Push deaktivieren' : 'Push aktivieren'}
	</button>
	<div class="prefs">
		{#each [
			{ k: 'lineup',          label: 'Aufstellung veröffentlicht' },
			{ k: 'lineup_reminder', label: 'Erinnerung (24h vor Frist)' },
			{ k: 'lineup_decline',  label: 'Absagen (nur Kapitäne)' },
			{ k: 'feedback',        label: 'Feedback-Anfrage nach Spiel' },
			{ k: 'meetup',          label: 'Treffpunkt'  },
			{ k: 'news',            label: 'News'        },
			{ k: 'poll',            label: 'Umfragen'    },
		] as p}
			<label class="toggle">
				<span>{p.label}</span>
				<input
					type="checkbox"
					checked={pushPrefs[p.k] ?? true}
					onchange={(e) => updatePref(p.k, e.target.checked)}
				/>
			</label>
		{/each}
	</div>
</section>

<button class="btn btn--ghost btn--logout" onclick={signOut}>
	<span class="material-symbols-outlined">logout</span> Abmelden
</button>
