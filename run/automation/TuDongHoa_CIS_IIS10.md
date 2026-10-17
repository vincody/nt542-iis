# Tự động hóa CIS Microsoft IIS 10: Audit → Remediate → Report

> File này đi kèm `..\manual\HuongDan_CIS_IIS10.md`. Hướng dẫn kia mô tả **từng tiêu chí riêng lẻ**; file này nói về **cách chạy tự động**, theo hai kiểu dùng chung một bộ code:
> - **Chạy một lần cả 7 phần:** `scripts\IIS-CIS.ps1`.
> - **Chạy riêng từng phần (1 đến 7):** mỗi phần có thư mục riêng với `Audit.ps1` và `Remediate.ps1`.
>
> **Mức kiểm chứng (đọc kỹ):** toàn bộ script đã được (1) kiểm tra cú pháp trên Windows PowerShell 5.1 và (2) chạy thử trên **IIS và registry giả lập** (mock): từng phần (Audit rồi Remediate rồi Audit lại), script chạy một lần (Audit → Remediate đợt 1, 2, 3 → Audit lại → Report), `-WhatIf`, id không tồn tại, và phần 6 (chỉ có mục Manual). Nó **chưa được chạy trên một máy IIS thật**; việc các lệnh `WebAdministration` thật có hành xử đúng như mô phỏng hay không thì chỉ chạy trên VM mới biết. **Hãy snapshot VM trước khi chạy Remediate.**

> ## ⚠️ Cảnh báo: KHÔNG chạy trên máy chính
>
> Các lệnh và script trong tài liệu này **sửa cấu hình hệ thống**: IIS, `machine.config`, registry SCHANNEL (tắt TLS 1.0/1.1, đổi thứ tự cipher), thư mục log, quyền truy cập. Chúng có thể làm các site hoặc kết nối mạng ngừng hoạt động, và một số thay đổi cần **khởi động lại** máy.
>
> - **Chỉ chạy trong máy ảo (VM) dành riêng cho bài lab** (Windows Server 2022 Desktop), và **chụp snapshot trước khi sửa** để quay lại được.
> - **Không chạy trên máy cá nhân hoặc máy đang dùng cho việc khác.** Đặc biệt đừng chạy `01-Seed-Baseline.ps1` ngoài VM vì nó cố tình làm yếu cấu hình.
> - Chỉ **kiểm tra (Audit)** thì an toàn hơn vì chỉ đọc; còn **sửa (Remediate)** thì không. Dùng `-WhatIf` để xem trước những gì sẽ thay đổi.

---

## 0. Đọc nhanh: Audit, Remediate và checks là gì

| Thuật ngữ | Nghĩa tiếng Việt | Làm gì | Sửa máy chủ? |
|---|---|---|---|
| **Audit** (`Audit.ps1`) | Kiểm tra, đánh giá | Chỉ **đọc** cấu hình và so với khuyến nghị CIS: mỗi mục ra `PASS` (đạt) hoặc `FAIL` (không đạt) | **Không** |
| **Remediate** (`Remediate.ps1`) | Khắc phục, sửa lỗi | **Sửa** các mục `FAIL` cho đúng khuyến nghị, rồi kiểm tra lại ngay từng mục vừa sửa | **Có** |
| **checks** (`checks.ps1`) | Danh sách định nghĩa tiêu chí | Chỉ là "sách công thức": mỗi tiêu chí kiểm tra bằng gì, sửa bằng gì. Bạn **không chạy** file này, `Audit.ps1` và `Remediate.ps1` đọc nó | Không |

**Thứ tự đúng (Audit được chạy hai lần):**

1. `Audit.ps1`: kiểm tra **trước khi sửa** → số liệu "trước" (baseline).
2. `Remediate.ps1`: sửa các mục `FAIL` (có sao lưu trước, có hỏi xác nhận).
3. `Audit.ps1` một lần nữa: kiểm tra **sau khi sửa** → số liệu "sau".
4. So sánh "trước" và "sau" bằng `-Mode Report` (xem §4.1) để đưa vào báo cáo.

