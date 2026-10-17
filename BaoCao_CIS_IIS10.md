# Báo cáo đồ án: Đánh giá & tự động hóa hardening Microsoft IIS 10 theo CIS Benchmark v1.2.1

> **Môn:** NT542 · **Tài liệu gốc:** `CIS_Microsoft_IIS_10_Benchmark_v1.2.1.pdf` (17-07-2023) · **Yêu cầu:** `yeu_cau.jpg`
>
> **Trạng thái:** báo cáo mô tả kế hoạch, phân tích tiêu chí và bộ công cụ đã xây dựng. Bộ script đã được kiểm tra cú pháp và chạy thử trên **IIS giả lập**, nhưng **chưa chạy trên IIS thật**, nên **chưa có số liệu thực tế** (chưa có kết quả trước/sau). Các mục kết quả ở §9.2 để trống, điền sau khi chạy trên máy ảo.

> ## ⚠️ Cảnh báo: KHÔNG chạy trên máy chính
>
> Bộ script này **sửa cấu hình hệ thống**: IIS, `machine.config`, registry SCHANNEL (tắt TLS 1.0/1.1, đổi thứ tự cipher), thư mục log, quyền truy cập, và có thể làm các site hoặc kết nối mạng ngừng hoạt động. Một số thay đổi còn cần **khởi động lại** máy.
>
> - **Chỉ chạy trong máy ảo (VM) dành riêng cho bài lab**, và **chụp snapshot trước khi sửa** để quay lại được.
> - **Không chạy trên máy cá nhân hoặc máy đang dùng cho việc khác.** Đặc biệt đừng chạy `01-Seed-Baseline.ps1` ngoài VM vì nó cố tình làm yếu cấu hình.
> - Chế độ `Audit` (chỉ đọc) thì an toàn hơn, nhưng `Remediate` thì không. Dùng `-WhatIf` để xem trước những gì sẽ thay đổi.

---

## 1. Tóm tắt

- Benchmark có **55 tiêu chí** chia thành **7 nhóm**: **40 Level 1 (L1)**, **15 Level 2 (L2)**.
- Theo nhãn của CIS: **41 Automated**, **14 Manual**.
- Yêu cầu của thầy: làm **toàn bộ L1** + **một số L2**. Mục nào nhãn *Automated* thì tự động hóa, *Manual* thì làm thủ công.
- Phạm vi đề xuất:
  - **L1:** làm cả 40 mục (30 auto, 10 manual).
  - **L2:** chọn 4 mục (2 auto, 2 manual), xem §5.2.
- **Công cụ:** bộ script PowerShell tự viết, có hai cách dùng chung một bộ định nghĩa: chạy **một lần cả 7 phần** (`IIS-CIS.ps1`) hoặc chạy **riêng từng phần 1 đến 7** (mỗi phần có `Audit.ps1` và `Remediate.ps1`). Việc sửa chia **3 đợt theo rủi ro** và có hỏi xác nhận. Kết quả xuất ra CSV, JSON và HTML. Mặc định chạy tự động **32 mục** (30 L1 Automated + 4.2, 7.12).
- **Theo dõi tiến độ:** file Excel tracker (tiến độ từng tiêu chí, người phụ trách, tiến độ viết báo cáo).
- **Chia việc:** 4 nhóm theo mục của benchmark (§6).

| | Automated | Manual | Tổng |
|---|---:|---:|---:|
| **L1** | 30 | 10 | 40 |
| **L2** | 11 | 4 | 15 |
| **Tổng** | 41 | 14 | 55 |

Phân bố theo nhóm của benchmark:

| Nhóm | Nội dung | Số mục | L1 | L2 |
|---|---|---:|---:|---:|
| 1 | Basic Configurations | 7 | 7 | 0 |
| 2 | Authentication & Authorization | 8 | 6 | 2 |
| 3 | ASP.NET Configuration | 12 | 5 | 7 |
| 4 | Request Filtering & restriction modules | 11 | 7 | 4 |
| 5 | IIS Logging | 3 | 3 | 0 |
| 6 | FTP | 2 | 2 | 0 |
| 7 | Transport Encryption (TLS/cipher) | 12 | 10 | 2 |

### Tài liệu và công cụ đi kèm

| Thành phần | Vị trí | Dùng để |
|---|---|---|
| Hướng dẫn từng tiêu chí (audit, remediate, các bước thủ công) | `run\manual\HuongDan_CIS_IIS10.md` | Đọc hiểu và làm thủ công từng mục |
| Script xem trạng thái 14 mục Manual (chỉ đọc) | `run\manual\scripts\Check-ManualItems.ps1` | Biết mục Manual nào còn `TODO`, giữ làm bằng chứng |
| Hướng dẫn chạy tự động | `run\automation\TuDongHoa_CIS_IIS10.md` | Cách chạy, tham số, đọc kết quả |
| Dựng lab, tạo baseline | `run\automation\scripts\00-Setup-Lab.ps1`, `01-Seed-Baseline.ps1` | Chuẩn bị VM thử nghiệm |
| Chạy một lần cả 7 phần | `run\automation\scripts\IIS-CIS.ps1` | Audit, Remediate theo đợt, Report |
| Chạy từng phần | `run\automation\1-Basic` ... `7-TLS` (`Audit.ps1`, `Remediate.ps1`, `checks.ps1`) | Làm riêng phần của mình |
| Theo dõi tiến độ | `CIS_IIS10_Tracker.xlsx` (và `CIS_IIS10_Tracker_Sheets.xlsx` cho Google Sheets) | Ai làm gì, đã xong chưa |

---

## 2. Cách đọc yêu cầu (`yeu_cau.jpg`)

