-- =====================================================================
-- FC Sale Team HCM · migration bản 13 (13/11/2026): CFO theo dõi nộp FC tuần
--  · team_members.cfo: admin tick MR làm CFO. CFO theo dõi MR cùng team.
--  · teams.wk_dow / wk_time / wk_from: hạn nộp FC tuần của từng team (giờ VN), theo dõi từ ngày.
--      Mặc định: WHC 13:00 thứ 2, CVRM 13:00 thứ 3.
--  · submit_log: mỗi lần MR bấm Submit / RFFM duyệt, trả lại / admin khoá, mở kỳ ghi 1 dòng, giờ lấy theo server.
--  · fc_snap: số FC theo brand của MR ở lần Submit gần nhất (FC, target, sales LYSP, quý trước) cho CFO xem,
--      CFO không đọc được số account của MR khác.
-- Không đổi quyền cũ. Chạy được nhiều lần.
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

notify pgrst, 'reload schema';

select public.app_db_version() as db_version,
  (select string_agg(team || ' ' || wk_dow || ' ' || wk_time, ' · ' order by sort) from public.teams) as han_nop,
  (select count(*) from public.submit_log) as so_dong_log;
