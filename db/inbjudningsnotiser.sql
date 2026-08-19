-- ============================================================
--  EQUIWORKS – NOTIS NÄR NÅGON SVARAR PÅ EN INBJUDAN
--  Den som skickade inbjudan får en notis i klockan när den
--  accepteras eller avböjs (databastrigger på invite-tabellen).
--  Själva loggen är invite-tabellen — visas under "Skickade
--  inbjudningar" på startsidan. Kräver db/arbetspass2.sql
--  (task_notice) + db/inbjudningar2.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create or replace function notify_invite_response() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_msg text; v_roll text;
begin
  if NEW.status in ('accepted','declined') and OLD.status is distinct from NEW.status then
    v_roll := case
      when NEW.kind = 'admin' then 'admin'
      when NEW.kind = 'staff' and NEW.staff_perm = 'teacher' then 'ridlärare'
      when NEW.kind = 'staff' then 'stallpersonal'
      else 'medlem' end;
    v_msg := coalesce(nullif(NEW.invite_name,''), NEW.email) || ' (' || v_roll || ') — '
             || coalesce((select name from stable where id = NEW.stable_id), 'stallet');
    insert into task_notice (stable_id, email, kind, task_name)
      values (NEW.stable_id, NEW.invited_by,
              case when NEW.status = 'accepted' then 'inv_accepted' else 'inv_declined' end,
              v_msg);
  end if;
  return NEW;
end $$;

drop trigger if exists trg_invite_response on invite;
create trigger trg_invite_response
  after update on invite
  for each row execute function notify_invite_response();
