# FC Sale CVRM HCM — web app

App forecast doanh số theo quý cho team CVRM HCM (kênh bệnh viện), thay cho file Excel dùng chung. Chạy trên GitHub Pages + Supabase.

## Phiên bản 4.0 (10/11/2026) — MR chỉ xem số của mình

- **MR**: Dashboard chỉ còn số của mình ("Dashboard của tôi"): bỏ ô chọn MR, biểu đồ và bảng theo MR, tiến độ nộp cả team; thêm ô Trạng thái FC của mình.
- **RFFM, Admin**: xem cả team như cũ.
- Chặn ở database (`migration_v4.sql`): MR chỉ đọc được account, sales, target, FC, trạng thái nộp, bản chốt của chính mình. Bảng giá, kỳ FC, danh sách thành viên vẫn đọc chung.
- Đề xuất account: vẫn gợi ý mã + tên khách hàng (không kèm doanh số).
- Cảnh báo "Ratio≠100%" chỉ hiện với RFFM/Admin (MR không thấy phần của MR khác nên không tự kiểm được).
- Bảng Theo brand / kênh bỏ dòng toàn số 0.
- Siết quyền gọi hàm theo Security Advisor của Supabase: người chưa đăng nhập không gọi được hàm nào, hàm trigger chỉ chạy qua trigger.
- **Cần làm 1 lần:** Supabase → SQL Editor → dán toàn bộ `migration_v4.sql` → Run. Chưa chạy thì Admin thấy dòng nhắc màu vàng; giao diện MR vẫn ẩn số team nhưng MR còn đọc được qua API.

## Phiên bản 3.5 (10/11/2026) — FC theo ngày dữ liệu, bỏ "ước đạt"

- **Tháng đã chốt** (đã có thực tế cả tháng): FC khóa bằng thực tế, không nhập.
- **Tháng đang chạy**: MR chỉ nhập FC từ ngày sau ngày dữ liệu (vd dữ liệu đến 09/11 → nhập từ 10/11). Số nhỏ bên trái ô là đơn đã lên, app cộng sẵn. Database vẫn lưu FC cả tháng (= đã lên + phần còn lại), nên khi nạp raw mới, phần "còn lại" tự giảm theo đơn vừa lên.
- **Tháng tới**: FC cả tháng.
- **FC quý** = thực tế tháng đã chốt + đơn đã lên tháng đang chạy + FC phần còn lại. Bỏ hẳn "ước đạt cuối quý" (thẻ, cột, biểu đồ, file Excel) và bảng độ chính xác FC trên Dashboard.
- Biểu đồ quý / tháng dạng cột chồng: xanh = thực tế / đơn đã lên, cam = FC còn lại.
- Excel xuất: tháng đã chốt ghi thực tế (xám), tháng đang chạy tách 2 cột "đã lên đến dd/mm" và "FC từ dd/mm" (ô nhập); nạp lại vào app tự cộng phần đã lên.
- Nạp file FC Sale của team: tháng đã chốt bỏ qua số trong file (giữ khóa theo thực tế).

## Phiên bản 3.4 (10/11/2026) — đọc file FC Sale của team, xuất Excel theo mẫu

**Nạp FC từ file Excel của team (Admin → Kỳ & nạp dữ liệu → 5)**
- Nhận file FC Sale của team (`.xlsm`, sheet **FC Sale**) và file xuất từ app (sheet **FC Input**). Đọc 3 cột FC tháng (box) + Note/Note2, ghép theo MR × Cust Code × SKU.
- Kiểm tra quý của file (theo tên cột `FC Oct (box)`, `Target Q4'26`…): sai quý thì chặn.
- Tên REP khác tên trong app (vd "Hoang Phan" ↔ "Phan Cong Huy Hoang"): app tự đoán, hỏi lại và nhớ cho lần sau.
- Dòng FC trống / toàn 0: mặc định không ghi đè. Dòng toàn 0 có Note: ghi FC = 0 kèm ghi chú. Số box lẻ: làm tròn.
- Tùy chọn *Đồng bộ phân bổ account theo file* (mặc định bật): tạo dòng account × SKU còn thiếu, Sales ratio theo file, MR khác đang giữ cùng account × SKU về 0%.
- Tùy chọn *File là bản chốt*: dòng file để trống / toàn 0 thì xóa FC đang có trong app.
- Luôn hỏi xác nhận trước khi ghi (số dòng, tổng FC, MR đã nộp/duyệt bị thay số).

