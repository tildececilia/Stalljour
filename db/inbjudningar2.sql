-- ============================================================
--  EQUIWORKS – INBJUDNINGAR MED ROLL (stallpersonal/ridlärare/admin)
--  "Bjud in"-dialogen under Profil skapar en inbjudan med roll.
--  Rollen delas ut FÖRST när personen accepterar (via RPC:n
--  respond_invite som körs med förhöjda rättigheter).
--  Kräver db/inbjudningar.sql + db/behorigheter.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

alter table invite alter column profile_id drop not null;
alter table invite add column if not exists kind        text not null default 'profile';  -- profile | staff | admin
alter table invite add column if not exists staff_perm  text;                             -- none | teacher (för kind=staff)
alter table invite add column if not exists invite_name text;                             -- personens namn (för personalposten)

-- en aktiv rollinbjudan per stall+mejl+typ
create unique index if not exists invite_school_uq on invite (stable_id, email, kind) where profile_id is null;

drop function if exists respond_invite(uuid, boolean);
create or replace function respond_invite(p_invite uuid, p_accept boolean, p_name text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v invite%rowtype;
  v_org uuid;
  v_staff uuid;
begin
  select * into v from invite where id = p_invite;
  if v.id is null or v.email <> my_email() then
    raise exception 'Inbjudan hittades inte';
  end if;
  update invite set status = case when p_accept then 'accepted' else 'declined' end,
                    responded_at = now()
    where id = p_invite;
  if not p_accept then return; end if;

  if v.kind = 'admin' then
    select org_id into v_org from stable where id = v.stable_id;
    if v_org is not null
       and not exists (select 1 from org_admin where org_id = v_org and email = v.email) then
      insert into org_admin (org_id, email) values (v_org, v.email);
    end if;
  elsif v.kind = 'staff' then
    if not exists (select 1 from rs_staff_member fm join rs_staff f on f.id = fm.staff_id
                   where f.stable_id = v.stable_id and fm.email = v.email) then
      insert into rs_staff (stable_id, name, perm)
        values (v.stable_id,
                coalesce(nullif(p_name,''), nullif(v.invite_name,''), split_part(v.email,'@',1)),
                coalesce(v.staff_perm,'none'))
        returning id into v_staff;
      insert into rs_staff_member (staff_id, email) values (v_staff, v.email);
    end if;
  end if;
end $$;
