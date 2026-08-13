-- ============================================================
--  STALLJOUR – GRUPPCHATT
--  En chatt per grupp. Ordinarie medlem = har häst i gruppen.
--  Ordinarie kan bjuda in/ta bort profiler från samma stall.
--  Kör hela filen i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists chat_member (          -- inbjudna utöver ordinarie
  group_id   uuid not null references duty_group(id) on delete cascade,
  profile_id uuid not null references profile(id)    on delete cascade,
  added_by   uuid references profile(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (group_id, profile_id)
);

create table if not exists chat_message (
  id         uuid primary key default gen_random_uuid(),
  stable_id  uuid not null references stable(id)     on delete cascade,
  group_id   uuid not null references duty_group(id) on delete cascade,
  profile_id uuid not null references profile(id)    on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists chat_msg_idx on chat_message (group_id, created_at);

-- Ordinarie medlem i gruppens chatt = min mejl sitter på en profil med häst i gruppen
create or replace function is_group_regular(gid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(
     select 1 from profile_member pm
     join horse h on h.profile_id = pm.profile_id
     where h.group_id = gid
       and pm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

-- Chattmedlem = ordinarie ELLER inbjuden
create or replace function is_chat_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select is_group_regular(gid) or exists(
     select 1 from chat_member cm
     join profile_member pm on pm.profile_id = cm.profile_id
     where cm.group_id = gid
       and pm.email = lower(coalesce(auth.jwt() ->> 'email',''))) $$;

alter table chat_member  enable row level security;
alter table chat_message enable row level security;

drop policy if exists cmem_select on chat_member;
drop policy if exists cmem_insert on chat_member;
drop policy if exists cmem_delete on chat_member;
create policy cmem_select on chat_member for select using ( is_chat_member(group_id) );
create policy cmem_insert on chat_member for insert with check ( is_group_regular(group_id) );
create policy cmem_delete on chat_member for delete
  using ( is_group_regular(group_id) or is_profile_member(profile_id) );  -- inbjuden får lämna själv

drop policy if exists cmsg_select on chat_message;
drop policy if exists cmsg_insert on chat_message;
create policy cmsg_select on chat_message for select using ( is_chat_member(group_id) );
create policy cmsg_insert on chat_message for insert
  with check ( is_chat_member(group_id) and is_profile_member(profile_id) );
