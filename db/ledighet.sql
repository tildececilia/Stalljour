-- ============================================================
--  EQUIWORKS – LEDIGHETSANSÖKAN FÖR PERSONAL
--  Personal ansöker om ledighet (semester/ledighet/vab) för ett
--  datumintervall. Chef och admin får notis och beviljar/avslår
--  i notisklockan. Beviljad ledighet visas i arbetspass-schemat
--  ("ledig"-markering + varning). Kräver db/arbetspass2.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists rs_leave (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id)  on delete cascade,
  staff_id     uuid not null references rs_staff(id) on delete cascade,
  kind         text not null default 'semester',    -- semester | ledighet | vab
  start_date   date not null,
  end_date     date not null,
  note         text,
  status       text not null default 'pending',     -- pending | approved | denied
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  responded_by text
);

alter table rs_leave enable row level security;
drop policy if exists rsl2_sel on rs_leave; drop policy if exists rsl2_ins on rs_leave;
drop policy if exists rsl2_upd on rs_leave; drop policy if exists rsl2_del on rs_leave;
create policy rsl2_sel on rs_leave for select
  using ( is_school_chef(stable_id) or is_my_staff(staff_id)
          or (status = 'approved' and is_school_member(stable_id)) );
create policy rsl2_ins on rs_leave for insert
  with check ( is_my_staff(staff_id) or is_school_chef(stable_id) );
create policy rsl2_upd on rs_leave for update using ( is_school_chef(stable_id) );
create policy rsl2_del on rs_leave for delete
  using ( is_school_chef(stable_id) or (is_my_staff(staff_id) and status = 'pending') );

-- Notis till den ansökande när chef/admin svarar (själva ansökan syns
-- som åtgärdskort med Bevilja/Avslå i chefens/adminens klocka)
create or replace function notify_leave() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_msg text;
begin
  if NEW.status in ('approved','denied') and OLD.status is distinct from NEW.status then
    v_msg := NEW.kind || ' ' || to_char(NEW.start_date,'FMDD/FMMM') || '–' || to_char(NEW.end_date,'FMDD/FMMM');
    insert into task_notice (stable_id, email, kind, task_name)
      select NEW.stable_id, fm.email,
             case when NEW.status = 'approved' then 'leave_approved' else 'leave_denied' end, v_msg
      from rs_staff_member fm where fm.staff_id = NEW.staff_id;
  end if;
  return NEW;
end $$;

drop trigger if exists trg_leave_notify on rs_leave;
create trigger trg_leave_notify
  after update on rs_leave
  for each row execute function notify_leave();