Ảnh nêu 6 bước. Mỗi bước tương ứng một phần của báo cáo này:

| # | Yêu cầu trong ảnh | Phần báo cáo |
|---|---|---|
| 1 | Đánh giá hạ tầng: khảo sát làm gì, triển khai kịch bản cho hạ tầng (tự chọn) | §3 |
| 2 | Triển khai thành phần hạ tầng (thủ công: cài máy ảo; tự động hóa: điểm cao hơn) | §4 |
| 3 | Áp tài liệu lên từng tiêu chí: tiêu chí nào có vấn đề gì không, kiểm tra bằng lệnh hay thủ công, chọn công cụ | §5 |
| 4 | Chọn 3–4 mục để chia task cho thành viên, mỗi người trả lời được: *tại sao tiêu chí đó không an toàn*, *lỗ hổng đó có các bước kiểm tra nào* | §6, §8 |
| 5 | Đưa tiêu chí vào công cụ tự động hóa. Cái nào không auto được thì làm manual | §7 |
| 6 | Xuất báo cáo: người đọc thấy được thực trạng, mục nào cần xử lý ngay (cảnh báo), cấu trúc báo cáo xuất tự động, chạy gì để khắc phục. Có thể thay đổi cần xác nhận. Remediation không bắt buộc cho tất cả | §9 |

Ảnh ghi *"có từ manual → không cần thực hiện ở bước tự động hóa (khó, cần kiểm tra thủ công, không bắt buộc)"*. Vì vậy các mục Manual chỉ cần checklist + bằng chứng, không cần ép vào script.

---

## 3. Đánh giá hạ tầng & kịch bản

### 3.1 Đối tượng cần bảo vệ

Một web server Windows chạy IIS 10, đại diện cho một dịch vụ web nhỏ:

- 1 site tĩnh (HTML) + 1 site/ứng dụng ASP.NET có Forms Authentication, để các mục nhóm 2–3 có chỗ áp dụng thật.
- 1 site FTP (FTP Service for IIS) để làm nhóm 6.
- Dùng cert tự ký (self-signed) cho HTTPS và FTPS.

> **Môi trường đã chốt:** **Windows Server 2022 Standard (Desktop Experience)**, bản Evaluation 180 ngày, chạy trên **1 máy ảo**. Chọn bản Desktop Experience vì các mục Manual cần IIS Manager (GUI).
>
> **Độ lệch so với benchmark:** benchmark ghi áp dụng cho **IIS 10 trên Windows Server 2016**. IIS 10 cũng có trên Server 2022 và các lệnh trong tài liệu (`WebAdministration`/`appcmd`) vẫn dùng được. Tuy nhiên một số giá trị mặc định (nhất là TLS/SCHANNEL) có thể khác phần "Default Value" trong PDF, nên baseline phải lấy từ kết quả chạy thật trên 2022, không lấy theo PDF.

### 3.2 Kịch bản

| Vai trò | Máy | Mục đích |
|---|---|---|
| **Target** | **1 VM Windows Server 2022 (Desktop Experience)** + IIS 10, cấu hình *mặc định* | Máy bị đánh giá, cố tình để nhiều lỗi cấu hình |
| **Operator** | Chính VM target, chạy PowerShell **Administrator** | Chạy công cụ audit/remediate |
| **Verifier** (không bắt buộc) | Dùng **máy thật** gọi vào IP của VM (hoặc `curl.exe` ngay trong VM gọi `localhost`) | Kiểm chứng: `curl`, `nmap`. Không cần dựng thêm VM |

Kịch bản đánh giá là **trước → sau**:

1. Dựng lab bằng `00-Setup-Lab.ps1`, rồi (tùy chọn) chạy `01-Seed-Baseline.ps1` để thêm cấu hình "xấu" có chủ đích (directory browsing bật, forms auth với mật khẩu dạng rõ, debug bật, Basic auth không SSL, v.v.). Chụp snapshot.
2. Chạy `Audit` để có báo cáo **baseline** (nhiều FAIL).
3. Chạy `Remediate` theo đợt cho các mục auto, làm thủ công các mục Manual.
4. Chạy `Audit` lại để có báo cáo **sau hardening**, và xác nhận site vẫn hoạt động.

---

## 4. Triển khai hạ tầng

Điểm cao hơn nếu **tự động hóa** việc dựng hạ tầng. Hai mức:

| Mức | Cách làm |
|---|---|
| Thủ công (tối thiểu) | Tạo VM bằng Hyper-V/VirtualBox/VMware, cài Windows Server, bật Role *Web Server (IIS)*, *FTP Server*, *Management Scripts and Tools*, ASP.NET. Chụp snapshot. |
| Tự động (đã làm) | `run\automation\scripts\00-Setup-Lab.ps1` chạy trong VM mới: cài các thành phần IIS cần cho benchmark (không cài WebDAV vì mục 1.7 yêu cầu *không có* WebDAV), tạo hai site mẫu `SiteA`/`SiteB`, cert tự ký và HTTPS binding, site FTP. `01-Seed-Baseline.ps1` (tùy chọn) làm yếu cấu hình để có baseline nhiều FAIL. Cả hai chạy lại được nhiều lần (bỏ qua phần đã có). |

Cấu hình VM đề xuất: 2 vCPU, 4 GB RAM, đĩa C: 40–60 GB, **thêm đĩa ảo thứ hai (D:)** để làm mục 1.1 (web content) và 5.1 (log). Mạng dùng host-only hoặc NAT để máy thật truy cập được. Khi cài, chọn đúng **"Windows Server 2022 Standard Evaluation (Desktop Experience)"**, không chọn bản không ghi Desktop Experience (đó là Server Core, không có GUI).

