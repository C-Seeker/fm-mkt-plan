-- =====================================================================
-- Full Marks — IB Maths Launch Dashboard
-- Supabase schema, security policies and seed data
--
-- HOW TO RUN
--   Supabase dashboard → SQL Editor → New query → paste all of this → Run
--   Safe to run more than once (everything is idempotent).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. ALLOWLIST — who is permitted to edit the board
--    Everyone can READ the board. Only emails in this table can WRITE.
-- ---------------------------------------------------------------------
create table if not exists public.allowlist (
  email      text primary key,
  note       text,
  added_at   timestamptz not null default now()
);

-- Approved editors. Stored lowercase — the policy lowercases before comparing.
insert into public.allowlist (email, note) values
  ('lyaraheducation@gmail.com', 'Approved editor'),
  ('seekhome.thailand@gmail.com', 'Approved editor')
on conflict (email) do nothing;


-- ---------------------------------------------------------------------
-- 2. BOARD STATE — every checkbox, note, metric and route status
--    One row per item. `kind` separates the different sections.
--      kind = 'task'   → item_id = 'D1-01', data = {done, note}
--      kind = 'asset'  → item_id = 'A01',   data = {done}
--      kind = 'metric' → item_id = 'M01',   data = {tgt, act}
--      kind = 'route'  → item_id = 'R1',    data = {status}
-- ---------------------------------------------------------------------
create table if not exists public.board_state (
  kind            text        not null,
  item_id         text        not null,
  data            jsonb       not null default '{}'::jsonb,
  updated_by      text,                    -- email of last editor
  updated_by_name text,                    -- display name of last editor
  updated_at      timestamptz not null default now(),
  primary key (kind, item_id),
  constraint board_state_kind_check
    check (kind in ('task','asset','metric','route','meta'))
);

create index if not exists board_state_kind_idx on public.board_state (kind);
create index if not exists board_state_updated_idx on public.board_state (updated_at desc);


-- ---------------------------------------------------------------------
-- 3. ACTIVITY LOG — the public record of who changed what
-- ---------------------------------------------------------------------
create table if not exists public.activity_log (
  id          bigint generated always as identity primary key,
  kind        text not null,
  item_id     text not null,
  label       text,                        -- human-readable item name
  action      text not null,               -- 'completed', 'reopened', 'noted', …
  actor_email text,
  actor_name  text,
  created_at  timestamptz not null default now()
);

create index if not exists activity_log_created_idx
  on public.activity_log (created_at desc);

-- Keep the log from growing without limit: trim to the newest 500 rows.
create or replace function public.trim_activity_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.activity_log
   where id < (
     select min(id) from (
       select id from public.activity_log order by id desc limit 500
     ) recent
   );
  return null;
end;
$$;

drop trigger if exists activity_log_trim on public.activity_log;
create trigger activity_log_trim
  after insert on public.activity_log
  execute function public.trim_activity_log();


-- ---------------------------------------------------------------------
-- 4. IS_EDITOR() — the single source of truth for write permission
--    Reads the email out of the signed-in user's JWT and checks the
--    allowlist. SECURITY DEFINER so it can read allowlist even though
--    that table is itself locked down.
-- ---------------------------------------------------------------------
create or replace function public.is_editor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.allowlist a
     where a.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

grant execute on function public.is_editor() to anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY
--    Read: anyone, including signed-out visitors.
--    Write: only allowlisted, signed-in users.
-- ---------------------------------------------------------------------
alter table public.board_state  enable row level security;
alter table public.activity_log enable row level security;
alter table public.allowlist    enable row level security;

-- board_state ---------------------------------------------------------
drop policy if exists board_read       on public.board_state;
drop policy if exists board_insert     on public.board_state;
drop policy if exists board_update     on public.board_state;
drop policy if exists board_no_delete  on public.board_state;

create policy board_read
  on public.board_state for select
  using (true);

create policy board_insert
  on public.board_state for insert
  to authenticated
  with check (
    public.is_editor()
    and updated_by = lower(auth.jwt() ->> 'email')   -- cannot write as someone else
  );

create policy board_update
  on public.board_state for update
  to authenticated
  using (public.is_editor())
  with check (
    public.is_editor()
    and updated_by = lower(auth.jwt() ->> 'email')
  );

-- No delete policy is created, so deletes are denied for everyone.

-- activity_log --------------------------------------------------------
drop policy if exists activity_read   on public.activity_log;
drop policy if exists activity_insert on public.activity_log;

create policy activity_read
  on public.activity_log for select
  using (true);

create policy activity_insert
  on public.activity_log for insert
  to authenticated
  with check (
    public.is_editor()
    and actor_email = lower(auth.jwt() ->> 'email')
  );

-- allowlist -----------------------------------------------------------
-- Editors may read the list (so the UI can show who has access).
-- Nobody can change it from the browser — add editors in the SQL editor.
drop policy if exists allowlist_read on public.allowlist;

create policy allowlist_read
  on public.allowlist for select
  to authenticated
  using (public.is_editor());


-- ---------------------------------------------------------------------
-- 5b. HARD DENY ON DELETE
--     RLS already blocks deletes (no DELETE policy exists, so a delete
--     matches zero rows). But a delete still returns HTTP 204, which
--     looks like success and makes the guarantee hard to verify.
--     Revoking the privilege outright makes it explicit and testable:
--     an attempted delete now returns a clear permission error.
-- ---------------------------------------------------------------------
revoke delete on public.board_state  from anon, authenticated;
revoke delete on public.activity_log from anon, authenticated;
revoke delete on public.allowlist    from anon, authenticated;

-- The allowlist is managed here in the SQL editor only — never from a browser.
revoke insert, update on public.allowlist from anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. REALTIME — push changes to every open browser instantly
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'board_state'
  ) then
    alter publication supabase_realtime add table public.board_state;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'activity_log'
  ) then
    alter publication supabase_realtime add table public.activity_log;
  end if;
end $$;


-- =====================================================================
-- DONE
--
-- To add another editor later:
--   insert into public.allowlist (email, note)
--   values ('someone@example.com', 'Their role')
--   on conflict (email) do nothing;
--
-- To remove an editor:
--   delete from public.allowlist where email = 'someone@example.com';
--
-- To check what the board currently holds:
--   select kind, count(*) from public.board_state group by kind;
--
-- To see recent activity:
--   select actor_name, action, label, created_at
--     from public.activity_log order by created_at desc limit 20;
-- =====================================================================