**Xuất Excel theo mẫu của team (Dashboard → Xuất Excel)**
- Sheet **FC Input**: cột giống sheet FC Sale (8 quý thực tế, target, FC tháng box, FC value, % đạt, % tăng trưởng, Note…), dòng tổng theo bộ lọc, cột nhập FC tô vàng. Sửa FC trong file rồi nạp lại được vào app.
- 5 sheet tổng hợp như pivot của mẫu: **RFFM_By Brand, RFFM_By Account, RFFM_By MR, MR_By Brand, MR_By Account**, có %Ach QTD, %Ach FC, % tăng trưởng; nhóm dòng mở/thu gọn; số là công thức SUMIFS trỏ về FC Input nên sửa FC trong Excel thì tự tính lại.
- Thêm sheet Tiến độ nộp, Demand plan SKU, SKUs (bảng giá cho công thức).
- Thư viện ExcelJS 4.4.0 tải từ jsDelivr khi bấm xuất.

## Phiên bản 3.3 (10/11/2026) — icon trên màn hình chính

- iPhone: Safari → nút Chia sẻ → **Thêm vào MH chính**. Icon `icons/apple-touch-icon.png`, tên dưới icon "FC CVRM", mở toàn màn hình như app (thanh trạng thái phủ màu navy, nội dung tránh tai thỏ).
- Android: Chrome → menu ⋮ → **Thêm vào màn hình chính / Cài đặt ứng dụng** (dùng `manifest.webmanifest`, icon 192/512 + bản maskable).
- Icon tab trình duyệt: `icons/favicon-32.png`.
- Mở từ màn hình chính là phiên riêng: lần đầu cần đăng nhập lại.

## Phiên bản 3.2 (10/11/2026) — nút Làm mới

- Nút **↻ Làm mới** trên thanh đầu trang (kèm giờ tải dữ liệu gần nhất): lưu nốt ô đang gõ rồi tải số mới nhất. Giữ nguyên tab, bộ lọc, vị trí cuộn.
- Quay lại tab app sau từ 1 phút trở lên: app tự làm mới (trừ tab Admin, khi đang mở hộp thoại, hoặc khi có ô lưu lỗi).
- Có ô lưu lỗi (mất mạng) mà bấm Làm mới: app hỏi lại trước để không mất số.

## Phiên bản 3.1 (10/11/2026) — cách hiển thị số

| Loại số | Cách hiển thị | Màu |
|---|---|---|
| % đạt target | Thanh tiến độ + số % (trong bảng: nhãn tròn có thanh nhỏ). Không dùng mũi tên. | Xanh ≥100% · vàng 80–99% · đỏ <80% |
| % đạt QTD | Như trên, thêm vạch đen = mốc tiến độ thời gian của quý | Màu so với mốc tiến độ, không so với 100% |
| Tăng trưởng (vs LYSP, vs quý trước) | Mũi tên + dấu: ↑ +14% / ↓ −22% | Xanh tăng · đỏ giảm |
| Thiếu / vượt target | −2.047 / +164 (triệu VND), thẻ ghi "còn thiếu… / vượt…" | Đỏ thiếu · xanh vượt |
| Độ chính xác FC | Nhãn viền | Xanh ≥85% · vàng 70–84% · đỏ <70% |
| Bias (FC lệch) | Số có dấu, màu trung tính | Cam khi lệch >10% |

- Thẻ KPI chia 2 nhóm: **So với target** (nền vàng nhạt) và **Tăng trưởng FC** (nền xanh nhạt). Cột trong bảng tô cùng màu nhóm.
- Thẻ KPI ở tab FC cập nhật ngay khi MR gõ số.

## Phiên bản 3 (10/11/2026)

**Target theo MR từ file Target Allocation của Bayer**
- Nạp nguyên file (ví dụ `2026Q4_Hospital_HCM_Target_Allocation_Send_Back_-_v2.xlsx`). App đọc sheet **Account**: REP · Cus. Code · Account · Product Name · Final Target · Volume Target. Các BU khác tự bỏ qua theo bảng giá SKU.
- Target gắn thẳng vào dòng MR × account × SKU, không chia theo Sales ratio. Account chia nhiều MR thì mỗi MR nhận đúng phần của mình.
- Tên REP trong file không khớp MR trong app (ví dụ `HCM Vacant 1`): app hỏi giao cho MR nào hoặc để "chưa giao MR". Lựa chọn được nhớ cho lần nạp sau.
- Tự tạo dòng FC cho MR có target nhưng chưa có dòng. Tùy chọn cập nhật Sales ratio theo tỷ trọng target.
- Kiểm tra kỳ theo tên file: nạp nhầm file của quý khác thì app chặn lại.
- Dashboard ghi rõ phần target chưa giao MR. Tab Account thiếu liệt kê target chưa có dòng FC.

## Phiên bản 2 (10/11/2026)

**Quy trình forecast**
- **Theo tháng:** actual từng tháng trong quý, ghi rõ tháng đã chốt / đang chạy / chưa tới, kèm ngày dữ liệu sales mới nhất (ví dụ "Sales đến 09/11").
- **Ước đạt cuối quý (Latest Estimate) và gap so với target:**
  - Tháng đã chốt lấy thực tế.
  - Tháng đang chạy lấy max(MTD, FC).
  - Tháng còn lại lấy FC.
