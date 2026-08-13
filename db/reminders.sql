-- ============================================================
--  STALLJOUR – PÅMINNELSER: två valbara påminnelser per profil
--  (minuter innan passet: 60 = 1 timme, 1440 = 1 dag, 2880 = 2 dagar)
--  Kör i Supabase → SQL Editor → Run.
-- ============================================================

alter table profile add column if not exists remind1_min int;
alter table profile add column if not exists remind2_min int;
