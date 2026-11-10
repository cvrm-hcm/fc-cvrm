-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 2 (chạy 1 lần)
-- Supabase → SQL Editor → dán toàn bộ file này → Run.
-- Giữ nguyên: thành viên, giá, danh sách account, target, FC đã nhập, trạng thái nộp.
-- Làm lại sau khi chạy: nạp lại RAW SALES (bản 2 lưu sales theo tháng + số box).
-- Chạy lại nhiều lần không sao.
-- =====================================================================

-- 1. Cột mới
alter table public.settings    add column if not exists data_as_of  date;
alter table public.settings    add column if not exists fc_rule_pct numeric not null default 0.5;
alter table public.settings    add column if not exists fc_rule_min numeric not null default 20000000;
alter table public.mapping     add column if not exists status        text not null default 'active';
alter table public.mapping     add column if not exists proposed_by   text;
alter table public.mapping     add column if not exists proposed_note text;
alter table public.fc_entries  add column if not exists reason      text;
alter table public.submissions add column if not exists status      text not null default 'submitted';
alter table public.submissions add column if not exists reviewed_by text;
alter table public.submissions add column if not exists reviewed_at timestamptz;
alter table public.submissions add column if not exists review_note text;
do $$ begin alter table public.mapping add constraint mapping_status_chk check (status in ('active','proposed')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.submissions add constraint submissions_status_chk check (status in ('submitted','approved','returned')); exception when duplicate_object then null; end $$;

-- 2. Sales theo tháng (dữ liệu tổng hợp từ raw → nạp lại raw sau khi chạy)
do $$ begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'sales_agg')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales_agg' and column_name = 'month') then
    drop table public.sales_agg;
  end if;
end $$;
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


-- 3. Hàm, trigger, phân quyền
create or replace function public.is_reviewer() returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from team_members where lower(email) = my_email() and role in ('RFFM','ADMIN')) $$;

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


notify pgrst, 'reload schema';
