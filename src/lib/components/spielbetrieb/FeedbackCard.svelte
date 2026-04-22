<script>
	import { sb } from '$lib/supabase';
	import { playerId } from '$lib/stores/auth';
	import { triggerToast } from '$lib/stores/toast.js';
	import { pickQuestion } from '$lib/utils/feedbackRotation.js';

	let { match, questions = [], existingFeedback = null, onSaved } = $props();

	const question = $derived(pickQuestion(questions, match?.id, $playerId));

	let answer = $state('');
	let saving = $state(false);
	let justSaved = $state(false);

	async function save() {
		if (!answer.trim() || !question || !$playerId) return;
		saving = true;
		const { data, error } = await sb
			.from('match_feedback')
			.upsert(
				{
					match_id:    match.id,
					player_id:   $playerId,
					question_id: question.id,
					answer:      answer.trim(),
				},
				{ onConflict: 'match_id,player_id' }
			)
			.select()
			.maybeSingle();
		saving = false;
		if (!error) {
			justSaved = true;
			triggerToast('Feedback gespeichert');
			onSaved?.(data);
		}
	}
</script>

<section class="mw-card">
	<div class="mw-card__head">
		<h3 class="mw-card__title">
			<span class="material-symbols-outlined" style="color: var(--color-secondary);">rate_review</span>
			Kurzes Feedback
		</h3>
	</div>

	{#if !question}
		<p class="mw-empty">Keine Frage verfügbar.</p>
	{:else if existingFeedback && !justSaved}
		<p class="mw-feedback__prompt">{question.prompt}</p>
		<div class="mw-feedback__answer">„{existingFeedback.answer}"</div>
		<span class="mw-feedback__thanks">
			<span class="material-symbols-outlined">check_circle</span>
			Danke für dein Feedback!
		</span>
	{:else if justSaved}
		<p class="mw-feedback__prompt">{question.prompt}</p>
		<div class="mw-feedback__answer">„{answer}"</div>
		<span class="mw-feedback__thanks">
			<span class="material-symbols-outlined">check_circle</span>
			Danke – gespeichert!
		</span>
	{:else}
		<p class="mw-feedback__prompt">{question.prompt}</p>
		<textarea
			class="mw-feedback__textarea"
			bind:value={answer}
			placeholder="Deine Antwort… (nur du &amp; der Kapitän sehen das)"
			enterkeyhint="send"
			autocapitalize="sentences"
			inputmode="text"
		></textarea>
		<p class="mw-feedback__hint">
			<span class="material-symbols-outlined">visibility_off</span>
			Anonym — Kapitän sieht deine Antwort ohne Name.
		</p>
		<button
			class="mw-btn mw-btn--primary mw-btn--wide"
			style="margin-top: var(--space-3);"
			disabled={saving || !answer.trim()}
			onclick={save}
		>
			<span class="material-symbols-outlined">send</span>
			Absenden
		</button>
	{/if}
</section>

<style>
	.mw-feedback__hint {
		display: flex; align-items: center; gap: var(--space-2);
		font-size: var(--text-label-sm);
		color: var(--color-on-surface-variant);
		margin: var(--space-2) 0 var(--space-2);
	}
	.mw-feedback__hint .material-symbols-outlined { font-size: 1rem; }
</style>