Nên **snapshot VM sạch** trước khi chạy `Remediate`. Một số mục (TLS, request filtering, `allowUnlisted=false`) có thể làm hỏng site và cần quay lại.

---

## 5. Áp dụng benchmark lên từng tiêu chí

### 5.1 Quy ước

- **Auto** = nhãn *Automated* trong benchmark, đưa vào script (audit, và remediate khi an toàn).
- **Manual** = nhãn *Manual*, làm bằng checklist + chụp màn hình/log làm bằng chứng.
- **Rủi ro**: khả năng remediate làm hỏng chức năng.
  - 🟢 thấp.
  - 🟡 cần xem ứng dụng.
  - 🔴 dễ làm gãy dịch vụ, cần test và có cơ chế rollback.
- Mỗi mục auto trả về 1 trong các trạng thái: `PASS` / `FAIL` / `N/A` / `ERROR` (mục Manual hiện là `MANUAL`).
  - `N/A` dùng cho trường hợp không có đối tượng để áp dụng, ví dụ không site nào dùng Forms Auth, hoặc chưa cài FTP. Nếu không có trạng thái này, báo cáo sẽ có FAIL giả.

### 5.2 L2 đề xuất chọn

Ảnh yêu cầu "chọn 1–2 tiêu chí level 2", thầy nói "một số". Đề xuất **4 mục**, bớt được nếu muốn:

| Mục | Loại | Vì sao chọn |
|---|---|---|
| **7.12** TLS cipher suite ordering | Auto | Cùng cơ chế registry với nhóm 7, làm thêm gần như không tốn công, và có chỗ để bàn về PFS |
| **4.2** `maxUrl` | Auto | Cấu hình `requestFiltering` đơn giản, dễ kiểm chứng bằng URL dài → 404.14 |
| **3.12** Server header removed | Manual | Kiểm chứng được bằng `curl -I`, trực quan khi demo |
| **7.1** HSTS | Manual | Liên quan trực tiếp đến HTTPS ở nhóm 7, kiểm chứng bằng `curl -I https://…` |

### 5.3 Bảng 55 tiêu chí

**Nhóm 1 — Basic Configurations**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 1.1 | L1 | Web content nằm ở ổ không phải ổ hệ thống | **Manual** | `appcmd list vdir`, `Get-Website \| fl Name,PhysicalPath`; di chuyển nội dung + sửa mapping, copy cả ACL | 🟡 |
| 1.2 | L1 | Host header cho mọi site | Auto | Duyệt binding của từng site; binding http có `bindingInformation` dạng `*:80:` (trống host) là FAIL; `Set-WebBinding -PropertyName HostHeader` để gán host | 🟡 |
| 1.3 | L1 | Tắt Directory Browsing | Auto | `Get-WebConfigurationProperty … directorybrowse -Name Enabled`; set `False` | 🟢 |
| 1.4 | L1 | App pool dùng identity ít quyền (ApplicationPoolIdentity) | Auto | `Get-ChildItem IIS:\AppPools \| select name, processModel.identityType`; đổi về `ApplicationPoolIdentity` | 🟡 |
| 1.5 | L1 | Mỗi site một app pool riêng | Auto | `Get-Website \| select Name, applicationPool` rồi tìm pool bị dùng chung | 🟡 |
| 1.6 | L1 | Anonymous user identity = app pool identity | Auto | `anonymousAuthentication userName=""` | 🟡 |
| 1.7 | L1 | Gỡ WebDAV | Auto | Audit: `Get-WindowsFeature Web-DAV-Publishing` (Installed?). Remediate: `Uninstall-WindowsFeature Web-DAV-Publishing` | 🟢 |

**Nhóm 2 — Authentication & Authorization**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 2.1 | L1 | Global authorization rule hạn chế truy cập | **Manual** | `Get-WebConfiguration … security/authorization`; xóa rule "Allow all users", chỉ allow Administrators ở mức server | 🔴 (chặn mọi site nếu không cấp lại ở mức site) |
| 2.2 | L1 | Chức năng nhạy cảm yêu cầu xác thực | **Manual** | Xem module authentication nào bật theo site/app; tắt Anonymous cho phần nhạy cảm | 🟡 |
| 2.3 | L1 | Forms auth bắt buộc SSL | Auto | `system.web/authentication/forms` → `requireSSL=True` | 🟡 |
| 2.4 | L2 | Forms auth dùng cookie | Auto | `cookieless=UseCookies` | 🟢 |
| 2.5 | L1 | Cookie protection mode = All | Auto | `protection=All` | 🟢 |
| 2.6 | L1 | Basic auth chạy trên TLS | Auto | `system.webServer/security/access` → `sslFlags=Ssl` (cần HTTPS binding) | 🟡 |
| 2.7 | L1 | `passwordFormat` không phải Clear | Auto | `forms/credentials` → `passwordFormat` | 🟢 |
| 2.8 | L2 | Không lưu credentials trong file config | Auto | Xóa `<credentials>`; phát hiện bằng đọc `web.config` của site | 🟡 |

