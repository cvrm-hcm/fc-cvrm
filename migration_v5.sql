-- =====================================================================
-- FC Sale CVRM HCM — NÂNG CẤP DATABASE LÊN BẢN 5: TỰ TRỪ SALES MỚI VÀO FC. Chạy 1 lần.
-- Supabase → SQL Editor → dán toàn bộ file này → Run. Chạy lại nhiều lần không sao.
-- Cần đang ở bản 4 (migration_v4.sql).
-- Sau khi chạy:
--   * Admin nạp raw sales mới: app giữ FC quý từng dòng, phần sales vượt / thấp hơn FC tháng tự dời sang tháng còn lại.
--   * Lần dời này giữ nguyên người sửa / giờ sửa của MR (không thành "có sửa sau submit"); lịch sử FC ghi src = 'auto'.
--   * MR sửa số tháng của dòng đã dời: ghi chú tự dời (auto_note) tự xóa.
--   * Không đổi dữ liệu đang có, không cần nạp lại gì.
-- =====================================================================

-- 1. Cột mới
alter table public.fc_entries add column if not exists auto_note text;          -- lần app tự dời FC theo sales mới (hiện ở dấu ↻)
alter table public.fc_entries add column if not exists auto_at   timestamptz;
alter table public.fc_history add column if not exists src text;                -- 'auto' = app tự dời khi nạp sales

-- 2. Trigger: lần dời tự động (app.fc_auto = '1', chỉ đặt trong hàm fc_auto_roll) giữ người sửa / giờ sửa của MR
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

-- 3. Admin nạp sales mới → app tính số mới từng dòng rồi gọi hàm này.
--    Chỉ ghi dòng chưa ai sửa kể từ lúc app tính (so số cũ o1..o3). Trả về số dòng đã ghi.
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

-- App đọc số này để biết database đã ở bản 5 chưa
create or replace function public.app_db_version() returns int
  language sql immutable set search_path = '' as $$ select 5 $$;

-- 4. Quyền gọi hàm: chỉ người đã đăng nhập (trong hàm còn chặn: chỉ admin)
revoke execute on function public.fc_auto_roll(text, jsonb) from public, anon;
grant execute on function public.fc_auto_roll(text, jsonb) to authenticated;
revoke execute on function public.app_db_version() from public, anon;
grant execute on function public.app_db_version() to authenticated;
revoke execute on function public.stamp_fc() from public, anon, authenticated;
revoke execute on function public.log_fc() from public, anon, authenticated;

notify pgrst, 'reload schema';

-- Kiểm tra: db_version = 5, có 2 cột auto_note / auto_at
select public.app_db_version() as db_version,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_entries' and column_name in ('auto_note', 'auto_at')) as cot_moi;
