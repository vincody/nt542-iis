# ⚠️ Cảnh báo: KHÔNG chạy trên máy chính

Các script và lệnh trong repo này **sửa cấu hình hệ thống**: IIS, `machine.config`, registry SCHANNEL (tắt TLS 1.0/1.1, đổi thứ tự cipher), thư mục log, quyền truy cập. Chúng có thể làm các site hoặc kết nối mạng ngừng hoạt động, và một số thay đổi cần **khởi động lại** máy.

- **Chỉ chạy trong máy ảo (VM) dành riêng cho bài lab** (Windows Server 2022 Desktop), và **chụp snapshot trước khi sửa** để quay lại được.
- **Không chạy trên máy cá nhân hoặc máy đang dùng cho việc khác.** Đặc biệt đừng chạy `01-Seed-Baseline.ps1` ngoài VM vì nó cố tình làm yếu cấu hình.
- Chỉ **kiểm tra (Audit)** thì an toàn hơn vì chỉ đọc; còn **sửa (Remediate)** thì không. Dùng `-WhatIf` để xem trước những gì sẽ thay đổi.
- Script **chưa được chạy trên IIS thật**, chỉ mới kiểm tra cú pháp và chạy thử trên IIS giả lập. Hãy thử trên VM trước khi tin kết quả.

---

# 👉 Đọc hướng dẫn trước khi chạy bất kỳ script nào

Hãy **vào các thư mục `scripts` và đọc kỹ file hướng dẫn `.md` đi kèm** để hiểu rõ từng bước, tham số và rủi ro. README này chỉ là tóm tắt.

| Bạn muốn | Vào thư mục | Đọc file |
|---|---|---|
| Chạy tự động (audit, sửa theo đợt, báo cáo) | [`run/automation/scripts`](run/automation/scripts) | [`run/automation/TuDongHoa_CIS_IIS10.md`](run/automation/TuDongHoa_CIS_IIS10.md) |
| Làm thủ công 14 mục Manual, xem hướng dẫn từng tiêu chí | [`run/manual/scripts`](run/manual/scripts) | [`run/manual/HuongDan_CIS_IIS10.md`](run/manual/HuongDan_CIS_IIS10.md) |
| Hiểu toàn bộ kế hoạch và phân tích | thư mục gốc | [`BaoCao_CIS_IIS10.md`](BaoCao_CIS_IIS10.md) |

---

# NT542: Hardening Microsoft IIS 10 theo CIS Benchmark v1.2.1

Đồ án môn NT542. Mục tiêu: đánh giá và củng cố (hardening) một web server **Windows Server 2022 + IIS 10** theo **CIS Microsoft IIS 10 Benchmark v1.2.1**, kết hợp tự động hóa và làm thủ công.

## Dự án làm gì

Benchmark có **55 tiêu chí** (40 Level 1, 15 Level 2), chia **7 nhóm**. Theo yêu cầu của thầy, nhóm làm **toàn bộ Level 1** và **một số Level 2**:

- Tiêu chí CIS gắn nhãn **Automated** (41 mục) thì **tự động hóa**: có script kiểm tra và sửa.
- Tiêu chí gắn nhãn **Manual** (14 mục) thì **làm thủ công** theo hướng dẫn, có script hỗ trợ xem trạng thái.
- Mặc định script tự động chạy **32 mục** (30 mục L1 Automated + 2 mục L2 đã chọn: 4.2 và 7.12). Thêm `-AllL2` để chạy cả các mục L2 Automated còn lại.

## Trong repo có gì

| Đường dẫn | Nội dung |
|---|---|
| [`BaoCao_CIS_IIS10.md`](BaoCao_CIS_IIS10.md) | **Báo cáo**: kế hoạch, bảng 55 tiêu chí, thiết kế công cụ, cấu trúc báo cáo xuất ra, các điểm lưu ý |
| [`run/manual/HuongDan_CIS_IIS10.md`](run/manual/HuongDan_CIS_IIS10.md) | **Hướng dẫn từng tiêu chí**: cách kiểm tra, sửa, các bước thủ công cho 14 mục Manual |
| [`run/manual/scripts/Check-ManualItems.ps1`](run/manual/scripts) | Xem trạng thái 14 mục Manual (**chỉ đọc**) |
| [`run/automation/TuDongHoa_CIS_IIS10.md`](run/automation/TuDongHoa_CIS_IIS10.md) | **Hướng dẫn chạy tự động**: cách chạy, tham số, đọc kết quả, xử lý sự cố |
| [`run/automation/scripts/`](run/automation/scripts) | `00-Setup-Lab.ps1` (dựng lab), `01-Seed-Baseline.ps1` (tùy chọn, làm yếu cấu hình), `IIS-CIS.ps1` (chạy một lần cả 7 phần), `Common.ps1` (bộ máy dùng chung) |
| `run/automation/1-Basic` ... `7-TLS` | Mỗi phần 1 đến 7 của benchmark có thư mục riêng với `Audit.ps1`, `Remediate.ps1`, `checks.ps1` |

