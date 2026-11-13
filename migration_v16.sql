-- =====================================================================
-- FC Sale Team HCM · migration bản 16 (14/11/2026): chương trình trade chọn kênh áp dụng
-- promos.channels: danh sách kênh account (Tender / Self-pay / Clinic) được chạy chương trình; trống = mọi kênh.
-- Không đổi quyền. Chạy được nhiều lần.
-- =====================================================================
alter table public.promos add column if not exists channels text[];

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 16 $$;

notify pgrst, 'reload schema';

select public.app_db_version() as db_version;
