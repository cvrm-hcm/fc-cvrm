-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 4: MR CHỈ XEM SỐ CỦA MÌNH. Chạy 1 lần.
-- Supabase → SQL Editor → dán toàn bộ file này → Run. Chạy lại nhiều lần không sao.
-- Cần đang ở bản 3 (đã chạy schema.sql bản 3 hoặc migration_v3.sql).
-- Sau khi chạy:
--   * MR: chỉ đọc được account, sales, target, FC, trạng thái nộp của chính mình.
--   * RFFM, ADMIN: xem cả team như cũ.
--   * Không đổi dữ liệu, không cần nạp lại gì.
-- =====================================================================

-- 1. Hàm hỗ trợ
-- App đọc số này để biết database đã ở bản 4 chưa
create or replace function public.app_db_version() returns int
  language sql immutable as $$ select 4 $$;

-- Account × SKU này có target giao thẳng cho MR chưa (đọc cả team, không lộ số ra ngoài)
create or replace function public.target_has_rep(p text, c text, s text) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from targets where period = p and cust_code = c and sku = s and rep_name <> '') $$;

-- Mã + tên khách hàng (không kèm doanh số) cho form "Đề xuất account"
create or replace function public.customer_names() returns table (cust_code text, cust_name text)
  language sql stable security definer set search_path = public as $$
  select x.cust_code, max(x.cust_name) from (
    select a.cust_code, a.cust_name from accounts_seen a union all select m.cust_code, m.cust_name from mapping m) x
  where public.is_member() and coalesce(x.cust_name, '') <> ''
  group by x.cust_code order by x.cust_code $$;

grant execute on function public.app_db_version() to authenticated;
grant execute on function public.target_has_rep(text, text, text) to authenticated;
grant execute on function public.customer_names() to authenticated;

-- 2. Quyền đọc theo người dùng (thay cho "member read" = ai trong team cũng đọc được)
do $$
declare t text;
begin
  foreach t in array array['mapping','sales_agg','accounts_seen','targets','fc_entries','fc_history','fc_archive','submissions'] loop
    execute format('drop policy if exists "member read" on public.%I', t);
    execute format('drop policy if exists "scoped read" on public.%I', t);
  end loop;
end $$;

-- Danh sách account × SKU: dòng của mình
create policy "scoped read" on public.mapping for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));

-- FC: dòng của mình
create policy "scoped read" on public.fc_entries for select to authenticated
  using ((select public.is_reviewer())
    or exists (select 1 from public.mapping m where m.id = fc_entries.mapping_id and m.rep_name = (select public.my_rep())));

create policy "scoped read" on public.fc_history for select to authenticated
  using ((select public.is_reviewer())
    or exists (select 1 from public.mapping m where m.id = fc_history.mapping_id and m.rep_name = (select public.my_rep())));

-- Sales: chỉ account × SKU có trong danh sách của mình
create policy "scoped read" on public.sales_agg for select to authenticated
  using ((select public.is_reviewer())
    or exists (select 1 from public.mapping m where m.rep_name = (select public.my_rep()) and m.cust_code = sales_agg.cust_code and m.sku = sales_agg.sku));

-- Target: target giao cho mình; target cấp account (chia theo Sales ratio) chỉ khi account × SKU đó chưa giao thẳng cho MR nào
create policy "scoped read" on public.targets for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep())
    or (rep_name = ''
        and exists (select 1 from public.mapping m where m.rep_name = (select public.my_rep()) and m.cust_code = targets.cust_code and m.sku = targets.sku)
        and not public.target_has_rep(targets.period, targets.cust_code, targets.sku)));

-- Trạng thái nộp, bản FC đã chốt: của mình
create policy "scoped read" on public.submissions for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));
create policy "scoped read" on public.fc_archive for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));

-- Sales mới nhất theo account (dùng để tìm account thiếu): chỉ RFFM / admin
create policy "scoped read" on public.accounts_seen for select to authenticated
  using ((select public.is_reviewer()));

-- Giữ nguyên: team_members, settings, prices — ai trong team cũng đọc được (tên, vai trò, kỳ FC, bảng giá)

notify pgrst, 'reload schema';

-- Kiểm tra: 8 dòng "scoped read" + 3 dòng "member read" (prices, settings, team_members)
select tablename as "Bảng", policyname as "Quyền đọc" from pg_policies
where schemaname = 'public' and policyname in ('member read', 'scoped read') order by 2, 1;
