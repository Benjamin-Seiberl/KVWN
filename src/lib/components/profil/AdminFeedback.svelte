<script>
  import { sb } from '$lib/supabase';
  import BottomSheet from '../BottomSheet.svelte';
  import { fmtDate } from '$lib/utils/dates.js';
  import { triggerToast } from '$lib/stores/toast.js';

  let { open = $bindable(false) } = $props();

  let matches   = $state([]);
  let selected  = $state(null);
  let answers   = $state([]);
  let questions = $state([]);
  let loading   = $state(true);
  let loadingAnswers = $state(false);

  async function load() {
    loading = true;
    const { data: q } = await sb.from('feedback_questions').select('id, prompt');
    questions = q ?? [];

    const since = new Date(Date.now() - 60 * 86_400_000).toISOString().slice(0, 10);
    const { data: fb } = await sb.from('match_feedback').select('match_id').gte('created_at', since);
    const ids = [...new Set((fb ?? []).map(x => x.match_id))];

    if (ids.length) {
      const { data: m } = await sb.from('matches')
        .select('id, date, opponent, leagues(name)')
        .in('id', ids)
        .order('date', { ascending: false });
      matches = m ?? [];
    } else {
      matches = [];
    }
    loading = false;
  }

  async function pick(m) {
    selected = m;
    loadingAnswers = true;
    const { data, error } = await sb.rpc('read_anon_feedback', { p_match_id: m.id });
    if (error) triggerToast('Fehler: ' + error.message);
    answers = data ?? [];
    loadingAnswers = false;
  }

  function back() { selected = null; answers = []; }

  function questionLabel(qid) {
    return questions.find(q => q.id === qid)?.prompt ?? '—';
  }

  $effect(() => {
    if (open) load();
  });
</script>

<BottomSheet bind:open title={selected ? 'Anonyme Antworten' : 'Feedback'}>
  {#if loading}
    <div class="skeleton-card animate-pulse-skeleton" style="height:64px; border-radius:var(--radius-md)"></div>
  {:else if !selected}
    {#if matches.length === 0}
      <p class="af-empty">Noch kein Feedback eingetroffen.</p>
    {:else}
      <p class="af-hint">Wähle ein Match, um anonyme Antworten zu sehen.</p>
      <div class="af-list">
        {#each matches as m (m.id)}
          <button class="af-row" onclick={() => pick(m)}>
            <div class="af-row-info">
              <span class="af-row-label">{m.opponent}</span>
              <span class="af-row-sub">{m.leagues?.name ?? ''} · {fmtDate(m.date)}</span>
            </div>
            <span class="material-symbols-outlined af-chev">chevron_right</span>
          </button>
        {/each}
      </div>
    {/if}
  {:else}
    <button class="af-back" onclick={back}>
      <span class="material-symbols-outlined">arrow_back</span>
      Zurück
    </button>
    <div class="af-match-hero">
      <span class="af-match-label">{selected.opponent}</span>
      <span class="af-match-sub">{selected.leagues?.name ?? ''} · {fmtDate(selected.date)}</span>
    </div>
    <p class="af-anon-hint">
      <span class="material-symbols-outlined">visibility_off</span>
      Antworten sind anonym — keine Zuordnung zu Spielern möglich.
    </p>

    {#if loadingAnswers}
      <div class="skeleton-card animate-pulse-skeleton" style="height:120px; border-radius:var(--radius-md)"></div>
    {:else if answers.length === 0}
      <p class="af-empty">Keine Antworten.</p>
    {:else}
      <div class="af-answers">
        {#each answers as a (a.id)}
          <article class="af-answer mw-card">
            <p class="af-question">{questionLabel(a.question_id)}</p>
            <p class="af-text">{a.answer}</p>
          </article>
        {/each}
      </div>
    {/if}
  {/if}
</BottomSheet>

<style>
  .af-empty, .af-hint { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); margin: 0 0 var(--space-3); }
  .af-list { display: flex; flex-direction: column; gap: var(--space-2); }
  .af-row {
    display: flex; align-items: center; gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface-container-low);
    border-radius: var(--radius-md);
    border: none; cursor: pointer; text-align: left; width: 100%;
    -webkit-tap-highlight-color: transparent;
  }
  .af-row-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .af-row-label { font-weight: 600; font-size: var(--text-body-md); color: var(--color-on-surface); }
  .af-row-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
  .af-chev { font-size: 1.2rem; color: var(--color-outline); }
  .af-back {
    display: inline-flex; align-items: center; gap: var(--space-1);
    border: none; background: none;
    font-size: var(--text-body-sm); font-weight: 600;
    color: var(--color-primary); cursor: pointer; padding: 0;
    margin-bottom: var(--space-3);
  }
  .af-match-hero {
    display: flex; flex-direction: column; gap: 2px;
    margin-bottom: var(--space-3); padding-bottom: var(--space-3);
    border-bottom: 1px solid var(--color-outline-variant);
  }
  .af-match-label { font-family: var(--font-display); font-weight: 700; font-size: var(--text-title-sm); color: var(--color-on-surface); }
  .af-match-sub { font-size: var(--text-body-sm); color: var(--color-on-surface-variant); }
  .af-anon-hint {
    display: flex; align-items: center; gap: var(--space-2);
    font-size: var(--text-body-sm); color: var(--color-on-surface-variant);
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-container-low);
    border-radius: var(--radius-md);
    margin: 0 0 var(--space-3);
  }
  .af-anon-hint .material-symbols-outlined { font-size: 1.1rem; }
  .af-answers { display: flex; flex-direction: column; gap: var(--space-2); }
  .af-answer { padding: var(--space-3); }
  .af-question { font-size: var(--text-label-sm); font-weight: 700; color: var(--color-on-surface-variant); margin: 0 0 var(--space-1); text-transform: uppercase; letter-spacing: 0.05em; }
  .af-text { font-size: var(--text-body-md); color: var(--color-on-surface); margin: 0; white-space: pre-wrap; }
</style>
