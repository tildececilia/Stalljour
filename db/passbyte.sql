-- ============================================================
--  EQUIWORKS – PASSBYTEN FÖR ARBETSPASS
--  Personal kan erbjuda bort ett arbetspass ett visst datum, eller
--  be om att få ta över någon annans. Kollegan svarar i notisklockan
--  och chef/admin godkänner bytet (om ingen av dem redan är chef).
--  Ett godkänt byte gäller bara det datumet — själva arbetspasset
--  (rs_task_staff) ändras inte.
--  Kräver db/arbetspass2.sql + db/behorigheter.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists rs_task_swap (
  id            uuid primary key default gen_random_uuid(),
  stable_id     uuid not null references stable(id)   on delete cascade,
  task_id       uuid not null references rs_task(id)  on delete cascade,
  work_date     date not null,
  giver_staff   uuid not null references rs_staff(id) on delete cascade,  -- lämnar passet
  taker_staff   uuid not null references rs_staff(id) on delete cascade,  -- tar passet
  asked_by      text not null default 'giver' check (asked_by in ('giver','taker')),
  asked_by_chef boolean not null default false,   -- frågan kom från chef/admin → inget extra godkännande
  note          text,
  status        text not null default 'pending' check (status in ('pending','accepted','declined')),
  chef_status   text not null default 'pending' check (chef_status in ('pending','approved','denied')),
  created_at    timestamptz not null default now(),
  answered_at   timestamptz,
  decided_at    timestamptz,
  decided_by    text,
  constraint rs_task_swap_two_people check (giver_staff <> taker_staff)
);

-- bara en väntande förfrågan per pass, datum och avlämnare
create unique index if not exists rs_task_swap_open
  on rs_task_swap (task_id, work_date, giver_staff) where status = 'pending';

-- Ett byte gäller (passet har flyttat) när status = 'accepted' och chef_status = 'approved'.

alter table rs_task_swap enable row level security;
drop policy if exists rsts_sel on rs_task_swap; drop policy if exists rsts_ins on rs_task_swap;
drop policy if exists rsts_upd on rs_task_swap; drop policy if exists rsts_del on rs_task_swap;
-- chef/admin ser allt, den som är inblandad ser sitt eget, godkända byten syns för alla i stallet
create policy rsts_sel on rs_task_swap for select
  using ( is_school_chef(stable_id) or is_my_staff(giver_staff) or is_my_staff(taker_staff)
          or (status = 'accepted' and chef_status = 'approved' and is_school_member(stable_id)) );
-- den som frågar måste vara sig själv (eller chef/admin som ordnar bytet)
create policy rsts_ins on rs_task_swap for insert
  with check ( is_school_chef(stable_id)
               or is_my_staff(case when asked_by = 'giver' then giver_staff else taker_staff end) );
-- svar och godkännande går via funktionerna nedan
create policy rsts_upd on rs_task_swap for update using ( is_school_chef(stable_id) );
create policy rsts_del on rs_task_swap for delete
  using ( is_school_chef(stable_id)
          or (status = 'pending'
              and is_my_staff(case when asked_by = 'giver' then giver_staff else taker_staff end)) );

-- Kom frågan från en chef/admin? Då behövs inget extra godkännande sedan.
create or replace function set_swap_asker_chef() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  NEW.asked_by_chef := is_school_chef(NEW.stable_id);
  return NEW;
end $$;

drop trigger if exists trg_swap_asker on rs_task_swap;
create trigger trg_swap_asker
  before insert on rs_task_swap
  for each row execute function set_swap_asker_chef();

