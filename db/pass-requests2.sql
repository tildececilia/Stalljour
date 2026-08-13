-- ============================================================
--  STALLJOUR – BYT PASS del 2: svars-notis till avsändaren
--  Kör hela filen i Supabase → SQL Editor → Run.
-- ============================================================

alter table pass_request add column if not exists seen_by_requester boolean not null default false;

-- Avsändaren kvitterar att hen sett svaret (godkänt/avböjt)
create or replace function mark_request_seen(p_request uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update pass_request pr set seen_by_requester = true
   where pr.id = p_request
     and exists (select 1 from profile_member pm
                 where pm.profile_id = pr.from_profile
                   and pm.email = lower(coalesce(auth.jwt() ->> 'email','')));
end $$;
grant execute on function mark_request_seen(uuid) to anon, authenticated;