- **Gợi ý FC:** trung bình box/tháng của 2 quý gần nhất, hiện mờ trong ô nhập. Nút **Điền theo gợi ý** điền sẵn cho các dòng chưa nhập.
- **Forecast theo ngoại lệ:**
  - Dòng có FC lệch quá 50% so với trung bình 2 quý (và từ 20 triệu/quý) bị gắn cờ, MR phải chọn lý do mới nộp được.
  - Có 9 lý do chuẩn: thầu, tồn kho, BHYT, đối thủ, listing mới, …
  - Ngưỡng % và ngưỡng giá trị chỉnh được trong Admin.
- **Quy trình duyệt:**
  - Trạng thái đi theo thứ tự: Chưa nộp → Đã nộp → Đã duyệt / Bị trả lại (có ghi chú).
  - RFFM/Admin duyệt hoặc trả lại. Sau khi duyệt, MR không sửa được nữa, trừ khi được mở lại.
  - App đánh dấu "có sửa sau nộp" nếu MR chỉnh sau khi đã nộp.
- **Độ chính xác FC:**
  - Mỗi quý chốt một bản FC, cuối quý so với thực tế.
  - Công thức: Độ chính xác = 1 − Σ|FC − thực tế| / Σ thực tế, tính ở mức account × SKU; Bias = FC / thực tế − 1.
  - Dòng có sales mà không FC được tính là FC = 0 (nhu cầu bị bỏ sót).
- **Đề xuất account/SKU:** MR đề xuất account mới, SKU mới (ví dụ sản phẩm sắp launch) hoặc account chuyển về mình. MR nhập FC được ngay, admin duyệt để thành dòng chính thức.

**Dashboard**
- Các chỉ số chính: Target, FC, Ước đạt, QTD, growth, tiến độ nộp/duyệt.
- Biểu đồ FC vs Target theo MR, biểu đồ theo quý và theo tháng.
- Bảng theo MR: kèm nút duyệt / trả lại.
- Bảng theo account: sắp xếp theo gap, target, mức giảm.
- Bảng theo brand / kênh.
- Bảng độ chính xác FC theo MR.
- Nút **Copy nhắc nộp FC**: tạo sẵn đoạn tin nhắn danh sách chưa nộp / bị trả lại để dán vào Teams/Zalo.
- **Xuất Excel** (RFFM/Admin), gồm các sheet:
  - FC Input (đủ cột tháng, ước đạt, lý do, người sửa)
  - Tổng hợp MR
  - **Demand plan SKU** (box theo tháng, cho supply chain).

## Vai trò

| Vai trò | Làm được |
|---|---|
| MR | Nhập FC account của mình, chọn lý do, nộp, đề xuất account/SKU. Chỉ xem dashboard và số của mình. |
| RFFM | Xem FC và dashboard cả team, duyệt / trả lại / mở lại, xuất Excel. Không sửa số. |
| ADMIN | Toàn quyền: nạp dữ liệu, đổi kỳ, khóa kỳ, chốt bản FC, phân bổ account, thành viên. |

Phân quyền chặn ở database (Row Level Security), đã test trên Postgres 16 + PostgREST:
- MR chỉ đọc được số của mình (bản 4): account, sales, target, FC, trạng thái nộp.
- MR không tự duyệt được, không ghi được dòng của MR khác, không sửa được sau khi đã duyệt hoặc khi kỳ đã khóa.
- RFFM không ghi được FC.
- Người ngoài danh sách team đọc 0 dòng.
- Mọi thay đổi FC đều được ghi vào `fc_history`.

## Nâng cấp từ bản 3 (đang chạy)

Supabase → **SQL Editor** → dán toàn bộ `migration_v4.sql` → **Run**. Không đổi dữ liệu, không cần nạp lại gì. Kết quả cuối file: 8 dòng `scoped read` + 3 dòng `member read`.

## Nâng cấp từ bản 1 hoặc 2 (đang chạy)

1. Supabase → **SQL Editor** → dán toàn bộ `migration_v3.sql` (đã gồm bản 2) → **Run**, sau đó chạy tiếp `migration_v4.sql`. Chạy lại nhiều lần không sao. Bước này giữ nguyên thành viên, giá, account, target, FC đã nhập và trạng thái nộp.
2. Mở app, Ctrl+Shift+R. Nếu còn thấy màn hình "Cần nâng cấp database" thì kiểm tra lại bước 1.
3. Vào Admin → Kỳ & nạp dữ liệu → **nạp lại Raw sales** (bản 2+ lưu sales theo tháng + số box) và **nạp file Target Allocation** của Bayer.
4. Vào Admin → FC lịch sử & chốt kỳ → nạp `3_FC_lich_su_Q3_2026.xlsx` để có ngay độ chính xác FC Q3'26.

