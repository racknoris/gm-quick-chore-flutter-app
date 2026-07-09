-- Initial schema for Personal Assistant Voice-to-Chores.
-- Owns: recordings + chores tables, RLS, updated_at triggers, storage bucket.
-- The Heroku backend reads/writes these tables but does not define them.

-- ---------------------------------------------------------------------------
-- Helper: keep updated_at fresh on every row update.
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- recordings
-- ---------------------------------------------------------------------------
create table public.recordings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  audio_path  text not null,
  status      text not null default 'uploaded'
              check (status in ('uploaded', 'processing', 'done', 'failed')),
  title       text,                         -- LLM-generated; set when status = done
  transcript  text,
  error       text,                         -- machine error code when failed
  created_at  timestamptz not null default now(),  -- treated as the recording date
  updated_at  timestamptz not null default now(),

  -- v2 (nullable, unused in MVP):
  recorded_at timestamptz                   -- client-supplied true record-start time
);

create index recordings_user_id_created_at_idx
  on public.recordings (user_id, created_at desc);

create trigger recordings_set_updated_at
  before update on public.recordings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- chores
-- ---------------------------------------------------------------------------
create table public.chores (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  recording_id uuid not null references public.recordings (id) on delete cascade,
  content      text not null,               -- the chore/note text
  is_done      boolean not null default false,
  position     numeric,                     -- fractional ordering; order by position
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- v2 (nullable, unused in MVP — LLM leaves these null):
  due_date     date,
  priority     text check (priority in ('low', 'normal', 'high')),
  notes        text
);

create index chores_recording_id_position_idx
  on public.chores (recording_id, position);

create index chores_user_id_idx
  on public.chores (user_id);

create trigger chores_set_updated_at
  before update on public.chores
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security: every row is scoped to its owner (auth.uid()).
-- The backend uses the user's JWT, so these policies apply to it too.
-- ---------------------------------------------------------------------------
alter table public.recordings enable row level security;
alter table public.chores     enable row level security;

-- Table-level privileges. RLS still restricts the `authenticated` role to owned
-- rows; `service_role` (used by the backend's background processing) bypasses RLS
-- but still needs the grant to touch the tables at all.
grant select, insert, update, delete on public.recordings to authenticated, service_role;
grant select, insert, update, delete on public.chores     to authenticated, service_role;

-- recordings: owner-only for all operations.
create policy recordings_select_own on public.recordings
  for select using (auth.uid() = user_id);

create policy recordings_insert_own on public.recordings
  for insert with check (auth.uid() = user_id);

create policy recordings_update_own on public.recordings
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy recordings_delete_own on public.recordings
  for delete using (auth.uid() = user_id);

-- chores: owner-only for all operations.
create policy chores_select_own on public.chores
  for select using (auth.uid() = user_id);

create policy chores_insert_own on public.chores
  for insert with check (auth.uid() = user_id);

create policy chores_update_own on public.chores
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy chores_delete_own on public.chores
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Storage: private "recordings" bucket, path convention
--   recordings/{user_id}/{recording_id}.m4a
-- The first path segment must equal the authenticated user's id.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('recordings', 'recordings', false)
on conflict (id) do nothing;

create policy recordings_storage_select_own on storage.objects
  for select using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy recordings_storage_insert_own on storage.objects
  for insert with check (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy recordings_storage_update_own on storage.objects
  for update using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy recordings_storage_delete_own on storage.objects
  for delete using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
