-- ============================================================
--  STALLJOUR – RIKTIG SÄKERHET (Row Level Security)
--  Ersätter de tillfälliga "öppna" utvecklingsreglerna.
--  Kör hela filen i Supabase → SQL Editor → Run.
--
--  Modellen:
--   · Medlem i ett stall = din inloggade mejl finns som admin
--     eller på en profil i stallet.
--   · Medlemmar kan LÄSA allt i sitt stall.
--   · Admin kan ÄNDRA allt i sitt stall.
--   · Vanliga medlemmar kan boka/avboka pass för sina profiler
--     och hantera hästarna på sina egna profiler.
--   · Utomstående (även med app-nyckeln) kommer inte åt något.
-- ============================================================

-- ---------- Hjälpfunktioner (security definer = kringgår RLS internt) ----------
create or replace function my_email() returns text
language sql stable as
$$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

create or replace function is_stable_admin(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from stable_admin
                 where stable_id = sid and email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function is_stable_member(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid) or exists(
     select 1 from profile_member pm
     join profile p on p.id = pm.profile_id
     where p.stable_id = sid
       and pm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function is_profile_member(pid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from profile_member
                 where profile_id = pid and email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function profile_stable(pid uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select stable_id from profile where id = pid $$;

-- ---------- Slå på RLS på alla tabeller ----------
alter table stable         enable row level security;
alter table stable_admin   enable row level security;
alter table duty_group     enable row level security;
alter table category       enable row level security;
alter table pass_def       enable row level security;
alter table profile        enable row level security;
alter table profile_member enable row level security;
alter table horse          enable row level security;
alter table booking        enable row level security;

-- Rensa ev. gamla policies (så filen kan köras om)
drop policy if exists stable_select  on stable;
drop policy if exists stable_update  on stable;
drop policy if exists stable_delete  on stable;
drop policy if exists sa_select      on stable_admin;
drop policy if exists sa_insert      on stable_admin;
drop policy if exists sa_delete      on stable_admin;
drop policy if exists dg_select      on duty_group;
drop policy if exists dg_write       on duty_group;
drop policy if exists dg_update      on duty_group;
drop policy if exists dg_delete      on duty_group;
drop policy if exists cat_select     on category;
drop policy if exists cat_write      on category;
drop policy if exists cat_update     on category;
drop policy if exists cat_delete     on category;
drop policy if exists pd_select      on pass_def;
drop policy if exists pd_write       on pass_def;
drop policy if exists pd_update      on pass_def;
drop policy if exists pd_delete      on pass_def;
drop policy if exists prof_select    on profile;
drop policy if exists prof_insert    on profile;
drop policy if exists prof_update    on profile;
drop policy if exists prof_delete    on profile;
drop policy if exists pm_select      on profile_member;
drop policy if exists pm_insert      on profile_member;
drop policy if exists pm_delete      on profile_member;
drop policy if exists horse_select   on horse;
drop policy if exists horse_insert   on horse;
drop policy if exists horse_update   on horse;
drop policy if exists horse_delete   on horse;
drop policy if exists bk_select      on booking;
drop policy if exists bk_insert      on booking;
drop policy if exists bk_delete      on booking;

-- ---------- STALL ----------
create policy stable_select on stable for select using ( is_stable_member(id) );
create policy stable_update on stable for update using ( is_stable_admin(id) );
create policy stable_delete on stable for delete using ( is_stable_admin(id) );
-- insert sker via create_stable() (security definer) – ingen direkt insert-policy behövs

-- ---------- ADMINS ----------
create policy sa_select on stable_admin for select
  using ( email = my_email() or is_stable_member(stable_id) );
create policy sa_insert on stable_admin for insert
  with check ( is_stable_admin(stable_id) );
create policy sa_delete on stable_admin for delete
  using ( is_stable_admin(stable_id) );

-- ---------- GRUPPER ----------
create policy dg_select on duty_group for select using ( is_stable_member(stable_id) );
create policy dg_write  on duty_group for insert with check ( is_stable_admin(stable_id) );
create policy dg_update on duty_group for update using ( is_stable_admin(stable_id) );
create policy dg_delete on duty_group for delete using ( is_stable_admin(stable_id) );

-- ---------- KATEGORIER ----------
create policy cat_select on category for select using ( is_stable_member(stable_id) );
create policy cat_write  on category for insert with check ( is_stable_admin(stable_id) );
create policy cat_update on category for update using ( is_stable_admin(stable_id) );
create policy cat_delete on category for delete using ( is_stable_admin(stable_id) );

-- ---------- PASS ----------
create policy pd_select on pass_def for select using ( is_stable_member(stable_id) );
create policy pd_write  on pass_def for insert with check ( is_stable_admin(stable_id) );
create policy pd_update on pass_def for update using ( is_stable_admin(stable_id) );
create policy pd_delete on pass_def for delete using ( is_stable_admin(stable_id) );

-- ---------- PROFILER ----------
create policy prof_select on profile for select using ( is_stable_member(stable_id) );
create policy prof_insert on profile for insert with check ( is_stable_admin(stable_id) );
create policy prof_update on profile for update
  using ( is_stable_admin(stable_id) or is_profile_member(id) );  -- medlem får ändra sin egen profils namn
create policy prof_delete on profile for delete using ( is_stable_admin(stable_id) );

-- ---------- PROFIL-MEJL ----------
create policy pm_select on profile_member for select
  using ( email = my_email() or is_stable_member(profile_stable(profile_id)) );
create policy pm_insert on profile_member for insert
  with check ( is_stable_admin(profile_stable(profile_id)) or is_profile_member(profile_id) );
create policy pm_delete on profile_member for delete
  using ( is_stable_admin(profile_stable(profile_id)) or is_profile_member(profile_id) );

-- ---------- HÄSTAR (medlem får hantera sina egna profilers hästar) ----------
create policy horse_select on horse for select
  using ( is_stable_member(profile_stable(profile_id)) );
create policy horse_insert on horse for insert
  with check ( is_stable_admin(profile_stable(profile_id)) or is_profile_member(profile_id) );
create policy horse_update on horse for update
  using ( is_stable_admin(profile_stable(profile_id)) or is_profile_member(profile_id) );
create policy horse_delete on horse for delete
  using ( is_stable_admin(profile_stable(profile_id)) or is_profile_member(profile_id) );

-- ---------- BOKNINGAR ----------
create policy bk_select on booking for select using ( is_stable_member(stable_id) );
create policy bk_insert on booking for insert
  with check ( is_stable_admin(stable_id) or (is_stable_member(stable_id) and is_profile_member(profile_id)) );
create policy bk_delete on booking for delete
  using ( is_stable_admin(stable_id) or is_profile_member(profile_id) );
