-- ============================================================
--  EQUIWORKS – BEHÖRIGHETER FÖR RIDSKOLA
--  Roller per personal (rs_staff.perm):
--    'none'    = stallpersonal: ser allt, ändrar inget (standard)
--    'teacher' = ridlärare: ändrar lektioner, elever, hästar,
--                tilldelningar, planering, sjukanmälan — EJ arbetspass
--    'chef'    = chef: ändrar arbetspass + bemanning — EJ lektioner
--  Admin kan allt som förut. Ledare och elever/föräldrar ser bara
--  (föräldrar kan sjukanmäla sitt barn som förut).
--  Elevbeskrivningar flyttas till rs_student_note som bara admin,
--  ridlärare och elevens egna målsmän kan läsa.
--  Kräver alla tidigare db-filer. Säker att köra om.
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

alter table rs_staff add column if not exists perm text not null default 'none';

create or replace function is_school_teacher(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid)
   or exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
             where f.stable_id = sid and f.perm = 'teacher' and fm.email = my_email()) $$;

create or replace function is_school_chef(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid)
   or exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
             where f.stable_id = sid and f.perm = 'chef' and fm.email = my_email()) $$;

create or replace function my_school_perm(sid uuid) returns text
language sql stable security definer set search_path = public as
$$ select case
     when is_stable_admin(sid) then 'admin'
     when exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
                 where f.stable_id = sid and f.perm = 'teacher' and fm.email = my_email()) then 'teacher'
     when exists(select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
                 where f.stable_id = sid and f.perm = 'chef' and fm.email = my_email()) then 'chef'
     else 'member' end $$;

-- ---------- Skyddade elevanteckningar ----------
create table if not exists rs_student_note (
  student_id uuid primary key references rs_student(id) on delete cascade,
  note text
);
alter table rs_student_note enable row level security;
drop policy if exists rsn_sel on rs_student_note; drop policy if exists rsn_ins on rs_student_note;
drop policy if exists rsn_upd on rs_student_note; drop policy if exists rsn_del on rs_student_note;
create policy rsn_sel on rs_student_note for select
  using ( is_school_teacher(student_school(student_id)) or is_my_student(student_id) );
create policy rsn_ins on rs_student_note for insert with check ( is_school_teacher(student_school(student_id)) );
create policy rsn_upd on rs_student_note for update using ( is_school_teacher(student_school(student_id)) );
create policy rsn_del on rs_student_note for delete using ( is_school_teacher(student_school(student_id)) );

-- migrera befintliga beskrivningar och rensa den öppna kolumnen
insert into rs_student_note (student_id, note)
  select id, description from rs_student where coalesce(description,'') <> ''
  on conflict (student_id) do nothing;
update rs_student set description = null where coalesce(description,'') <> '';

-- ---------- Ridlärare: lektioner, elever, hästar ----------
drop policy if exists rss_ins on rs_student; drop policy if exists rss_upd on rs_student; drop policy if exists rss_del on rs_student;
create policy rss_ins on rs_student for insert with check ( is_school_teacher(stable_id) );
create policy rss_upd on rs_student for update using ( is_school_teacher(stable_id) );
create policy rss_del on rs_student for delete using ( is_school_teacher(stable_id) );

drop policy if exists rsm_ins on rs_student_member; drop policy if exists rsm_del on rs_student_member;
create policy rsm_ins on rs_student_member for insert
  with check ( is_school_teacher(student_school(student_id)) or is_my_student(student_id) );
create policy rsm_del on rs_student_member for delete
  using ( is_school_teacher(student_school(student_id)) or is_my_student(student_id) );

drop policy if exists rsh_ins on rs_horse; drop policy if exists rsh_upd on rs_horse; drop policy if exists rsh_del on rs_horse;
create policy rsh_ins on rs_horse for insert with check ( is_school_teacher(stable_id) );
create policy rsh_upd on rs_horse for update using ( is_school_teacher(stable_id) );
create policy rsh_del on rs_horse for delete using ( is_school_teacher(stable_id) );