Lưu ý: `Remediate.ps1` có tự kiểm tra lại từng mục ngay sau khi sửa (ghi vào cột `After`), nhưng đó chỉ là bước xác nhận nhanh. Số liệu "sau" dùng cho báo cáo nên lấy từ lần chạy `Audit.ps1` thứ hai.

---

## 1. Ý tưởng

Thay vì chạy lệnh rời rạc cho từng tiêu chí, bộ script có 3 chế độ (dùng chung cho script chạy một lần và script từng phần):

| Chế độ | Làm gì | Có sửa hệ thống không |
|---|---|---|
| `Audit` | Kiểm tra toàn bộ tiêu chí Automated trong phạm vi, ghi PASS/FAIL/N/A/ERROR, xuất báo cáo | **Không**, chỉ đọc |
| `Remediate` | Sao lưu → sửa các mục FAIL **của đợt được chọn** → kiểm tra lại ngay → ghi Before/After | **Có** |
| `Report` | Ghép hai file kết quả (trước và sau) thành báo cáo so sánh | Không |

Các tiêu chí **Manual** (14 mục) không tự sửa được; script chỉ liệt kê chúng thành dòng `MANUAL` trong báo cáo để báo cáo đủ 55 tiêu chí. Cách làm thủ công nằm trong `..\manual\HuongDan_CIS_IIS10.md`; để xem trạng thái các mục này dùng `manual\scripts\Check-ManualItems.ps1`.

### 1.1 Vì sao Remediate chia ba đợt

Chạy sửa một lần cho tất cả là rủi ro: nếu site hỏng, khó biết mục nào gây ra. Script chia mục sửa được theo **mức rủi ro**:

| Đợt | Rủi ro | Số mục | Hành vi khi chạy |
|---|---|---:|---|
| **1** | Thấp | 23 | Có thể dùng `-Force` để không hỏi |
| **2** | Trung bình | 14 | Có thể dùng `-Force`; nên kiểm tra site sau đợt này |
| **3** | Cao | 4 | **Luôn hỏi `y/N` từng mục**, trừ khi dùng `-ForceHighRisk` |

Quy trình khuyến nghị:

```
Audit (baseline) → Remediate đợt 1 → kiểm tra site → Remediate đợt 2 → kiểm tra site
→ Remediate đợt 3 (hỏi từng mục) → reboot → Audit (sau) → Report (so sánh)
```

### 1.2 Phạm vi mặc định

- **Tất cả L1** (30 mục Automated) + **2 mục L2 Automated đã chọn** (4.2, 7.12) = 32 mục chạy tự động.
- Thêm `-AllL2` để chạy cả 9 mục L2 Automated còn lại (2.4, 2.8, 3.2, 3.3, 3.5, 3.6, 3.8, 4.3, 4.4).
- Dòng `MANUAL` trong báo cáo: 12 mục theo phạm vi mặc định (L1 + 3.12, 7.1); `-AllL2` thêm 3.11 và 4.1.

---

## 2. Cấu trúc thư mục và chạy file nào

```
automation\
├── TuDongHoa_CIS_IIS10.md             (file này)
├── scripts\
│   ├── 00-Setup-Lab.ps1                dựng lab (một lần)
│   ├── 01-Seed-Baseline.ps1            (tùy chọn) làm yếu cấu hình để có baseline
│   ├── IIS-CIS.ps1                     CHẠY MỘT LẦN cả 7 phần: Audit / Remediate / Report
│   └── Common.ps1                      bộ máy dùng chung (không chạy trực tiếp)
├── 1-Basic\             checks.ps1  Audit.ps1  Remediate.ps1
├── 2-AuthN-AuthZ\       checks.ps1  Audit.ps1  Remediate.ps1
├── 3-ASPNET\            checks.ps1  Audit.ps1  Remediate.ps1
├── 4-RequestFiltering\  checks.ps1  Audit.ps1  Remediate.ps1
├── 5-Logging\           checks.ps1  Audit.ps1  Remediate.ps1
├── 6-FTP\               checks.ps1  Audit.ps1  Remediate.ps1
└── 7-TLS\               checks.ps1  Audit.ps1  Remediate.ps1
```

