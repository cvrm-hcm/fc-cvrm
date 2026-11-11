-- =====================================================================
-- FC Sale CVRM HCM — Supabase schema v5 + Row Level Security
-- CÀI MỚI: chạy 1 lần trong Supabase → SQL Editor, sửa dòng INSERT admin ở cuối.
-- ĐANG CHẠY BẢN CŨ: bản 1–2 chạy migration_v3.sql → migration_v4.sql → migration_v5.sql; bản 3 chạy v4 rồi v5; bản 4 chỉ chạy migration_v5.sql.
-- Quyền:
--   * Chỉ email có trong team_members mới đọc được dữ liệu.
--   * MR: chỉ xem số của mình (account, sales, target, FC, trạng thái nộp);
--         nhập/sửa FC dòng của mình, đúng kỳ hiện tại, khi kỳ chưa khóa và FC chưa được duyệt;
--         nộp FC; đề xuất account/SKU mới cho chính mình.
--   * RFFM: xem cả team, duyệt / trả lại FC.
--   * ADMIN: toàn quyền.
-- =====================================================================

create table if not exists public.team_members (
  email     text primary key,
  rep_name  text not null,
  role      text not null default 'MR' check (role in ('MR','RFFM','ADMIN'))
);

create or replace function public.my_email() returns text
  language sql stable set search_path = '' as $$ select lower(coalesce(auth.jwt() ->> 'email', '')) $$;
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

-- Target theo kỳ: rep_name = '' là target cấp account (chia theo Sales ratio); có rep_name = target giao thẳng cho MR (file Target Allocation)
create table if not exists public.targets (
  period    text not null,
  rep_name  text not null default '',
  cust_code text not null,
  sku       text not null,
  value     numeric not null,
  qty       numeric,
  primary key (period, rep_name, cust_code, sku)
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
  auto_note  text,          -- lần app tự dời FC theo sales mới (bản 5)
  auto_at    timestamptz,
  primary key (period, mapping_id)
);

create table if not exists public.fc_history (
  id         bigint generated always as identity primary key,
  period     text, mapping_id bigint,
  old_m1 numeric, old_m2 numeric, old_m3 numeric,
  new_m1 numeric, new_m2 numeric, new_m3 numeric,
  changed_by text default public.my_email(),
  changed_at timestamptz default now(),
  src        text          -- 'auto' = app tự dời khi nạp sales (bản 5)
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
-- Lần dời tự động (app.fc_auto = '1', chỉ đặt trong hàm fc_auto_roll) giữ người sửa / giờ sửa của MR
create or replace function public.stamp_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('app.fc_auto', true), '') = '1' then
    new.updated_by := old.updated_by; new.updated_at := old.updated_at;
  else
    new.updated_by := my_email(); new.updated_at := now();
    if tg_op = 'UPDATE' and (old.m1, old.m2, old.m3) is distinct from (new.m1, new.m2, new.m3) then
      new.auto_note := null; new.auto_at := null;      -- MR / admin đã sửa số: bỏ dấu tự dời
    end if;
  end if;
  return new;
end $$;
create or replace function public.log_fc() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (old.m1, old.m2, old.m3) is not distinct from (new.m1, new.m2, new.m3) then return null; end if;
  insert into fc_history(period, mapping_id, old_m1, old_m2, old_m3, new_m1, new_m2, new_m3, src)
  values (new.period, new.mapping_id,
          case when tg_op = 'UPDATE' then old.m1 end, case when tg_op = 'UPDATE' then old.m2 end, case when tg_op = 'UPDATE' then old.m3 end,
          new.m1, new.m2, new.m3,
          case when coalesce(current_setting('app.fc_auto', true), '') = '1' then 'auto' end);
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
    execute format('drop policy if exists "scoped read" on public.%I', t);
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
  -- Ai trong team cũng đọc được: tên / vai trò, kỳ FC, bảng giá
  foreach t in array array['team_members','settings','prices'] loop
    execute format('create policy "member read" on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;

-- Hàm hỗ trợ quyền đọc
-- App đọc số này để biết database đã ở bản mấy
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 5 $$;

-- Admin nạp sales mới → app tính số mới từng dòng (giữ FC quý) rồi gọi hàm này.
-- Chỉ ghi dòng chưa ai sửa kể từ lúc app tính (so số cũ o1..o3). Trả về số dòng đã ghi.
create or replace function public.fc_auto_roll(p_period text, p_rows jsonb) returns int
  language plpgsql set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Chỉ admin được tự dời FC'; end if;
  perform set_config('app.fc_auto', '1', true);
  update public.fc_entries f
     set m1 = (x->>'m1')::numeric, m2 = (x->>'m2')::numeric, m3 = (x->>'m3')::numeric,
         auto_note = left(x->>'note', 1000), auto_at = now()
    from jsonb_array_elements(p_rows) x
   where f.period = p_period and f.mapping_id = (x->>'mapping_id')::bigint
     and f.m1 is not distinct from (x->>'o1')::numeric
     and f.m2 is not distinct from (x->>'o2')::numeric
     and f.m3 is not distinct from (x->>'o3')::numeric;
  get diagnostics n = row_count;
  perform set_config('app.fc_auto', '', true);
  return n;
end $$;

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


-- Quyền đọc theo người dùng: RFFM / admin xem cả team, MR chỉ xem số của mình
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

-- Quyền gọi hàm: người chưa đăng nhập không gọi được hàm nào; hàm trigger chỉ chạy qua trigger.
do $$
declare f text;
begin
  foreach f in array array['my_email()', 'is_member()', 'is_admin()', 'is_reviewer()', 'my_rep()', 'current_period()', 'period_open()', 'rep_approved(text)',
                           'app_db_version()', 'target_has_rep(text, text, text)', 'customer_names()', 'fc_auto_roll(text, jsonb)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['log_fc()', 'stamp_fc()', 'stamp_mapping()', 'stamp_submission()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

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
