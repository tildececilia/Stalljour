-- ============================================================
--  EQUIWORKS – SJUKNOTISER TILL CHEF OCH ADMIN
--  När personal sjukanmäler sig (eller ångrar) på ett arbetspass
--  får stallets admins och chefer en notis i klockan automatiskt
--  (databastrigger — fungerar oavsett varifrån anmälan görs).
--  Kräver db/arbetspass2.sql. Säker att köra om.
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

create or replace function notify_task_absence() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_stable uuid; v_org uuid; v_name text; v_task text; v_msg text; v_kind text;
  v_date date; v_staff uuid; v_task_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_kind := 'sick'; v_date := NEW.work_date; v_staff := NEW.staff_id; v_task_id := NEW.task_id;
  else
    v_kind := 'sick_removed'; v_date := OLD.work_date; v_staff := OLD.staff_id; v_task_id := OLD.task_id;
  end if;
  select f.name, f.stable_id into v_name, v_stable from rs_staff f where f.id = v_staff;
  if v_stable is null then return coalesce(NEW, OLD); end if;
  select t.name into v_task from rs_task t where t.id = v_task_id;
  select org_id into v_org from stable where id = v_stable;
  v_msg := coalesce(v_name,'Personal') || ' — ' || coalesce(v_task,'arbetspass') || ' ' || to_char(v_date, 'FMDD/FMMM');
  insert into task_notice (stable_id, email, kind, task_name)
    select v_stable, e.email, v_kind, v_msg from (
      select oa.email from org_admin oa where oa.org_id = v_org
      union
      select fm.email from rs_staff_member fm join rs_staff f2 on f2.id = fm.staff_id
        where f2.stable_id = v_stable and f2.perm = 'chef'
    ) e
    where e.email not in (select fm2.email from rs_staff_member fm2 where fm2.staff_id = v_staff);
  return coalesce(NEW, OLD);
end $$;

drop trigger if exists trg_task_absence_notify on rs_task_absence;
create trigger trg_task_absence_notify
  after insert or delete on rs_task_absence
  for each row execute function notify_task_absence();