### 2.1 Mỗi thư mục phần có gì

| File | Vai trò | Sửa hệ thống? |
|---|---|---|
| `Audit.ps1` | Kiểm tra các mục Automated của phần đó, liệt kê các mục Manual thành dòng `MANUAL`, xuất báo cáo | **Không** |
| `Remediate.ps1` | Sao lưu, sửa các mục FAIL của phần đó, kiểm tra lại, ghi Before/After | **Có** |
| `checks.ps1` | **Định nghĩa** các tiêu chí của phần đó (một nguồn duy nhất). Không chạy trực tiếp; `Audit.ps1`, `Remediate.ps1` và `IIS-CIS.ps1` đều đọc file này | Không |

Vì tất cả cùng đọc `checks.ps1`, chạy từng phần hay chạy một lần đều ra **cùng kết quả**, không có hai bản lệch nhau.

### 2.2 Phần nào có những mục nào

`*` = L2. Cột "Mặc định" là số mục Automated chạy trong phạm vi mặc định (tất cả L1 + 4.2, 7.12); `-AllL2` thêm các mục L2 khác.

| Phần | Thư mục | Mục Automated | Mặc định | Mục Manual (chỉ liệt kê) |
|---|---|---|---:|---|
| 1 | `1-Basic` | 1.2, 1.3, 1.4, 1.5, 1.6, 1.7 | 6 | 1.1 |
| 2 | `2-AuthN-AuthZ` | 2.3, 2.4*, 2.5, 2.6, 2.7, 2.8* | 4 | 2.1, 2.2 |
| 3 | `3-ASPNET` | 3.2*, 3.3*, 3.4, 3.5*, 3.6*, 3.7, 3.8*, 3.9, 3.10 | 4 | 3.1, 3.11*, 3.12* |
| 4 | `4-RequestFiltering` | 4.2*, 4.3*, 4.4*, 4.5, 4.7, 4.9, 4.10 | 5 | 4.1*, 4.6, 4.8, 4.11 |
| 5 | `5-Logging` | 5.1, 5.2 | 2 | 5.3 |
| 6 | `6-FTP` | *(không có)* | 0 | 6.1, 6.2 |
| 7 | `7-TLS` | 7.2 đến 7.11, 7.12* | 11 | 7.1* |
| | | **Tổng** | **32** | 12 theo phạm vi mặc định |

Phần 6 chỉ có mục Manual: `Audit.ps1` của nó chỉ liệt kê hai dòng `MANUAL`, còn `Remediate.ps1` báo "không có gì để sửa tự động". Để xem trạng thái hai mục này dùng `manual\scripts\Check-ManualItems.ps1`.

### 2.3 Thứ tự chạy gợi ý

| Bước | File | Ghi chú |
|---|---|---|
| 1 | `scripts\00-Setup-Lab.ps1` | Một lần, ngay sau khi cài VM. Chụp snapshot |
| 2 | `scripts\01-Seed-Baseline.ps1` | *Tùy chọn*: làm yếu cấu hình để có nhiều FAIL. Chỉ dùng trong VM lab |
| 3 | `scripts\IIS-CIS.ps1 -Mode Audit -Label before` (hoặc `Audit.ps1` từng phần) | Baseline "trước" |
| 4 | `scripts\IIS-CIS.ps1 -Mode Remediate -Wave ...` (hoặc `Remediate.ps1` từng phần) | Sửa theo đợt, xem §4 |
| 5 | `manual\scripts\Check-ManualItems.ps1` | Trạng thái 14 mục Manual, làm tay rồi chạy lại |
| 6 | `scripts\IIS-CIS.ps1 -Mode Audit -Label after` rồi `-Mode Report` | Số liệu "sau" và báo cáo so sánh |

