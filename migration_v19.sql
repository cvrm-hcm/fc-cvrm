-- migration_v19.sql — Rà soát raw sales: đơn trùng / nghi trùng (bản app 4.33)
-- Admin nạp raw → app tìm dòng lặp lại y hệt (cùng số đơn, lô, SL, tiền, MR) và đơn nghi nhảy 2 lần
-- (cùng MR × khách × SKU × SL × tiền, ≥ 2 số đơn khác nhau cùng ngày hoặc hôm sau, không có dòng trả hàng bù lại).
-- MR chỉ thấy cảnh báo của mình; RFFM / admin thấy cả team. MR / RFFM / admin ghi được trạng thái kiểm tra + Note.

create table if not exists public.sales_dups (
  sig text primary key,                 -- chữ ký ổn định: team|MR|khách|SKU|ngày|SL|tiền|các số đơn
  team text not null default 'CVRM',
  rep_name text not null,
  cust_code text, cust_name text, sku text,
  kind text not null check (kind in ('dup', 'sus')),   -- dup: dòng lặp y hệt / cùng số hoá đơn; sus: nghi trùng đơn
  inv_date date, qty numeric, value numeric, n int, extra_value numeric,
  orders text, gov text,
  status text not null default 'open' check (status in ('open', 'real', 'fixed')),   -- open: chưa kiểm tra · real: 2 đơn thật · fixed: đã báo sửa raw
  note text, by_email text, checked_at timestamptz,
  found_at timestamptz not null default now()
);
create index if not exists sales_dups_rep on public.sales_dups (rep_name);

alter table public.sales_dups enable row level security;
drop policy if exists "admin write" on public.sales_dups;
drop policy if exists "scoped read" on public.sales_dups;
drop policy if exists "check own dup" on public.sales_dups;
create policy "admin write" on public.sales_dups for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "scoped read" on public.sales_dups for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));
-- MR (dòng của mình) và RFFM ghi trạng thái kiểm tra
create policy "check own dup" on public.sales_dups for update to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()))
  with check ((select public.is_reviewer()) or rep_name = (select public.my_rep()));
grant select, insert, update, delete on public.sales_dups to authenticated;

-- MR / RFFM chỉ được đổi trạng thái, Note, người kiểm tra (không sửa số)
create or replace function public.sales_dups_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if not public.is_admin() then
    new.sig := old.sig; new.team := old.team; new.rep_name := old.rep_name; new.cust_code := old.cust_code; new.cust_name := old.cust_name;
    new.sku := old.sku; new.kind := old.kind; new.inv_date := old.inv_date; new.qty := old.qty; new.value := old.value; new.n := old.n;
    new.extra_value := old.extra_value; new.orders := old.orders; new.gov := old.gov; new.found_at := old.found_at;
  end if;
  if new.status is distinct from old.status or new.note is distinct from old.note then
    new.by_email := public.my_email(); new.checked_at := now();   -- người / giờ kiểm tra
  end if;
  return new;
end $$;
drop trigger if exists trg_sales_dups_guard on public.sales_dups;
create trigger trg_sales_dups_guard before update on public.sales_dups for each row execute function public.sales_dups_guard();

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 19 $$;

notify pgrst, 'reload schema';

select public.app_db_version() as db_version;
