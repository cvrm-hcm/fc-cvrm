-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 8: MERGE CODE. Chạy 1 lần.
-- Supabase → SQL Editor → dán toàn bộ file này → Run. Chạy lại nhiều lần không sao.
-- Cần đang ở bản 7 (migration_v7.sql).
-- Sau khi chạy:
--   * Bảng cust_merge: mã KH → merge code (account Bayer). Bayer giao target theo account: mã Khoa Dược / BHYT
--     của BV là merge code, mã NTBV / dịch vụ / mã trùng gộp vào (theo cách merge của Commex).
--   * App tính target, %Ach, cảnh báo theo merge code; FC vẫn nhập theo từng mã.
--   * Ai trong team cũng đọc được (không có doanh số); chỉ ADMIN ghi (nạp file ở Admin → Kỳ & nạp dữ liệu).
-- =====================================================================

create table if not exists public.cust_merge (
  cust_code  text primary key,
  merge_code text not null,
  merge_name text,
  source     text,          -- Commex / Claude (suy luận) / File
  note       text,
  updated_at timestamptz not null default now()
);
create index if not exists cust_merge_merge_code_idx on public.cust_merge (merge_code);
alter table public.cust_merge enable row level security;
drop policy if exists "member read" on public.cust_merge;
drop policy if exists "admin write" on public.cust_merge;
create policy "member read" on public.cust_merge for select to authenticated using (public.is_member());
create policy "admin write" on public.cust_merge for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.cust_merge to authenticated;

-- App đọc số này để biết database đã ở bản 8 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 8 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 8, số merge code / số mã
select public.app_db_version() as db_version,
       (select count(distinct merge_code) from public.cust_merge) as merge_codes,
       (select count(*) from public.cust_merge) as codes;
