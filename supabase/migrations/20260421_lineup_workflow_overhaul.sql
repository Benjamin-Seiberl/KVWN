alter table public.game_plan_players
  add column if not exists confirmed_at         timestamptz,
  add column if not exists replaced_at          timestamptz,
  add column if not exists replaced_from_id     uuid references public.players(id),
  add column if not exists replaced_reason_code text,
  add column if not exists replaced_reason_text text;

create or replace function public.tg_set_confirmed_at() returns trigger as $$
begin
  if (new.confirmed is distinct from old.confirmed) and new.confirmed is not null then
    new.confirmed_at := now();
  elsif new.confirmed is null then
    new.confirmed_at := null;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists game_plan_players_confirmed_at on public.game_plan_players;
create trigger game_plan_players_confirmed_at
  before update on public.game_plan_players
  for each row execute function public.tg_set_confirmed_at();

drop policy if exists "game_plan_players confirm own" on public.game_plan_players;
create policy "game_plan_players confirm own" on public.game_plan_players
  for update using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  )
  with check (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

drop policy if exists "game_plan_players kapitaen write" on public.game_plan_players;
create policy "game_plan_players kapitaen write" on public.game_plan_players
  for all using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  )
  with check (true);