## Cài mới

1. Tạo project Supabase (region Singapore).
2. **SQL Editor:** chạy `schema.sql`, nhớ sửa email + tên admin ở cuối file.
3. **Authentication → Providers → Email:** tắt *Allow new users to sign up*.
4. **Authentication → Users → Add user:** tạo tài khoản cho email admin, tick Auto Confirm.
5. **Project Settings → API:** copy Project URL + publishable (anon) key, dán vào `window.FC_CONFIG` trong `index.html`.
6. Đẩy `index.html` lên repo, bật **Settings → Pages** (branch `main`, `/ (root)`).
7. Quay lại Supabase → **Authentication → URL Configuration**, đặt Site URL = link GitHub Pages.

**Lưu ý:**
- Tuyệt đối không đưa *secret / service_role key* vào code.
- Email có sẵn của Supabase chỉ gửi được 2 email/giờ, nên admin tạo tài khoản kèm mật khẩu tạm trong Supabase. Lần đầu đăng nhập, người dùng phải đổi mật khẩu.

## Nạp dữ liệu (Admin → Kỳ & nạp dữ liệu)

Nạp theo thứ tự. Mỗi mục có nút *File mẫu*, và app tự dò cột theo tên tiêu đề.

1. **Bảng giá & SKU:** Brand · SKU · Giá/box (VND)
2. **Danh sách account × SKU × MR:** REP Name · Cust Code · Cust Name · Brand · SKU · Sales ratio · Kênh. Nhận được cả sheet FC Input của file Excel v2.
3. **Raw sales:** file export Power BI để nguyên. App lưu theo tháng và tự lấy ngày hóa đơn mới nhất.
4. **Target:** file Target Allocation của Bayer (sheet Account, có cột REP: target theo MR), hoặc file đơn giản Cust Code · SKU · Target quý FC (VND) (chia theo Sales ratio)
5. **FC lịch sử** (tab FC lịch sử & chốt kỳ): Kỳ (vd 2026Q3) · REP Name · Cust Code · SKU · Sales ratio · FC tháng 1–3 (box)

## Quy trình mỗi quý

1. **Admin mở kỳ:** Admin → Kỳ & nạp dữ liệu → đổi Năm/Quý + hạn nộp → Lưu. App hỏi có chốt bản FC kỳ cũ không, chọn **Đồng ý**.
2. **Admin nạp dữ liệu:** raw sales mới nhất và target. Xem tab **Account thiếu** và **Phân bổ account → Đề xuất chờ duyệt**.
3. **MR nhập FC:** dùng *Điền theo gợi ý* rồi chỉnh, chọn lý do cho dòng gắn cờ, rồi **Nộp FC**.
4. **RFFM duyệt:** duyệt / trả lại ở Dashboard → Theo MR. Dùng **Copy nhắc nộp FC** để nhắc người chưa nộp.
5. **Trong quý:** nạp raw sales mỗi tuần, theo dõi Ước đạt và gap, cho MR cập nhật FC tháng còn lại.
6. **Hết hạn:** tick **Khóa nhập** → **Chốt bản FC** → **Xuất Excel** (sheet Demand plan gửi supply chain).

## Backlog (đề xuất các bản sau)

| Ưu tiên | Hạng mục | Lý do |
|---|---|---|
| Cao | Rolling forecast 2 quý (quý này + quý sau) | Supply chain cần tầm nhìn 3–6 tháng để đặt hàng nhập khẩu |
| Cao | Theo dõi thầu: số lượng trúng thầu còn lại, ngày hết hạn thầu theo BV × SKU | Dự báo kênh bệnh viện phụ thuộc thầu; FC nên bị chặn trên bởi quota thầu |
| Cao | Module launch Firialta: danh sách BV mục tiêu, trạng thái listing/HĐT, đường uptake | Sản phẩm mới không có lịch sử nên gợi ý thống kê không dùng được |
| Trung bình | Tồn kho tại BV / nhà phân phối (sell-in vs sell-out) | Tránh FC cao khi BV còn tồn nhiều |
| Trung bình | Phạm vi RFFM theo nhóm MR, phân quyền MR chỉ xem tổng của người khác | Khi team lớn hơn hoặc có nhiều RFFM |
| Trung bình | Lịch sử chỉnh sửa từng dòng ngay trên app (đọc từ fc_history) | Giải trình khi FC thay đổi lớn |
| Thấp | Đăng nhập Bayer SSO (Entra ID), nhắc nộp qua email/Teams | Cần IT hỗ trợ |
| Thấp | Tự lấy raw sales từ Power BI thay vì upload tay | Cần quyền API/dataset |
