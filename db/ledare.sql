-- ============================================================
--  EQUIWORKS – LEDARE SOM EGEN LISTA (ridskola)
--  Ledare blir egna poster (namn + mejl) som kan kopplas till
--  lektioner. Varje lektion får en ja/nej-flagga (has_leaders,
--  standard nej) — bara lektioner med "ja" visar ledarsektionen.
--  Gamla fritextledare (rs_leader) migreras automatiskt.
--  Kräver db/ridskola.sql + db/personal.sql. Säker att köra om.
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

alter table rs_group add column if not exists has_leaders boolean not null default false;

create table if not exists rs_instructor (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  description text,
  created_at  timestamptz not null default now()
);
create table if not exists rs_instructor_member (   -- mejl med åtkomst
  instructor_id uuid not null references rs_instructor(id) on delete cascade,
  email         text not null,
  primary key (instructor_id, email)
);
create table if not exists rs_group_instructor (
  group_id      uuid not null references rs_group(id)      on delete cascade,
  instructor_id uuid not null references rs_instructor(id) on delete cascade,
  primary key (group_id, instructor_id)
);

-- Ledarmejl räknas som medlemmar i ridskolan (ser allt, kan inte ändra)
create or replace function is_school_member(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid)
   or exists(select 1 from rs_student_member sm join rs_student s on s.id = sm.student_id
             where s.stable_id = sid and sm.email = lower(coalesce(auth.jwt() ->> 'email','')))
   or exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
             where f.stable_id = sid and fm.email = lower(coalesce(auth.jwt() ->> 'email','')))
   or exists(select 1 from rs_instructor_member im join rs_instructor i on i.id = im.instructor_id
             where i.stable_id = sid and im.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function instructor_school(iid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from rs_instructor where id = iid $$;

alter table rs_instructor        enable row level security;
alter table rs_instructor_member enable row level security;
alter table rs_group_instructor  enable row level security;

drop policy if exists rsi_sel on rs_instructor; drop policy if exists rsi_ins on rs_instructor;
drop policy if exists rsi_upd on rs_instructor; drop policy if exists rsi_del on rs_instructor;
create policy rsi_sel on rs_instructor for select using ( is_school_member(stable_id) );
create policy rsi_ins on rs_instructor for insert with check ( is_stable_admin(stable_id) );
create policy rsi_upd on rs_instructor for update using ( is_stable_admin(stable_id) );
create policy rsi_del on rs_instructor for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsim_sel on rs_instructor_member; drop policy if exists rsim_ins on rs_instructor_member; drop policy if exists rsim_del on rs_instructor_member;
create policy rsim_sel on rs_instructor_member for select
  using ( email = my_email() or is_school_member(instructor_school(instructor_id)) );
create policy rsim_ins on rs_instructor_member for insert with check ( is_stable_admin(instructor_school(instructor_id)) );
create policy rsim_del on rs_instructor_member for delete using ( is_stable_admin(instructor_school(instructor_id)) );

drop policy if exists rsgi_sel on rs_group_instructor; drop policy if exists rsgi_ins on rs_group_instructor; drop policy if exists rsgi_del on rs_group_instructor;
create policy rsgi_sel on rs_group_instructor for select using ( is_school_member(group_school(group_id)) );
create policy rsgi_ins on rs_group_instructor for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsgi_del on rs_group_instructor for delete using ( is_stable_admin(group_school(group_id)) );

-- ---------- Migrera gamla fritextledare ----------
insert into rs_instructor (stable_id, name)
  select distinct group_school(l.group_id), l.name from rs_leader l
  where group_school(l.group_id) is not null
    and not exists (select 1 from rs_instructor i
                    where i.stable_id = group_school(l.group_id) and i.name = l.name);
insert into rs_group_instructor (group_id, instructor_id)
  select l.group_id, i.id from rs_leader l
  join rs_instructor i on i.stable_id = group_school(l.group_id) and i.name = l.name
  on conflict do nothing;
update rs_group g set has_leaders = true
  where exists (select 1 from rs_leader l where l.group_id = g.id) and not g.has_leaders;
