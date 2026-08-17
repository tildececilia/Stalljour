-- ============================================================
--  EQUIWORKS – PLANERING PER LEKTIONSTILLFÄLLE
--  En anteckning per lektion och datum ("vad gör vi idag"),
--  skrivs i schemats detaljpanel. Skiljer sig från lektionens
--  fasta beskrivning. Kräver db/ridskola.sql. Säker att köra om.
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

create table if not exists rs_lesson_note (
  group_id    uuid not null references rs_group(id) on delete cascade,
  lesson_date date not null,
  note        text,
  primary key (group_id, lesson_date)
);

alter table rs_lesson_note enable row level security;

drop policy if exists rsln_sel on rs_lesson_note; drop policy if exists rsln_ins on rs_lesson_note;
drop policy if exists rsln_upd on rs_lesson_note; drop policy if exists rsln_del on rs_lesson_note;
create policy rsln_sel on rs_lesson_note for select using ( is_school_member(group_school(group_id)) );
create policy rsln_ins on rs_lesson_note for insert with check ( is_stable_admin(group_school(group_id)) );
create policy rsln_upd on rs_lesson_note for update using ( is_stable_admin(group_school(group_id)) );
create policy rsln_del on rs_lesson_note for delete using ( is_stable_admin(group_school(group_id)) );