-- ---------- Svara på en förfrågan (bara mottagaren) ----------
create or replace function respond_task_swap(p_swap uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare r rs_task_swap%rowtype; v_recipient uuid;
begin
  select * into r from rs_task_swap where id = p_swap and status = 'pending';
  if r.id is null then
    raise exception 'Förfrågan finns inte längre.';
  end if;
  v_recipient := case when r.asked_by = 'giver' then r.taker_staff else r.giver_staff end;
  if not is_my_staff(v_recipient) then
    raise exception 'Det här är inte din förfrågan.';
  end if;
  if not p_accept then
    update rs_task_swap set status = 'declined', answered_at = now() where id = r.id;
    return;
  end if;
  if r.work_date < current_date then
    raise exception 'Passet har redan varit.';
  end if;
  if not exists (select 1 from rs_task_staff where task_id = r.task_id and staff_id = r.giver_staff) then
    raise exception 'Personen står inte längre på arbetspasset.';
  end if;
  if exists (select 1 from rs_task_swap s
             where s.task_id = r.task_id and s.work_date = r.work_date
               and s.giver_staff = r.giver_staff and s.id <> r.id
               and s.status = 'accepted' and s.chef_status = 'approved') then
    raise exception 'Passet är redan bytt bort den dagen.';
  end if;
  if is_school_chef(r.stable_id) or r.asked_by_chef then
    -- chef inblandad redan → bytet gäller direkt
    update rs_task_swap set status = 'accepted', answered_at = now(),
           chef_status = 'approved', decided_at = now(), decided_by = my_email()
     where id = r.id;
  else
    update rs_task_swap set status = 'accepted', answered_at = now() where id = r.id;
  end if;
end $$;
grant execute on function respond_task_swap(uuid, boolean) to anon, authenticated;

-- ---------- Godkänn / neka bytet (chef eller admin) ----------
create or replace function approve_task_swap(p_swap uuid, p_approve boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare r rs_task_swap%rowtype;
begin
  select * into r from rs_task_swap
   where id = p_swap and status = 'accepted' and chef_status = 'pending';
  if r.id is null then
    raise exception 'Passbytet finns inte längre.';
  end if;
  if not is_school_chef(r.stable_id) then
    raise exception 'Bara chef och admin kan godkänna passbyten.';
  end if;
  update rs_task_swap
     set chef_status = case when p_approve then 'approved' else 'denied' end,
         decided_at = now(), decided_by = my_email()
   where id = r.id;
end $$;
grant execute on function approve_task_swap(uuid, boolean) to anon, authenticated;

-- ---------- Notiser i klockan ----------
--  Själva förfrågan och godkännandet visas som åtgärdskort (hämtas
--  direkt ur tabellen). Här skickas svarsnotiserna:
--    swap_declined  – kollegan tackade nej
--    swap_wait      – kollegan tackade ja, väntar på chefens godkännande
--    swap_approved  – bytet är godkänt (till båda)
--    swap_denied    – bytet nekades (till båda)
create or replace function notify_task_swap() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_msg text; v_task text; v_giver text; v_taker text; v_asker uuid;
begin
  select name into v_task  from rs_task  where id = NEW.task_id;
  select name into v_giver from rs_staff where id = NEW.giver_staff;
  select name into v_taker from rs_staff where id = NEW.taker_staff;
  v_msg := coalesce(v_task,'arbetspass') || ' ' || to_char(NEW.work_date,'FMDD/FMMM')
           || ' · ' || coalesce(v_giver,'?') || ' → ' || coalesce(v_taker,'?');
  v_asker := case when NEW.asked_by = 'giver' then NEW.giver_staff else NEW.taker_staff end;

  if NEW.status = 'declined' and OLD.status is distinct from NEW.status then
    insert into task_notice (stable_id, email, kind, task_name)
      select NEW.stable_id, fm.email, 'swap_declined', v_msg
        from rs_staff_member fm where fm.staff_id = v_asker;
  elsif NEW.status = 'accepted' and OLD.status is distinct from NEW.status
        and NEW.chef_status = 'pending' then
    insert into task_notice (stable_id, email, kind, task_name)
      select NEW.stable_id, fm.email, 'swap_wait', v_msg
        from rs_staff_member fm where fm.staff_id = v_asker;
  end if;

  if NEW.chef_status in ('approved','denied') and OLD.chef_status is distinct from NEW.chef_status then
    insert into task_notice (stable_id, email, kind, task_name)
      select NEW.stable_id, fm.email,
             case when NEW.chef_status = 'approved' then 'swap_approved' else 'swap_denied' end,
             v_msg
        from rs_staff_member fm
       where fm.staff_id in (NEW.giver_staff, NEW.taker_staff);
  end if;
  return NEW;
end $$;

drop trigger if exists trg_task_swap_notify on rs_task_swap;
create trigger trg_task_swap_notify
  after update on rs_task_swap
  for each row execute function notify_task_swap();
