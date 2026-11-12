# FC Sale Team HCM — web app

App forecast doanh số theo quý cho team HCM (CVRM, WHC; kênh bệnh viện), thay cho file Excel dùng chung. Chạy trên GitHub Pages + Supabase.

## Phiên bản 4.12 (13/11/2026) — Type BV + kênh theo raw, New launch theo merge code

- **Type BV** (BV công / BV tư / Clinic) và **kênh** (Tender / Self-pay / Clinic) lấy theo Customer Local Group 1 Desc (hoặc Channel_name nếu raw không có cột này), Group 2, Group 3:
  - Clinic: Sub-dis clinics, Clinic Pharmacy (phòng khám, PKĐK) → kênh Clinic.
  - BV tư (Private entities) → kênh Self-pay (100%).
  - BV công (GOV'T. ENTITIES): Khoa Dược (VN:PharmacyDepartmnt, PMC Center) → Tender; Nhà thuốc BV (VN:Service Pharmacy) → Self-pay.
  - Mã chưa có trong raw: mã NTBV / mã phụ lấy type của mã gốc merge code (mã gốc chưa có thì lấy từ mã NTBV cùng account); còn lại đoán theo tên (PK / PM / Phòng khám → Clinic, Nhà thuốc → Self-pay, Khoa Dược → Tender). NTBV nằm trong merge code của BV nhưng raw ghi Sub-dis clinics (vd NT BV FV, NT BV ĐK Nhà Bè) tính theo BV, kênh Self-pay.
  - Kênh theo raw đè lên cột Tender/Self-pay của file account; Admin → Phân bổ account chỉ cho chọn tay khi mã chưa có trong raw.
- **Dashboard Overview:** By channel tách từng brand (sales 4 quý, QTD, FC, % FC, Gr vs LYSP, Gr vs quý trước), không %Ach vì target giao theo account. Bảng mới **By type BV** (có target, %Ach) tách brand.
- **FC Input:** chip kênh Tender / NTBV / Self-pay / Clinic theo raw, ghi type BV cạnh mã KH.
- **Excel:** FC Input thêm cột Type BV, cột Tender/Self-pay có thêm Clinic; 2 sheet pivot mới RFFM_By Channel, RFFM_By Type BV (kênh / type × brand).
- **New launch:** BV gộp theo merge code (dòng merge → mã Tender (gốc) → mã NTBV → SKU; điện thoại: khung merge chứa thẻ từng mã), tổng merge cập nhật khi nhập. Dashboard New launch By BV cũng theo merge code. Gov / Priv / Clinic ở New launch đổi tên thành **Type BV** cho khỏi lẫn với kênh.
- Raw nạp lần sau tự cập nhật danh mục khách hàng (log ghi số mã theo type và kênh). Không cần migration.

## Phiên bản 4.11 (12/11/2026) — Bảng Forecast theo brand, sửa file Excel, gọn Dashboard

- **Sửa lỗi file Excel xuất từ Dashboard:** Excel báo file hỏng, sau khi sửa thì 5 sheet pivot (RFFM_By Brand, RFFM_By Account, RFFM_By MR, MR_By Brand, MR_By Account) trống. Nguyên nhân: thư viện ExcelJS ghi thẻ thiết lập in trước thẻ outline ở các sheet này, sai thứ tự chuẩn của Excel (LibreOffice / Google Sheets bỏ qua nên không thấy). Các sheet pivot giờ in theo tỉ lệ 70% thay cho "vừa 1 trang ngang"; file đã kiểm tra theo schema chuẩn của Excel.
- **Overview → bảng Forecast Q4-2026 theo brand** (theo mẫu báo cáo RFFM; chọn Cả 2 team để có đủ CVRM + WHC): Act. Q4'25 · Act. FY25 · QTD · YTD Q3'26 · Target Q4'26 (gồm phần chưa giao MR) · Target FY26 · từng tháng (Act. / Act. + FC / FC) · %Ach FC Q4 · Gr vs Q4'25 · %Ach FC FY (= (YTD + FC Q4) / Target FY) · Gr vs FY25. Có New launch (Firialta, Qlaira). Nút **⬇ Excel** tải riêng bảng này (số VND, công thức %, dòng Grand Total) để đưa vào báo cáo. Admin bấm **Nhập Target FY** để nhập target năm theo brand (lưu ở bảng targets, kỳ `2026FY`, không cần chạy migration).
- **FC Input:** tên app "FC Sale Team HCM". Không submit được khi còn dòng cần lý do **hoặc** dòng có sales / target chưa nhập FC (không có đơn thì nhập 0); app tự lọc ra các dòng đó. New launch xếp BV theo kênh Gov → Priv → Clinic, mỗi kênh có dòng tiêu đề.
- **Dashboard:** Overview đưa bảng Forecast, By brand, By channel lên đầu; bỏ dòng "Cách đọc". By MR bỏ cột Gap vs target, FC vs TB 2Q, Account rủi ro, Gap ở các account; thêm Gr vs quý trước. Chi tiết account: theo brand (không theo SKU), cột Kênh BHYT / Self-pay; account merge có dòng tổng brand (target, %Ach) rồi từng kênh.

## Phiên bản 4.10 (12/11/2026) — Merge code: tính theo account Bayer

Bayer giao target theo account (merge code), không theo kênh. App gộp mã Khoa Dược (tender / BHYT) và mã NTBV của cùng một BV thành 1 merge code theo cách của Commex: mã Khoa Dược là merge code, mã NTBV / dịch vụ gộp vào.

- **FC Input:** mỗi account 1 dòng merge code (target, FC, %Ach, growth của cả account) → bên dưới là dòng mã Tender (mã gốc) rồi mã NTBV → các SKU. MR vẫn nhập FC theo từng mã như cũ.
- **Target, %Ach, growth, cảnh báo lệch TB 2Q, "chưa nhập"** tính theo MR × merge code × SKU (cộng các mã). Số hiện ở dòng SKU của mã gốc, dòng mã còn lại ghi "·". Cảnh báo và lý do chỉ cần 1 lần ở dòng mã gốc, có ghi "(merge code)". Chuyển FC giữa Tender và NTBV không còn bị cảnh báo sai.
- **Cả team, Dashboard (By account, Risk), chi tiết account, Excel** (cột Merge Code · Merge Name ở FC Input, RFFM_By Account / MR_By Account gộp theo merge code, Risk accounts có cột các mã KH) đều theo merge code.
- **Admin → Kỳ & nạp dữ liệu → Merge code:** nạp file *Mapping Channel* của Commex (Customer Code · Merge Code2 · Merge Name 1) hoặc file tải từ nút *File mẫu* (Merge Code · Merge Name · Customer Code · Customer Name · Nguồn · Ghi chú). Nạp = thay toàn bộ danh sách. Muốn sửa: tải file mẫu (là danh sách đang dùng), sửa, nạp lại.
- **DB bản 8** (`migration_v8.sql`): bảng `cust_merge` (thành viên đọc, chỉ admin ghi).

## Phiên bản 4.9.1 (12/11/2026) — Phân bổ New launch

- **Admin → Phân bổ account** có cả dòng New launch: lọc "New launch", sửa MR / ratio / kênh Gov · Priv · Clinic từng dòng, cảnh báo khi tổng ratio ≠ 1.
- New launch: BV chưa có FC xếp theo quy mô In-market của account (target / TB 2Q), account lớn lên trước.

## Phiên bản 4.9 (12/11/2026) — New launch: Firialta (CVRM), Qlaira (WHC)

- **FC Input → New launch** (nút In-market / New launch cạnh tiêu đề): FC cho sản phẩm chưa có target. MR tự thêm BV / phòng khám (chọn trong danh mục khách hàng, hoặc gõ tên BV mới, app tạo mã tạm `NEW-…`), chọn SKU, nhập box theo tháng như In-market. Không tính %Ach, không cờ rủi ro; FC New launch vẫn nằm trong bản submit của MR. Admin thêm BV cho MR bất kỳ ở Cả team.
- **Kênh Gov / Priv / Clinic** từng BV: tự lấy theo raw sales (Customer Local Group 3 Desc: GOV'T → Gov · Private → Priv; Channel_name hoặc Group 2 có "clinic" → Clinic), MR đổi được.
- **Dashboard → New launch** (RFFM / Admin): tổng FC, By channel (tiền, box, BV có FC, kênh × SKU), By month (tr VND), By MR (bấm tên mở FC New launch của MR đó), By BV / phòng khám (lọc kênh, tìm). MR có thẻ New launch ở Dashboard của tôi.
- **Excel:** thêm sheet *New launch* (từng dòng) và *New launch_Summary* (by channel / MR / SKU). Demand plan SKU gồm cả SKU New launch; các sheet In-market không lẫn New launch.
- **Admin → Thành viên & giá:** cột New launch. SKU New launch chưa có giá vẫn lưu được (FC chỉ có box). File Bảng giá nhận thêm cột "New launch" (x / 1 / có).
- Nạp danh sách account "Thay toàn bộ": giữ dòng New launch MR đã thêm (file không có SKU đó) và giữ kênh MR đã chọn.
- **DB bản 7** (`migration_v7.sql`): cột `prices.launch`, `mapping.segment`, bảng `customers`; MR chỉ thêm / đổi kênh / xoá BV New launch của chính mình, khi kỳ còn mở và chưa được duyệt.

## Phiên bản 4.8.2 (12/11/2026) — Dashboard By MR: bảng theo brand + growth

- Bảng "%Ach FC by MR × SKU" đổi thành **By MR × brand**: mỗi brand (và cột Tổng) có 3 cột %Ach FC · Gr LYSP · Gr quý trước. Gr = FC quý FC so với sales cùng kỳ năm trước / sales quý trước. Brand xếp theo target. Rê chuột vào ô để xem số FC, target, sales so sánh.

## Phiên bản 4.8.1 (11/11/2026) — Rà giao diện lượt 2

- **Laptop 1280–1366:** bảng FC Input vừa màn hình, không cuộn ngang (lề ô, cột Note, Lý do gọn lại ở khổ này).
- **Admin:** tab con (Kỳ & nạp dữ liệu, FC lịch sử, Account thiếu, Phân bổ, Thành viên & giá) dùng cùng kiểu tab với Dashboard; trên điện thoại vuốt ngang thay vì 4 hàng nút. Ô nhập, ô chọn trong bảng Phân bổ / Thành viên / Giá bo góc, cùng kiểu app; nút Xóa từng dòng nhạt, đỏ khi rê chuột. Form Kỳ FC trên điện thoại 1 cột.
- **Dashboard trên điện thoại:** 3 ô lọc + nút Excel còn 2 hàng; thẻ FC đứng đầu, Target và Act. QTD chung 1 hàng.
- **FC Input Cả team trên điện thoại:** ghi chú Cả team còn 1 dòng.
- **Chung:** viền focus rõ khi dùng bàn phím; tôn trọng chế độ giảm chuyển động; màn hình đăng nhập không dính mép trên điện thoại.

## Phiên bản 4.8 (11/11/2026) — Giao diện gọn, dễ nhập hơn

- **FC Input gọn:** các thẻ KPI gom thành 1 dải (Target · FC + %Ach · Act. QTD vs phasing · Growth · Việc cần xử lý). Bấm **Chi tiết** để mở lại thẻ đầy đủ và 3 tháng; app nhớ lựa chọn trên từng máy. Bấm "N dòng cần lý do" / "dòng có lịch sử chưa nhập" để lọc ngay các dòng đó. Bảng nhập lên ngay màn hình đầu (máy tính: ô nhập đầu tiên từ y≈870 lên ≈460).
- **Bảng nhập:** mặc định ẩn 3 quý cũ (LYSP … Q-2), giữ quý gần nhất, QTD, Target, TB 2Q; nút "Hiện Q4'25–Q2'26" mở lại. Màn hình 1440 không còn cuộn ngang, thấy cột Note. **Enter / ↓** xuống ô cùng tháng ở dòng dưới, **Shift+Enter / ↑** lên dòng trên; vào ô là chọn sẵn số cũ để gõ đè; dòng đang nhập được tô sáng.
- **Điện thoại:** header 2 hàng (tên ngắn "FC Sale", chip ngày gói 1 hàng); nút Submit / Duyệt / Trả lại nằm ở thanh cố định đáy màn hình; thanh lọc 2 hàng; ô nhập đầu tiên nằm trong màn hình đầu (trước đây phải cuộn khoảng 2 màn hình). Dashboard: 2 ô lọc chung 1 hàng.
- **Chung:** nhãn nhóm KPI không viết hoa toàn bộ; màu chữ chính đổi sang navy đậm cho hợp màu app; form Admin → Kỳ FC & quy tắc xếp theo ô, nút chọn file đồng bộ kiểu nút của app; thẻ Admin không còn kéo giãn khoảng trống. Tooltip trên điện thoại chỉ hiện khi chạm, không còn treo ở góc màn hình.
- Không đổi chức năng, số liệu, tên cột. Test mới: `test_ui48.py`.

## Phiên bản 4.7.1 (11/11/2026) — FC Input xếp account từ lớn đến bé

- FC Input (từng MR và Cả team, máy tính và điện thoại): account xếp từ lớn đến bé, SKU trong account cũng vậy. Quy mô = số lớn hơn giữa target quý FC và TB sales 2 quý gần nhất, nên thứ tự đứng yên trong quý, không nhảy khi MR nhập FC. Account mới chưa có target, chưa có sales nằm cuối.

## Phiên bản 4.7 (11/11/2026) — 2 team: CVRM và WHC

- **Ô Team ở header** (CVRM / WHC / Cả 2 team) cho người xem được cả 2 team (ADMIN, RFFM để Team = Cả 2 team). Áp cho FC Input, Dashboard, Admin; app nhớ lựa chọn trên từng máy. MR chỉ thấy team của mình, không có ô Team.
- **2 ô nạp raw sales** ở Admin → Kỳ & nạp dữ liệu: "Raw sales CVRM" và "Raw sales WHC". Mỗi ô chỉ lấy SKU của team đó, chỉ thay sales của team đó, lưu ngày dữ liệu riêng và tự trừ sales vào FC của đúng team.
- **Ngày dữ liệu riêng từng team**: tháng đã chốt / đang chạy, "FC từ ngày …", phasing tính theo ngày dữ liệu của team. Cả 2 team: mỗi dòng theo team của nó; header ghi "Sales CVRM dd/mm · WHC dd/mm"; nhãn chung lấy ngày sớm hơn; phasing bình quân theo quy mô sales từng team. Xem 1 MR thì theo team của MR đó.
- **Nạp giá, account, target, file FC, FC lịch sử theo Team đang chọn ở header**: chỉ thay dữ liệu của team đó ("Thay toàn bộ" account chỉ xoá dòng của team đó; target chỉ thay target của team đó). Đang chọn Cả 2 team thì các ô này khoá, nhắc chọn 1 team.
- **Thành viên & giá**: thêm cột Team (MR: CVRM / WHC; ADMIN, RFFM: Cả 2 team). Dán danh sách từ Excel nhận thêm cột Team. Bảng giá có cột Team cho từng SKU.
- **Kỳ FC, deadline, khoá nhập, quy tắc cảnh báo dùng chung 2 team.** REP Group trong raw khai riêng từng team (mặc định CVRM, WHC).
- Excel xuất theo team đang chọn (FC_Sale_WHC_HCM_…, FC_Sale_CVRM_WHC_HCM_… khi xem Cả 2 team).
- **Cần làm 1 lần:** Supabase → SQL Editor → dán toàn bộ `migration_v6.sql` → Run (database của team đã chạy). Dữ liệu đang có thành CVRM, ADMIN / RFFM thành Cả 2 team.

## Phiên bản 4.6 (11/11/2026) — Tăng tốc tải và vẽ

- **Làm mới / mở app nhanh hơn ~3 lần**: kiểm tra cấu trúc database 1 lần mỗi phiên (trước: 6 request nối tiếp mỗi lần tải); bảng lớn (raw sales ~3,900 dòng) tải các trang 1000 dòng song song, xếp theo khoá chính nên không trùng / sót dòng. Đo với độ trễ ~110 ms mỗi request: Làm mới 1.4 s → 0.5 s.
- **Thư viện Excel (~0.9 MB) chỉ tải khi cần** (nạp file, tải file mẫu): mở app không phải chờ tải thư viện.
- **FC Input · Cả team**: vẽ trước 50 account lớn nhất (theo target); nút "Xem thêm" / "Hiện tất cả" nối tiếp vào bảng, giữ vị trí cuộn. Subtotal, KPI vẫn tính đủ mọi dòng theo bộ lọc; đổi bộ lọc / tìm kiếm thì quay về 50 account đầu. Điện thoại: vẽ Cả team 0.7 s → 0.35 s.
- Dữ liệu hiện tại nhỏ so với gói Free: database 13 MB / 500 MB; mỗi lần admin tải ~1 MB, MR tải ít hơn nhiều.
- Không đổi dữ liệu, không cần chạy SQL.

## Phiên bản 4.5 (11/11/2026) — Tự trừ sales mới vào FC; TB 2Q

- **Tự trừ sales mới vào FC, giữ FC quý từng dòng**: Admin nạp raw sales mới (Admin → 3. Raw sales, ô "Tự trừ sales mới vào FC của team" tick sẵn) → app giữ nguyên FC quý (box) của từng dòng MR đã nhập, phần chênh tự dời sang tháng còn lại. MR không phải sửa lại nếu tình hình đặt hàng không đổi.
  - Trong tháng đang chạy, sales chưa vượt FC tháng: như cũ, FC cả tháng giữ nguyên, phần "FC từ ngày …" tự giảm theo đơn mới lên.
  - Sales tháng vượt FC tháng (đơn tháng sau lên sớm, hoặc tháng chốt cao hơn FC): trừ vào tháng còn lại gần nhất, vd Nov vượt FC 30 box → Dec −30. Tháng đang chạy không xuống dưới đơn đã lên, tháng tới không xuống dưới 0; vượt cả FC quý thì FC quý tăng theo sales.
  - Tháng chốt thấp hơn FC (đơn trễ sang tháng sau): phần thiếu cộng vào tháng còn lại gần nhất, vd Nov chốt thấp hơn FC 20 box → Dec +20. Đơn mất thật thì MR sửa lại.
  - Dòng chưa nhập FC, dòng có người sửa đúng lúc nạp: để nguyên. File có ngày dữ liệu cũ hơn bản đang có, hoặc sales quý thấp hơn bản đang có quá 3% (file thiếu dữ liệu): không dời, log ghi lý do.
  - MR thấy dấu **↻** dưới SKU (rê chuột / chạm để xem các lần dời), dòng ghi chú đầu trang và bộ lọc "Tự dời theo sales"; sửa số tháng của dòng đó thì dấu mất. Cả team: dấu ↻ ở dòng account × SKU.
  - Không tính là "có sửa sau submit"; trạng thái submit / duyệt giữ nguyên. Lịch sử FC (`fc_history`) ghi `src = auto`. Log nạp ghi số dòng, số MR, số box dời theo tháng.
- **TB 2Q** thay Est. 2Q trên Dashboard RFFM / Admin: TB sales quý của 2 quý gần nhất, cùng mốc với cảnh báo "FC lệch TB 2Q" ở FC Input. Tín hiệu "FC > TB 2Q", "Target > TB 2Q" và cột "FC vs TB 2Q" dùng mốc này.
- Bỏ số gợi ý mờ trong ô nhập FC; nút "Điền theo TB 2Q" vẫn giữ.
- **Cần làm 1 lần:** Supabase → SQL Editor → dán toàn bộ `migration_v5.sql` → Run (database của team đã chạy). Chưa chạy thì app vẫn dùng bình thường, chỉ chưa tự trừ sales vào FC; Admin thấy dòng nhắc màu vàng.

## Phiên bản 4.4 (11/11/2026) — Admin sửa số ở Cả team; sửa xoay ngang trên iPhone

- **Cả team, admin sửa số tổng**: ô tháng (tháng đang chạy: FC từ ngày sau ngày dữ liệu; tháng tới: FC cả tháng) cho admin nhập số box tổng của account × SKU. App chia cho từng MR theo tỷ trọng ratio, làm tròn box mà tổng vẫn đúng số nhập (vd 1000 box, ratio 0.2 / 0.5 / 0.3 → 200 / 500 / 300; 3 MR × 0.33 → 334 / 333 / 333), ghi đè số tháng đó của từng MR và tự lưu. Tháng đang chạy: phần đã lên của từng MR giữ nguyên, chỉ chia phần FC còn lại. RFFM xem Cả team vẫn chỉ xem.
- Sửa ở Cả team là sửa FC của từng MR: MR đã submit sẽ hiện "có sửa sau submit".
- **iPhone xoay ngang**: Safari không tự phóng to chữ nữa (text-size-adjust); cột Account / SKU xuống dòng, trên màn hình nhỏ rộng 180–220px; màn hình thấp (≤ 520px) thì header không dính, bảng cao gần hết màn hình.

## Phiên bản 4.3 (11/11/2026) — FC Input: Cả team, Subtotal; sửa header mờ trên iPhone

- **Cả team** (RFFM / Admin): ô MR ở tab FC Input thêm lựa chọn "Cả team". Số các MR cộng lại theo account × SKU, ra full sale account (không chia ratio). Dòng nhiều MR hiện tên MR + ratio; bấm tên để mở FC của MR đó. Chỉ xem; nhập, submit, duyệt vẫn ở từng MR.
- **Địa bàn**: ở Cả team, ô "Địa bàn" chọn 1 MR → các account × SKU MR đó giữ, số đủ của mọi MR (full sale địa bàn). Ô tìm kiếm nhận tên account, mã KH, SKU, tên MR. Chọn từng MR ở ô trên thì số vẫn theo ratio của MR đó.
- **Subtotal** ở đầu bảng, theo bộ lọc đang chọn: Act. 4 quý, QTD, Target, FC từng tháng (tr), FC quý, %Ach, Gr vs LYSP, Gr vs quý trước, số dòng cần lý do. Dính ngay dưới tiêu đề khi cuộn; trên điện thoại là thanh dính đầu danh sách. Gõ FC là Subtotal và dòng account tự cập nhật.
- **Header mờ trên iPhone (iOS 26)**: iOS 26 bỏ `theme-color`, lấy màu status bar từ phần tử fixed ở mép trên trang, không có thì phủ lớp mờ theo màu nền xám. Thêm dải navy cố định sau status bar để status bar lấy màu navy.

## Phiên bản 4.2 (11/11/2026) — Thuật ngữ & thông số Bayer

Toàn bộ chữ trên app (FC Input, Dashboard MR / RFFM / Admin, Admin, file Excel xuất) dùng cách gọi của team và file Target Allocation / FC Sale:
- **Số**: thập phân dấu chấm, nghìn dấu phẩy (1.3 · 28.64 tỷ · 1,852 tr). Ngày dd/mm/yyyy, giờ 24h.
- **Chỉ số**: %Ach FC · %Ach QTD · Gr vs LYSP · Gr vs Q3'26 · Gap vs target · Act. / Act. QTD · FC remain · TB 2Q (box/tháng).
- **Phasing** thay "mốc mùa vụ": %Ach QTD so với phần sales quý thường đạt tới ngày dữ liệu (vd 32% tới 09/11).
- **Est. 2Q** thay "Nhịp 2Q": Act. QTD + TB sales quý của 2 quý gần nhất × phần quý còn lại theo phasing. Không gọi là run rate vì run rate dùng cho quota thầu.
- **Kênh**: Khoa Dược (tender), NTBV (self-pay), Other; xếp theo thứ tự này. Dữ liệu gốc vẫn là Tender / Self-pay / Other.
- **Trạng thái**: Chưa submit · Đã submit, chờ duyệt · Đã duyệt · Trả lại. Nút Submit FC / Submit lại. Ghi chú → Note.
- **Lý do điều chỉnh FC**: Thầu mới / first order · Out of quota / gap thầu · MSBS 30% / stock up quota (mới) · Tồn kho BV cao / sell-out chậm · Vượt quỹ BHYT / khoá thuốc · Gx / đối thủ gain share · Listing mới / BS mới kê toa · BS ngưng kê / BS nghỉ · Thay đổi ratio / phân bổ account · Khác (ghi rõ ở Note). Lý do đã chọn ở bản cũ tự đổi sang nhãn mới (database và file Excel cũ).
- **Dashboard RFFM/Admin**: tab Overview · By MR · By account · Risk & issue; nhóm issue Thầu / quota, Tồn kho, Vượt quỹ BHYT / khoá thuốc, Gx / đối thủ, NTBV / self-pay, HCP / listing; SKU viết gọn Xa20 · Xa15 · Xa10 · Xa2.5 · Adalat LA 30; Sales ratio dạng 0.6. Bridge target → FC ghi rõ phần bù từ account vượt target và từ account không có target.
- **Excel xuất**: cột theo mẫu team (Act. sales Qn'yy, %Ach QTD, %Ach FC, % Growth, Note); sheet Tracking submit và Risk accounts (thay Tiến độ nộp, BV rủi ro). File xuất từ bản cũ vẫn nạp lại được.
- Không cần chạy SQL.

## Phiên bản 4.1 (11/11/2026) — Dashboard RFFM / Admin nhiều góc nhìn

Dashboard của RFFM/Admin chia 4 tab, dùng chung bộ lọc MR / Brand / Kênh:
- **Tổng quan**: KPI; 4 thẻ cần chú ý (BV rủi ro cao, MR thiếu target, FC cần kiểm tra, vấn đề MR ghi nhận); cầu nối Target → FC (vượt ở BV nào, thiếu ở BV nào, FC ở BV không có target); FC vs target theo MR; theo quý, theo tháng, brand, kênh.
- **Theo MR**: bảng MR thêm % đạt QTD theo mốc mùa vụ, FC so với nhịp bán, số BV rủi ro, phần thiếu ở các BV (không bù trừ BV vượt); duyệt / trả lại tại đây; heatmap % đạt target MR × SKU.
- **Theo bệnh viện**: ma trận quy mô × % đạt (tô vùng BV trọng điểm dưới target), mức độ tập trung (bao nhiêu BV tạo 80% target), bảng BV có nhịp 2Q, FC vs nhịp, mức rủi ro, ghi chú; bấm BV để xem chi tiết từng SKU, xu hướng 5 quý, ghi chú của MR.
- **Rủi ro & vấn đề**: danh sách BV theo mức Cao / Trung bình / Theo dõi kèm tín hiệu (thiếu target, FC cao hơn nhịp, chưa có đơn, ngưng đơn, chưa nhập FC, giảm vs cùng kỳ) và ghi chú MR; nhóm vấn đề tự gom từ lý do + từ khóa trong ghi chú (thầu/quota, tồn kho, BHYT, đối thủ/generic, đặt hàng/công nợ, BS/listing); nút copy tóm tắt cho họp.
- **Mốc mùa vụ**: đơn BV dồn cuối quý (TB các quý gần nhất: tháng 1 ≈ 22%, tháng 2 ≈ 33%, tháng 3 ≈ 45% doanh số quý), nên % đạt QTD so với phần doanh số thường đạt tới ngày dữ liệu, không so với % thời gian đã qua.
- **Nhịp 2Q** = thực tế tới ngày dữ liệu + TB doanh số quý của 2 quý gần nhất × phần quý còn lại theo mùa vụ: mức BV sẽ đạt nếu mua như 2 quý gần nhất, dùng để kiểm tra FC.
- File Excel xuất thêm sheet **BV rủi ro** (mức, tín hiệu, nhóm vấn đề, ghi chú MR).
- MR vẫn chỉ thấy dashboard của mình. Không cần chạy SQL.

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
| MR | Nhập FC account của mình, chọn lý do, nộp, đề xuất account/SKU, thêm BV / phòng khám New launch. Chỉ xem dashboard và số của mình. |
| RFFM | Xem FC và dashboard cả team, duyệt / trả lại / mở lại, xuất Excel. Không sửa số. |
| ADMIN | Toàn quyền: nạp dữ liệu, đổi kỳ, khóa kỳ, chốt bản FC, phân bổ account, thành viên. |

Phân quyền chặn ở database (Row Level Security), đã test trên Postgres 16 + PostgREST:
- MR chỉ đọc được số của mình (bản 4): account, sales, target, FC, trạng thái nộp.
- MR không tự duyệt được, không ghi được dòng của MR khác, không sửa được sau khi đã duyệt hoặc khi kỳ đã khóa.
- New launch (bản 7): MR chỉ thêm / đổi kênh / xoá dòng SKU New launch của chính mình; không tự thêm được dòng SKU có target (vẫn qua Đề xuất account).
- Merge code (bản 8): mọi thành viên đọc được, chỉ admin nạp / sửa.
- RFFM không ghi được FC.
- Người ngoài danh sách team đọc 0 dòng.
- Mọi thay đổi FC đều được ghi vào `fc_history` (lần app tự trừ sales vào FC ghi `src = auto`, chỉ admin chạy được).

## Nâng cấp từ bản 7 (đang chạy)

1. Supabase → **SQL Editor** → dán toàn bộ `migration_v8.sql` → **Run**. Kết quả cuối file: `db_version = 8`. Không đổi dữ liệu đang có.
2. Admin → Kỳ & nạp dữ liệu → **Merge code**: nạp file Mapping Channel của Commex hoặc file merge đã rà.

## Nâng cấp từ bản 6 (đang chạy)

1. Supabase → **SQL Editor** → dán toàn bộ `migration_v7.sql` → **Run**. Kết quả cuối file: `db_version = 7`. Không đổi dữ liệu đang có.
2. Admin → **Thành viên & giá**: tick **New launch** cho Qlaira; thêm 2 SKU Firialta đúng tên trong raw (chưa có giá thì để trống), tick New launch → Lưu.
3. Admin → Kỳ & nạp dữ liệu: nạp lại **Raw sales** từng team để app có danh mục khách hàng và tự điền kênh Gov / Priv / Clinic.
4. Làm tiếp phần Nâng cấp từ bản 7.

## Nâng cấp từ bản 5 (đang chạy)

Supabase → **SQL Editor** → dán toàn bộ `migration_v6.sql` → **Run**. Dữ liệu đang có thành team CVRM, ADMIN / RFFM xem cả 2 team. Kết quả cuối file: `db_version = 6`, danh sách team. Sau đó làm tiếp phần Nâng cấp từ bản 6.

## Nâng cấp từ bản 4 (đang chạy)

Supabase → **SQL Editor** → dán toàn bộ `migration_v5.sql` → **Run** (kết quả `db_version = 5`, `cot_moi = 2`), rồi chạy tiếp `migration_v6.sql`, `migration_v7.sql`, `migration_v8.sql`.

## Nâng cấp từ bản 3 (đang chạy)

Supabase → **SQL Editor** → dán toàn bộ `migration_v4.sql` → **Run** (kết quả cuối file: 8 dòng `scoped read` + 3 dòng `member read`), rồi chạy tiếp `migration_v5.sql`, `migration_v6.sql`, `migration_v7.sql`, `migration_v8.sql`. Không đổi dữ liệu, không cần nạp lại gì.

## Nâng cấp từ bản 1 hoặc 2 (đang chạy)

1. Supabase → **SQL Editor** → dán toàn bộ `migration_v3.sql` (đã gồm bản 2) → **Run**, sau đó chạy tiếp `migration_v4.sql`, `migration_v5.sql`, `migration_v6.sql`, `migration_v7.sql`, `migration_v8.sql`. Chạy lại nhiều lần không sao. Bước này giữ nguyên thành viên, giá, account, target, FC đã nhập và trạng thái nộp.
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

Nạp theo thứ tự. Mỗi mục có nút *File mẫu*, và app tự dò cột theo tên tiêu đề. Chọn Team (CVRM hoặc WHC) ở header trước khi nạp giá, account, target, file FC: dữ liệu ghi cho team đó, không đụng team kia.

1. **Bảng giá & SKU:** Brand · SKU · Giá/box (VND) · New launch (tuỳ chọn: x cho SKU chưa có target)
2. **Danh sách account × SKU × MR:** REP Name · Cust Code · Cust Name · Brand · SKU · Sales ratio · Kênh. Nhận được cả sheet FC Input của file Excel v2.
3. **Raw sales** (mỗi team 1 ô: CVRM, WHC): file export Power BI để nguyên. App lưu theo tháng và tự lấy ngày hóa đơn mới nhất. Tick sẵn "Tự trừ sales mới vào FC": giữ FC quý từng dòng, phần sales vượt / thấp hơn FC tháng tự dời sang tháng còn lại (bản 4.5). Mỗi lần nạp, app cập nhật danh mục khách hàng và kênh Gov / Priv / Clinic dùng cho New launch (bản 4.9).
4. **Target:** file Target Allocation của Bayer (sheet Account, có cột REP: target theo MR), hoặc file đơn giản Cust Code · SKU · Target quý FC (VND) (chia theo Sales ratio)
5. **Merge code:** file Mapping Channel của Commex hoặc file mẫu (Merge Code · Merge Name · Customer Code). Nạp = thay toàn bộ.
6. **FC lịch sử** (tab FC lịch sử & chốt kỳ): Kỳ (vd 2026Q3) · REP Name · Cust Code · SKU · Sales ratio · FC tháng 1–3 (box)

## Quy trình mỗi quý

1. **Admin mở kỳ:** Admin → Kỳ & nạp dữ liệu → đổi Năm/Quý + hạn nộp → Lưu. App hỏi có chốt bản FC kỳ cũ không, chọn **Đồng ý**.
2. **Admin nạp dữ liệu:** raw sales mới nhất và target. Xem tab **Account thiếu** và **Phân bổ account → Đề xuất chờ duyệt**.
3. **MR nhập FC:** dùng *Điền theo gợi ý* rồi chỉnh, chọn lý do cho dòng gắn cờ, rồi **Nộp FC**.
4. **RFFM duyệt:** duyệt / trả lại ở Dashboard → Theo MR. Dùng **Copy nhắc nộp FC** để nhắc người chưa nộp.
5. **Trong quý:** nạp raw sales mỗi tuần. App tự trừ sales mới vào FC (giữ FC quý); MR chỉ sửa dòng có thay đổi về đặt hàng (xem dấu ↻). Theo dõi %Ach, gap vs target trên Dashboard.
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
