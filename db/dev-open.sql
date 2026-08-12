-- ============================================================
--  TILLFÄLLIGA UTVECKLINGSREGLER
--  Öppnar tabellerna så vi kan bygga och testa appen.
--  OBS: Detta är INTE säkert för skarp drift.
--  Ersätts med riktig säkerhet (en liten backend som håller den
--  hemliga nyckeln) innan appen används på riktigt.
-- ============================================================

alter table app_user       disable row level security;
alter table stable         disable row level security;
alter table stable_admin   disable row level security;
alter table duty_group     disable row level security;
alter table category       disable row level security;
alter table pass_def       disable row level security;
alter table profile        disable row level security;
alter table profile_member disable row level security;
alter table horse          disable row level security;
alter table booking        disable row level security;
