-- =====================================================================
-- FC Sale Team HCM · migration_v10 (bản 4.14): Tender quota
--   * tenders: gói thầu theo mã KH × SKU từ file Tender Data (admin nạp, thay toàn bộ mỗi lần).
--   * tender_upcoming: ◇ quota dự kiến team nhập (thầu mới, MSBS 30%, gia hạn) chưa có trong file.
--   * Quyền: RFFM / admin đọc hết; MR đọc gói thầu và quota dự kiến của mã KH có trong danh sách của mình.
--     MR thêm / sửa / xoá quota dự kiến của mình (đứng tên mình, mã KH của mình, trạng thái "expected"); admin toàn quyền.
--   * Chạy 1 lần trong Supabase → SQL Editor.
-- =====================================================================

create table if not exists public.tenders (
  id          bigint generated always as identity primary key,
  cust_code   text not null,
  cust_name   text,
  sku         text not null,
  quota       numeric not null,
  start_date  date,
  end_date    date,
  remaining   numeric,
  run_rate    numeric,
  as_of       date,
  team        text not null default 'CVRM',
  created_at  timestamptz not null default now()
);
create index if not exists tenders_code_sku_idx on public.tenders (cust_code, sku);

create table if not exists public.tender_upcoming (
  id          bigint generated always as identity primary key,
  cust_code   text not null,
  cust_name   text,
  sku         text not null,
  qty         numeric not null check (qty > 0),
  eff_month   date not null,
  kind        text,
  note        text,
  rep_name    text,
  team        text not null default 'CVRM',
  status      text not null default 'expected' check (status in ('expected', 'confirmed')),
  created_by  text default public.my_email(),
  created_at  timestamptz not null default now(),
  updated_by  text,
  updated_at  timestamptz not null default now()
);
create index if not exists tender_upcoming_code_sku_idx on public.tender_upcoming (cust_code, sku);

create or replace function public.stamp_tender_upcoming() returns trigger
  language plpgsql security definer set search_path = public as $$
begin new.updated_by := my_email(); new.updated_at := now(); if tg_op = 'INSERT' then new.created_by := my_email(); end if; return new; end $$;
drop trigger if exists trg_stamp_tender_upcoming on public.tender_upcoming;
create trigger trg_stamp_tender_upcoming before insert or update on public.tender_upcoming for each row execute function public.stamp_tender_upcoming();

-- Mã KH có trong danh sách của MR đang đăng nhập
create or replace function public.my_code(c text) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from mapping m where m.cust_code = c and m.rep_name = my_rep()) $$;

alter table public.tenders enable row level security;
alter table public.tender_upcoming enable row level security;
drop policy if exists "admin write" on public.tenders;
drop policy if exists "scoped read" on public.tenders;
drop policy if exists "admin write" on public.tender_upcoming;
drop policy if exists "scoped read" on public.tender_upcoming;
drop policy if exists "mr add upcoming" on public.tender_upcoming;
drop policy if exists "mr edit upcoming" on public.tender_upcoming;
drop policy if exists "mr remove upcoming" on public.tender_upcoming;

create policy "admin write" on public.tenders for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "scoped read" on public.tenders for select to authenticated
  using ((select public.is_reviewer()) or public.my_code(cust_code));

create policy "admin write" on public.tender_upcoming for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "scoped read" on public.tender_upcoming for select to authenticated
  using ((select public.is_reviewer()) or public.my_code(cust_code));
create policy "mr add upcoming" on public.tender_upcoming for insert to authenticated
  with check (rep_name = public.my_rep() and status = 'expected' and public.my_code(cust_code));
create policy "mr edit upcoming" on public.tender_upcoming for update to authenticated
  using (rep_name = public.my_rep() and status = 'expected')
  with check (rep_name = public.my_rep() and status = 'expected' and public.my_code(cust_code));
create policy "mr remove upcoming" on public.tender_upcoming for delete to authenticated
  using (rep_name = public.my_rep() and status = 'expected');

grant select, insert, update, delete on public.tenders, public.tender_upcoming to authenticated;
revoke execute on function public.my_code(text) from public, anon;
grant execute on function public.my_code(text) to authenticated;

-- App đọc số này để biết database đã ở bản 10 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 10 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 10, số gói thầu, số quota dự kiến
select public.app_db_version() as db_version,
       (select count(*) from public.tenders) as tenders,
       (select count(*) from public.tender_upcoming) as upcoming;
