-- =====================================================================
-- FC Sale CVRM HCM — Supabase schema + Row Level Security
-- Chạy 1 lần trong Supabase → SQL Editor. Sau đó sửa dòng INSERT admin ở cuối.
-- Nguyên tắc quyền:
--   * Chỉ email có trong team_members mới đọc được dữ liệu.
--   * MR chỉ thêm/sửa FC của các dòng account được gán cho mình, khi kỳ chưa khóa.
--   * ADMIN toàn quyền (nạp raw sales, target, phân bổ account, thành viên, khóa kỳ).
--   * RFFM xem tất cả, không sửa.
-- =====================================================================

-- ---------- Thành viên ----------
create table if not exists public.team_members (
  email     text primary key,
  rep_name  text not null,                -- phải trùng REP Name trong danh sách account
  role      text not null default 'MR' check (role in ('MR','RFFM','ADMIN'))
);

create or replace function public.my_email() returns text
  language sql stable as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;

create or replace function public.is_member() returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from team_members where lower(email) = my_email()) $$;

create or replace function public.is_admin() returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from team_members where lower(email) = my_email() and role = 'ADMIN') $$;

create or replace function public.my_rep() returns text
  language sql stable security definer set search_path = public as
  $$ select rep_name from team_members where lower(email) = my_email() limit 1 $$;

-- ---------- Cấu hình kỳ ----------
create table if not exists public.settings (
  id               int primary key default 1 check (id = 1),
  year             int not null,
  quarter          int not null check (quarter between 1 and 4),
  deadline         date,
  locked           boolean not null default false,
  team_filter      text not null default 'CVRM',
  exclude_keywords text not null default 'Vacant,New MR,Uncovered'
);

create or replace function public.current_period() returns text
  language sql stable security definer set search_path = public as
  $$ select year::text || 'Q' || quarter::text from settings where id = 1 $$;

create or replace function public.period_open() returns boolean
  language sql stable security definer set search_path = public as
  $$ select coalesce((select not locked from settings where id = 1), false) $$;

-- ---------- Giá ----------
create table if not exists public.prices (
  sku   text primary key,
  brand text not null,
  price numeric not null
);

-- ---------- Phân bổ account × SKU × MR ----------
create table if not exists public.mapping (
  id         bigint generated always as identity primary key,
  rep_name   text not null,
  cust_code  text not null,
  cust_name  text,
  brand      text,
  sku        text not null,
  ratio      numeric not null default 1,
  channel    text,
  created_at timestamptz not null default now(),
  unique (rep_name, cust_code, sku)
);
create index if not exists mapping_rep_idx on public.mapping (rep_name);

-- ---------- Sales tổng hợp (khách × SKU × quý) — app tự tổng hợp từ file export ----------
create table if not exists public.sales_agg (
  cust_code text not null,
  sku       text not null,
  year      int  not null,
  quarter   int  not null,
  value     numeric not null,
  primary key (cust_code, sku, year, quarter)
);

-- Account có sales + đã gán MR (để báo account chưa có trên FC)
create table if not exists public.accounts_seen (
  cust_code text not null,
  sku       text not null,
  cust_name text,
  rep_name  text,
  value     numeric,
  primary key (cust_code, sku)
);

-- ---------- Target theo kỳ ----------
create table if not exists public.targets (
  period    text not null,
  cust_code text not null,
  sku       text not null,
  value     numeric not null,
  primary key (period, cust_code, sku)
);

-- ---------- FC MR nhập ----------
create table if not exists public.fc_entries (
  period     text   not null,
  mapping_id bigint not null references public.mapping(id) on delete cascade,
  m1 numeric check (m1 is null or m1 >= 0),
  m2 numeric check (m2 is null or m2 >= 0),
  m3 numeric check (m3 is null or m3 >= 0),
  note       text,
  updated_by text not null default public.my_email(),
  updated_at timestamptz not null default now(),
  primary key (period, mapping_id)
);