**Nhóm 3 — ASP.NET**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 3.1 | L1 | `<deployment retail="true">` | **Manual** | Sửa `machine.config` (32-bit và 64-bit) thủ công, vì sửa file hệ thống nên để manual theo đúng nhãn | 🟡 |
| 3.2 | L2 | `compilation debug=false` | Auto | `system.web/compilation` → `debug` | 🟢 |
| 3.3 | L2 | `customErrors` không Off | Auto | `mode` ∈ {On, RemoteOnly} | 🟢 |
| 3.4 | L1 | `httpErrors errorMode` = DetailedLocalOnly hoặc Custom | Auto | `system.webServer/httpErrors` → `errorMode` | 🟢 |
| 3.5 | L2 | Tắt ASP.NET tracing | Auto | `system.web/trace` → `enabled=False` | 🟢 |
| 3.6 | L2 | Session state dùng cookie | Auto | `sessionState cookieless=UseCookies` | 🟢 |
| 3.7 | L1 | `httpOnlyCookies=true` | Auto | `<httpCookies httpOnlyCookies="true">` | 🟢 |
| 3.8 | L2 | MachineKey validation (.NET 3.5) | Auto | SHA1 hoặc AES | 🟢 |
| 3.9 | L1 | MachineKey validation (.NET 4.5) | Auto | `HMACSHA256` trở lên | 🟢 |
| 3.10 | L1 | Global .NET trust level ≤ Medium | Auto | `system.web/trust` → `level=Medium` | 🔴 (app cần Full Trust sẽ lỗi) |
| 3.11 | L2 | Bỏ header `X-Powered-By` | **Manual** | Xóa custom header `X-Powered-By` | 🟢 |
| 3.12 | L2 | Bỏ header `Server` | **Manual** | `requestFiltering removeServerHeader=True` | 🟢 |

**Nhóm 4 — Request Filtering**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 4.1 | L2 | `maxAllowedContentLength` | **Manual** | Đặt giá trị phù hợp từng app (mặc định 30000000) | 🟡 |
| 4.2 | L2 | `maxUrl` | Auto | `requestLimits` → `maxUrl` (4096) | 🟢 |
| 4.3 | L2 | `maxQueryString` | Auto | `maxQueryString` (2048) | 🟢 |
| 4.4 | L2 | Cấm ký tự non-ASCII trong URL | Auto | `allowHighBitCharacters=False` | 🟡 (site đa ngôn ngữ) |
| 4.5 | L1 | Từ chối double-encoded request | Auto | `allowDoubleEscaping=False` | 🟡 |
| 4.6 | L1 | Chặn HTTP TRACE | **Manual** | `requestFiltering/verbs`: `TRACE allowed=false`; kiểm chứng `curl -X TRACE` → 404.6 | 🟢 |
| 4.7 | L1 | Không cho phép đuôi file chưa liệt kê | Auto | `fileExtensions allowUnlisted=False`, phải liệt kê đuôi cần dùng | 🔴 |
| 4.8 | L1 | Handler không có cả Write và Script/Execute | **Manual** | `handlers accessPolicy` phải là `Read,Script`; **không sửa được bằng IIS Manager** | 🟢 |
| 4.9 | L1 | `notListedIsapisAllowed=false` | Auto | `isapiCgiRestriction` | 🟢 |
| 4.10 | L1 | `notListedCgisAllowed=false` | Auto | `isapiCgiRestriction` | 🟢 |
| 4.11 | L1 | Bật Dynamic IP Restrictions | **Manual** | `dynamicIpSecurity/denyByConcurrentRequests`; phải kích hoạt thử để thấy 403 | 🟡 |

**Nhóm 5 — Logging**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 5.1 | L1 | Chuyển log khỏi ổ hệ thống | Auto | `siteDefaults/logFile` → `directory`; set NTFS ACL chỉ Administrators + SYSTEM | 🟢 |
| 5.2 | L1 | Bật Advanced Logging | Auto | Xem §10 (ghi chú: module Advanced Logging) | 🟡 |
| 5.3 | L1 | Bật ETW logging | **Manual** | Logging → W3C + "Both log file and ETW event"; kiểm chứng bằng Message Analyzer/`logman` | 🟢 |

**Nhóm 6 — FTP**

| ID | Lv | Tiêu chí | Loại | Kiểm tra / Khắc phục (rút gọn) | Rủi ro |
|---|---|---|---|---|---|
| 6.1 | L1 | FTP dùng SSL | **Manual** | `controlChannelPolicy` & `dataChannelPolicy` = `SslRequire` | 🟡 |
| 6.2 | L1 | Giới hạn đăng nhập FTP thất bại | **Manual** | `system.ftpServer/security/authentication/denyByFailure` → `enabled=True` | 🟢 |

**Nhóm 7 — Transport Encryption** (tất cả là registry SCHANNEL, cần **reboot** để có hiệu lực)

