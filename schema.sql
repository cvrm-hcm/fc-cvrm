-- =====================================================================
-- FC Sale CVRM HCM — Supabase schema v14 (2 team CVRM / WHC, New launch, merge code, tender, địa bàn chung, CFO nộp FC tuần, ghi chú cả team, địa bàn tự add + tra cứu) + Row Level Security
-- CÀI MỚI: chạy 1 lần trong Supabase → SQL Editor, sửa dòng INSERT admin ở cuối.
-- ĐANG CHẠY BẢN CŨ: bản 1–2 chạy migration_v3.sql → v4 → v5 → v6 → v7 → v8; bản 3 chạy v4 → … → v8; bản 4 chạy v5 → v6 → v7 → v8; bản 5 chạy v6 → v7 → v8; bản 6 chạy v7 rồi v8; bản 7 chỉ chạy migration_v8.sql.
-- Quyền:
--   * Chỉ email có trong team_members mới đọc được dữ liệu.
--   * MR: chỉ xem số của mình (account, sales, target, FC, trạng thái nộp);
--         nhập/sửa FC dòng của mình, đúng kỳ hiện tại, khi kỳ chưa khóa và FC chưa được duyệt;
--         nộp FC; đề xuất account/SKU mới cho chính mình;
--         New launch: tự thêm / đổi kênh / xoá BV, phòng khám của mình (SKU prices.launch).
--   * CFO (bản 13): MR được admin tick; xem nhật ký nộp FC tuần + số FC theo brand (lần Submit gần nhất) của MR cùng team.
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
  language sql immutable set search_path = '' as $$ select 13 $$;

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
-- Bản 11: RLS tính nhanh khi cả team cùng vào (giống migration_v11.sql, không đổi quyền)
-- =====================================================================
-- 1. Policy "admin write" (FOR ALL nên cũng tham gia mọi lần đọc)
do $$
declare t text;
begin
  foreach t in array array['accounts_seen', 'cust_merge', 'customers', 'fc_archive', 'fc_entries', 'fc_history', 'mapping', 'prices', 'sales_agg',
                           'settings', 'submissions', 'targets', 'team_members', 'teams', 'tender_upcoming', 'tenders'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'admin write') then
      execute format('alter policy "admin write" on public.%I using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    end if;
  end loop;
  foreach t in array array['cust_merge', 'customers', 'prices', 'settings', 'team_members', 'teams'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'member read') then
      execute format('alter policy "member read" on public.%I using ((select public.is_member()))', t);
    end if;
  end loop;
end $$;

-- 2. Đọc theo phạm vi MR
alter policy "scoped read" on public.sales_agg using (
  (select public.is_reviewer())
  or (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.fc_entries using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.fc_history using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.targets using (
  (select public.is_reviewer())
  or rep_name = (select public.my_rep())
  or (rep_name = '' and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()))
      and not public.target_has_rep(period, cust_code, sku)));

alter policy "scoped read" on public.tenders using (
  (select public.is_reviewer())
  or cust_code in (select m.cust_code from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "scoped read" on public.tender_upcoming using (
  (select public.is_reviewer())
  or cust_code in (select m.cust_code from public.mapping m where m.rep_name = (select public.my_rep())));

-- 3. MR ghi FC của mình (nút "Điền theo TB 2Q" lưu cả trăm dòng 1 lần)
alter policy "mr insert own fc" on public.fc_entries with check (
  period = (select public.current_period()) and (select public.period_open()) and not public.rep_approved(period)
  and mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "mr update own fc" on public.fc_entries
  using (mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())))
  with check (period = (select public.current_period()) and (select public.period_open()) and not public.rep_approved(period)
    and mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep())));

alter policy "reviewer review" on public.submissions using ((select public.is_reviewer())) with check ((select public.is_reviewer()));

