-- ============================================================
--  EQUIWORKS – ÄGARE + MEJLADRESSBYTE
--  1) Stallets skapare blir ÄGARE: bara ägaren kan ta bort andra
--     admins, och ingen kan ta bort ägaren. Vanliga admins kan
--     lämna själva. Befintliga stall med EN admin får den som
--     ägare automatiskt.
--  2) Mejladressbyte: användaren begär byte (request_email_change),
--     bekräftar via Supabase Auth-mejlen, och vid första inloggning
--     med nya adressen flyttar apply_email_change alla medlemskap.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

-- ---------- Ägare ----------
alter table org add column if not exists owner_email text;

-- nya stall: skaparen blir ägare
drop function if exists create_stable(text, text, text);
create or replace function create_stable(p_name text, p_kind text default 'stall', p_unit_name text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare oid uuid; uid uuid; k text; un text;
begin
  k := case when p_kind = 'ridskola' then 'ridskola' else 'stall' end;
  un := coalesce(nullif(trim(p_unit_name), ''), case when k = 'ridskola' then 'Ridskolan' else 'Jourschema' end);
  insert into org(name, owner_email) values (p_name, lower(auth.jwt() ->> 'email')) returning id into oid;
  insert into org_admin(org_id, email) values (oid, lower(auth.jwt() ->> 'email'));
  insert into stable(name, kind, org_id) values (un, k, oid) returning id into uid;
  return uid;
end $$;
grant execute on function create_stable(text, text, text) to anon, authenticated;

-- befintliga stall med exakt en admin: den blir ägare
update org o set owner_email = (select min(email) from org_admin a where a.org_id = o.id)
  where o.owner_email is null
    and (select count(*) from org_admin a where a.org_id = o.id) = 1;
-- (har ett stall flera admins redan: sätt ägaren manuellt, t.ex.
--  update org set owner_email = 'din@mejl.se' where name = 'RHC';)

create or replace function is_org_owner(oid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from org where id = oid
                 and owner_email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

-- Admin-borttagning: ägaren tar bort vem som helst (utom ägaren),
-- övriga admins kan bara ta bort sig själva. Ägarens rad är skyddad.
drop policy if exists oa_del on org_admin;
create policy oa_del on org_admin for delete using (
  (is_org_owner(org_id) or email = my_email())
  and email is distinct from (select owner_email from org o where o.id = org_id)
);

-- ---------- Mejladressbyte ----------
create table if not exists email_change (
  old_email  text primary key,
  new_email  text not null,
  created_at timestamptz not null default now()
);
alter table email_change enable row level security;   -- inga policies: nås bara via funktionerna nedan

create or replace function request_email_change(p_new text) returns void
language plpgsql security definer set search_path = public as $$
declare v_new text;
begin
  v_new := lower(trim(p_new));
  if v_new not like '%@%' then raise exception 'Ogiltig mejladress'; end if;
  if v_new = my_email() then raise exception 'Det är redan din adress'; end if;
  delete from email_change where old_email = my_email();
  insert into email_change (old_email, new_email) values (my_email(), v_new);
end $$;

create or replace function apply_email_change() returns boolean
language plpgsql security definer set search_path = public as $$
declare v email_change%rowtype;
begin
  select * into v from email_change where new_email = my_email();
  if v.old_email is null then return false; end if;

  -- dubbletter (nya adressen redan medlem på samma ställe) rensas före flytt
  delete from profile_member pm where pm.email = v.old_email
    and exists (select 1 from profile_member x where x.profile_id = pm.profile_id and x.email = v.new_email);
  update profile_member set email = v.new_email where email = v.old_email;

  delete from rs_staff_member m where m.email = v.old_email
    and exists (select 1 from rs_staff_member x where x.staff_id = m.staff_id and x.email = v.new_email);
  update rs_staff_member set email = v.new_email where email = v.old_email;

  delete from rs_student_member m where m.email = v.old_email
    and exists (select 1 from rs_student_member x where x.student_id = m.student_id and x.email = v.new_email);
  update rs_student_member set email = v.new_email where email = v.old_email;

  delete from rs_instructor_member m where m.email = v.old_email
    and exists (select 1 from rs_instructor_member x where x.instructor_id = m.instructor_id and x.email = v.new_email);
  update rs_instructor_member set email = v.new_email where email = v.old_email;

  delete from org_admin a where a.email = v.old_email
    and exists (select 1 from org_admin x where x.org_id = a.org_id and x.email = v.new_email);
  update org_admin set email = v.new_email where email = v.old_email;

  delete from invite i where i.email = v.old_email and (
      (i.profile_id is not null and exists (select 1 from invite x where x.profile_id = i.profile_id and x.email = v.new_email))
   or (i.profile_id is null and exists (select 1 from invite x where x.profile_id is null and x.stable_id = i.stable_id and x.kind = i.kind and x.email = v.new_email)));
  update invite set email = v.new_email where email = v.old_email;
  update invite set invited_by = v.new_email where invited_by = v.old_email;

  update org set owner_email = v.new_email where owner_email = v.old_email;
  update stable_admin set email = v.new_email where email = v.old_email;

  delete from email_change where old_email = v.old_email;
  return true;
end $$;
grant execute on function request_email_change(text) to authenticated;
grant execute on function apply_email_change() to authenticated;
