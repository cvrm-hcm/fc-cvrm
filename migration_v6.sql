-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 6: 2 TEAM (CVRM, WHC). Chạy 1 lần.
-- Supabase → SQL Editor → dán toàn bộ file này → Run. Chạy lại nhiều lần không sao.
-- Cần đang ở bản 5 (migration_v5.sql).
-- Sau khi chạy:
--   * Bảng teams: mỗi team có ngày dữ liệu raw sales và giá trị REP Group riêng.
--   * Cột team ở thành viên, SKU, account × SKU × MR, raw sales, target, bản chốt FC.
--     Dữ liệu đang có = CVRM. ADMIN / RFFM = ALL (xem cả 2 team).
--   * Nạp raw / target / account của team nào chỉ thay dữ liệu của team đó.
-- =====================================================================

-- 1. Bảng team
create table if not exists public.teams (
  team        text primary key,
  name        text not null,
  data_as_of  date,                 -- ngày hóa đơn mới nhất trong raw sales của team
  team_filter text,                 -- giá trị cột REP Group của team trong raw
  sort        int not null default 0
);
insert into public.teams (team, name, data_as_of, team_filter, sort)
  select 'CVRM', 'CVRM', s.data_as_of, coalesce(nullif(s.team_filter, ''), 'CVRM'), 1 from public.settings s where s.id = 1
  on conflict (team) do nothing;
insert into public.teams (team, name, data_as_of, team_filter, sort) values ('CVRM', 'CVRM', null, 'CVRM', 1), ('WHC', 'WHC', null, 'WHC', 2)
  on conflict (team) do nothing;

-- 2. Cột team (dữ liệu đang có thuộc CVRM)
alter table public.team_members  add column if not exists team text not null default 'CVRM';   -- MR: team của MR; ADMIN / RFFM: ALL = cả 2 team
alter table public.prices        add column if not exists team text not null default 'CVRM';
alter table public.mapping       add column if not exists team text not null default 'CVRM';
alter table public.sales_agg     add column if not exists team text not null default 'CVRM';
alter table public.accounts_seen add column if not exists team text not null default 'CVRM';
alter table public.targets       add column if not exists team text not null default 'CVRM';
alter table public.fc_archive    add column if not exists team text not null default 'CVRM';
-- Chỉ lần đầu: admin / RFFM đang có xem cả 2 team
do $$ begin
  if not exists (select 1 from public.team_members where team <> 'CVRM') then
    update public.team_members set team = 'ALL' where role in ('ADMIN', 'RFFM');
  end if;
end $$;

-- 3. Quyền: ai trong team cũng đọc được danh sách team; chỉ admin sửa
alter table public.teams enable row level security;
drop policy if exists "member read" on public.teams;
drop policy if exists "admin write" on public.teams;
create policy "member read" on public.teams for select to authenticated using (public.is_member());
create policy "admin write" on public.teams for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- App đọc số này để biết database đã ở bản 6 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 6 $$;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 6, 2 team
select public.app_db_version() as db_version, (select string_agg(team || ' ' || coalesce(to_char(data_as_of, 'DD/MM'), '-'), ' · ' order by sort) from public.teams) as teams;
