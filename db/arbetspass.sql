-- ============================================================
--  STALLJOUR – LEKTIONSKOPPLINGAR + ARBETSPASS
--  1) Hästar och personal kan kopplas till lektioner (rs_group).
--  2) Arbetspass: återkommande sysslor för personalen som inte
--     är lektioner (t.ex. "Mocka boxar"), med veckodag, tid,
--     beskrivning och tilldelad personal.
--  Kräver: db/ridskola.sql och db/personal.sql. Säker att köra om.
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

-- ---------- Kopplingar till lektioner ----------
create table if not exists rs_group_horse (
  group_id uuid not null references rs_group(id) on delete cascade,
  horse_id uuid not null references rs_horse(id) on delete cascade,
  primary key (group_id, horse_id)
);
create table if not exists rs_group_staff (
  group_id uuid not null references rs_group(id) on delete cascade,
  staff_id uuid not null references rs_staff(id) on delete cascade,
  primary key (group_id, staff_id)
);

alter table rs_group_horse enable row level security;
alter table rs_group_staff enable row level security;

drop policy if exists rsgh_sel on rs_group_horse; drop policy if exists rsgh_ins on rs_group_horse; drop policy if exists rsgh_del on rs_group_horse;
create policy rsgh_sel on rs_group_horse for select using ( is_school_member(group_school(group_id)) );
create policy rsgh_ins on rs_group_horse for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsgh_del on rs_group_horse for delete using ( is_stable_admin(group_school(group_id)) );

drop policy if exists rsgf_sel on rs_group_staff; drop policy if exists rsgf_ins on rs_group_staff; drop policy if exists rsgf_del on rs_group_staff;
create policy rsgf_sel on rs_group_staff for select using ( is_school_member(group_school(group_id)) );
create policy rsgf_ins on rs_group_staff for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsgf_del on rs_group_staff for delete using ( is_stable_admin(group_school(group_id)) );

-- ---------- Arbetspass ----------
create table if not exists rs_task (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id) on delete cascade,
  name         text not null,
  description  text,
  weekday      int  not null default 1,        -- 1=måndag … 7=söndag
  start_time   text not null default '08:00',
  duration_min int  not null default 60,
  sort_order   int  not null default 0
);
create table if not exists rs_task_staff (
  task_id  uuid not null references rs_task(id)  on delete cascade,
  staff_id uuid not null references rs_staff(id) on delete cascade,
  primary key (task_id, staff_id)
);

create or replace function task_school(tid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from rs_task where id = tid $$;

alter table rs_task       enable row level security;
alter table rs_task_staff enable row level security;

drop policy if exists rst_sel on rs_task; drop policy if exists rst_ins on rs_task;
drop policy if exists rst_upd on rs_task; drop policy if exists rst_del on rs_task;
create policy rst_sel on rs_task for select using ( is_school_member(stable_id) );
create policy rst_ins on rs_task for insert with check ( is_stable_admin(stable_id) );
create policy rst_upd on rs_task for update using ( is_stable_admin(stable_id) );
create policy rst_del on rs_task for delete using ( is_stable_admin(stable_id) );

drop policy if exists rstf_sel on rs_task_staff; drop policy if exists rstf_ins on rs_task_staff; drop policy if exists rstf_del on rs_task_staff;
create policy rstf_sel on rs_task_staff for select using ( is_school_member(task_school(task_id)) );
create policy rstf_ins on rs_task_staff for insert with check ( is_stable_admin(task_school(task_id)) );
create policy rstf_del on rs_task_staff for delete using ( is_stable_admin(task_school(task_id)) );
