-- =====================================================================
-- FC Sale Team HCM · migration bản 17 (15/11/2026), app 4.23
--  · poa_inputs: số MR tự điền ở thẻ FC POA (best case, sell-out, tồn kho, ghi chú, account phân tích full)
--  · app_assets: file mẫu PowerPoint POA, chỉ thành viên đăng nhập đọc được (không để file mẫu trong repo public)
--  · MR gỡ được dòng đề xuất (status proposed) của mình khi điền nhầm, kỳ còn mở
--  · sales_agg.last_date: ngày hoá đơn cuối trong tháng (nạp raw từ bản này trở đi)
--  · recent_orders(code): đơn gần nhất của account chưa ai phụ trách (Tra cứu địa bàn)
-- Chạy được nhiều lần.
-- =====================================================================

-- 1. FC POA: 1 dòng / MR / kỳ, dữ liệu dạng jsonb
create table if not exists public.poa_inputs (
  period    text not null,
  rep_name  text not null,
  data      jsonb not null default '{}'::jsonb,
  at        timestamptz not null default now(),
  by_email  text,
  primary key (period, rep_name)
);
create or replace function public.stamp_poa() returns trigger
  language plpgsql security definer set search_path = public as $$
begin new.at := now(); new.by_email := my_email(); return new; end $$;
drop trigger if exists trg_stamp_poa on public.poa_inputs;
create trigger trg_stamp_poa before insert or update on public.poa_inputs for each row execute function public.stamp_poa();

alter table public.poa_inputs enable row level security;
drop policy if exists "admin write" on public.poa_inputs;
drop policy if exists "scoped read" on public.poa_inputs;
drop policy if exists "mr write own poa" on public.poa_inputs;
create policy "admin write" on public.poa_inputs for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "scoped read" on public.poa_inputs for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));
create policy "mr write own poa" on public.poa_inputs for all to authenticated
  using (rep_name = (select public.my_rep()))
  with check (rep_name = (select public.my_rep()) and period = (select public.current_period()));
grant select, insert, update, delete on public.poa_inputs to authenticated;

-- 2. File mẫu (base64, chia nhiều phần)
create table if not exists public.app_assets (
  name  text not null,
  part  int  not null default 0,
  b64   text not null,
  primary key (name, part)
);
alter table public.app_assets enable row level security;
drop policy if exists "member read" on public.app_assets;
drop policy if exists "admin write" on public.app_assets;
create policy "member read" on public.app_assets for select to authenticated using ((select public.is_member()));
create policy "admin write" on public.app_assets for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
grant select on public.app_assets to authenticated;
grant insert, update, delete on public.app_assets to authenticated;

-- 3. MR gỡ dòng đề xuất của mình (điền nhầm). Dòng New launch đã có policy "mr remove launch mapping" (bản 7).
drop policy if exists "mr remove own proposed" on public.mapping;
create policy "mr remove own proposed" on public.mapping for delete to authenticated
  using (rep_name = (select public.my_rep()) and status = 'proposed' and (select public.period_open()));

-- 4. Ngày hoá đơn cuối trong tháng
alter table public.sales_agg add column if not exists last_date date;

-- 5. Đơn gần nhất của account (cả nhóm merge code). MR chỉ xem được khi account chưa ai phụ trách; RFFM / admin xem mọi account.
create or replace function public.recent_orders(code text)
returns table (cust_code text, cust_name text, sku text, year int, month int, qty numeric, value numeric, last_date date)
language sql stable security definer set search_path = public as $$
  with root as (select coalesce((select m.merge_code from cust_merge m where m.cust_code = code limit 1), code) as rc),
  grp as (select code as c union select rc from root union select m.cust_code from cust_merge m, root where m.merge_code = root.rc),
  owned as (select 1 from mapping mp where mp.cust_code in (select c from grp) and (mp.ratio > 0 or mp.status = 'proposed') limit 1)
  select s.cust_code, cu.cust_name, s.sku, s.year, s.month, s.qty, s.value, s.last_date
  from sales_agg s left join customers cu on cu.cust_code = s.cust_code
  where s.cust_code in (select c from grp) and public.is_member()
    and (public.is_reviewer() or not exists (select 1 from owned))
  order by s.year desc, s.month desc, s.last_date desc nulls last, s.value desc
  limit 60
$$;
revoke execute on function public.recent_orders(text) from public, anon;
grant execute on function public.recent_orders(text) to authenticated;

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 17 $$;

notify pgrst, 'reload schema';

select public.app_db_version() as db_version;
