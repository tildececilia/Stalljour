-- ============================================================
--  STALLJOUR – logg för borttagna pass
--  (bokningar raderas helt, så borttag sparas i egen loggtabell)
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists booking_log (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id) on delete cascade,
  pass_date    date not null,
  pass_name    text not null,
  profile_id   uuid references profile(id) on delete set null,
  profile_name text not null,
  action       text not null default 'cancel',
  created_at   timestamptz not null default now()
);

alter table booking_log enable row level security;
drop policy if exists bl_sel on booking_log;
drop policy if exists bl_ins on booking_log;
create policy bl_sel on booking_log for select using ( is_stable_member(stable_id) );
create policy bl_ins on booking_log for insert with check ( is_stable_member(stable_id) );