-- Lịch sử thay đổi FC (ai sửa, lúc nào, số cũ → mới)
create table if not exists public.fc_history (
  id         bigint generated always as identity primary key,
  period     text, mapping_id bigint,
  old_m1 numeric, old_m2 numeric, old_m3 numeric,
  new_m1 numeric, new_m2 numeric, new_m3 numeric,
  changed_by text default public.my_email(),
  changed_at timestamptz default now()
);
create or replace function public.stamp_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  new.updated_by := my_email(); new.updated_at := now(); return new;
end $$;
create or replace function public.log_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (old.m1, old.m2, old.m3) is not distinct from (new.m1, new.m2, new.m3) then
    return null;
  end if;
  insert into fc_history(period, mapping_id, old_m1, old_m2, old_m3, new_m1, new_m2, new_m3)
  values (new.period, new.mapping_id,
          case when tg_op = 'UPDATE' then old.m1 end, case when tg_op = 'UPDATE' then old.m2 end, case when tg_op = 'UPDATE' then old.m3 end,
          new.m1, new.m2, new.m3);
  return null;
end $$;
drop trigger if exists trg_stamp_fc on public.fc_entries;
create trigger trg_stamp_fc before insert or update on public.fc_entries for each row execute function public.stamp_fc();
drop trigger if exists trg_log_fc on public.fc_entries;
create trigger trg_log_fc after insert or update on public.fc_entries for each row execute function public.log_fc();

-- ---------- Nộp FC ----------
create table if not exists public.submissions (
  period       text not null,
  rep_name     text not null,
  submitted_at timestamptz not null default now(),
  submitted_by text not null default public.my_email(),
  primary key (period, rep_name)
);

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
alter table public.team_members  enable row level security;
alter table public.settings      enable row level security;
alter table public.prices        enable row level security;
alter table public.mapping       enable row level security;
alter table public.sales_agg     enable row level security;
alter table public.accounts_seen enable row level security;
alter table public.targets       enable row level security;
alter table public.fc_entries    enable row level security;
alter table public.fc_history    enable row level security;
alter table public.submissions   enable row level security;

do $$
declare t text;
begin
  foreach t in array array['team_members','settings','prices','mapping','sales_agg','accounts_seen','targets','fc_entries','fc_history','submissions'] loop
    execute format('drop policy if exists "member read" on public.%I', t);
    execute format('create policy "member read" on public.%I for select to authenticated using (public.is_member())', t);
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- MR: thêm / sửa FC dòng của mình, đúng kỳ hiện tại, khi kỳ chưa khóa
drop policy if exists "mr insert own fc" on public.fc_entries;
create policy "mr insert own fc" on public.fc_entries for insert to authenticated
  with check (
    period = public.current_period() and public.period_open()
    and exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep())
  );
drop policy if exists "mr update own fc" on public.fc_entries;
create policy "mr update own fc" on public.fc_entries for update to authenticated
  using (exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep()))
  with check (
    period = public.current_period() and public.period_open()
    and exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep())
  );

-- MR: nộp FC của mình
drop policy if exists "mr submit own" on public.submissions;
create policy "mr submit own" on public.submissions for insert to authenticated
  with check (rep_name = public.my_rep() and period = public.current_period() and public.period_open());
drop policy if exists "mr resubmit own" on public.submissions;
create policy "mr resubmit own" on public.submissions for update to authenticated
  using (rep_name = public.my_rep())
  with check (rep_name = public.my_rep() and period = public.current_period() and public.period_open());

-- =====================================================================
-- KHỞI TẠO — sửa email + tên của bạn rồi chạy
-- =====================================================================
insert into public.settings (id, year, quarter, deadline) values (1, 2026, 4, '2026-11-20')
  on conflict (id) do nothing;

-- Giá list/box: không ghi trong file này (repo có thể public).
-- App tự lấy giá từ sheet Setup khi admin nạp file FC_Sale_CVRM_HCM_v2.xlsx, hoặc nhập tay ở tab Admin → Thành viên & giá.

insert into public.team_members (email, rep_name, role)
  values ('email.cua.ban@bayer.com', 'Nguyen Thanh Kha', 'ADMIN')
on conflict (email) do update set role = 'ADMIN';
