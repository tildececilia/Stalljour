-- ============================================================
--  STALLJOUR – BYT PASS: förfrågningar + notiser
--  Kör hela filen i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists pass_request (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id)  on delete cascade,
  booking_id   uuid not null references booking(id) on delete cascade,
  type         text not null check (type in ('give','take')),  -- ge bort / ta över
  from_profile uuid not null references profile(id) on delete cascade,  -- den som frågar
  to_profile   uuid not null references profile(id) on delete cascade,  -- den som får notisen
  status       text not null default 'pending',   -- pending | accepted | declined
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);

alter table pass_request enable row level security;
drop policy if exists pr_select on pass_request;
drop policy if exists pr_insert on pass_request;
create policy pr_select on pass_request for select using ( is_stable_member(stable_id) );
create policy pr_insert on pass_request for insert
  with check ( is_stable_member(stable_id) and is_profile_member(from_profile) );

-- Svara på en förfrågan (bara mottagaren). Vid "ja" flyttas bokningen.
create or replace function resolve_pass_request(p_request uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare r pass_request%rowtype;
begin
  select * into r from pass_request where id = p_request and status = 'pending';
  if r.id is null then
    raise exception 'Förfrågan finns inte längre.';
  end if;
  if not exists (select 1 from profile_member
                 where profile_id = r.to_profile
                   and email = lower(coalesce(auth.jwt() ->> 'email',''))) then
    raise exception 'Det här är inte din förfrågan.';
  end if;
  if p_accept then
    if not exists (select 1 from booking where id = r.booking_id) then
      raise exception 'Passet finns inte längre.';
    end if;
    if r.type = 'give' then
      update booking set profile_id = r.to_profile   where id = r.booking_id;
    else
      update booking set profile_id = r.from_profile where id = r.booking_id;
    end if;
    update pass_request set status = 'accepted', resolved_at = now() where id = r.id;
    -- avböj automatiskt andra väntande förfrågningar på samma bokning
    update pass_request set status = 'declined', resolved_at = now()
      where booking_id = r.booking_id and status = 'pending' and id <> r.id;
  else
    update pass_request set status = 'declined', resolved_at = now() where id = r.id;
  end if;
end $$;
grant execute on function resolve_pass_request(uuid, boolean) to anon, authenticated;
