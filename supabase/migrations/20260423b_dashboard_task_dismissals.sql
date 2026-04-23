-- Persistent dismiss for dashboard task-cards (e.g. "Landesbewerb anmelden").
-- Once a player dismisses a task-card, it should stay dismissed across devices
-- and future loads. Extensible via task_kind so non-landesbewerb cards can
-- share the same mechanism later.

create table if not exists public.dashboard_task_dismissals (
  player_id    uuid not null references public.players(id) on delete cascade,
  task_kind    text not null,        -- 'landesbewerb' for now; extensible
  task_ref_id  uuid not null,        -- e.g. matches.id when task_kind='landesbewerb'
  dismissed_at timestamptz not null default now(),
  primary key (player_id, task_kind, task_ref_id)
);

alter table public.dashboard_task_dismissals enable row level security;

drop policy if exists "own_select" on public.dashboard_task_dismissals;
create policy "own_select" on public.dashboard_task_dismissals
  for select using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

drop policy if exists "own_insert" on public.dashboard_task_dismissals;
create policy "own_insert" on public.dashboard_task_dismissals
  for insert with check (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

drop policy if exists "own_delete" on public.dashboard_task_dismissals;
create policy "own_delete" on public.dashboard_task_dismissals
  for delete using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );
