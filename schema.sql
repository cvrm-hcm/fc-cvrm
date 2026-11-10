-- =====================================================================
-- FC Sale CVRM HCM — Supabase schema v2 + Row Level Security
-- CÀI MỚI: chạy 1 lần trong Supabase → SQL Editor, sửa dòng INSERT admin ở cuối.
-- ĐANG CHẠY BẢN 1: dùng migration_v2.sql thay cho file này.
-- Quyền:
--   * Chỉ email có trong team_members mới đọc được dữ liệu.
--   * MR: nhập/sửa FC dòng của mình, đúng kỳ hiện tại, khi kỳ chưa khóa và FC chưa được duyệt;
--         nộp FC; đề xuất account/SKU mới cho chính mình.
--   * RFFM: xem tất cả, duyệt / trả lại FC.
--   * ADMIN: toàn quyền.
-- =====================================================================

create table if not exists public.team_members (
  email     text primary key,
  rep_name  text not null,
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
create or replace function public.is_reviewer() returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from team_members where lower(email) = my_email() and role in ('RFFM','ADMIN')) $$;
create or replace function public.my_rep() returns text
  language sql stable security definer set search_path = public as
  $$ select rep_name from team_members where lower(email) = my_email() limit 1 $$;

create table if not exists public.settings (
  id               int primary key default 1 check (id = 1),
  year             int not null,
  quarter          int not null check (quarter between 1 and 4),
  deadline         date,
  locked           boolean not null default false,
  team_filter      text not null default 'CVRM',
  exclude_keywords text not null default 'Vacant,New MR,Uncovered',
  data_as_of       date,
  fc_rule_pct      numeric not null default 0.5,
  fc_rule_min      numeric not null default 20000000
);
create or replace function public.current_period() returns text
  language sql stable security definer set search_path = public as
  $$ select year::text || 'Q' || quarter::text from settings where id = 1 $$;
create or replace function public.period_open() returns boolean
  language sql stable security definer set search_path = public as
  $$ select coalesce((select not locked from settings where id = 1), false) $$;

create table if not exists public.prices (
  sku   text primary key,
  brand text not null,
  price numeric not null
);

create table if not exists public.mapping (
  id            bigint generated always as identity primary key,
  rep_name      text not null,
  cust_code     text not null,
  cust_name     text,
  brand         text,
  sku           text not null,
  ratio         numeric not null default 1,
  channel       text,
  status        text not null default 'active' check (status in ('active','proposed')),
  proposed_by   text,
  proposed_note text,
  created_at    timestamptz not null default now(),
  unique (rep_name, cust_code, sku)
);
create index if not exists mapping_rep_idx on public.mapping (rep_name);

-- Sales tổng hợp theo tháng (khách × SKU × tháng) — app tự tổng hợp từ file export
create table if not exists public.sales_agg (
  cust_code text not null,
  sku       text not null,
  year      int  not null,
  month     int  not null check (month between 1 and 12),
  value     numeric not null,
  qty       numeric not null default 0,
  primary key (cust_code, sku, year, month)
);

create table if not exists public.accounts_seen (
  cust_code text not null,
  sku       text not null,
  cust_name text,
  rep_name  text,
  value     numeric,
  primary key (cust_code, sku)
);

create table if not exists public.targets (
  period    text not null,
  cust_code text not null,
  sku       text not null,
  value     numeric not null,
  primary key (period, cust_code, sku)
);

create table if not exists public.fc_entries (
  period     text   not null,
  mapping_id bigint not null references public.mapping(id) on delete cascade,
  m1 numeric check (m1 is null or m1 >= 0),
  m2 numeric check (m2 is null or m2 >= 0),
  m3 numeric check (m3 is null or m3 >= 0),
  note       text,
  reason     text,
  updated_by text not null default public.my_email(),
  updated_at timestamptz not null default now(),
  primary key (period, mapping_id)
);

create table if not exists public.fc_history (
  id         bigint generated always as identity primary key,
  period     text, mapping_id bigint,
  old_m1 numeric, old_m2 numeric, old_m3 numeric,
  new_m1 numeric, new_m2 numeric, new_m3 numeric,
  changed_by text default public.my_email(),
  changed_at timestamptz default now()
);