-- =====================================================================
-- Bản 12: FC giùm địa bàn chung (giống migration_v12.sql)
-- =====================================================================
-- Các dòng mapping (mọi MR) ở account × SKU mà mình đang phụ trách
create index if not exists mapping_cust_sku_idx on public.mapping (cust_code, sku);
create or replace function public.my_shared_ids() returns setof bigint
  language sql stable security definer set search_path = public as $$
  select o.id from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active'
  where x.rep_name = my_rep() and x.status = 'active'
$$;

-- Đồng nghiệp cùng phụ trách ít nhất 1 account × SKU với mình
create or replace function public.my_co_reps() returns setof text
  language sql stable security definer set search_path = public as $$
  select distinct o.rep_name from mapping x join mapping o on o.cust_code = x.cust_code and o.sku = x.sku and o.status = 'active' and o.rep_name <> x.rep_name
  where x.rep_name = my_rep() and x.status = 'active'
$$;

-- FC của MR giữ dòng mapping này đã được duyệt chưa
create or replace function public.mapping_rep_approved(mid bigint, p text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from mapping m join submissions s on s.rep_name = m.rep_name where m.id = mid and s.period = p and s.status = 'approved')
$$;

do $$
declare f text;
begin
  foreach f in array array['my_shared_ids()', 'my_co_reps()', 'mapping_rep_approved(bigint, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- Đọc
alter policy "scoped read" on public.mapping using (
  (select public.is_reviewer()) or rep_name = (select public.my_rep()) or id in (select public.my_shared_ids()));

alter policy "scoped read" on public.fc_entries using (
  (select public.is_reviewer())
  or mapping_id in (select m.id from public.mapping m where m.rep_name = (select public.my_rep()))
  or mapping_id in (select public.my_shared_ids()));

alter policy "scoped read" on public.targets using (
  (select public.is_reviewer())
  or rep_name = (select public.my_rep())
  or (rep_name = '' and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()))
      and not public.target_has_rep(period, cust_code, sku))
  or (rep_name in (select public.my_co_reps())
      and (cust_code, sku) in (select m.cust_code, m.sku from public.mapping m where m.rep_name = (select public.my_rep()) and m.status = 'active')));

alter policy "scoped read" on public.submissions using (
  (select public.is_reviewer()) or rep_name = (select public.my_rep()) or rep_name in (select public.my_co_reps()));

-- Ghi FC giùm ở địa bàn chung
drop policy if exists "mr insert shared fc" on public.fc_entries;
create policy "mr insert shared fc" on public.fc_entries for insert to authenticated
  with check (period = (select public.current_period()) and (select public.period_open())
    and mapping_id in (select public.my_shared_ids()) and not public.mapping_rep_approved(mapping_id, period));

drop policy if exists "mr update shared fc" on public.fc_entries;
create policy "mr update shared fc" on public.fc_entries for update to authenticated
  using (mapping_id in (select public.my_shared_ids()))
  with check (period = (select public.current_period()) and (select public.period_open())
    and mapping_id in (select public.my_shared_ids()) and not public.mapping_rep_approved(mapping_id, period));

-- =====================================================================
-- Bản 13: CFO theo dõi nộp FC tuần (giống migration_v13.sql)
-- =====================================================================
-- 1. CFO
alter table public.team_members add column if not exists cfo boolean not null default false;

create or replace function public.is_cfo() returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from team_members where lower(email) = my_email() and cfo) $$;

-- MR thuộc team của CFO (CFO là MR; CFO team ALL thì theo dõi cả 2 team)
create or replace function public.cfo_reps() returns setof text
  language sql stable security definer set search_path = public as $$
  select o.rep_name from team_members me join team_members o on o.role = 'MR' and (o.team = me.team or me.team = 'ALL')
  where lower(me.email) = my_email() and me.cfo
$$;