## Thuật ngữ: Audit, Remediate, checks

| Thuật ngữ | Nghĩa | Sửa máy chủ? |
|---|---|---|
| **Audit** (`Audit.ps1`) | Kiểm tra, đánh giá: chỉ **đọc** cấu hình và so với khuyến nghị CIS, ra `PASS` hoặc `FAIL` | **Không** |
| **Remediate** (`Remediate.ps1`) | Khắc phục: **sửa** các mục `FAIL`, rồi kiểm tra lại ngay | **Có** |
| **checks** (`checks.ps1`) | "Sách công thức": định nghĩa mỗi tiêu chí kiểm tra và sửa bằng gì. **Không chạy trực tiếp**; `Audit.ps1`, `Remediate.ps1` và `IIS-CIS.ps1` đều đọc file này nên cho cùng kết quả | Không |

Thứ tự đúng: **Audit** (số liệu "trước") → **Remediate** (sửa) → **Audit lại** (số liệu "sau") → **Report** (so sánh).

Việc sửa chia **3 đợt theo mức rủi ro**: đợt 1 (thấp, 23 mục), đợt 2 (trung bình, 14 mục), đợt 3 (cao, 4 mục: 3.10, 4.7, 7.4, 7.5, luôn hỏi xác nhận từng mục). Kiểm tra site còn chạy sau mỗi đợt.

## Cách dùng nhanh (trong VM)

> Đây chỉ là bản tóm tắt. Trước khi chạy, hãy mở thư mục `run/automation/scripts` và đọc [`TuDongHoa_CIS_IIS10.md`](run/automation/TuDongHoa_CIS_IIS10.md) (và [`HuongDan_CIS_IIS10.md`](run/manual/HuongDan_CIS_IIS10.md) cho phần thủ công) để biết đầy đủ thông tin.

1. Cài VM **Windows Server 2022 Standard (Desktop Experience)**, thêm đĩa ảo thứ hai (D:), **chụp snapshot**.
2. Chép thư mục `run` vào VM, mở **PowerShell as Administrator**:

```powershell
Set-Location C:\run\automation\scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem C:\run -Recurse -Filter *.ps1 | Unblock-File

.\00-Setup-Lab.ps1                                  # dựng lab (một lần), rồi chụp snapshot
.\01-Seed-Baseline.ps1                              # tùy chọn: tạo baseline nhiều FAIL (chỉ trong VM)

.\IIS-CIS.ps1 -Mode Audit -Label before             # 1) kiểm tra "trước"
.\IIS-CIS.ps1 -Mode Remediate -Wave 1 -WhatIf       # xem trước, không sửa gì
.\IIS-CIS.ps1 -Mode Remediate -Wave 1 -Force        # 2) sửa theo đợt, kiểm tra site sau mỗi đợt
.\IIS-CIS.ps1 -Mode Remediate -Wave 2
.\IIS-CIS.ps1 -Mode Remediate -Wave 3
Restart-Computer                                    # cần cho các mục registry (nhóm 7)

.\IIS-CIS.ps1 -Mode Audit -Label after              # 3) kiểm tra "sau"
```

Muốn làm riêng một phần (ví dụ phần 4): `Set-Location C:\run\automation\4-RequestFiltering` rồi chạy `.\Audit.ps1` và `.\Remediate.ps1`.

Các mục Manual: chạy `run\manual\scripts\Check-ManualItems.ps1` để biết mục nào còn `TODO`, làm thủ công theo `HuongDan_CIS_IIS10.md`, rồi chạy lại để xác nhận `DONE`.

**Lưu ý khi dùng `-Id`:** luôn đặt id trong dấu nháy, ví dụ `-Id '3.10'`. PowerShell biến `3.10` không có nháy thành `3.1` nên sẽ chạy nhầm mục.

Kết quả (CSV, JSON, báo cáo HTML) được ghi vào `run\automation\out\`.

## Mức kiểm chứng

- Toàn bộ script đã qua bộ phân tích cú pháp của Windows PowerShell 5.1.
- Đã chạy thử trên **IIS và registry giả lập**: từng phần (Audit, Remediate, Audit lại), script chạy một lần (Audit, Remediate 3 đợt, Audit lại, Report), `-WhatIf`, id không tồn tại.
- **Chưa chạy trên IIS thật.** `00-Setup-Lab.ps1` và `01-Seed-Baseline.ps1` mới chỉ kiểm tra cú pháp.
- Bộ script **không thay thế CIS-CAT** (công cụ đánh giá chính thức của CIS). Kết quả nên báo cáo là "đạt X/Y tiêu chí trong phạm vi đã chọn, kèm ngoại lệ", không phải "đạt chuẩn CIS".

## Nguồn

- *CIS Microsoft IIS 10 Benchmark v1.2.1* (17-07-2023), Center for Internet Security. Bản quyền thuộc CIS; repo chỉ tham chiếu, không chứa tài liệu gốc.
