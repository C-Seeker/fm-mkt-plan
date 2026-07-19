-- =====================================================================
-- Patch — custom tasks
-- Run once in Supabase → SQL Editor. Safe to run more than once.
--
-- Lets approved editors add their own tasks to the 10-day plan, and
-- hide ones they don't need. Nothing is ever hard-deleted: removal sets
-- `archived`, so a mistake can always be undone.
-- =====================================================================

create table if not exists public.custom_tasks (
  id              text primary key,
  day             int  not null check (day between 1 and 10),
  workstream      text not null,
  priority        text not null default 'Medium'
                    check (priority in ('Critical','High','Medium')),
  title           text not null check (length(trim(title)) > 0),
  deliverable     text,
  archived        boolean not null default false,
  created_by      text,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists custom_tasks_day_idx
  on public.custom_tasks (day) where archived = false;


-- ---------------------------------------------------------------------
-- Security: same model as everything else.
--   Read  — anyone, so viewers see the full plan.
--   Write — approved editors only, and only as themselves.
--   Delete — nobody. Removal is an archive flag.
-- ---------------------------------------------------------------------
alter table public.custom_tasks enable row level security;

drop policy if exists ct_read   on public.custom_tasks;
drop policy if exists ct_insert on public.custom_tasks;
drop policy if exists ct_update on public.custom_tasks;

create policy ct_read
  on public.custom_tasks for select
  using (true);

create policy ct_insert
  on public.custom_tasks for insert
  to authenticated
  with check (
    public.is_editor()
    and created_by = lower(auth.jwt() ->> 'email')
  );

create policy ct_update
  on public.custom_tasks for update
  to authenticated
  using (public.is_editor())
  with check (public.is_editor());

revoke delete on public.custom_tasks from anon, authenticated;


-- ---------------------------------------------------------------------
-- Realtime so added and removed tasks appear on every open screen
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname='supabase_realtime' and schemaname='public' and tablename='custom_tasks'
  ) then
    alter publication supabase_realtime add table public.custom_tasks;
  end if;
end $$;


-- ---------------------------------------------------------------------
-- Verify: should return the table with RLS enabled and no DELETE grant.
-- ---------------------------------------------------------------------
select
  (select count(*) from pg_policies
    where schemaname='public' and tablename='custom_tasks')            as policies,
  (select relrowsecurity from pg_class
    where oid = 'public.custom_tasks'::regclass)                       as rls_on,
  (select count(*) from information_schema.role_table_grants
    where table_schema='public' and table_name='custom_tasks'
      and grantee in ('anon','authenticated')
      and privilege_type='DELETE')                                     as delete_grants;