`00-Setup-Lab.ps1` và `01-Seed-Baseline.ps1` **không** thuộc quy trình CIS, chỉ để chuẩn bị môi trường thử nghiệm. Đừng chạy chúng trên máy thật. Hai file này, cùng với `Check-ManualItems.ps1`, mới được kiểm tra cú pháp (riêng `Check-ManualItems.ps1` đã chạy thử với giả lập); chưa chạy trên VM thật.

---

## 3. Chuẩn bị

1. Máy ảo Windows Server 2022 Desktop (xem `..\manual\HuongDan_CIS_IIS10.md` §0.4). Chụp snapshot.
2. Chép **cả thư mục `run`** vào VM (ví dụ `C:\run`).
3. Mở **Windows PowerShell as Administrator** (script nhắm tới PowerShell 5.1 có sẵn trên Server 2022). Script tự kiểm tra và dừng nếu không phải Administrator.
4. Cho phép chạy script trong phiên hiện tại. Nếu file chép từ internet hoặc qua chat bị Windows chặn, gỡ chặn luôn:

```powershell
Set-Location C:\run\automation
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
```

Kết quả được ghi vào `automation\out\` (mọi script dùng chung thư mục này; đổi bằng `-OutDir`).

---

## 4. Cách chạy

### 4.1 Chạy một lần cả 7 phần (`scripts\IIS-CIS.ps1`)

```powershell
Set-Location C:\run\automation\scripts

# Bước 1: audit baseline (chỉ đọc)
.\IIS-CIS.ps1 -Mode Audit -Label before

# Bước 2: thử "chạy khô" (không sửa gì), rồi sửa theo đợt, kiểm tra site sau mỗi đợt
.\IIS-CIS.ps1 -Mode Remediate -Wave 1 -WhatIf
.\IIS-CIS.ps1 -Mode Remediate -Wave 1 -Force -Label after-w1     # rủi ro thấp, không hỏi
.\IIS-CIS.ps1 -Mode Remediate -Wave 2 -Label after-w2            # trung bình, hỏi y/N từng mục
.\IIS-CIS.ps1 -Mode Remediate -Wave 3 -Label after-w3            # cao, luôn hỏi y/N từng mục
Restart-Computer                                                   # cần cho các mục registry (phần 7)

# Bước 3: audit lại và so sánh
.\IIS-CIS.ps1 -Mode Audit -Label after
.\IIS-CIS.ps1 -Mode Report `
  -BeforeCsv ..\out\<thư-mục>-before\results.csv `
  -AfterCsv  ..\out\<thư-mục>-after\results.csv
