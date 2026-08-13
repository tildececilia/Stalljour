-- ============================================================
--  STALLJOUR – RIDSKOLA (parallell verksamhetstyp)
--  Ett "stall" kan nu vara av typen 'stall' eller 'ridskola'.
--  Ridskolan har grupper (lektionstider), elever (med föräldra-
--  mejl), hästar, ledare, hästtilldelning per tillfälle och
--  sjukanmälan. Kör hela filen i Supabase → SQL Editor → Run.
-- ============================================================

alter table stable add column if not exists kind text not null default 'stall';

create table if not exists rs_student (
  id         uuid primary key default gen_random_uuid(),
  stable_id  uuid not null references stable(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now()
);
create table if not exists rs_student_member (      -- mejl med åtkomst (föräldrar)
  student_id uuid not null references rs_student(id) on delete cascade,
  email      text not null,
  primary key (student_id, email)
);
create table if not exists rs_horse (
  id        uuid primary key default gen_random_uuid(),
  stable_id uuid not null references stable(id) on delete cascade,
  name      text not null
);
create table if not exists rs_group (
  id             uuid primary key default gen_random_uuid(),
  stable_id      uuid not null references stable(id) on delete cascade,
  name           text not null,
  category_id    uuid references category(id) on delete set null,
  weekday        int  not null default 1,       -- 1=måndag … 7=söndag
  start_time     text not null default '17:00',
  duration_min   int  not null default 60,
  capacity       int  not null default 8,
  horse_rotation int  not null default 1,       -- antal gånger innan hästbyte
  sort_order     int  not null default 0
);
create table if not exists rs_group_student (
  group_id   uuid not null references rs_group(id)   on delete cascade,
  student_id uuid not null references rs_student(id) on delete cascade,
  primary key (group_id, student_id)
);
create table if not exists rs_leader (
  id       uuid primary key default gen_random_uuid(),
  group_id uuid not null references rs_group(id) on delete cascade,
  name     text not null
);
create table if not exists rs_assignment (          -- häst per elev och tillfälle
  group_id    uuid not null references rs_group(id)   on delete cascade,
  lesson_date date not null,
  student_id  uuid not null references rs_student(id) on delete cascade,
  horse_id    uuid references rs_horse(id) on delete set null,
  primary key (group_id, lesson_date, student_id)
);
create table if not exists rs_absence (             -- sjukanmälan
  group_id    uuid not null references rs_group(id)   on delete cascade,
  lesson_date date not null,
  student_id  uuid not null references rs_student(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (group_id, lesson_date, student_id)
);

-- ---------- Hjälpfunktioner ----------
create or replace function is_school_member(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid) or exists(
     select 1 from rs_student_member sm join rs_student s on s.id = sm.student_id
     where s.stable_id = sid and sm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function is_my_student(stid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from rs_student_member
                 where student_id = stid and email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function student_school(stid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from rs_student where id = stid $$;

create or replace function group_school(gid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from rs_group where id = gid $$;

-- ---------- RLS ----------
alter table rs_student        enable row level security;
alter table rs_student_member enable row level security;
alter table rs_horse          enable row level security;
alter table rs_group          enable row level security;
alter table rs_group_student  enable row level security;
alter table rs_leader         enable row level security;
alter table rs_assignment     enable row level security;
alter table rs_absence        enable row level security;

drop policy if exists rss_sel on rs_student;  drop policy if exists rss_ins on rs_student;
drop policy if exists rss_upd on rs_student;  drop policy if exists rss_del on rs_student;
create policy rss_sel on rs_student for select using ( is_school_member(stable_id) );
create policy rss_ins on rs_student for insert with check ( is_stable_admin(stable_id) );
create policy rss_upd on rs_student for update using ( is_stable_admin(stable_id) );
create policy rss_del on rs_student for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsm_sel on rs_student_member; drop policy if exists rsm_ins on rs_student_member; drop policy if exists rsm_del on rs_student_member;
create policy rsm_sel on rs_student_member for select
  using ( email = my_email() or is_school_member(student_school(student_id)) );
create policy rsm_ins on rs_student_member for insert
  with check ( is_stable_admin(student_school(student_id)) or is_my_student(student_id) );
create policy rsm_del on rs_student_member for delete
  using ( is_stable_admin(student_school(student_id)) or is_my_student(student_id) );

drop policy if exists rsh_sel on rs_horse; drop policy if exists rsh_ins on rs_horse;
drop policy if exists rsh_upd on rs_horse; drop policy if exists rsh_del on rs_horse;
create policy rsh_sel on rs_horse for select using ( is_school_member(stable_id) );
create policy rsh_ins on rs_horse for insert with check ( is_stable_admin(stable_id) );
create policy rsh_upd on rs_horse for update using ( is_stable_admin(stable_id) );
create policy rsh_del on rs_horse for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsg_sel on rs_group; drop policy if exists rsg_ins on rs_group;
drop policy if exists rsg_upd on rs_group; drop policy if exists rsg_del on rs_group;
create policy rsg_sel on rs_group for select using ( is_school_member(stable_id) );
create policy rsg_ins on rs_group for insert with check ( is_stable_admin(stable_id) );
create policy rsg_upd on rs_group for update using ( is_stable_admin(stable_id) );
create policy rsg_del on rs_group for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsgs_sel on rs_group_student; drop policy if exists rsgs_ins on rs_group_student; drop policy if exists rsgs_del on rs_group_student;
create policy rsgs_sel on rs_group_student for select using ( is_school_member(group_school(group_id)) );
create policy rsgs_ins on rs_group_student for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsgs_del on rs_group_student for delete using ( is_stable_admin(group_school(group_id)) );

drop policy if exists rsl_sel on rs_leader; drop policy if exists rsl_ins on rs_leader;
drop policy if exists rsl_upd on rs_leader; drop policy if exists rsl_del on rs_leader;
create policy rsl_sel on rs_leader for select using ( is_school_member(group_school(group_id)) );
create policy rsl_ins on rs_leader for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsl_upd on rs_leader for update using ( is_stable_admin(group_school(group_id)) );
create policy rsl_del on rs_leader for delete using ( is_stable_admin(group_school(group_id)) );

drop policy if exists rsa_sel on rs_assignment; drop policy if exists rsa_ins on rs_assignment;
drop policy if exists rsa_upd on rs_assignment; drop policy if exists rsa_del on rs_assignment;
create policy rsa_sel on rs_assignment for select using ( is_school_member(group_school(group_id)) );
create policy rsa_ins on rs_assignment for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsa_upd on rs_assignment for update using ( is_stable_admin(group_school(group_id)) );
create policy rsa_del on rs_assignment for delete using ( is_stable_admin(group_school(group_id)) );

drop policy if exists rsab_sel on rs_absence; drop policy if exists rsab_ins on rs_absence; drop policy if exists rsab_del on rs_absence;
create policy rsab_sel on rs_absence for select using ( is_school_member(group_school(group_id)) );
create policy rsab_ins on rs_absence for insert
  with check ( is_stable_admin(group_school(group_id)) or is_my_student(student_id) );
create policy rsab_del on rs_absence for delete
  using ( is_stable_admin(group_school(group_id)) or is_my_student(student_id) );

-- ---------- Skapa stall/ridskola med typ ----------
drop function if exists create_stable(text);
create or replace function create_stable(p_name text, p_kind text default 'stall')
returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  insert into stable(name, kind) values (p_name, case when p_kind = 'ridskola' then 'ridskola' else 'stall' end)
    returning id into new_id;
  insert into stable_admin(stable_id, email) values (new_id, lower(auth.jwt() ->> 'email'));
  return new_id;
end $$;
grant execute on function create_stable(text, text) to anon, authenticated;
