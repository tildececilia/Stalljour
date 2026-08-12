-- ============================================================
--  STALLJOUR – databasstruktur (PostgreSQL / Supabase)
--  Motsvarar datamodellen: användare, stall, grupper,
--  kategorier, pass, profiler, hästar och bokningar.
--  Kör hela filen i Supabase → SQL Editor → RUN.
-- ============================================================

-- 1) ANVÄNDARE — inloggningsidentitet (telefonnumret är nyckeln)
create table if not exists app_user (
  id            uuid primary key default gen_random_uuid(),
  phone         text unique not null,
  display_name  text,
  created_at    timestamptz not null default now()
);

-- 2) STALL / SCHEMA — ett stall som t.ex. "RHC" eller "Grönadal"
create table if not exists stable (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  week_starts_on   int  not null default 1,   -- 1 = måndag
  rotation_offset  int  not null default 0,   -- förskjuter gruppernas turordning
  created_at       timestamptz not null default now()
);

-- 3) ADMINS — vilka användare som administrerar ett stall
create table if not exists stable_admin (
  stable_id  uuid not null references stable(id)   on delete cascade,
  user_id    uuid not null references app_user(id) on delete cascade,
  primary key (stable_id, user_id)
);

-- 4) GRUPPER — roterar veckoansvaret (sort_order = turordning)
create table if not exists duty_group (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  color       text,
  sort_order  int  not null default 0
);

-- 5) KATEGORIER — t.ex. Utsläpp och Fodringar (valfria)
create table if not exists category (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  sort_order  int  not null default 0
);

-- 6) PASS — mallen som upprepas varje vecka
create table if not exists pass_def (
  id           uuid primary key default gen_random_uuid(),
  stable_id    uuid not null references stable(id) on delete cascade,
  name         text not null,
  start_time   text,                      -- "07:00"
  category_id  uuid references category(id) on delete set null,
  capacity     int  not null default 1,   -- antal personer som behövs
  day_rule     text not null default 'all', -- 'all' | 'weekday' | 'weekend' | 'weekdays'
  weekdays     int[],                     -- vid 'weekdays': [1..7], mån=1
  sort_order   int  not null default 0
);

-- 7) PROFILER — en andel i stallet (personer som delar åtkomst)
create table if not exists profile (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

-- 8) PROFIL-MEDLEMMAR — vilka användare som får boka på en profil
create table if not exists profile_member (
  profile_id  uuid not null references profile(id)  on delete cascade,
  user_id     uuid not null references app_user(id) on delete cascade,
  primary key (profile_id, user_id)
);

-- 9) HÄSTAR — en häst = en andel, hör till en grupp
create table if not exists horse (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profile(id)    on delete cascade,
  name        text,
  group_id    uuid references duty_group(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- 10) BOKNINGAR — vem tog vilket pass, vilket datum
create table if not exists booking (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id)  on delete cascade,
  pass_id     uuid not null references pass_def(id) on delete cascade,
  pass_date   date not null,
  profile_id  uuid not null references profile(id)  on delete cascade,
  horse_id    uuid references horse(id)   on delete cascade,
  booked_by   uuid references app_user(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- Snabbare uppslag + hindra att samma häst dubbelbokas på samma pass-tillfälle
create index    if not exists booking_by_date on booking (stable_id, pass_date);
create unique index if not exists booking_unique_horse
  on booking (pass_id, pass_date, horse_id) where horse_id is not null;