-- 2. Hạn nộp FC tuần theo team
alter table public.teams add column if not exists wk_dow  int  check (wk_dow between 1 and 7);                       -- 1 = thứ 2 … 7 = chủ nhật
alter table public.teams add column if not exists wk_time text check (wk_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');  -- giờ VN, HH:MM
alter table public.teams add column if not exists wk_from date;                                                      -- theo dõi các hạn từ ngày này
update public.teams set wk_dow = coalesce(wk_dow, case team when 'WHC' then 1 else 2 end),
                        wk_time = coalesce(wk_time, '13:00'),
                        wk_from = coalesce(wk_from, date '2026-11-14');

-- 3. Nhật ký nộp FC
create table if not exists public.submit_log (
  id        bigint generated always as identity primary key,
  period    text not null,
  rep_name  text not null,               -- '' = sự kiện của cả kỳ (khoá / mở nhập)
  status    text not null,               -- submitted · approved · returned · locked · unlocked
  at        timestamptz not null default now(),
  by_email  text
);
create index if not exists submit_log_rep_at_idx on public.submit_log (rep_name, at);
create index if not exists submit_log_at_idx on public.submit_log (at);

create or replace function public.log_submission() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status and new.submitted_at is not distinct from old.submitted_at then return null; end if;
  insert into submit_log (period, rep_name, status, at, by_email)
  values (new.period, new.rep_name, new.status,
          case when new.status = 'submitted' then new.submitted_at else coalesce(new.reviewed_at, now()) end,
          case when new.status = 'submitted' then new.submitted_by else new.reviewed_by end);
  return null;
end $$;
drop trigger if exists trg_log_sub on public.submissions;
create trigger trg_log_sub after insert or update on public.submissions for each row execute function public.log_submission();

create or replace function public.log_lock() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if new.locked is distinct from old.locked then
    insert into submit_log (period, rep_name, status, by_email)
    values (new.year::text || 'Q' || new.quarter::text, '', case when new.locked then 'locked' else 'unlocked' end, my_email());
  end if;
  return null;
end $$;
drop trigger if exists trg_log_lock on public.settings;
create trigger trg_log_lock after update on public.settings for each row execute function public.log_lock();

-- Ghi lại các lần submit / duyệt đang có
insert into public.submit_log (period, rep_name, status, at, by_email)
select s.period, s.rep_name, 'submitted', s.submitted_at, s.submitted_by from public.submissions s
where not exists (select 1 from public.submit_log l where l.period = s.period and l.rep_name = s.rep_name and l.status = 'submitted' and l.at = s.submitted_at);
insert into public.submit_log (period, rep_name, status, at, by_email)
select s.period, s.rep_name, s.status, s.reviewed_at, s.reviewed_by from public.submissions s
where s.status in ('approved', 'returned') and s.reviewed_at is not null
  and not exists (select 1 from public.submit_log l where l.period = s.period and l.rep_name = s.rep_name and l.status = s.status and l.at = s.reviewed_at);

-- 4. Số FC theo brand ở lần Submit gần nhất
create table if not exists public.fc_snap (
  period    text not null,
  rep_name  text not null,
  brand     text not null,
  team      text not null default 'CVRM',
  fcv       numeric not null default 0,   -- FC quý (VND)
  tgt       numeric not null default 0,   -- target quý (VND)
  act_ly    numeric not null default 0,   -- sales cùng quý năm trước (LYSP)
  act_lq    numeric not null default 0,   -- sales quý trước
  act_qtd   numeric not null default 0,   -- sales quý này đến ngày dữ liệu
  n_rows    int not null default 0,
  n_filled  int not null default 0,
  at        timestamptz not null default now(),
  by_email  text,
  primary key (period, rep_name, brand)
);
create or replace function public.stamp_snap() returns trigger
  language plpgsql security definer set search_path = public as $$
begin new.at := now(); new.by_email := my_email(); return new; end $$;
drop trigger if exists trg_stamp_snap on public.fc_snap;
create trigger trg_stamp_snap before insert or update on public.fc_snap for each row execute function public.stamp_snap();

-- 5. Quyền
alter table public.submit_log enable row level security;
alter table public.fc_snap enable row level security;
do $$
declare t text;
begin
  foreach t in array array['submit_log', 'fc_snap'] loop
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('drop policy if exists "scoped read" on public.%I', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
  end loop;
end $$;
-- Đọc: RFFM / admin cả team, MR của mình, CFO các MR cùng team; sự kiện khoá / mở kỳ ai cũng đọc
create policy "scoped read" on public.submit_log for select to authenticated
  using ((select public.is_reviewer()) or (rep_name = '' and (select public.is_member())) or rep_name = (select public.my_rep()) or rep_name in (select public.cfo_reps()));
create policy "scoped read" on public.fc_snap for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()) or rep_name in (select public.cfo_reps()));
-- MR ghi số của mình ở kỳ hiện tại (app ghi lúc bấm Submit)
drop policy if exists "mr write own snap" on public.fc_snap;
create policy "mr write own snap" on public.fc_snap for all to authenticated
  using (rep_name = (select public.my_rep()))
  with check (rep_name = (select public.my_rep()) and period = (select public.current_period()));

grant select on public.submit_log to authenticated;
grant select, insert, update, delete on public.fc_snap to authenticated;
revoke all on public.submit_log, public.fc_snap from anon;

do $$
declare f text;
begin
  foreach f in array array['is_cfo()', 'cfo_reps()'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['log_submission()', 'log_lock()', 'stamp_snap()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 13 $$;

-- =====================================================================
-- Bản 14: ghi chú cả team + admin có FC tính nộp tuần + địa bàn tự add, tra cứu (giống migration_v14.sql + 14.1)
-- 1. Ai phải nộp FC tuần
create or replace function public.wk_people() returns table (team text, rep_name text)
  language sql stable security definer set search_path = public as $$
  select coalesce(t.team, 'CVRM'), t.rep_name from team_members t where t.role = 'MR' and (select is_member())
  union
  select distinct m.team, m.rep_name from mapping m join team_members t on t.rep_name = m.rep_name and t.role <> 'MR'
  where m.status = 'active' and (select is_member())
$$;
create or replace function public.cfo_reps() returns setof text
  language sql stable security definer set search_path = public as $$
  select w.rep_name from team_members me join public.wk_people() w on (w.team = me.team or me.team = 'ALL')
  where lower(me.email) = my_email() and me.cfo
$$;

-- 2. Ai điền ghi chú ở dòng FC
alter table public.fc_entries add column if not exists note_by text;
alter table public.fc_entries add column if not exists note_at timestamptz;
create or replace function public.stamp_note() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' and coalesce(new.note, '') <> '') or (tg_op = 'UPDATE' and coalesce(new.note, '') is distinct from coalesce(old.note, '')) then
    new.note_by := my_email(); new.note_at := now();
  elsif tg_op = 'UPDATE' then
    new.note_by := old.note_by; new.note_at := old.note_at;
  else
    new.note_by := null; new.note_at := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_stamp_note on public.fc_entries;
create trigger trg_stamp_note before insert or update on public.fc_entries for each row execute function public.stamp_note();

-- 3. Ghi chú ở "Cả team" của người không có dòng FC ở account × SKU đó
create table if not exists public.fc_notes (
  period    text not null,
  cust_code text not null,
  sku       text not null,
  by_email  text not null,
  note      text not null default '',
  at        timestamptz not null default now(),
  primary key (period, cust_code, sku, by_email)
);
create or replace function public.stamp_fc_note() returns trigger
  language plpgsql security definer set search_path = public as $$
begin new.by_email := my_email(); new.at := now(); return new; end $$;
drop trigger if exists trg_stamp_fc_note on public.fc_notes;
create trigger trg_stamp_fc_note before insert or update on public.fc_notes for each row execute function public.stamp_fc_note();

alter table public.fc_notes enable row level security;
drop policy if exists "admin write" on public.fc_notes;
drop policy if exists "scoped read" on public.fc_notes;
drop policy if exists "write own note" on public.fc_notes;
create policy "admin write" on public.fc_notes for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "scoped read" on public.fc_notes for select to authenticated
  using ((select public.is_reviewer()) or public.my_code(cust_code));
create policy "write own note" on public.fc_notes for all to authenticated
  using (by_email = (select public.my_email()))
  with check (by_email = (select public.my_email()) and period = (select public.current_period())
              and ((select public.is_reviewer()) or public.my_code(cust_code)));
grant select, insert, update, delete on public.fc_notes to authenticated;
revoke all on public.fc_notes from anon;

-- 4. Địa bàn tự add (bản 4.21): nhãn "tự add" cho dòng MR tự thêm trên app (Thêm BV ở New launch, Đề xuất account).
--    Code = mã KH hoặc SĐT phòng khám / BS; địa chỉ để đồng đội tra cứu.
alter table public.mapping add column if not exists self_add boolean not null default false;
alter table public.mapping add column if not exists added_by text;
alter table public.mapping add column if not exists added_at timestamptz;
alter table public.mapping add column if not exists address text;
alter table public.customers add column if not exists address text;   -- từ raw sales nếu có cột địa chỉ

-- Tự add = người phụ trách tự thêm dòng của mình bằng tool trên app (Thêm BV New launch / Đề xuất account), kể cả admin có FC.
-- Dòng nạp từ raw / danh sách allocate, hoặc admin thêm cho MR khác = được allocate, không có nhãn.
create or replace function public.stamp_mapping() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'proposed' and new.proposed_by is null then new.proposed_by := my_email(); end if;
  if my_email() <> '' then
    if not public.is_admin() then new.self_add := true;                                   -- MR chỉ thêm được dòng của mình qua tool
    elsif new.rep_name is distinct from public.my_rep() then new.self_add := false; end if;   -- admin thêm cho MR khác = allocate
  end if;
  if new.self_add and my_email() <> '' then new.added_by := my_email(); new.added_at := now(); end if;
  return new;
end $$;

-- Dòng đang có (raw / danh sách allocate) giữ self_add = false: chỉ dòng tự add từ bản này trở đi mới có nhãn.

-- MR không sửa được nhãn / người add (admin sửa được)
create or replace function public.keep_add_stamp() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if my_email() <> '' and not public.is_admin() then new.self_add := old.self_add; new.added_by := old.added_by; new.added_at := old.added_at; end if;
  return new;
end $$;
drop trigger if exists trg_keep_add_stamp on public.mapping;
create trigger trg_keep_add_stamp before update on public.mapping for each row execute function public.keep_add_stamp();

-- Tra cứu địa bàn: tìm theo mã KH / SĐT hoặc tên (không dấu), trả code, tên, địa chỉ, ai đang phụ trách. Không có doanh số.
create or replace function public.vn_fold(s text) returns text
  language sql immutable parallel safe set search_path = '' as $$
  select lower(translate(normalize(coalesce(s, ''), NFC),
    'àáảãạăằắẳẵặâầấẩẫậÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬèéẻẽẹêềếểễệÈÉẺẼẸÊỀẾỂỄỆìíỉĩịÌÍỈĨỊòóỏõọôồốổỗộơờớởỡợÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢùúủũụưừứửữựÙÚỦŨỤƯỪỨỬỮỰỳýỷỹỵỲÝỶỸỴđĐ',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaeeeeeeeeeeeeeeeeeeeeeeiiiiiiiiiioooooooooooooooooooooooooooooooooouuuuuuuuuuuuuuuuuuuuuuyyyyyyyyyydd')) $$;
create or replace function public.phone_norm(s text) returns text
  language sql immutable parallel safe set search_path = '' as $$
  select case when d ~ '^84[0-9]{9,10}$' then '0' || substr(d, 3) else d end
  from (select regexp_replace(coalesce(s, ''), '[^0-9]', '', 'g') as d) x $$;

create or replace function public.find_account(q text)
  returns table (cust_code text, cust_name text, address text, segment text, in_raw boolean, merge_code text, merge_name text, reps jsonb)
  language plpgsql stable security definer set search_path = public as $$
declare t text := btrim(coalesce(q, '')); d text; f text;
begin
  if not public.is_member() or length(t) < 2 then return; end if;
  d := public.phone_norm(t); f := btrim(regexp_replace(public.vn_fold(t), '\s+', ' ', 'g'));
  return query
  with cand as (
    select c.cust_code, c.cust_name, c.address, c.segment, true as in_raw from public.customers c
    union all select m.cust_code, max(m.cust_name), max(m.address), max(m.segment), false from public.mapping m group by m.cust_code
    union all select a.cust_code, max(a.cust_name), null, null, false from public.accounts_seen a group by a.cust_code
  ), acc as (
    select x.cust_code, (array_agg(x.cust_name order by x.in_raw desc) filter (where coalesce(x.cust_name, '') <> ''))[1] as cust_name,
      max(x.address) as address, max(x.segment) as segment, bool_or(x.in_raw) as in_raw
    from cand x group by x.cust_code
  ), hit as (
    select a.*, case when public.phone_norm(a.cust_code) = d or lower(a.cust_code) = lower(t) then 0
                     when length(d) >= 4 and public.phone_norm(a.cust_code) like d || '%' then 1
                     when public.vn_fold(a.cust_name) like f || '%' then 2 else 3 end as score
    from acc a
    where lower(a.cust_code) = lower(t)
       or (length(d) >= 4 and public.phone_norm(a.cust_code) like d || '%')
       or (length(f) >= 2 and not exists (select 1 from unnest(string_to_array(f, ' ')) w
             where w <> '' and position(w in public.vn_fold(coalesce(a.cust_name, '') || ' ' || a.cust_code)) = 0))
    order by score, a.cust_name limit 30
  )
  select h.cust_code, h.cust_name, h.address, h.segment, h.in_raw, cm.merge_code, cm.merge_name,
    (select coalesce(jsonb_agg(jsonb_build_object('rep', r.rep_name, 'team', r.team, 'n', r.n, 'brands', r.brands, 'self', r.self,
        'prop', r.prop, 'direct', r.direct, 'by', coalesce(tm.rep_name, r.by_email), 'at', r.at) order by r.direct desc, r.rep_name), '[]'::jsonb)
     from (select m.rep_name, max(m.team) as team, count(*) as n, string_agg(distinct m.brand, ', ') as brands, bool_or(m.self_add) as self,
             bool_and(m.status = 'proposed') as prop, bool_or(m.cust_code = h.cust_code) as direct, max(m.added_by) as by_email, max(m.added_at) as at
           from public.mapping m
           where (m.cust_code = h.cust_code or m.cust_code = coalesce(cm.merge_code, h.cust_code)
                  or m.cust_code in (select c2.cust_code from public.cust_merge c2 where c2.merge_code = coalesce(cm.merge_code, h.cust_code)))
             and (m.ratio > 0 or m.status = 'proposed')
           group by m.rep_name) r
     left join public.team_members tm on lower(tm.email) = lower(r.by_email))
  from hit h left join public.cust_merge cm on cm.cust_code = h.cust_code
  order by h.score, h.cust_name;
end $$;

do $$
declare f text;
begin
  foreach f in array array['find_account(text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['keep_add_stamp()', 'stamp_mapping()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['wk_people()', 'cfo_reps()'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['stamp_note()', 'stamp_fc_note()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 14 $$;

notify pgrst, 'reload schema';

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
