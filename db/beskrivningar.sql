-- Beskrivningsfält på grupper, elever, hästar, personal och kategorier.
-- Kör i Supabase SQL Editor. Säker att köra flera gånger.
alter table category          add column if not exists description text;
alter table rs_group          add column if not exists description text;
alter table rs_student        add column if not exists description text;
alter table rs_horse          add column if not exists description text;
alter table rs_staff          add column if not exists description text;
alter table rs_staff_category add column if not exists description text;
