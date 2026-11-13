-- =====================================================================
-- FC Sale Team HCM · migration bản 11 (13/11/2026): tăng tốc RLS khi cả team cùng vào
-- Không đổi quyền: ai đọc / ghi được gì vẫn y như bản 10, chỉ đổi cách Postgres tính.
--  · is_admin() / is_member() / my_rep() / current_period() / period_open() bọc trong (select …)
--    → tính 1 lần cho mỗi truy vấn thay vì 1 lần cho mỗi dòng.
--  · Kiểm tra "dòng của MR" dùng IN (danh sách mapping của MR) thay cho EXISTS từng dòng.
-- Load test 20 MR cùng đăng nhập: thời gian đọc sales_agg / mapping / fc_entries của 1 MR giảm nhiều lần.
-- Chạy được nhiều lần.
-- =====================================================================

-- 1. Policy "admin write" (FOR ALL nên cũng tham gia mọi lần đọc)
do $$
declare t text;
begin
  foreach t in array array['accounts_seen', 'cust_merge', 'customers', 'fc_archive', 'fc_entries', 'fc_history', 'mapping', 'prices', 'sales_agg',
                           'settings', 'submissions', 'targets', 'team_members', 'teams', 'tender_upcoming', 'tenders'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'admin write') then
      execute format('alter policy "admin write" on public.%I using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    end if;
  end loop;
  foreach t in array array['cust_merge', 'customers', 'prices', 'settings', 'team_members', 'teams'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'member read') then
      execute format('alter policy "member read" on public.%I using ((select public.is_member()))', t);
    end if;
  end loop;
end $$;

-- 2. Đọc theo phạm vi MR
alter policy "scoped read" on public.sales_agg using (
  (select public.is_reviewer())
  or (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.fc_entries using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.fc_history using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.targets using (
  (select public.is_reviewer())
  or rep_name = (select public.my_rep())
  or (rep_name = '' and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()))
      and not public.target_has_rep(period, cust_code, sku)));

alter policy "scoped read" on public.tenders using (
  (select public.is_reviewer())
  or cust_code in (select m.cust_code from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.tender_upcoming using (
  (select public.is_reviewer())
  or cust_code in (select m.cust_code from public.mapping m where m.rep_name = (select public.my_rep())));

-- 3. MR ghi FC của mình (nút "Điền theo TB 2Q" lưu cả trăm dòng 1 lần)
alter policy "mr insert own fc" on public.fc_entries with check (
  period = (select public.current_period()) and (select public.period_open()) and not public.rep_approved(period)
  and mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "mr update own fc" on public.fc_entries
  using (mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())))
  with check (period = (select public.current_period()) and (select public.period_open()) and not public.rep_approved(period)
    and mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "reviewer review" on public.submissions using ((select public.is_reviewer())) with check ((select public.is_reviewer()));

-- App đọc số này để biết database đã ở bản nào
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 11 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 11
select public.app_db_version() as db_version;
