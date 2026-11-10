# FC Sale CVRM HCM — web app

App nhập FC sale theo quý cho team CVRM HCM, thay cho file Excel dùng chung.

- **MR:** đăng nhập bằng email, chỉ thấy và chỉ sửa được FC các account của mình. Nhập box theo tháng (máy tính hoặc điện thoại), tự lưu, bấm **Nộp FC** khi xong.
- **Dashboard:** performance cá nhân và cả team: Target, FC, %Ach, QTD, so với LYSP và quý trước, theo MR / brand / kênh, ai đã nộp hay chưa.
- **Admin:**
  - Đặt kỳ FC, hạn nộp, khóa kỳ.
  - Nạp raw sales (file export Power BI, tự dò cột theo tên), file FC (sheet FC Input), target.
  - Phân bổ account cho MR, xử lý account có sales mà chưa có trên FC.
  - Quản lý thành viên và giá.
  - Xuất Excel.

## Kiến trúc

| Phần | Dùng gì |
|---|---|
| Giao diện | 1 file `index.html`, host bằng GitHub Pages |
| Đăng nhập + database | Supabase (Auth + Postgres), giống app Sổ hợp đồng HCP |
| Phân quyền | Row Level Security trong `schema.sql`, chặn ở database chứ không chỉ ẩn trên giao diện |
| Đọc / xuất Excel | SheetJS, chạy trong trình duyệt |

Không có server riêng. File raw sales được tổng hợp ngay trong trình duyệt (khách × SKU × quý) rồi mới lưu lên, nên database chỉ khoảng vài nghìn dòng.

**Phân quyền** (đã test trên Postgres 16 + PostgREST, cùng thành phần Supabase dùng):

- MR thêm/sửa FC chỉ cho dòng account gán cho mình, đúng kỳ hiện tại, khi kỳ chưa khóa.
- Email không có trong `team_members` không đọc được gì.
- Chỉ ADMIN nạp dữ liệu, sửa phân bổ, khóa kỳ.
- RFFM xem tất cả, không sửa.
- Mọi thay đổi FC được ghi vào bảng `fc_history` (ai sửa, lúc nào, số cũ → số mới).

## Chạy thử (demo)

Mở `index.html` khi `SUPABASE_URL` còn trống: app chạy chế độ demo với dữ liệu giả, lưu trong trình duyệt. Đăng nhập bằng vai MR / RFFM / Admin để xem từng màn hình. Ở vai Admin có thể nạp file thật để thử: dữ liệu chỉ nằm trong trình duyệt của máy đó.

## Triển khai thật (khoảng 30 phút)

### A. Supabase

