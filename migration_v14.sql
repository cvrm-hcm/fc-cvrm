-- =====================================================================
-- FC Sale Team HCM · migration bản 14 (13/11/2026): ghi chú cả team + admin có FC tính nộp tuần + địa bàn tự add, tra cứu
--  · wk_people(): người phải nộp FC tuần theo team = MR của team + admin / RFFM có dòng FC (mapping active) ở team đó.
--      CFO theo dõi cả admin có FC (vd anh Kha, anh Chung ở CVRM).
--  · fc_entries.note_by / note_at: server ghi ai điền ghi chú, lúc nào (chỉ khi ghi chú đổi), client không sửa được.
--  · fc_notes: ghi chú theo account × SKU của người không có dòng FC ở đó (admin / RFFM nhập ở "Cả team"),
--      mỗi người 1 ghi chú / dòng, ghi tên người điền. MR đọc được ghi chú ở mã KH mình phụ trách.
--  · mapping.self_add / added_by / added_at / address: nhãn "tự add" cho dòng MR tự thêm trên app (server ghi, MR không sửa được).
--  · find_account(q): tra cứu mã KH / SĐT / tên PK, BV (không dấu) → code, tên, địa chỉ, ai phụ trách. Không có doanh số.
-- Không đổi quyền cũ. Chạy được nhiều lần.
-- =====================================================================

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

create or replace function public.stamp_mapping() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'proposed' and new.proposed_by is null then new.proposed_by := my_email(); end if;
  if my_email() <> '' and not public.is_admin() then new.self_add := true; end if;   -- MR chỉ thêm được qua app
  if new.self_add and my_email() <> '' then new.added_by := my_email(); new.added_at := now(); end if;
  return new;
end $$;

-- Dòng cũ: đề xuất của MR + New launch (BV MR thêm trên app) là tự add
update public.mapping m set self_add = true, added_by = coalesce(m.added_by, m.proposed_by), added_at = coalesce(m.added_at, m.created_at)
where not m.self_add and (m.status = 'proposed' or m.proposed_by is not null
  or exists (select 1 from public.prices p where p.sku = m.sku and p.launch));

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

select public.app_db_version() as db_version,
  (select string_agg(team || ': ' || n, ' · ') from (select team, count(*) n from public.wk_people() group by team) x) as so_nguoi_nop_tuan;
