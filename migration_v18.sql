-- =====================================================================
-- FC Sale Team HCM · migration bản 18 (15/11/2026), app 4.24 — Ước tính thưởng (PBR)
--  · incentive_cfg: scheme thưởng (hạn mức, tỷ trọng, khung chi trả). Số của scheme là tài liệu nội bộ:
--    chỉ lưu trong database (thành viên đăng nhập đọc, admin ghi), không để trong repo.
--  · incentive_inputs: số MR tự nhập (MCCP, CLM, điểm test, Active Clinic, quý trước…)
--  · team_perf(team): tổng target / FC / Act. QTD của team (từ fc_snap) cho Enterprise factor
-- Chỉ tiêu Self-pay theo MR lưu ở bảng targets, kỳ '<kỳ>-SP', cust_code '*', sku 'SELF-PAY' (không cần bảng mới).
-- Chạy được nhiều lần.
-- =====================================================================
create table if not exists public.incentive_cfg (
  id    text primary key default 'current',
  data  jsonb not null default '{}'::jsonb,
  at    timestamptz not null default now()
);
alter table public.incentive_cfg enable row level security;
drop policy if exists "member read" on public.incentive_cfg;
drop policy if exists "admin write" on public.incentive_cfg;
create policy "member read" on public.incentive_cfg for select to authenticated using ((select public.is_member()));
create policy "admin write" on public.incentive_cfg for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
grant select on public.incentive_cfg to authenticated;
grant insert, update, delete on public.incentive_cfg to authenticated;

create table if not exists public.incentive_inputs (
  period    text not null,
  rep_name  text not null,
  data      jsonb not null default '{}'::jsonb,
  at        timestamptz not null default now(),
  by_email  text,
  primary key (period, rep_name)
);
drop trigger if exists trg_stamp_inc on public.incentive_inputs;
create trigger trg_stamp_inc before insert or update on public.incentive_inputs for each row execute function public.stamp_poa();
alter table public.incentive_inputs enable row level security;
drop policy if exists "admin write" on public.incentive_inputs;
drop policy if exists "scoped read" on public.incentive_inputs;
drop policy if exists "mr write own inc" on public.incentive_inputs;
create policy "admin write" on public.incentive_inputs for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "scoped read" on public.incentive_inputs for select to authenticated
  using ((select public.is_reviewer()) or rep_name = (select public.my_rep()));
create policy "mr write own inc" on public.incentive_inputs for all to authenticated
  using (rep_name = (select public.my_rep()))
  with check (rep_name = (select public.my_rep()) and period = (select public.current_period()));
grant select, insert, update, delete on public.incentive_inputs to authenticated;

-- Tổng của team (chỉ trả về tổng, không lộ số từng MR)
create or replace function public.team_perf(p_team text)
returns table (n_rep int, tgt numeric, fcv numeric, qtd numeric, at timestamptz)
language sql stable security definer set search_path = public as $$
  select count(distinct s.rep_name)::int, coalesce(sum(s.tgt), 0), coalesce(sum(s.fcv), 0), coalesce(sum(s.act_qtd), 0), max(s.at)
  from fc_snap s
  where s.period = public.current_period() and s.team = p_team and public.is_member()
$$;
revoke execute on function public.team_perf(text) from public, anon;
grant execute on function public.team_perf(text) to authenticated;

create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 18 $$;

notify pgrst, 'reload schema';

select public.app_db_version() as db_version;
