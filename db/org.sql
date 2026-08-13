-- ============================================================
--  STALLJOUR – STALL SOM ÖVERKATEGORI
--  Ett stall (org) kan innehålla flera jourscheman och flera
--  ridskolor (units = befintliga "stable"-rader).
--  Befintliga stall migreras automatiskt: varje gammalt stall
--  blir en org med sin gamla del under sig. Admins flyttas med.
--  Kör hela filen i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists org (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now()
);
alter table stable add column if not exists org_id uuid references org(id) on delete cascade;

create table if not exists org_admin (
  org_id uuid not null references org(id) on delete cascade,
  email  text not null,
  primary key (org_id, email)
);

-- ---------- Migrering av befintliga stall ----------
do $$
declare r record; oid uuid;
begin
  for r in select * from stable where org_id is null loop
    insert into org(name) values (r.name) returning id into oid;
    update stable set org_id = oid where id = r.id;
    insert into org_admin(org_id, email)
      select oid, email from stable_admin where stable_id = r.id
      on conflict do nothing;
  end loop;
end $$;

-- ---------- Behörighetsfunktioner ----------
create or replace function is_org_admin(oid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from org_admin
                 where org_id = oid and email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function is_org_member(oid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_org_admin(oid)
   or exists(select 1 from profile_member pm
             join profile p on p.id = pm.profile_id
             join stable st on st.id = p.stable_id
             where st.org_id = oid and pm.email = lower(coalesce(auth.jwt() ->> 'email','')))
   or exists(select 1 from rs_student_member sm
             join rs_student s on s.id = sm.student_id
             join stable st on st.id = s.stable_id
             where st.org_id = oid and sm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

-- Admin på en del = admin på stallet (org). Legacy stable_admin gäller också.
create or replace function is_stable_admin(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from stable st join org_admin oa on oa.org_id = st.org_id
                 where st.id = sid and oa.email = lower(coalesce(auth.jwt() ->> 'email','')))
   or exists(select 1 from stable_admin
             where stable_id = sid and email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

create or replace function am_i_admin(sid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_stable_admin(sid) $$;
grant execute on function am_i_admin(uuid) to anon, authenticated;

-- ---------- RLS för org-tabellerna ----------
alter table org       enable row level security;
alter table org_admin enable row level security;
drop policy if exists org_sel on org;
drop policy if exists org_upd on org;
create policy org_sel on org for select using ( is_org_member(id) );
create policy org_upd on org for update using ( is_org_admin(id) );
drop policy if exists oa_sel on org_admin;
drop policy if exists oa_ins on org_admin;
drop policy if exists oa_del on org_admin;
create policy oa_sel on org_admin for select using ( is_org_member(org_id) );
create policy oa_ins on org_admin for insert with check ( is_org_admin(org_id) );
create policy oa_del on org_admin for delete using ( is_org_admin(org_id) );

-- ---------- Skapa stall (org + första delen) ----------
drop function if exists create_stable(text, text);
create or replace function create_stable(p_name text, p_kind text default 'stall', p_unit_name text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare oid uuid; uid uuid; k text; un text;
begin
  k := case when p_kind = 'ridskola' then 'ridskola' else 'stall' end;
  un := coalesce(nullif(trim(p_unit_name), ''), case when k = 'ridskola' then 'Ridskolan' else 'Jourschema' end);
  insert into org(name) values (p_name) returning id into oid;
  insert into org_admin(org_id, email) values (oid, lower(auth.jwt() ->> 'email'));
  insert into stable(name, kind, org_id) values (un, k, oid) returning id into uid;
  return uid;
end $$;
grant execute on function create_stable(text, text, text) to anon, authenticated;

-- ---------- Skapa ny del i ett befintligt stall (bara admin) ----------
create or replace function create_unit(p_org uuid, p_name text, p_kind text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid; k text;
begin
  if not is_org_admin(p_org) then
    raise exception 'Bara admin kan skapa nya delar.';
  end if;
  k := case when p_kind = 'ridskola' then 'ridskola' else 'stall' end;
  insert into stable(name, kind, org_id)
    values (coalesce(nullif(trim(p_name), ''), case when k = 'ridskola' then 'Ridskolan' else 'Jourschema' end), k, p_org)
    returning id into uid;
  return uid;
end $$;
grant execute on function create_unit(uuid, text, text) to anon, authenticated;
