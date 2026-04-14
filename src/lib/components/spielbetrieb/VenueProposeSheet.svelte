<script>
	import BottomSheet from '$lib/components/BottomSheet.svelte';
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';

	let { open = $bindable(false), match, onSaved } = $props();
	let name = $state('');
	let saving = $state(false);

	$effect(() => { if (open) name = ''; });

	async function save() {
		if (!name.trim()) return;
		saving = true;
		const { data, error } = await sb
			.from('match_venues')
			.insert({
				match_id:    match.id,
				name:        name.trim(),
				proposed_by: $playerId,
			})
			.select()
			.maybeSingle();
		saving = false;
		if (!error) {
			onSaved?.(data);
			open = false;
		}
	}
</script>

<BottomSheet bind:open title="Lokal vorschlagen">
	<div class="mw-field">
		<label class="mw-field__label" for="mw-venue">Name des Lokals</label>
		<input id="mw-venue" type="text" bind:value={name} placeholder="z.B. Pizzeria Bella" />
	</div>
	<button class="mw-btn mw-btn--primary mw-btn--wide" disabled={saving || !name.trim()} onclick={save}>
		<span class="material-symbols-outlined">check</span>
		Vorschlagen
	</button>
</BottomSheet>
