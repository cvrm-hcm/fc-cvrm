-- =====================================================================
-- FC Sale Team HCM · migration bản 12.1 (13/11/2026): tăng tốc quyền địa bàn chung, KHÔNG đổi quyền
-- my_co_reps() 30 ms → 2 ms, my_shared_ids() 3 ms → 1.5 ms mỗi lần tải (join thẳng theo account × SKU thay vì IN danh sách).
-- Chạy được nhiều lần.
-- =====================================================================
create index if not exists mapping_cust_sku_idx on public.mapping (cust_code, sku);

create or replace function public.my_shared_ids() returns setof bigint
  language sql stable security definer set search_path = public as $$
  select o.id from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active'
  where x.rep_name = my_rep() and x.status = 'active'
$$;

create or replace function public.my_co_reps() returns setof text
  language sql stable security definer set search_path = public as $$
  select distinct o.rep_name from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active' and o.rep_name <> x.rep_name
  where x.rep_name = my_rep() and x.status = 'active'
$$;

notify pgrst, 'reload schema';