1. **Tạo project:** vào [supabase.com](https://supabase.com), đăng nhập (dùng chung tài khoản với app HCP được), bấm **New project**:
   - Tên: `fc-sale-cvrm-hcm`
   - Region: **Southeast Asia (Singapore)**
   - Đặt database password và lưu lại.
2. **Chạy schema:** vào **SQL Editor**, dán toàn bộ `schema.sql`. Sửa dòng cuối thành email và tên của bạn (ADMIN), tên phải trùng REP Name, ví dụ `Nguyen Thanh Kha`. Bấm **Run**.
3. **Khóa đăng ký:** vào **Authentication → Sign In / Providers → Email**, tắt *Allow new users to sign up*. Chỉ admin mới tạo được tài khoản.
4. **Tạo tài khoản cho bạn:** vào **Authentication → Users → Add user → Create new user**:
   - Email của bạn và mật khẩu tạm.
   - Tick **Auto Confirm User**.
5. **Lấy key:** vào **Project Settings → API**, copy *Project URL* và *anon public key*.

### B. GitHub

6. **Điền cấu hình:** mở `index.html`, điền vào `window.FC_CONFIG`:
   ```js
   SUPABASE_URL: 'https://xxxx.supabase.co',
   SUPABASE_ANON_KEY: 'eyJ...',
   ```
7. **Đưa lên GitHub Pages:** đẩy `index.html` lên repo `fc-sale-cvrm-hcm`, rồi vào **Settings → Pages**, chọn Source = *Deploy from a branch*, branch `main`, thư mục `/ (root)`. Khoảng 1 phút sau có link `https://<tên-github>.github.io/fc-sale-cvrm-hcm/`.
8. **Đặt Site URL:** quay lại Supabase, vào **Authentication → URL Configuration**, Site URL = link ở bước 7.

### C. Nạp dữ liệu (trong app, tài khoản ADMIN)

9. **Đăng nhập lần đầu:** app bắt đổi mật khẩu.
10. **Nạp dữ liệu:** vào Admin → Kỳ & nạp dữ liệu, nạp **theo đúng thứ tự**:
    1. File `FC_Sale_CVRM_HCM_v2.xlsx`: lấy danh sách account, giá SKU (sheet Setup) và số FC đã nhập.
    2. Raw sales (file export Power BI).
    3. Target (lại chọn file v2, app đọc sheet Target).
11. **Thêm thành viên:** vào Admin → Thành viên & giá.
    - Bấm *Thêm MR còn thiếu từ danh sách account*, điền email từng người.
    - Hoặc mở *Dán cả danh sách từ Excel*, dán 3 cột Email | Tên MR | Vai trò.
    - Bấm **Lưu**.
12. **Tạo tài khoản cho MR:** với mỗi MR, vào Supabase → Authentication → Users → **Add user**:
    - Email và mật khẩu tạm, tick Auto Confirm.
    - Gửi link app + mật khẩu tạm cho MR. MR đăng nhập lần đầu sẽ bị yêu cầu đổi mật khẩu.

**Vì sao không gửi email mời:** email có sẵn của Supabase chỉ gửi tới thành viên của project Supabase, tối đa 2 email/giờ, nên không dùng để mời 20 người được. Muốn MR tự đăng nhập bằng link email thì cần cấu hình SMTP riêng (Brevo/Resend), sau đó đặt `EMAIL_LINK: true` trong `index.html`.

**MR quên mật khẩu:** admin xóa user đó trong Supabase → Users rồi tạo lại với mật khẩu tạm mới. Dữ liệu FC không mất, vì quyền gắn theo email, không gắn theo user.

**Repo public có an toàn không:** repo chỉ chứa code giao diện và dữ liệu demo giả, không có số thật, không có giá thật. Anon key là key công khai theo thiết kế của Supabase; quyền đọc/ghi do RLS trong database quyết định (đã test: người ngoài đọc 0 dòng, MR không ghi được dòng của người khác, không xóa được dữ liệu). Tuyệt đối **không** đưa *service_role key* vào code.

## Quy trình mỗi quý

1. **Admin mở kỳ mới:** Admin → Kỳ & nạp dữ liệu → đổi Năm/Quý, đặt hạn nộp → Lưu. FC và target kỳ mới bắt đầu trống, dữ liệu kỳ cũ vẫn giữ.
2. **Nạp raw sales** mới nhất, sau đó xem tab **Account thiếu** và thêm account mới vào FC.
3. **Nạp target** quý mới.
4. **MR nhập FC và bấm Nộp.** Admin theo dõi cột Trạng thái ở Dashboard.
5. **Hết hạn:** tick **Khóa nhập**, rồi **Xuất Excel** để gửi lên trên.

## Giới hạn hiện tại

- **Đồng bộ Excel một chiều:** app là nơi lưu dữ liệu chính, xuất Excel khi cần. Sửa file Excel không làm thay đổi số trên app.
- **Supabase gói free tự tạm dừng sau 7 ngày không ai dùng:** mở lại trong dashboard là chạy tiếp. Gói Pro không bị.
- **MR xem được account của MR khác:** mọi MR đọc được số của cả team, giống file Excel hiện tại. Muốn MR chỉ thấy số tổng của người khác thì cần thêm view tổng hợp ở database.
