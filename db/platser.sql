-- ============================================================
--  EQUIWORKS – PLATSER FÖR LEKTIONER
--  T.ex. "Stora ridhuset", "Utebanan". Läggs upp fristående i
--  inställningarna eller väljs när lektionen skapas/redigeras.
--  Schemat varnar när lektioner överlappar i tid på samma plats
--  (eller när plats saknas). Kräver db/behorigheter.sql.
--  Säker att köra om. Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists rs_place (
  id          uuid primary key default gen_random_uuid(),
  stable_id   uuid not null references stable(id) on delete cascade,
  name        text not null,
  description text,
  sort_order  int  not null default 0
);
alter table rs_group add column if not exists place_id uuid references rs_place(id) on delete set null;

alter table rs_place enable row level security;
drop policy if exists rsp_sel on rs_place; drop policy if exists rsp_ins on rs_place;
drop policy if exists rsp_upd on rs_place; drop policy if exists rsp_del on rs_place;
create policy rsp_sel on rs_place for select using ( is_school_member(stable_id) );
create policy rsp_ins on rs_place for insert with check ( is_school_teacher(stable_id) );
create policy rsp_upd on rs_place for update using ( is_school_teacher(stable_id) );
create policy rsp_del on rs_place for delete using ( is_school_teacher(stable_id) );
