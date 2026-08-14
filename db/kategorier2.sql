-- ============================================================
--  STALLJOUR – KATEGORIER FÖR HÄSTAR OCH ELEVER (ridskola)
--  T.ex. hästar: "Hopphäst", "Nybörjarvänlig"; elever kan också
--  kategoriseras. Används för att välja kategori först när man
--  lägger till på lektioner. Kräver db/ridskola.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists rs_horse_category (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  description text,
  sort_order  int  not null default 0
);
create table if not exists rs_student_category (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  description text,
  sort_order  int  not null default 0
);
alter table rs_horse   add column if not exists category_id uuid references rs_horse_category(id)   on delete set null;
alter table rs_student add column if not exists category_id uuid references rs_student_category(id) on delete set null;

alter table rs_horse_category   enable row level security;
alter table rs_student_category enable row level security;

drop policy if exists rshc_sel on rs_horse_category; drop policy if exists rshc_ins on rs_horse_category;
drop policy if exists rshc_upd on rs_horse_category; drop policy if exists rshc_del on rs_horse_category;
create policy rshc_sel on rs_horse_category for select using ( is_school_member(stable_id) );
create policy rshc_ins on rs_horse_category for insert with check ( is_stable_admin(stable_id) );
create policy rshc_upd on rs_horse_category for update using ( is_stable_admin(stable_id) );
create policy rshc_del on rs_horse_category for delete using ( is_stable_admin(stable_id) );

drop policy if exists rsec_sel on rs_student_category; drop policy if exists rsec_ins on rs_student_category;
drop policy if exists rsec_upd on rs_student_category; drop policy if exists rsec_del on rs_student_category;
create policy rsec_sel on rs_student_category for select using ( is_school_member(stable_id) );
create policy rsec_ins on rs_student_category for insert with check ( is_stable_admin(stable_id) );
create policy rsec_upd on rs_student_category for update using ( is_stable_admin(stable_id) );
create policy rsec_del on rs_student_category for delete using ( is_stable_admin(stable_id) );