drop policy if exists rsg_ins on rs_group; drop policy if exists rsg_upd on rs_group; drop policy if exists rsg_del on rs_group;
create policy rsg_ins on rs_group for insert with check ( is_school_teacher(stable_id) );
create policy rsg_upd on rs_group for update using ( is_school_teacher(stable_id) );
create policy rsg_del on rs_group for delete using ( is_school_teacher(stable_id) );

drop policy if exists rsgs_ins on rs_group_student; drop policy if exists rsgs_del on rs_group_student;
create policy rsgs_ins on rs_group_student for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsgs_del on rs_group_student for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rsa_ins on rs_assignment; drop policy if exists rsa_upd on rs_assignment; drop policy if exists rsa_del on rs_assignment;
create policy rsa_ins on rs_assignment for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsa_upd on rs_assignment for update using ( is_school_teacher(group_school(group_id)) );
create policy rsa_del on rs_assignment for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rsab_ins on rs_absence; drop policy if exists rsab_del on rs_absence;
create policy rsab_ins on rs_absence for insert
  with check ( is_school_teacher(group_school(group_id)) or is_my_student(student_id) );
create policy rsab_del on rs_absence for delete
  using ( is_school_teacher(group_school(group_id)) or is_my_student(student_id) );

drop policy if exists rsln_ins on rs_lesson_note; drop policy if exists rsln_upd on rs_lesson_note; drop policy if exists rsln_del on rs_lesson_note;
create policy rsln_ins on rs_lesson_note for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsln_upd on rs_lesson_note for update using ( is_school_teacher(group_school(group_id)) );
create policy rsln_del on rs_lesson_note for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rsgh_ins on rs_group_horse; drop policy if exists rsgh_del on rs_group_horse;
create policy rsgh_ins on rs_group_horse for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsgh_del on rs_group_horse for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rsgf_ins on rs_group_staff; drop policy if exists rsgf_del on rs_group_staff;
create policy rsgf_ins on rs_group_staff for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsgf_del on rs_group_staff for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rsgi_ins on rs_group_instructor; drop policy if exists rsgi_del on rs_group_instructor;
create policy rsgi_ins on rs_group_instructor for insert with check ( is_school_teacher(group_school(group_id)) );
create policy rsgi_del on rs_group_instructor for delete using ( is_school_teacher(group_school(group_id)) );

drop policy if exists rshc_ins on rs_horse_category; drop policy if exists rshc_upd on rs_horse_category; drop policy if exists rshc_del on rs_horse_category;
create policy rshc_ins on rs_horse_category for insert with check ( is_school_teacher(stable_id) );
create policy rshc_upd on rs_horse_category for update using ( is_school_teacher(stable_id) );
create policy rshc_del on rs_horse_category for delete using ( is_school_teacher(stable_id) );

drop policy if exists rsec_ins on rs_student_category; drop policy if exists rsec_upd on rs_student_category; drop policy if exists rsec_del on rs_student_category;
create policy rsec_ins on rs_student_category for insert with check ( is_school_teacher(stable_id) );
create policy rsec_upd on rs_student_category for update using ( is_school_teacher(stable_id) );
create policy rsec_del on rs_student_category for delete using ( is_school_teacher(stable_id) );

drop policy if exists cat_write on category; drop policy if exists cat_update on category; drop policy if exists cat_delete on category;
create policy cat_write  on category for insert with check ( is_school_teacher(stable_id) );
create policy cat_update on category for update using ( is_school_teacher(stable_id) );
create policy cat_delete on category for delete using ( is_school_teacher(stable_id) );

-- ---------- Chef: arbetspass + bemanning ----------
drop policy if exists rst_ins on rs_task; drop policy if exists rst_upd on rs_task; drop policy if exists rst_del on rs_task;
create policy rst_ins on rs_task for insert with check ( is_school_chef(stable_id) );
create policy rst_upd on rs_task for update using ( is_school_chef(stable_id) );
create policy rst_del on rs_task for delete using ( is_school_chef(stable_id) );

drop policy if exists rstf_ins on rs_task_staff; drop policy if exists rstf_del on rs_task_staff;
create policy rstf_ins on rs_task_staff for insert with check ( is_school_chef(task_school(task_id)) );
create policy rstf_del on rs_task_staff for delete using ( is_school_chef(task_school(task_id)) );
