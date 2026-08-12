-- ============================================================
--  STALLJOUR – byt medlemskap från telefon till mejl
--  (Supabase Auth med engångskod). Kör hela filen i SQL Editor.
--  OBS: gamla telefon-baserade kopplingar tas bort – profiler,
--  hästar, grupper, pass och bokningar påverkas INTE.
-- ============================================================

-- Ta bort gamla telefon-baserade tabeller/kopplingar
drop table if exists profile_member cascade;
drop table if exists stable_admin cascade;
drop table if exists app_user cascade;

-- Medlemskap via mejl
create table stable_admin (
  stable_id uuid not null references stable(id) on delete cascade,
  email text not null,
  primary key (stable_id, email)
);
create table profile_member (
  profile_id uuid not null references profile(id) on delete cascade,
  email text not null,
  primary key (profile_id, email)
);

-- booked_by pekar nu på Supabase-användarens id
alter table booking drop column if exists booked_by;
alter table booking add column booked_by uuid;

-- Skapa stall + gör den som skapar till admin (fungerar även när säkerheten är på)
create or replace function create_stable(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  insert into stable(name) values (p_name) returning id into new_id;
  insert into stable_admin(stable_id, email)
    values (new_id, lower(auth.jwt() ->> 'email'));
  return new_id;
end;
$$;
grant execute on function create_stable(text) to anon, authenticated;

-- ------------------------------------------------------------
--  GÖR DIG TILL ADMIN FÖR DITT BEFINTLIGA STALL (RHC):
--  Byt ut mejladressen mot din egen och kör den här raden också.
-- ------------------------------------------------------------
-- insert into stable_admin(stable_id, email)
--   select id, lower('DIN-MEJL@exempel.se') from stable where name = 'RHC'
--   on conflict do nothing;
