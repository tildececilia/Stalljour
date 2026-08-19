-- ============================================================
--  EQUIWORKS – ARBETSPASS: SJUKANMÄLAN + NOTISER
--  1) rs_task_absence: personal sjukanmäler sig på arbetspass
--     (egen anmälan, eller chef/admin).
--  2) task_notice: notis i klockan när någon sätts på eller tas
--     bort från ett arbetspass.
--  Kräver db/arbetspass.sql + db/behorigheter.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create or replace function is_my_staff(fid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from rs_staff_member where staff_id = fid and email = my_email()) $$;

create table if not exists rs_task_absence (
  task_id    uuid not null references rs_task(id)  on delete cascade,
  work_date  date not null,
  staff_id   uuid not null references rs_staff(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (task_id, work_date, staff_id)
);
alter table rs_task_absence enable row level security;
drop policy if exists rsta_sel on rs_task_absence; drop policy if exists rsta_ins on rs_task_absence; drop policy if exists rsta_del on rs_task_absence;
create policy rsta_sel on rs_task_absence for select using ( is_school_member(task_school(task_id)) );
create policy rsta_ins on rs_task_absence for insert
  with check ( is_school_chef(task_school(task_id)) or is_my_staff(staff_id) );
create policy rsta_del on rs_task_absence for delete
  using ( is_school_chef(task_school(task_id)) or is_my_staff(staff_id) );

create table if not exists task_notice (
  id         uuid primary key default gen_random_uuid(),
  stable_id  uuid not null references stable(id) on delete cascade,
  email      text not null,
  kind       text not null,          -- added | removed
  task_name  text not null,
  created_at timestamptz not null default now(),
  seen       boolean not null default false
);
alter table task_notice enable row level security;
drop policy if exists tn_sel on task_notice; drop policy if exists tn_ins on task_notice; drop policy if exists tn_upd on task_notice;
create policy tn_sel on task_notice for select using ( email = my_email() );
create policy tn_ins on task_notice for insert with check ( is_school_chef(stable_id) );
create policy tn_upd on task_notice for update using ( email = my_email() );
