-- =====================================================================
-- FC Sale Team HCM · migration_v9 (bản 4.13): giá / box theo kênh
--   * prices.price_tender / price_selfpay / price_clinic: giá riêng từng kênh, để trống = prices.price (Giá chung).
--   * Kênh giá của account: Tender (Khoa Dược BV công) · Self-pay (NTBV, BV tư, NT phòng khám mua trực tiếp) ·
--     Clinic (phòng khám, phòng mạch mua qua sub-dis). App tự lấy theo Customer Local Group trong raw.
--   * Chạy 1 lần trong Supabase → SQL Editor. Không đổi quyền: ai trong team cũng đọc bảng giá, chỉ ADMIN ghi.
-- =====================================================================

alter table public.prices add column if not exists price_tender  numeric;
alter table public.prices add column if not exists price_selfpay numeric;
alter table public.prices add column if not exists price_clinic  numeric;

-- App đọc số này để biết database đã ở bản 9 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 9 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 9, số SKU có giá kênh riêng
select public.app_db_version() as db_version,
       (select count(*) from public.prices where coalesce(price_tender, price_selfpay, price_clinic) is not null) as sku_gia_kenh;
