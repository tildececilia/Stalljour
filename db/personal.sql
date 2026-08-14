-- ============================================================
--  STALLJOUR – PERSONAL för ridskolor
--  Personer med mejladresser och egna kategorier (t.ex.
--  Ridlärare, Stallpersonal). Personalens mejl ger inloggning
--  och läsbehörighet i ridskolan. Kör i SQL Editor → Run.
-- ============================================================

create table if not exists rs_staff_category (
  id         uuid primary key default gen_random_uuid(),
  stable_id  uuid not null references stable(id) on delete cascade,
  name       text not null,
  sort_order int  not null default 0
);
create table if not exists rs_staff (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  category_id uuid references rs_staff_category(id) on delete set null,
  created_at  timestamptz not null default now()
);
create table if not exists rs_staff_member (
  staff_id uuid not null references rs_staff(id) on delete cascade,
  email    text not null,
  primary key (staff_id, email)
);

-- Personal räknas som medlemmar i ridskolan (ser allt, kan inte ändra)
create or replace function is_school_member(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid)
   or exists(select 1 from rs_student_member sm join rs_student s on s.id = sm.student_id
             where s.stable_id = sid and sm.email = lower(coalesce(auth.jwt() ->> 'email','')))
   or exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
             where f.stable_id = sid and fm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

alter table rs_staff_category enable row level security;
alter table rs_staff          enable row level security;
alter table rs_staff_member   enable row level security;

drop policy if exists rsc_sel on rs_staff_category; drop policy if exists rsc_ins on rs_staff_category;
drop policy if exists rsc_upd on rs_staff_category; drop policy if exists rsc_del on rs_staff_category;
create policy rsc_sel on rs_staff_category for select using ( is_school_member(stable_id) );
create policy rsc_ins on rs_staff_category for insert with check ( is_stable_admin(stable_id) );
create policy rsc_upd on rs_staff_category for update using ( is_stable_admin(stable_id) );
create policy rsc_del on rs_staff_category for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsf_sel on rs_staff; drop policy if exists rsf_ins on rs_staff;
drop policy if exists rsf_upd on rs_staff; drop policy if exists rsf_del on rs_staff;
create policy rsf_sel on rs_staff for select using ( is_school_member(stable_id) );
create policy rsf_ins on rs_staff for insert with check ( is_stable_admin(stable_id) );
create policy rsf_upd on rs_staff for update using ( is_stable_admin(stable_id) );
create policy rsf_del on rs_staff for delete using ( is_stable_admin(stable_id) );

create or replace function staff_school(fid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from rs_staff where id = fid $$;

drop policy if exists rsfm_sel on rs_staff_member; drop policy if exists rsfm_ins on rs_staff_member; drop policy if exists rsfm_del on rs_staff_member;
create policy rsfm_sel on rs_staff_member for select
  using ( email = my_email() or is_school_member(staff_school(staff_id)) );
create policy rsfm_ins on rs_staff_member for insert with check ( is_stable_admin(staff_school(staff_id)) );
create policy rsfm_del on rs_staff_member for delete using ( is_stable_admin(staff_school(staff_id)) );
