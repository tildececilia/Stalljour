-- ============================================================
--  EQUIWORKS – INBJUDNINGAR (jourstall)
--  När en mejladress läggs på en profil skapas en inbjudan.
--  Den inbjudna ser den i notisklockan efter inloggning och kan
--  acceptera eller avböja — och ångra ett avböjande senare via
--  Mina förfrågningar. Kräver db/org.sql (my_email, is_stable_admin).
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists invite (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id)  on delete cascade,
  profile_id   uuid not null references profile(id) on delete cascade,
  email        text not null,
  invited_by   text not null,
  status       text not null default 'pending',   -- pending | accepted | declined
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  unique (profile_id, email)
);

alter table invite enable row level security;

drop policy if exists inv_sel on invite; drop policy if exists inv_ins on invite;
drop policy if exists inv_upd on invite; drop policy if exists inv_del on invite;
create policy inv_sel on invite for select using ( email = my_email() or is_stable_admin(stable_id) );
create policy inv_ins on invite for insert with check ( is_stable_admin(stable_id) );
create policy inv_upd on invite for update using ( email = my_email() or is_stable_admin(stable_id) );
create policy inv_del on invite for delete using ( is_stable_admin(stable_id) );