```

Mở `report.html` trong thư mục `...-compare` vừa tạo. Khi chạy Remediate, script tự sao lưu trước (`appcmd add backup` và `reg export`) và in cách hoàn tác (`appcmd restore backup <tên>`).

### 4.2 Chạy riêng từng phần (ví dụ phần 4)

```powershell
Set-Location C:\run\automation\4-RequestFiltering
.\Audit.ps1                         # chỉ kiểm tra phần 4
.\Remediate.ps1 -WhatIf             # chạy khô
.\Remediate.ps1 -Force              # sửa; đợt 3 (4.7) vẫn hỏi y/N
.\Audit.ps1 -Label after            # kiểm tra lại
```

`Remediate.ps1` của từng phần mặc định xét cả 3 đợt (`-Wave 1,2,3`) và **hỏi y/N cho từng mục** nếu bạn không thêm `-Force` (đợt 1-2) hoặc `-ForceHighRisk` (đợt 3). Muốn chỉ làm đợt nhẹ: `.\Remediate.ps1 -Wave 1 -Force`.

Một số phần có thêm tham số riêng:

| Phần | Tham số riêng | Dùng cho |
|---|---|---|
| 1 | `-HostMap @{'SiteA'='a.lab.local'}`, `-HostSuffix` | Mục 1.2: tên host; nếu bỏ trống dùng `<tên site>.<HostSuffix>` |
| 4 | `-AllowedExtensions '.html','.css'` | Mục 4.7: các đuôi file được phép |
| 5 | `-LogDir E:\IISLogs` | Mục 5.1: thư mục log mới, **không được nằm trên ổ hệ thống** |

### 4.3 Bảng tham số chung

| Tham số | Ý nghĩa |
|---|---|
| `-Mode` | (chỉ `IIS-CIS.ps1`) `Audit` (mặc định), `Remediate`, `Report` |
| `-Wave 1,2,3` | Đợt cần sửa (`IIS-CIS.ps1` bắt buộc khi `Remediate`; `Remediate.ps1` từng phần mặc định cả 3) |
| `-Id '1.3','4.2'` | Chỉ chạy các mục này. **Luôn đặt id trong dấu nháy** (xem lưu ý dưới) |
| `-AllL2` | Thêm tất cả mục L2 Automated vào phạm vi |
| `-Force` | Không hỏi xác nhận cho đợt 1 và 2 |
| `-ForceHighRisk` | Không hỏi xác nhận cho đợt 3 (cẩn thận) |
| `-WhatIf` | Chạy khô: kiểm tra và in dự định sửa, không thay đổi gì (báo cáo vẫn được ghi) |
| `-Label` | Nhãn đặt vào tên thư mục kết quả (`before`, `after`...) |
| `-OutDir` | Thư mục kết quả (mặc định `automation\out`) |
| `-BeforeCsv`, `-AfterCsv` | (chỉ `IIS-CIS.ps1 -Mode Report`) file đầu vào |

**Lưu ý quan trọng về `-Id`:** PowerShell biến `3.10` không có dấu nháy thành số `3.1`, nên `-Id 3.10` sẽ chạy nhầm mục 3.1. Hãy viết `-Id '3.10'` (tương tự `'7.10'`, `'4.10'`). Script luôn in dòng `Checks selected (...)` ngay đầu; hãy nhìn dòng đó để chắc đã chọn đúng mục.

---

## 5. Danh sách 41 mục tự động và đợt sửa

`*` = L2. Cột "Reboot" là mục sửa registry, cần khởi động lại.

**Đợt 1: rủi ro thấp (23 mục)**

| ID | Mục | Reboot |
|---|---|---|
| 1.3 | Directory browsing tắt | |
| 1.7 | Gỡ WebDAV | |
| 2.4* | Forms auth dùng cookie | |
| 2.5 | Cookie protection mode | |
| 2.7 | `passwordFormat` không phải Clear | |
| 3.2* | `debug` tắt | |
| 3.3* | customErrors không Off | |
| 3.4 | httpErrors không lộ chi tiết từ xa | |
| 3.5* | ASP.NET trace tắt | |
| 3.6* | Session state dùng cookie | |
| 3.7 | Cookie HttpOnly | |
| 3.8* | MachineKey .NET 3.5 | |
| 3.9 | MachineKey .NET 4.5 (SHA-2) | |
| 4.2* | `maxUrl` | |
| 4.3* | `maxQueryString` | |
| 4.9 | `notListedIsapisAllowed=false` | |
| 4.10 | `notListedCgisAllowed=false` | |
| 7.2 | Tắt SSLv2 | ✔ |
| 7.3 | Tắt SSLv3 | ✔ |
| 7.6 | Bật TLS 1.2 | ✔ |
| 7.7 | Tắt NULL cipher | ✔ |
| 7.8 | Tắt DES | ✔ |
| 7.11 | Bật AES 256/256 | ✔ |

**Đợt 2: rủi ro trung bình (14 mục)**

| ID | Mục | Lưu ý | Reboot |
|---|---|---|---|
| 1.2 | Host header cho mọi site | Đổi cách truy cập site; xem `-HostMap` | |
| 1.4 | App pool identity | Pool đang dùng tài khoản riêng bị đổi | |
| 1.5 | Mỗi site một app pool | Tạo pool mới cho site dùng chung | |
| 1.6 | Anonymous = app pool identity | Có thể cần cấp quyền thư mục cho `IIS AppPool\<tên>` | |
| 2.3 | Forms auth bắt buộc SSL | Site cần HTTPS | |
| 2.6 | Basic auth bắt buộc SSL | Site cần HTTPS binding, nếu chưa có thì ghi `FixError` | |
| 2.8* | Không lưu credentials trong config | Xóa `<credentials>` | |
| 4.4* | Cấm ký tự non-ASCII trong URL | Site đa ngôn ngữ có thể ảnh hưởng | |
| 4.5 | Từ chối double-encoded | | |
| 5.1 | Chuyển log sang ổ khác | Cần `-LogDir` ngoài ổ hệ thống | |
| 5.2 | Trường log W3C | Xem ghi chú §7 | |
| 7.9 | Tắt RC4 | | ✔ |
| 7.10 | Tắt AES 128/128 | | ✔ |
| 7.12* | Thứ tự cipher suite | | ✔ |

**Đợt 3: rủi ro cao (4 mục, luôn hỏi xác nhận)**

| ID | Mục | Rủi ro | Reboot |
|---|---|---|---|
| 3.10 | Trust level Medium | App cần Full Trust sẽ lỗi | |
| 4.7 | `allowUnlisted=False` | Thiếu đuôi file cần dùng thì site trả 404.7 | |
| 7.4 | Tắt TLS 1.0 | Client cũ không kết nối được | ✔ |
| 7.5 | Tắt TLS 1.1 | Client cũ không kết nối được | ✔ |

**14 mục Manual** (chỉ hiện dòng `MANUAL` trong báo cáo): 1.1, 2.1, 2.2, 3.1, 3.11*, 3.12*, 4.1*, 4.6, 4.8, 4.11, 5.3, 6.1, 6.2, 7.1*. Cách làm xem `..\manual\HuongDan_CIS_IIS10.md`.

---

## 6. Đọc kết quả

### 6.1 Các cột trong `results.csv`

| Cột | Ý nghĩa |
|---|---|
| `Id`, `Title`, `Level` | Mã, tên, level của tiêu chí |
| `Wave` | Đợt sửa (0 = mục Manual) |
| `Target` | Đối tượng được kiểm tra: `SERVER`, `ROOT`, tên site, tên app pool, tên key registry |
| `Before` | Kết quả trước khi sửa: `PASS`, `FAIL`, `N/A`, `ERROR`, `MANUAL` |
| `After` | Kết quả sau khi sửa (rỗng nếu không sửa mục đó) |
| `Action` | `Fixed`, `Declined` (bạn trả lời n), `WhatIf`, hoặc `FixError: <lý do>` |
| `Detail` | Giá trị thực đo được |
| `FixHint` | Mô tả cách sửa |

Một tiêu chí có thể có **nhiều dòng**, mỗi dòng một đối tượng (ví dụ 1.3 có `SERVER`, `SiteA`, `SiteB`).

### 6.2 Ý nghĩa trạng thái

| Trạng thái | Ý nghĩa |
|---|---|
| `PASS` | Cấu hình đúng khuyến nghị |
| `FAIL` | Cấu hình sai |
| `N/A` | Không có đối tượng để kiểm tra (ví dụ site không dùng Forms auth, không có `web.config`) |
| `ERROR` | Lệnh kiểm tra bị lỗi (ví dụ chưa cài ASP.NET): coi như chưa kiểm tra được |
| `MANUAL` | Mục Manual, làm thủ công |

### 6.3 `report.html` gồm gì

1. **Summary:** số lượng từng trạng thái (cột Before, và After nếu đã sửa).
2. **Needs action now:** các dòng còn `FAIL`/`ERROR`, xếp theo đợt, kèm cách sửa và lệnh gợi ý để chạy.
3. **All results:** toàn bộ dòng, tô màu theo trạng thái.

Báo cáo này đáp ứng ý "người đọc thấy thực trạng, mục nào cần xử lý ngay, chạy gì để khắc phục". Lưu thư mục kết quả làm bằng chứng và dán số liệu Before/After vào báo cáo.

---

## 7. Xử lý sự cố và giới hạn

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| Nhiều dòng `ERROR` ở mục nhóm 3 (`system.web`) | Chưa cài `Web-Asp-Net45`; cài rồi chạy lại |
| `FixError: ... no HTTPS binding` (2.6) | Site cần có HTTPS binding trước (xem `..\manual\HuongDan_CIS_IIS10.md` §1.2, hoặc chạy lại `00-Setup-Lab.ps1`) |
| `FixError: -LogDir ... is on the system drive` (5.1) | Truyền `-LogDir` trỏ sang ổ khác, ví dụ `-LogDir E:\IISLogs` |
| Site trả 404.7 sau 4.7 | Thêm đuôi file cần dùng vào `-AllowedExtensions`. Với trang gốc `/` không đuôi: **chưa kiểm chứng**, test trên VM |
| Site trả 401/403 sau 1.6 | Cấp quyền đọc thư mục web cho `IIS AppPool\<tên pool>` |
| Script dừng ở dòng "apply fix? (y/N)" | Đó là bước xác nhận. Dùng `-Force` (đợt 1-2) hoặc `-ForceHighRisk` (đợt 3) khi chạy không tương tác |
| Báo lỗi "running scripts is disabled" hoặc file bị chặn | Làm bước 4 ở §3: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` và `Unblock-File` |
| Gõ `-Id 3.10` nhưng thấy chạy mục 3.1 | Quên dấu nháy; viết `-Id '3.10'`. Xem dòng `Checks selected (...)` để kiểm tra |
| `Remediate.ps1` của một phần hỏi y/N liên tục | Đúng thiết kế khi không có `-Force`/`-ForceHighRisk`; thêm cờ đó nếu muốn chạy không hỏi |
| Báo "REBOOT REQUIRED" | Khởi động lại VM trước khi audit lại các mục nhóm 7 |
| Muốn hoàn tác | `appcmd restore backup <tên in ra>`; registry: `reg import` file `.reg` trong `out\backup`; hoặc quay snapshot VM |

