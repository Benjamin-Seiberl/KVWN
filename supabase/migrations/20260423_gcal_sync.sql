-- Google-Calendar Sync: externe IDs, Sync-Status-Tabelle, RLS fuer events
alter table public.events
  add column if not exists external_id text unique,
  add column if not exists source      text not null default 'manual'
    check (source in ('manual','gcal')),
  add column if not exists synced_at   timestamptz,
  add column if not exists etag        text;

create index if not exists events_external_id_idx on public.events (external_id);
create index if not exists events_source_idx      on public.events (source);

alter table public.matches
  add column if not exists external_id text unique,
  add column if not exists etag        text,
  add column if not exists synced_at   timestamptz;

create index if not exists matches_external_id_idx on public.matches (external_id);

create table if not exists public.gcal_sync_state (
  calendar_id text primary key,
  sync_token  text,
  last_full_sync_at timestamptz,
  last_run_at timestamptz
);

alter table public.gcal_sync_state enable row level security;
create policy "gcal_sync_state readable" on public.gcal_sync_state
  for select to authenticated using (true);

alter table public.events enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies
    where schemaname='public' and tablename='events' and policyname='events_read_all') then
    create policy "events_read_all" on public.events
      for select to authenticated using (true);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_policies
    where schemaname='public' and tablename='events' and policyname='events_write_captain') then
    create policy "events_write_captain" on public.events
      for all to authenticated
      using (exists (select 1 from players
        where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin')))
      with check (exists (select 1 from players
        where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin')));
  end if;
end $$;
