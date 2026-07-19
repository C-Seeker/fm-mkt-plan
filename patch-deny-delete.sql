-- =====================================================================
-- Hardening patch — run this once in Supabase → SQL Editor
--
-- Row-level security already blocks deletes, but they return HTTP 204
-- ("no content"), which is indistinguishable from a successful delete
-- of zero rows. Revoking the privilege makes the denial explicit and
-- verifiable.
--
-- Safe to run more than once.
-- =====================================================================

revoke delete on public.board_state  from anon, authenticated;
revoke delete on public.activity_log from anon, authenticated;
revoke delete on public.allowlist    from anon, authenticated;

-- The allowlist is managed here in the SQL editor only, never from a browser.
revoke insert, update on public.allowlist from anon, authenticated;


-- ---------------------------------------------------------------------
-- Verify it worked. This should return NO rows for delete on any table.
-- ---------------------------------------------------------------------
select grantee, table_name, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public'
   and table_name in ('board_state','activity_log','allowlist')
   and grantee in ('anon','authenticated')
   and privilege_type = 'DELETE';