Giới hạn cần biết:

- **Chưa chạy trên IIS thật** (xem đầu file). Phần cú pháp và logic điều khiển đã được kiểm tra; hành vi cụ thể của từng lệnh trên IIS thật thì chưa.
- **5.2 (Advanced Logging):** module Advanced Logging là bản tải riêng và **không** được script cài. Script chỉ kiểm tra/đặt các trường log W3C theo bước "Select Fields" của PDF. Khả năng cài module trên Server 2022 chưa được kiểm chứng.
- **1.2:** nếu không có `-HostMap`, tên host được đặt là `<tên-site-viết-thường>.lab.local`. Script không sửa file `hosts`, bạn tự thêm nếu muốn gọi bằng tên.
- **2.7 và 2.8** đọc/ghi trực tiếp `web.config` của từng site (có tạo bản `.bak`). **2.7**: mật khẩu dạng rõ phải được băm lại thủ công sau khi đổi `passwordFormat`.
- **3.8** chỉ có đối tượng khi đã cài .NET Framework 3.5; nếu không, báo `N/A`.
- **7.x:** cả `Enabled` và `DisabledByDefault` được kiểm tra; khóa registry chưa tồn tại được tính là `FAIL` (đúng yêu cầu CIS phải đặt khóa tường minh). Kiểm chứng từ ngoài bằng `nmap --script ssl-enum-ciphers -p 443 <IP>` sau khi reboot.
- Script **không** làm 14 mục Manual, và **không** cài thêm role/feature.
- Giá trị mặc định (ví dụ giới hạn `maxUrl`, thư mục log) có thể khác trên Windows Server 2022 so với PDF (viết cho 2016); dùng kết quả `Before` đo được làm baseline.