| ID | Lv | Tiêu chí | Loại | Registry (dưới `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\`) | Rủi ro |
|---|---|---|---|---|---|
| 7.1 | L2 | HSTS header | **Manual** | Custom header `Strict-Transport-Security` | 🟡 (khó gỡ nếu đã gửi max-age lớn) |
| 7.2 | L1 | Tắt SSLv2 | Auto | `Protocols\SSL 2.0\{Server,Client}`: `Enabled=0`, `DisabledByDefault=1` | 🟢 |
| 7.3 | L1 | Tắt SSLv3 | Auto | tương tự với `SSL 3.0` | 🟢 |
| 7.4 | L1 | Tắt TLS 1.0 | Auto | tương tự với `TLS 1.0` | 🔴 |
| 7.5 | L1 | Tắt TLS 1.1 | Auto | tương tự với `TLS 1.1` | 🔴 |
| 7.6 | L1 | Bật TLS 1.2 | Auto | `Protocols\TLS 1.2\Server`: `Enabled=1`, `DisabledByDefault=0` | 🟢 |
| 7.7 | L1 | Tắt NULL cipher | Auto | `Ciphers\NULL` → `Enabled=0` | 🟢 |
| 7.8 | L1 | Tắt DES | Auto | `Ciphers\DES 56/56` → `Enabled=0` | 🟢 |
| 7.9 | L1 | Tắt RC4 | Auto | `Ciphers\RC4 40/128`, `56/128`, `64/128`, `128/128` → `Enabled=0` | 🟡 |
| 7.10 | L1 | Tắt AES 128/128 | Auto | `Ciphers\AES 128/128` → `Enabled=0` | 🟡 |
| 7.11 | L1 | Bật AES 256/256 | Auto | `Ciphers\AES 256/256` → `Enabled=1` | 🟢 |
| 7.12 | L2 | Thứ tự cipher suite | Auto | `HKLM\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002` → `Functions` | 🟡 |

**Tổng kết kế hoạch triển khai:**

- **Auto:** 30 L1 + 2 L2 (7.12, 4.2) = 32 mục chạy tự động mặc định.
- **Manual:** 10 L1 + 2 L2 (3.12, 7.1) = 12 mục làm thủ công.
- 11 mục L2 còn lại không nằm trong phạm vi đề xuất. Nếu còn thời gian, thêm `-AllL2` để chạy nốt 9 mục L2 Auto (2.4, 2.8, 3.2, 3.3, 3.5, 3.6, 3.8, 4.3, 4.4), vì cùng mẫu `Get/Set-WebConfigurationProperty`.

---

## 6. Phân công (4 nhóm)

Ảnh nói "chọn 3 đến 4 mục trên 9 mục". Benchmark này có **7 nhóm**, nên gom lại thành 4 nhóm làm việc, số mục tương đối đều. Mỗi nhóm có sẵn thư mục script riêng:

| Nhóm | Phạm vi | Số mục | Thư mục script | Đặc điểm công việc |
|---|---|---:|---|---|
| **A** | Nhóm 1 + 2: cấu hình cơ bản, authN/Z | 15 | `1-Basic`, `2-AuthN-AuthZ` | Nhiều thao tác app pool/site, 3 mục manual (1.1, 2.1, 2.2) |
| **B** | Nhóm 3: ASP.NET | 12 | `3-ASPNET` | Hầu hết một mẫu `Set-WebConfigurationProperty`, 3 mục manual (3.1, 3.11, 3.12) |
| **C** | Nhóm 4 + 5 + 6: request filtering, logging, FTP | 16 | `4-RequestFiltering`, `5-Logging`, `6-FTP` | Nhiều mục manual (4.1, 4.6, 4.8, 4.11, 5.3, 6.1, 6.2). Cần cài FTP, và kiểm chứng bằng request giả lập. Phần 6 chỉ có mục manual |
| **D** | Nhóm 7: TLS/cipher | 12 | `7-TLS` | Một mẫu registry lặp lại, cần reboot. Kiểm chứng bằng `nmap`/`testssl.sh`. Phần HSTS (7.1) |

Mỗi người phụ trách một nhóm phải tự trả lời được 3 câu (xem §8): tiêu chí này chống rủi ro gì, kiểm tra bằng cách nào, làm sao xác nhận remediate không phá dịch vụ.

---

## 7. Thiết kế công cụ tự động hóa

### 7.1 Lựa chọn công cụ

| Phương án | Ưu | Nhược |
|---|---|---|
| **PowerShell + module `WebAdministration`** (đã chọn) | Có sẵn trên Windows, đúng các lệnh mà benchmark đã cho, không cần cài thêm | Phải tự viết khung báo cáo |
| `appcmd.exe` | Có sẵn, nhanh | Khó parse output, chỉ dùng cho sao lưu/hoàn tác |
| DSC / Ansible (`win_*`) | Tốt cho triển khai nhiều máy | Học thêm, hơi nặng cho 1 máy; để như hướng mở rộng |
| Audit bên ngoài (`nmap --script ssl-enum-ciphers`, `testssl.sh`, `curl`) | Kiểm chứng từ góc nhìn kẻ tấn công cho nhóm 4 và 7 | Không đọc được config nội bộ |

### 7.2 Cấu trúc

```
run\automation\
├── scripts\
│   ├── 00-Setup-Lab.ps1, 01-Seed-Baseline.ps1   dựng lab, tạo baseline
│   ├── IIS-CIS.ps1                               chạy MỘT LẦN cả 7 phần (Audit / Remediate / Report)
│   └── Common.ps1                                bộ máy dùng chung
└── 1-Basic ... 7-TLS\   mỗi thư mục: Audit.ps1, Remediate.ps1, checks.ps1
```

- **`checks.ps1`** của mỗi phần là nơi **định nghĩa tiêu chí**. Mỗi tiêu chí là một mục dữ liệu gồm: mã, tên, level, **đợt sửa** (1, 2 hoặc 3), cách **kiểm tra** (`Test`), cách **sửa** (`Fix`), mô tả cách sửa (`FixHint`) và cờ cần reboot. Các mục Manual của phần đó được liệt kê riêng.
- **`Audit.ps1`**, **`Remediate.ps1`** của từng phần và **`IIS-CIS.ps1`** cùng đọc các `checks.ps1`, nên chạy từng phần hay chạy một lần đều ra **cùng kết quả**, không có hai bản lệch nhau.
- **`Common.ps1`** chứa bộ máy: các hàm đọc/ghi cấu hình, vòng lặp Audit/Remediate, sao lưu, xác nhận, và xuất báo cáo.

### 7.3 Ba chế độ và ba đợt sửa

| Chế độ | Làm gì | Sửa hệ thống? |
|---|---|---|
| `Audit` | Kiểm tra mục Automated trong phạm vi, ghi `PASS`/`FAIL`/`N/A`/`ERROR`, liệt kê mục Manual thành `MANUAL` | **Không** |
| `Remediate` | Sao lưu → sửa các mục FAIL của đợt được chọn → kiểm tra lại ngay → ghi Before/After | **Có** |
| `Report` | Ghép hai file kết quả (trước và sau) thành báo cáo so sánh | Không |

| Đợt | Rủi ro | Số mục | Xác nhận |
|---|---|---:|---|
| **1** | Thấp | 23 | Có thể dùng `-Force` để không hỏi |
| **2** | Trung bình | 14 | Có thể dùng `-Force`; nên kiểm tra site sau đợt này |
| **3** | Cao (3.10, 4.7, 7.4, 7.5) | 4 | **Luôn hỏi `y/N` từng mục**, trừ khi dùng `-ForceHighRisk` |

Quy trình: `Audit (baseline)` → `Remediate đợt 1` → kiểm tra site → `Remediate đợt 2` → kiểm tra site → `Remediate đợt 3` (hỏi từng mục) → reboot → `Audit` (sau) → `Report` (so sánh). **`Audit` được chạy hai lần** (trước và sau khi sửa); `Remediate` tự kiểm tra lại từng mục vừa sửa nhưng đó chỉ là bước xác nhận nhanh.

### 7.4 Tham số chính

| Tham số | Ý nghĩa |
|---|---|
| `-Mode Audit \| Remediate \| Report` | Chế độ (chỉ `IIS-CIS.ps1`; script từng phần đã cố định chế độ) |
| `-Wave 1,2,3` | Đợt cần sửa |
| `-Id '1.3','4.2'` | Chỉ chạy các mục này. **Luôn đặt id trong dấu nháy**: PowerShell biến `3.10` không có nháy thành `3.1` |
| `-AllL2` | Thêm tất cả mục L2 Automated |
| `-Force` / `-ForceHighRisk` | Bỏ hỏi xác nhận đợt 1-2 / đợt 3 |
| `-WhatIf` | Chạy khô: in dự định sửa, không thay đổi gì |
| `-Label` | Nhãn đặt vào tên thư mục kết quả |
| `-OutDir` | Thư mục kết quả (mặc định `automation\out`) |

Một số mục có tham số riêng: `-HostMap`/`-HostSuffix` (1.2), `-AllowedExtensions` (4.7), `-LogDir` (5.1, không được nằm trên ổ hệ thống).

### 7.5 Nguyên tắc thiết kế

1. **Audit tách khỏi Remediate**: audit chỉ đọc, an toàn và chạy lại nhiều lần.
2. **Remediate có xác nhận** (ảnh: "một số thay đổi cần sự xác nhận"). Mục rủi ro cao (đợt 3) luôn hỏi lại, trừ khi chủ động dùng `-ForceHighRisk`.
3. **Sao lưu trước khi sửa**: `appcmd add backup` và `reg export` cho SCHANNEL; in cách hoàn tác. Nếu sao lưu lỗi, script dừng và không sửa gì.
4. **Không tự sửa các mục Manual**. Script chỉ liệt kê chúng; `Check-ManualItems.ps1` cho biết mục nào còn `TODO`.
5. **Sửa theo từng mục và chỉ khi giá trị chưa đạt**, nên chạy lại không gây thay đổi thừa (thiết kế như vậy; chưa kiểm chứng trên IIS thật).
6. **Kiểm tra quyền Administrator** khi chạy, dừng sớm nếu thiếu.
7. **Chỉ dùng ký tự ASCII** trong script để tránh lỗi mã hóa trên Windows PowerShell 5.1.

### 7.6 Mức kiểm chứng của công cụ

- Toàn bộ script đã qua bộ phân tích cú pháp của Windows PowerShell 5.1.
- Đã chạy thử trên **IIS và registry giả lập**: từng phần (Audit, Remediate, Audit lại), script chạy một lần (Audit, Remediate đợt 1-2-3, Audit lại, Report so sánh), `-WhatIf` không ghi gì, id không tồn tại, chọn trống, và phần 6 (chỉ có mục Manual). Mọi mục sửa xong đều PASS, trừ 5.1 do chủ ý thử đường báo lỗi.
- **Chưa chạy trên IIS thật.** Hành vi cụ thể của các lệnh `WebAdministration` thật cần được kiểm chứng trên VM. `00-Setup-Lab.ps1` và `01-Seed-Baseline.ps1` mới chỉ kiểm tra cú pháp.

---

## 8. Với mỗi nhóm: vì sao không an toàn, kiểm tra thế nào

Phần này để mỗi thành viên trả lời khi vấn đáp (ảnh mục 4). Nội dung lấy từ phần *Rationale* và *Audit* của benchmark.

**Nhóm A (1–2)**
- **Directory browsing (1.3):** nếu không có default document, IIS liệt kê toàn bộ file trong thư mục → lộ backup, file cấu hình. Kiểm tra: `directoryBrowse enabled="false"`; kiểm chứng bằng cách browse vào thư mục không có `index.html`.
- **App pool identity (1.4–1.6):** pool chạy bằng tài khoản nhiều quyền (hoặc dùng chung) thì khi app bị chiếm, kẻ tấn công thừa hưởng quyền đó và nhảy sang site khác. Kiểm tra: `identityType`, và pool nào đang được nhiều site chia sẻ.
- **Forms/Basic auth không có SSL (2.3, 2.6):** credential đi qua mạng dạng rõ. Kiểm tra: `requireSSL`, `sslFlags`; truy cập bằng `http://` phải nhận 403.4.
- **Global authorization (2.1):** mặc định "allow all", nội dung mới thêm vào sẽ mở cho tất cả.

**Nhóm B (3)**
- **Rò rỉ thông tin (3.1–3.5):** debug/trace/detailed error để lộ stack trace, đường dẫn, phiên bản. Lưu ý 3.2/3.3/3.5 là **defense in depth** vì `deployment retail=true` (3.1) đã ghi đè.
- **HttpOnly (3.7):** giảm thiệt hại của XSS (script không đọc được `document.cookie`).
- **Trust level (3.10):** Full Trust cho app toàn quyền; Medium chặn truy cập file ngoài thư mục app và registry.
- **Header (3.11, 3.12):** giúp kẻ tấn công fingerprint công nghệ để nhắm lỗ hổng đã biết. Kiểm chứng bằng `curl -I`.

**Nhóm C (4–6)**
- **TRACE (4.6):** phản chiếu header của request (cookie, auth) trong response. Kiểm chứng: `curl -X TRACE http://host/` phải trả 404.6/405.
- **Double-encoding, non-ASCII, URL/query quá dài (4.2–4.5):** tấn công canonicalization, và gây hành vi bất thường của app. Kiểm chứng bằng URL tạo sẵn (`%252e%252e`, URL > 4096) và đọc mã 404.11/404.14/404.15 trong log.
- **Unlisted extensions, ISAPI/CGI (4.7, 4.9, 4.10):** ngăn tải `.config`, `.bat`, hoặc chạy binary lạ được thả lên server.
- **Write + Script/Execute (4.8):** cho phép upload rồi thực thi mã.
- **Log (5.1–5.3):** kẻ tấn công thường xóa log; log trên ổ hệ thống có thể bị đầy hoặc bị sửa. ETW cho phép xem gần thời gian thực.
- **FTP (6.1, 6.2):** FTP thường truyền credential dạng rõ và dễ bị brute-force.

**Nhóm D (7)**
- Giao thức cũ (SSLv2/v3, TLS 1.0/1.1) và cipher yếu (NULL, DES, RC4) có lỗ hổng đã biết (ví dụ POODLE cho SSLv3, benchmark có tham chiếu). Kiểm tra: đọc `Enabled`/`DisabledByDefault` trong registry **và** kiểm chứng từ ngoài bằng `nmap --script ssl-enum-ciphers -p 443 <host>` hoặc `testssl.sh`.
- **Hiểu vì sao có hai khóa `Enabled` và `DisabledByDefault`:** theo benchmark, `Enabled=0` là cách tắt chắc chắn (app không ghi đè được); `DisabledByDefault=1` chỉ ngăn gửi Hello qua giao thức đó và có thể bị app ghi đè.
- **HSTS (7.1):** buộc trình duyệt luôn dùng HTTPS, chặn SSL-strip.
- **Cipher order (7.12):** ưu tiên suite có Perfect Forward Secrecy và hash mạnh.

---

## 9. Báo cáo đầu ra (bước 6 của ảnh)

### 9.1 Cấu trúc báo cáo tự động

Mỗi lần chạy tạo một thư mục `automation\out\<thời-gian>-<nhãn>\` gồm ba file: `results.csv` và `results.json` (cho máy đọc, dùng để so sánh trước/sau) và `report.html` (cho người đọc). Chế độ `Report` tạo thêm thư mục `...-compare` ghép hai lần chạy. `report.html` gồm:

1. **Header:** tên máy, thời điểm tạo, benchmark.
2. **Summary:** số lượng `PASS / FAIL / N/A / ERROR / MANUAL` ở cột *Before*, và cột *After* nếu đã sửa hoặc so sánh.
3. **Needs action now:** các dòng còn `FAIL`/`ERROR`, xếp theo đợt, kèm **cách sửa đề xuất** và **lệnh gợi ý để chạy**.
4. **All results:** toàn bộ dòng với `Before`, `After`, `Action` (`Fixed`, `Declined`, `WhatIf`, `FixError: ...`) và `Detail` (giá trị đo thực tế), tô màu theo trạng thái.

Các cột trong `results.csv`: `Id`, `Title`, `Level`, `Wave`, `Target`, `Before`, `After`, `Action`, `Detail`, `FixHint`. Một tiêu chí có thể có nhiều dòng, mỗi dòng một đối tượng (server, từng site, từng app pool, từng khóa registry).

Các mục **Manual** xuất hiện dưới dạng dòng `MANUAL`; trạng thái chi tiết của chúng lấy từ `Check-ManualItems.ps1` (`DONE`/`TODO`/`REVIEW`/`N/A`/`ERROR`, lưu CSV riêng) để làm bằng chứng.

Người đọc từ báo cáo thấy rõ:
- **Thực trạng hạ tầng** (Summary).
- **Cái nào cần xử lý ngay** (Needs action now).
- **Chạy lệnh gì để khắc phục** (cột Suggested fix và Command).
- **Cái nào cần xác nhận** trước khi áp dụng (đợt 3 luôn hỏi; cột Wave cho biết đợt).

Báo cáo HTML chưa có tỉ lệ tuân thủ theo nhóm/level; số liệu đó xem ở sheet *Tổng quan* của file Excel tracker.

### 9.2 Mẫu bảng kết quả (điền sau khi chạy trên VM)

| | Trước | Sau |
|---|---:|---:|
| PASS | _ | _ |
| FAIL | _ | _ |
| N/A | _ | _ |
| MANUAL (đã làm tay) | _ | _ |

| ID | Trạng thái trước | Trạng thái sau | Ghi chú / bằng chứng |
|---|---|---|---|
| … | | | |

---

## 10. Điểm cần lưu ý khi áp dụng (phát hiện khi đọc benchmark)

Một số chỗ trong PDF mâu thuẫn hoặc dễ làm sai nếu copy lệnh nguyên văn. Các script đã xử lý như cột bên phải, và đây cũng là điểm cộng khi trình bày:

| Mục | Vấn đề | Cách xử lý trong script |
|---|---|---|
| **4.5** | Lệnh PowerShell remediation trong PDF đặt `allowDoubleEscaping` = **`"True"`**, ngược với mục tiêu (phải `False`; lệnh `appcmd` trong cùng mục đúng) | Đặt `False` |
| **1.7** | Phần Audit dùng `Install-WindowsFeature Web-DAV-Publishing` (lệnh này **cài** feature chứ không chỉ kiểm tra) | Audit bằng `Get-WindowsFeature Web-DAV-Publishing` |
| **1.6** | Lệnh PowerShell remediation đặt `passAnonymousToken` trên app pool, không phải `anonymousAuthentication userName=""` mà phần Audit kiểm tra | Đặt thẳng `userName` thành chuỗi rỗng bằng `Set-WebConfigurationProperty` (không dùng `--password` như lệnh `appcmd` trong PDF) |
| **3.6** | Lệnh PowerShell remediation đặt `mode = StateServer`, không liên quan đến `cookieless=UseCookies` mà audit yêu cầu | Đặt `cookieless` trên `system.web/sessionState` |
| **2.7 vs 2.8** | 2.7 chấp nhận hash SHA1 trong `<credentials>`, còn 2.8 (L2) yêu cầu không có `<credentials>` | Nếu làm cả L2 thì 2.8 là điều kiện chặt hơn, 2.7 tự thỏa khi 2.8 PASS |
| **7.10 vs 7.12** | 7.10 tắt cipher `AES 128/128`, nhưng danh sách 7.12 vẫn có các suite AES-128 (GCM/CBC) | Nêu rõ trong báo cáo; kiểm chứng bằng `testssl.sh` xem suite nào còn thương lượng được thực tế |
| **7.x** | Thay đổi SCHANNEL cần **reboot**; bật/tắt giao thức có thể làm khách hàng cũ không kết nối được | Sao lưu registry tự động, in nhắc reboot, test lại site sau khi chạy |
| **5.2** | Benchmark nói Advanced Logging "enabled by default", nhưng audit chỉ yêu cầu có file log do module sinh ra. Module *IIS Advanced Logging* là add-on riêng; **chưa xác minh** có cài được trên Windows Server 2022 | Script **không cài** module; kiểm tra/đặt các trường log W3C theo bước *Select Fields* của PDF và báo trạng thái module. Nếu không cài được, ghi nhận là ngoại lệ có lý do |
| **Nhóm 2–3** | Nhiều mục chỉ có nghĩa nếu app có dùng Forms auth/ASP.NET. Không có thì không có đối tượng kiểm tra | Trả `N/A` thay vì `FAIL` |
| **`-Id` trên dòng lệnh** | PowerShell biến `-Id 3.10` (không nháy) thành số `3.1`, chạy nhầm mục | Luôn viết `-Id '3.10'`; script in dòng `Checks selected (...)` để kiểm tra |
| **Profile** | Benchmark nhắm Windows Server 2016, lab chạy 2022 | Ghi rõ trong báo cáo; đối chiếu "Default Value" của PDF với giá trị đo thực tế trên 2022 |

---

## 11. Kế hoạch thực hiện

| Bước | Việc | Ai |
|---|---|---|
| 1 | Cài VM Windows Server 2022 Desktop, chạy `00-Setup-Lab.ps1`, chụp snapshot (§4) | Cả nhóm |
| 2 | (Tùy chọn) chạy `01-Seed-Baseline.ps1` để có baseline nhiều FAIL, chụp snapshot | Cả nhóm |
| 3 | Chạy `IIS-CIS.ps1 -Mode Audit -Label before` và `Check-ManualItems.ps1` để có số liệu "trước" | Cả nhóm |
| 4 | Mỗi nhóm chạy `Remediate.ps1` của phần mình theo đợt (`-WhatIf` trước), kiểm tra site sau mỗi đợt | A, B, C, D |
| 5 | Làm thủ công các mục Manual theo `HuongDan_CIS_IIS10.md`, chụp bằng chứng, chạy lại `Check-ManualItems.ps1` | Mỗi nhóm |
| 6 | Reboot, chạy `IIS-CIS.ps1 -Mode Audit -Label after`, rồi `-Mode Report` để so sánh | Cả nhóm |
| 7 | Chạy thật trên VM, ghi nhận ngoại lệ và chỗ khác với PDF; điền §9.2 | Cả nhóm |
| 8 | Cập nhật Excel tracker, ghép báo cáo, chuẩn bị trả lời câu hỏi §8 | Cả nhóm |

---

## 12. Giới hạn của báo cáo này

- **Chưa chạy trên IIS thật.** Bộ script đã qua kiểm tra cú pháp và chạy thử trên IIS giả lập; kết quả trước/sau trên VM thật chưa có. Cần chạy thử trên VM trước khi tin.
- Mức rủi ro 🟢/🟡/🔴 là đánh giá của người viết báo cáo, không phải của CIS.
- Một số tiêu chí là **cách hiểu của người viết** khi PDF mâu thuẫn (ví dụ 5.2), và một số giá trị là lựa chọn cho lab (danh sách đuôi file ở 4.7, tên host ở 1.2).
- Script kiểm tra ở mức server, từng site và `ROOT`; **chưa quét từng application hay virtual directory** bên trong site.
- Script **không thay thế CIS-CAT** (công cụ đánh giá chính thức của CIS). Kết quả nên báo cáo là "đạt X/Y tiêu chí trong phạm vi đã chọn, kèm ngoại lệ", không phải "đạt chuẩn CIS".
- Danh sách 4 mục L2 ở §5.2 là đề xuất, nên chốt lại với thầy (ảnh ghi "1–2", lời thầy là "một số").
- Phần Nhóm 7 chỉ tóm tắt registry key; chi tiết đầy đủ (kể cả lệnh tạo key) nằm ở benchmark trang 134–172.
