-- =====================================================================
-- FC Sale Team HCM · migration bản 15 (14/11/2026): chương trình trade (vd Mirena cận date giảm 20%)
-- - promos: admin khai báo SKU, tên chương trình, giá trade / box, từ ngày – đến ngày. Mọi thành viên đọc, admin ghi.
-- - fc_entries.t1..t3: trong số box FC tháng 1..3 của quý, bao nhiêu box là hàng trade (MR nhập từng account × SKU).
-- - sales_agg.qty_promo / value_promo: box và tiền bán giá trade (app tách khi nạp raw theo đơn giá ±2%).
-- Không đổi quyền cũ. Chạy được nhiều lần.
-- =====================================================================
create table if not exists public.promos (
  id          bigserial primary key,
  sku         text not null,
  name        text not null,
  base_price  numeric,            -- giá gốc dùng để tính % giảm (tham khảo)
  disc        numeric,            -- % giảm (0.2 = 20%), tham khảo
  price       numeric not null,   -- giá trade / box (dùng để tính FC tiền và nhận diện đơn trade trong raw)
  date_from   date not null,
  date_to     date not null,
  team        text,
  note        text,
  created_by  text,
  created_at  timestamptz not null default now(),
  check (date_to >= date_from)
);
alter table public.promos enable row level security;
drop policy if exists "member read" on public.promos;
drop policy if exists "admin write" on public.promos;
create policy "member read" on public.promos for select to authenticated using ((select public.is_member()));
create policy "admin write" on public.promos for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
grant select, insert, update, delete on public.promos to authenticated;
grant usage, select on sequence public.promos_id_seq to authenticated;

alter table public.fc_entries add column if not exists t1 numeric;
alter table public.fc_entries add column if not exists t2 numeric;
alter table public.fc_entries add column if not exists t3 numeric;

alter table public.sales_agg add column if not exists qty_promo numeric not null default 0;
alter table public.sales_agg add column if not exists value_promo numeric not null default 0;

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 15 $$;

notify pgrst, 'reload schema';

select public.app_db_version() as db_version;
