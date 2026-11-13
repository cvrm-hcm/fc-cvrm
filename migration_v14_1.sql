-- =====================================================================
-- FC Sale Team HCM · migration bản 14.1 (13/11/2026): sửa nhãn "tự add"
--  · Bản 14 lỡ gắn nhãn tự add cho đề xuất cũ + mọi BV New launch. Account từ raw / danh sách allocate là được allocate:
--      gỡ nhãn ở mọi dòng tạo trước 20:47 13/11 (lúc này chưa có địa bàn nào tự add).
--  · Quy tắc mới: tự add = người phụ trách tự thêm dòng của mình bằng tool (Thêm BV New launch / Đề xuất account),
--      kể cả admin có FC tự thêm dòng của mình. Admin thêm cho MR khác = allocate, không có nhãn.
-- Chạy sau migration_v14.sql. Chạy được nhiều lần.
-- =====================================================================

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

revoke execute on function public.stamp_mapping() from public, anon, authenticated;

update public.mapping set self_add = false, added_by = null, added_at = null
where self_add and created_at < timestamptz '2026-11-13 20:47:00+07';

select public.app_db_version() as db_version,
  count(*) filter (where self_add) as dong_tu_add,
  count(*) as tong_dong
from public.mapping;
