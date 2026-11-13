-- =====================================================================
-- FC Sale CVRM HCM — Supabase schema v8 (2 team CVRM / WHC, New launch, merge code) + Row Level Security
-- CÀI MỚI: chạy 1 lần trong Supabase → SQL Editor, sửa dòng INSERT admin ở cuối.
-- ĐANG CHẠY BẢN CŨ: bản 1–2 chạy migration_v3.sql → v4 → v5 → v6 → v7 → v8; bản 3 chạy v4 → … → v8; bản 4 chạy v5 → v6 → v7 → v8; bản 5 chạy v6 → v7 → v8; bản 6 chạy v7 rồi v8; bản 7 chỉ chạy migration_v8.sql.
-- Quyền:
--   * Chỉ email có trong team_members mới đọc được dữ liệu.
--   * MR: chỉ xem số của mình (account, sales, target, FC, trạng thái nộp);
--         nhập/sửa FC dòng của mình, đúng kỳ hiện tại, khi kỳ chưa khóa và FC chưa được duyệt;
--         nộp FC; đề xuất account/SKU mới cho chính mình;
--         New launch: tự thêm / đổi kênh / xoá BV, phòng khám của mình (SKU prices.launch).
--   * RFFM: xem cả team, duyệt / trả lại FC.
--   * ADMIN: toàn quyền.
-- =====================================================================

create table if not exists public.team_members (
  email     text primary key,
  rep_name  text not null,
  role      text not null default 'MR' check (role in ('MR','RFFM','ADMIN')),
  team      text not null default 'CVRM'   -- MR: team của MR (CVRM / WHC); ADMIN / RFFM: ALL = cả 2 team
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
  sku    text primary key,
  brand  text not null,
  price  numeric not null,
  team   text not null default 'CVRM',
  launch boolean not null default false,    -- SKU new launch (chưa có target): FC nhập riêng, không tính vào %Ach (bản 7)
  price_tender  numeric,                     -- giá riêng từng kênh, trống = price (bản 9)
  price_selfpay numeric,
  price_clinic  numeric
);

-- Team: mỗi team có ngày dữ liệu raw sales và giá trị REP Group riêng (bản 6)
create table if not exists public.teams (
  team        text primary key,
  name        text not null,
  data_as_of  date,
  team_filter text,
  sort        int not null default 0
);
insert into public.teams (team, name, team_filter, sort) values ('CVRM', 'CVRM', 'CVRM', 1), ('WHC', 'WHC', 'WHC', 2) on conflict (team) do nothing;

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
  team          text not null default 'CVRM',
  segment       text check (segment is null or segment in ('gov', 'priv', 'clinic')),   -- kênh New launch: BV công / BV tư / phòng khám (bản 7)
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
  team      text not null default 'CVRM',
  primary key (cust_code, sku, year, month)
);

-- Danh mục khách hàng từ raw sales: tên, kênh Gov / Priv / Clinic tự phân loại (bản 7). Không có doanh số.
create table if not exists public.customers (
  cust_code  text primary key,
  cust_name  text,
  segment    text check (segment is null or segment in ('gov', 'priv', 'clinic')),
  channel    text,          -- Channel_name: Hospital, Sub-dis clinics, Pharmacy, Wholesales
  cust_group text,          -- Customer Local Group 2 Desc
  sector     text,          -- Customer Local Group 3 Desc: GOV'T. ENTITIES / Private entities
  updated_at timestamptz not null default now()
);

-- Merge code (bản 8): mã KH → account Bayer. Mã Khoa Dược / BHYT của BV là merge code, mã NTBV / dịch vụ / mã trùng gộp vào.
-- App tính target, %Ach, cảnh báo theo merge code; FC vẫn nhập theo từng mã.
create table if not exists public.cust_merge (
  cust_code  text primary key,
  merge_code text not null,
  merge_name text,
  source     text,          -- Commex / Claude (suy luận) / File
  note       text,
  updated_at timestamptz not null default now()
);
create index if not exists cust_merge_merge_code_idx on public.cust_merge (merge_code);

create table if not exists public.accounts_seen (
  cust_code text not null,
  sku       text not null,
  cust_name text,
  rep_name  text,
  value     numeric,
  team      text not null default 'CVRM',
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
  team      text not null default 'CVRM',
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
  team       text not null default 'CVRM',
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
  foreach t in array array['team_members','settings','prices','teams','customers','cust_merge','mapping','sales_agg','accounts_seen','targets','fc_entries','fc_history','fc_archive','submissions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "member read" on public.%I', t);
    execute format('drop policy if exists "scoped read" on public.%I', t);
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
  -- Ai trong team cũng đọc được: tên / vai trò, kỳ FC, bảng giá, danh mục khách hàng, merge code (không có doanh số)
  foreach t in array array['team_members','settings','prices','teams','customers','cust_merge'] loop
    execute format('create policy "member read" on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;

-- Hàm hỗ trợ quyền đọc
-- App đọc số này để biết database đã ở bản mấy
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 10 $$;

-- SKU new launch? (bản 7)
create or replace function public.is_launch_sku(s text) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from prices where sku = s and launch) $$;

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

-- New launch (bản 7): MR thêm / sửa kênh / xoá BV, phòng khám của mình khi kỳ còn mở, chưa được duyệt
drop policy if exists "mr add launch mapping" on public.mapping;
create policy "mr add launch mapping" on public.mapping for insert to authenticated
  with check (rep_name = public.my_rep() and status = 'active' and public.period_open()
              and not public.rep_approved(public.current_period()) and public.is_launch_sku(sku));
drop policy if exists "mr edit launch mapping" on public.mapping;
create policy "mr edit launch mapping" on public.mapping for update to authenticated
  using (rep_name = public.my_rep() and public.is_launch_sku(sku))
  with check (rep_name = public.my_rep() and status = 'active' and public.period_open()
              and not public.rep_approved(public.current_period()) and public.is_launch_sku(sku));
drop policy if exists "mr remove launch mapping" on public.mapping;
create policy "mr remove launch mapping" on public.mapping for delete to authenticated
  using (rep_name = public.my_rep() and public.is_launch_sku(sku) and public.period_open()
         and not public.rep_approved(public.current_period()));

-- Quyền gọi hàm: người chưa đăng nhập không gọi được hàm nào; hàm trigger chỉ chạy qua trigger.
do $$
declare f text;
begin
  foreach f in array array['my_email()', 'is_member()', 'is_admin()', 'is_reviewer()', 'my_rep()', 'current_period()', 'period_open()', 'rep_approved(text)',
                           'app_db_version()', 'target_has_rep(text, text, text)', 'customer_names()', 'fc_auto_roll(text, jsonb)', 'is_launch_sku(text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['log_fc()', 'stamp_fc()', 'stamp_mapping()', 'stamp_submission()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- =====================================================================
-- Tender quota (bản 10): gói thầu + quota dự kiến
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

-- =====================================================================
-- KHỞI TẠO — sửa email + tên của bạn rồi chạy
-- =====================================================================
insert into public.settings (id, year, quarter, deadline) values (1, 2026, 4, '2026-11-20')
  on conflict (id) do nothing;

-- Giá list/box: không ghi trong file này (repo có thể public).
-- Nạp ở app: Admin → Kỳ & nạp dữ liệu → 1. Bảng giá & SKU.

insert into public.team_members (email, rep_name, role, team)
  values ('email.cua.ban@bayer.com', 'Nguyen Thanh Kha', 'ADMIN', 'ALL')
on conflict (email) do update set role = 'ADMIN', team = 'ALL';

notify pgrst, 'reload schema';
