-- =====================================================================
-- FC Sale Team HCM · migration bản 12 (13/11/2026): FC giùm địa bàn chung
-- Account × SKU có từ 2 MR (ratio chia nhau): MR nào cũng nhập được số cả account, app chia cho từng MR theo ratio.
--  · MR đọc thêm mapping / FC / target / trạng thái submit của đồng nghiệp, CHỈ ở các account × SKU mình cũng phụ trách.
--  · MR ghi FC giùm đồng nghiệp ở các dòng đó khi kỳ còn mở và FC của đồng nghiệp chưa được duyệt.
--  · Địa bàn 1 mình: không đổi gì.
-- Chạy được nhiều lần.
-- =====================================================================

-- Các dòng mapping (mọi MR) ở account × SKU mà mình đang phụ trách
create index if not exists mapping_cust_sku_idx on public.mapping (cust_code, sku);
create or replace function public.my_shared_ids() returns setof bigint
  language sql stable security definer set search_path = public as $$
  select o.id from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active'
  where x.rep_name = my_rep() and x.status = 'active'
$$;

-- Đồng nghiệp cùng phụ trách ít nhất 1 account × SKU với mình
create or replace function public.my_co_reps() returns setof text
  language sql stable security definer set search_path = public as $$
  select distinct o.rep_name from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active' and o.rep_name <> x.rep_name
  where x.rep_name = my_rep() and x.status = 'active'
$$;

-- FC của MR giữ dòng mapping này đã được duyệt chưa
create or replace function public.mapping_rep_approved(mid bigint, p text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from mapping m join submissions s on s.rep_name = m.rep_name where m.id = mid and s.period = p and s.status = 'approved')
$$;

do $$
declare f text;
begin
  foreach f in array array['my_shared_ids()', 'my_co_reps()', 'mapping_rep_approved(bigint, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- Đọc
alter policy "scoped read" on public.mapping using (
  (select public.is_reviewer()) or rep_name = (select public.my_rep()) or id in (select public.my_shared_ids()));

alter policy "scoped read" on public.fc_entries using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep()))
  or mapping_id in (select public.my_shared_ids()));

alter policy "scoped read" on public.targets using (
  (select public.is_reviewer())
  or rep_name = (select public.my_rep())
  or (rep_name = '' and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()))
      and not public.target_has_rep(period, cust_code, sku))
  or (rep_name in (select public.my_co_reps())
      and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()) and m.status = 'active')));

alter policy "scoped read" on public.submissions using (
  (select public.is_reviewer()) or rep_name = (select public.my_rep()) or rep_name in (select public.my_co_reps()));

-- Ghi FC giùm ở địa bàn chung
drop policy if exists "mr insert shared fc" on public.fc_entries;
create policy "mr insert shared fc" on public.fc_entries for insert to authenticated
  with check (period = (select public.current_period()) and (select public.period_open())
    and mapping_id in (select public.my_shared_ids()) and not public.mapping_rep_approved(mapping_id, period));

drop policy if exists "mr update shared fc" on public.fc_entries;
create policy "mr update shared fc" on public.fc_entries for update to authenticated
  using (mapping_id in (select public.my_shared_ids()))
  with check (period = (select public.current_period()) and (select public.period_open())
    and mapping_id in (select public.my_shared_ids()) and not public.mapping_rep_approved(mapping_id, period));

-- App đọc số này để biết database đã ở bản nào
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 12 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 12
select public.app_db_version() as db_version;
