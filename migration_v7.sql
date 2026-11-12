-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 7: NEW LAUNCH. Chạy 1 lần.
-- Supabase → SQL Editor → dán toàn bộ file này → Run. Chạy lại nhiều lần không sao.
-- Cần đang ở bản 6 (migration_v6.sql).
-- Sau khi chạy:
--   * prices.launch: đánh dấu SKU new launch (chưa có target, vd Firialta, Qlaira).
--     FC của SKU này nhập riêng ở FC Input → New launch, không tính vào target / %Ach / risk.
--   * mapping.segment: kênh của account cho New launch: gov (BV công) · priv (BV tư) · clinic (phòng khám).
--   * Bảng customers: danh mục khách hàng lấy từ raw sales (tên, kênh tự phân loại theo
--     Customer Local Group 3 Desc / Channel_name). Ai trong team cũng đọc được (không có doanh số).
--   * MR tự thêm BV / phòng khám, đổi kênh, xoá account New launch của chính mình khi kỳ FC còn mở.
-- =====================================================================

-- 1. Cột mới
alter table public.prices  add column if not exists launch  boolean not null default false;
alter table public.mapping add column if not exists segment text;
alter table public.mapping drop constraint if exists mapping_segment_check;
alter table public.mapping add constraint mapping_segment_check check (segment is null or segment in ('gov', 'priv', 'clinic'));

-- 2. Danh mục khách hàng (admin ghi mỗi lần nạp raw sales)
create table if not exists public.customers (
  cust_code  text primary key,
  cust_name  text,
  segment    text check (segment is null or segment in ('gov', 'priv', 'clinic')),
  channel    text,          -- Channel_name trong raw: Hospital, Sub-dis clinics, Pharmacy, Wholesales
  cust_group text,          -- Customer Local Group 2 Desc: Khoa Dược, NTBV, Clinic Pharmacy…
  sector     text,          -- Customer Local Group 3 Desc: GOV'T. ENTITIES / Private entities
  updated_at timestamptz not null default now()
);
alter table public.customers enable row level security;
drop policy if exists "member read" on public.customers;
drop policy if exists "admin write" on public.customers;
create policy "member read" on public.customers for select to authenticated using (public.is_member());
create policy "admin write" on public.customers for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 3. SKU new launch?
create or replace function public.is_launch_sku(s text) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from prices where sku = s and launch) $$;
revoke execute on function public.is_launch_sku(text) from public, anon;
grant execute on function public.is_launch_sku(text) to authenticated;

-- 4. MR: thêm / sửa kênh / xoá account New launch của mình (kỳ còn mở, chưa được duyệt).
--    SKU có target vẫn đi qua "Đề xuất account" (status = proposed, admin duyệt) như cũ.
drop policy if exists "mr add launch mapping" on public.mapping;
create policy "mr add launch mapping" on public.mapping for insert to authenticated
  with check (rep_name = public.my_rep() and status = 'active' and public.period_open()
              and not public.rep_approved(public.current_period()) and public.is_launch_sku(sku));
drop policy if exists "mr edit launch mapping" on public.mapping;
create policy "mr edit launch mapping" on public.mapping for update to authenticated
  using (rep_name = public.my_rep() and public.is_launch_sku(sku))
  with check (rep_name = public.my_rep() and status = 'active' and public.period_open()
              and not public.rep_approved(public.current_period()) and public.is_launch_sku(sku));
drop policy if exists "mr remove launch mapping" on public.mapping;
create policy "mr remove launch mapping" on public.mapping for delete to authenticated
  using (rep_name = public.my_rep() and public.is_launch_sku(sku) and public.period_open()
         and not public.rep_approved(public.current_period()));

-- App đọc số này để biết database đã ở bản 7 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 7 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 7, SKU new launch, số khách hàng trong danh mục
select public.app_db_version() as db_version,
       (select coalesce(string_agg(sku, ', '), '(chưa có)') from public.prices where launch) as launch_skus,
       (select count(*) from public.customers) as customers;