-- Bản FC đã chốt theo kỳ — dùng đo độ chính xác FC (không phụ thuộc phân bổ account hiện tại)
create table if not exists public.fc_archive (
  period     text not null,
  rep_name   text not null,
  cust_code  text not null,
  sku        text not null,
  ratio      numeric not null default 1,
  m1 numeric, m2 numeric, m3 numeric,
  value      numeric,
  created_at timestamptz not null default now(),
  primary key (period, rep_name, cust_code, sku)
);

create table if not exists public.submissions (
  period       text not null,
  rep_name     text not null,
  status       text not null default 'submitted' check (status in ('submitted','approved','returned')),
  submitted_at timestamptz not null default now(),
  submitted_by text not null default public.my_email(),
  reviewed_by  text,
  reviewed_at  timestamptz,
  review_note  text,
  primary key (period, rep_name)
);

create or replace function public.rep_approved(p text) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from submissions where period = p and rep_name = my_rep() and status = 'approved') $$;

-- ---------- Triggers ----------
create or replace function public.stamp_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin new.updated_by := my_email(); new.updated_at := now(); return new; end $$;
create or replace function public.log_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (old.m1, old.m2, old.m3) is not distinct from (new.m1, new.m2, new.m3) then return null; end if;
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

create or replace function public.stamp_submission() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' then
    new.submitted_at := now(); new.submitted_by := my_email();
    new.reviewed_by := null; new.reviewed_at := null; new.review_note := null;
  else
    new.reviewed_by := my_email(); new.reviewed_at := now();
    if tg_op = 'UPDATE' then new.submitted_at := old.submitted_at; new.submitted_by := old.submitted_by; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_stamp_sub on public.submissions;
create trigger trg_stamp_sub before insert or update on public.submissions for each row execute function public.stamp_submission();

create or replace function public.stamp_mapping() returns trigger
  language plpgsql security definer set search_path = public as $$
begin if new.status = 'proposed' and new.proposed_by is null then new.proposed_by := my_email(); end if; return new; end $$;
drop trigger if exists trg_stamp_mapping on public.mapping;
create trigger trg_stamp_mapping before insert on public.mapping for each row execute function public.stamp_mapping();

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['team_members','settings','prices','mapping','sales_agg','accounts_seen','targets','fc_entries','fc_history','fc_archive','submissions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "member read" on public.%I', t);
    execute format('create policy "member read" on public.%I for select to authenticated using (public.is_member())', t);
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

drop policy if exists "mr insert own fc" on public.fc_entries;
create policy "mr insert own fc" on public.fc_entries for insert to authenticated
  with check (
    period = public.current_period() and public.period_open() and not public.rep_approved(period)
    and exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep())
  );
drop policy if exists "mr update own fc" on public.fc_entries;
create policy "mr update own fc" on public.fc_entries for update to authenticated
  using (exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep()))
  with check (
    period = public.current_period() and public.period_open() and not public.rep_approved(period)
    and exists (select 1 from public.mapping m where m.id = mapping_id and m.rep_name = public.my_rep())
  );

drop policy if exists "mr submit own" on public.submissions;
create policy "mr submit own" on public.submissions for insert to authenticated
  with check (rep_name = public.my_rep() and period = public.current_period() and public.period_open() and status = 'submitted');
drop policy if exists "mr resubmit own" on public.submissions;
create policy "mr resubmit own" on public.submissions for update to authenticated
  using (rep_name = public.my_rep() and status <> 'approved')
  with check (rep_name = public.my_rep() and period = public.current_period() and public.period_open() and status = 'submitted');
drop policy if exists "reviewer review" on public.submissions;
create policy "reviewer review" on public.submissions for update to authenticated
  using (public.is_reviewer()) with check (public.is_reviewer());

drop policy if exists "mr propose mapping" on public.mapping;
create policy "mr propose mapping" on public.mapping for insert to authenticated
  with check (rep_name = public.my_rep() and status = 'proposed' and public.period_open());

-- =====================================================================
-- KHỞI TẠO — sửa email + tên của bạn rồi chạy
-- =====================================================================
insert into public.settings (id, year, quarter, deadline) values (1, 2026, 4, '2026-11-20')
  on conflict (id) do nothing;

-- Giá list/box: không ghi trong file này (repo có thể public).
-- Nạp ở app: Admin → Kỳ & nạp dữ liệu → 1. Bảng giá & SKU.

insert into public.team_members (email, rep_name, role)
  values ('email.cua.ban@bayer.com', 'Nguyen Thanh Kha', 'ADMIN')
on conflict (email) do update set role = 'ADMIN';

notify pgrst, 'reload schema';
