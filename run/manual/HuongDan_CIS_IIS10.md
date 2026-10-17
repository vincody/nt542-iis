# Hướng dẫn chi tiết: 55 tiêu chí CIS Microsoft IIS 10 Benchmark v1.2.1

> Nguồn: `CIS_Microsoft_IIS_10_Benchmark_v1.2.1.pdf` (17-07-2023). Môi trường: **Windows Server 2022 (Desktop Experience) + IIS 10**, 1 máy ảo.
>
> **Trạng thái kiểm chứng:** các script trong file này mới được **kiểm tra cú pháp** bằng bộ phân tích PowerShell. **Chưa chạy trên một máy IIS thật**, nên cần thử trên VM (đã snapshot) trước khi tin. Các chỗ tôi chưa chắc được ghi rõ là *chưa kiểm chứng*.

> ## ⚠️ Cảnh báo: KHÔNG chạy trên máy chính
>
> Các lệnh và script trong tài liệu này **sửa cấu hình hệ thống**: IIS, `machine.config`, registry SCHANNEL (tắt TLS 1.0/1.1, đổi thứ tự cipher), thư mục log, quyền truy cập. Chúng có thể làm các site hoặc kết nối mạng ngừng hoạt động, và một số thay đổi cần **khởi động lại** máy.
>
> - **Chỉ chạy trong máy ảo (VM) dành riêng cho bài lab** (Windows Server 2022 Desktop), và **chụp snapshot trước khi sửa** để quay lại được.
> - **Không chạy trên máy cá nhân hoặc máy đang dùng cho việc khác.** Đặc biệt đừng chạy `01-Seed-Baseline.ps1` ngoài VM vì nó cố tình làm yếu cấu hình.
> - Chỉ **kiểm tra (Audit)** thì an toàn hơn vì chỉ đọc; còn **sửa (Remediate)** thì không. Dùng `-WhatIf` để xem trước những gì sẽ thay đổi.

---

## 0. Cách dùng tài liệu

### 0.1 Mỗi tiêu chí có gì

| Loại tiêu chí | Nội dung |
|---|---|
| **Automated** (41 mục) | Script **Audit** (ghi `PASS`/`FAIL`/`N/A`/`ERROR`) + script **Remediate** (sửa) + cách kiểm chứng |
| **Manual** (14 mục) | **Các bước làm thủ công** theo PDF + lệnh kiểm tra hỗ trợ + cách kiểm chứng. Không ép vào script, đúng yêu cầu đề bài |

Đánh dấu phạm vi (theo file Excel theo dõi): **L1** = bắt buộc. **L2 (chọn)** = 4 mục đã chọn: 3.12, 4.2, 7.1, 7.12. **L2 (tùy chọn)** = 11 mục còn lại, có trong tài liệu nhưng ngoài phạm vi đề xuất.

### 0.2 Quy ước

- Chạy **PowerShell as Administrator** trên VM. Nên dùng Windows PowerShell 5.1 (có sẵn trên Server 2022).
- Làm theo thứ tự: **§1 chuẩn bị lab (hoặc chạy `00-Setup-Lab.ps1`) → §2 helper dùng chung (dán trước) → audit baseline → remediate → audit lại**.
- Mọi khối script dùng chung hàm `Add-Result` ở §2 để kết quả gom được vào một danh sách rồi xuất báo cáo (§Phụ lục A).
- Script chỉ dùng ký tự ASCII trong chuỗi, tránh lỗi mã hóa khi lưu thành `.ps1`.
- **Snapshot VM** trước khi remediate, và chạy `appcmd add backup` (xem Phụ lục B).
- Các mục L1 nhóm 7 (TLS/cipher) cần **reboot** mới có hiệu lực.

### 0.3 Các sai sót trong PDF đã được sửa trong tài liệu này

| Mục | PDF ghi | Tài liệu này làm |
|---|---|---|
| 1.6 | PowerShell remediation đặt `passAnonymousToken` trên app pool | Đặt `anonymousAuthentication userName = ''` (đúng điều audit kiểm tra) |
| 1.7 | Audit dùng `Install-WindowsFeature` (lệnh này **cài** feature) | Audit bằng `Get-WindowsFeature` |
| 3.6 | PowerShell remediation đặt `mode = StateServer` | Đặt `sessionState cookieless = UseCookies` (đúng điều audit yêu cầu) |
| 4.5 | PowerShell remediation đặt `allowDoubleEscaping = "True"` | Đặt `False` |
| 5.2 | "Advanced Logging enabled by default" nhưng audit yêu cầu có file log do module sinh ra | Xem chi tiết ở mục 5.2 |
| 7.10 vs 7.12 | 7.10 tắt `AES 128/128` nhưng danh sách 7.12 có các suite AES-128 | Làm theo từng mục; ghi chú xung đột ở 7.12 |

### 0.4 Script đi kèm: chạy file nào

Cấu trúc thư mục:

```
run\
├── manual\
│   ├── HuongDan_CIS_IIS10.md             (file này)
│   └── scripts\
│       └── Check-ManualItems.ps1         xem trạng thái 14 mục Manual (chỉ đọc)
└── automation\
    ├── TuDongHoa_CIS_IIS10.md            (hướng dẫn chạy tự động)
    ├── scripts\
    │   ├── 00-Setup-Lab.ps1              dựng lab
    │   ├── 01-Seed-Baseline.ps1          (tùy chọn) làm yếu cấu hình để có baseline
    │   ├── IIS-CIS.ps1                   chạy MỘT LẦN cả 7 phần: audit / remediate / report
    │   └── Common.ps1                    bộ máy dùng chung (không chạy trực tiếp)
    ├── 1-Basic\             Audit.ps1  Remediate.ps1  checks.ps1
    ├── 2-AuthN-AuthZ\       Audit.ps1  Remediate.ps1  checks.ps1
    ├── 3-ASPNET\            Audit.ps1  Remediate.ps1  checks.ps1
    ├── 4-RequestFiltering\  Audit.ps1  Remediate.ps1  checks.ps1
    ├── 5-Logging\           Audit.ps1  Remediate.ps1  checks.ps1
    ├── 6-FTP\               Audit.ps1  Remediate.ps1  checks.ps1
    └── 7-TLS\               Audit.ps1  Remediate.ps1  checks.ps1
```

Các thư mục `1-Basic` ... `7-TLS` ứng với **§3 đến §9** của file này (Nhóm 1 đến Nhóm 7 của benchmark): mỗi phần có `Audit.ps1` (chỉ kiểm tra) và `Remediate.ps1` (sửa), giống các khối Audit/Remediate trong từng tiêu chí bên dưới nhưng chạy cho cả phần một lần. `checks.ps1` là nơi định nghĩa các tiêu chí, không chạy trực tiếp.

| Bạn muốn | Chạy file | Ghi chú |
|---|---|---|
| Dựng lab (IIS, 2 site, HTTPS, FTP) | `automation\scripts\00-Setup-Lab.ps1` | Thay cho các lệnh ở §1.1 và §1.2 bên dưới |
| Làm yếu cấu hình để có "trước" nhiều FAIL | `automation\scripts\01-Seed-Baseline.ps1` | Tùy chọn, thay cho §1.3. Chỉ dùng trong VM lab |
| Kiểm tra / sửa **cả 7 phần** một lần | `automation\scripts\IIS-CIS.ps1` | Xem `..\automation\TuDongHoa_CIS_IIS10.md` |
| Kiểm tra / sửa **một phần** (ví dụ phần 4) | `automation\4-RequestFiltering\Audit.ps1` và `Remediate.ps1` | Cùng bộ định nghĩa với script chạy một lần |
| Xem trạng thái các mục **Manual** | `manual\scripts\Check-ManualItems.ps1` | Chạy **trước và sau** khi làm thủ công, giữ kết quả làm bằng chứng |

Với 14 mục Manual: chạy `Check-ManualItems.ps1` để biết mục nào còn `TODO`, **làm thủ công** theo các bước trong §3–§9 bên dưới, rồi chạy lại script để xác nhận chuyển sang `DONE`. Script chỉ đọc, không sửa gì. Mục `REVIEW` (2.2, 4.1) cần bạn tự quyết định vì giá trị phụ thuộc ứng dụng.

```powershell
Set-Location C:\run\manual\scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Check-ManualItems.ps1            # kết quả lưu vào .\out\manual-check-<thời gian>.csv
```

Khi dùng `-Id` với script tự động, **luôn đặt id trong dấu nháy** (`-Id '3.10'`), vì PowerShell biến `3.10` không có nháy thành `3.1`.

---

## 1. Chuẩn bị môi trường lab

> Các lệnh trong §1 đã được đóng gói thành `automation\scripts\00-Setup-Lab.ps1` và `01-Seed-Baseline.ps1` (xem §0.4). Nên chạy hai file đó thay vì dán lại các khối bên dưới.

### 1.1 Bật các thành phần IIS cần cho benchmark

```powershell
#Requires -RunAsAdministrator
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, `
  Web-Basic-Auth, Web-Windows-Auth, Web-Url-Auth, Web-IP-Security, Web-Http-Logging, Web-Custom-Logging, `
  Web-Ftp-Server, Web-Mgmt-Console, Web-Scripting-Tools -IncludeManagementTools
```

`Web-DAV-Publishing` **không** cài ở đây vì mục 1.7 yêu cầu *không có* WebDAV. Muốn có baseline FAIL cho 1.7, cài thêm: `Install-WindowsFeature Web-DAV-Publishing`.

### 1.2 Tạo site mẫu, HTTPS và FTP (tùy chọn, để có đối tượng kiểm tra)

Cần **ổ D:** (đĩa ảo thứ hai). Nếu chưa có, đổi `$Drive`.

```powershell
Import-Module WebAdministration
$Drive = 'D:'
$sites = @{ 'SiteA' = 8081; 'SiteB' = 8082 }   # cố tình KHÔNG đặt host header

foreach ($name in $sites.Keys) {
  $path = "$Drive\wwwroot\$name"
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  Set-Content -Path "$path\index.html" -Value "<h1>$name</h1>"
  if (-not (Get-Website -Name $name)) {
    New-Website -Name $name -PhysicalPath $path -Port $sites[$name] -ApplicationPool 'DefaultAppPool' | Out-Null
  }
}

# Cert tu ky + HTTPS binding cho SiteA
$cert = New-SelfSignedCertificate -DnsName 'sitea.lab.local' -CertStoreLocation Cert:\LocalMachine\My
if (-not (Get-WebBinding -Name 'SiteA' -Protocol https)) {
  New-WebBinding -Name 'SiteA' -Protocol https -Port 443 -SslFlags 0
  (Get-WebBinding -Name 'SiteA' -Protocol https).AddSslCertificate($cert.Thumbprint, 'My')
}

# Site FTP (chua SSL) cho nhom 6
New-Item -ItemType Directory -Path "$Drive\ftproot" -Force | Out-Null
if (-not (Get-Website -Name 'FtpLab')) {
  New-WebFtpSite -Name 'FtpLab' -Port 21 -PhysicalPath "$Drive\ftproot" -Force | Out-Null
}
```

### 1.3 Tạo cấu hình "xấu" cho baseline (tùy chọn)

Để audit trước hardening có nhiều `FAIL`:

```powershell
Import-Module WebAdministration
$Drive = 'D:'

# 1.3: bat directory browsing cho SiteB
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST/SiteB' `
  -Filter 'system.webServer/directoryBrowse' -Name enabled -Value $true

# nhom 2-3: web.config co Forms auth, credentials Clear, debug bat, customErrors Off, trace bat
$webConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.web>
    <authentication mode="Forms">
      <forms loginUrl="login.aspx">
        <credentials passwordFormat="Clear">
          <user name="demo" password="demo123" />
        </credentials>
      </forms>
    </authentication>
    <compilation debug="true" />
    <customErrors mode="Off" />
    <trace enabled="true" />
  </system.web>
</configuration>
'@
Set-Content -Path "$Drive\wwwroot\SiteA\web.config" -Value $webConfig -Encoding UTF8

# 2.6: bat Basic auth cho SiteB (section bi khoa o applicationHost nen dung -Location)
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'SiteB' `
  -Filter 'system.webServer/security/authentication/basicAuthentication' -Name enabled -Value $true
```

---

## 2. Helper dùng chung (dán vào PowerShell trước khi chạy bất kỳ khối nào)

```powershell
#Requires -RunAsAdministrator
Import-Module WebAdministration -ErrorAction Stop

$AppHostPath = 'MACHINE/WEBROOT/APPHOST'
$RootWebPath = 'MACHINE/WEBROOT'
$AppCmd      = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Id,
    [ValidateSet('PASS','FAIL','N/A','ERROR','INFO')][string]$Status,
    [string]$Detail = ''
  )
  $script:Results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Detail = $Detail })
  $color = switch ($Status) { 'PASS' {'Green'} 'FAIL' {'Red'} 'ERROR' {'Yellow'} default {'Gray'} }
  Write-Host ('[{0}] {1}  {2}' -f $Status, $Id, $Detail) -ForegroundColor $color
}

# Doc 1 thuoc tinh cau hinh, tra ve gia tri thuan (bo vo ConfigurationAttribute neu co)
function Get-Cfg {
  param([string]$Filter, [string]$Name, [string]$PSPath = $AppHostPath, [string]$Location)
  $p = @{ Filter = $Filter; Name = $Name; PSPath = $PSPath }
  if ($Location) { $p.Location = $Location }
  $v = Get-WebConfigurationProperty @p
  if ($null -ne $v -and $v.PSObject.Properties['Value']) { $v.Value } else { $v }
}

function Set-Cfg {
  param([string]$Filter, [string]$Name, $Value, [string]$PSPath = $AppHostPath, [string]$Location)
  $p = @{ Filter = $Filter; Name = $Name; Value = $Value; PSPath = $PSPath }
  if ($Location) { $p.Location = $Location }
  Set-WebConfigurationProperty @p
}

# Cac site co binding http/https (bo qua site chi co ftp)
function Get-HttpSites {
  Get-Website | Where-Object { @($_.bindings.Collection | Where-Object { $_.protocol -like 'http*' }).Count -gt 0 }
}

# Server + tung site (dung cho section system.webServer, ke ca khi bi web.config ghi de)
function Get-IisPaths {
  $list = @([pscustomobject]@{ Name = 'SERVER'; PSPath = $AppHostPath })
  foreach ($s in Get-HttpSites) { $list += [pscustomobject]@{ Name = $s.Name; PSPath = "$AppHostPath/$($s.Name)" } }
  $list
}

# Root web.config + tung site (dung cho section system.web cua ASP.NET)
function Get-AspPaths {
  $list = @([pscustomobject]@{ Name = 'ROOT'; PSPath = $RootWebPath })
  foreach ($s in Get-HttpSites) { $list += [pscustomobject]@{ Name = $s.Name; PSPath = "$AppHostPath/$($s.Name)" } }
  $list
}

# --- Registry SCHANNEL (nhom 7) ---
$SchannelRoot = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'

function Get-SchannelValue {
  param([string]$SubPath, [string]$Name)
  $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$SchannelRoot\$SubPath")
  if ($null -eq $k) { return $null }
  try { $k.GetValue($Name) } finally { $k.Close() }
}

# Dung API .NET vi ten key co dau '/' (vi du 'AES 128/128') - New-Item cua PowerShell se tach thanh 2 key
function Set-SchannelValue {
  param([string]$SubPath, [string]$Name, [int]$Value)
  $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey("$SchannelRoot\$SubPath")
  try { $k.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() }
}

# Audit mot giao thuc: $Sides = 'Server','Client'
function Test-SchannelProtocol {
  param([string]$Id, [string]$Protocol, [string[]]$Sides, [int]$Enabled, [int]$DisabledByDefault)
  foreach ($side in $Sides) {
    $e = Get-SchannelValue "Protocols\$Protocol\$side" 'Enabled'
    $d = Get-SchannelValue "Protocols\$Protocol\$side" 'DisabledByDefault'
    $okE = ($null -ne $e) -and ((($Enabled -eq 0) -and ($e -eq 0)) -or (($Enabled -ne 0) -and ($e -ne 0)))
    $okD = ($null -ne $d) -and ($d -eq $DisabledByDefault)
    $detail = "$Protocol\$side Enabled=$e DisabledByDefault=$d"
    if ($okE -and $okD) { Add-Result $Id 'PASS' $detail } else { Add-Result $Id 'FAIL' $detail }
  }
}

function Set-SchannelProtocol {
  param([string]$Protocol, [string[]]$Sides, [int]$Enabled, [int]$DisabledByDefault)
  foreach ($side in $Sides) {
    Set-SchannelValue "Protocols\$Protocol\$side" 'Enabled' $Enabled
    Set-SchannelValue "Protocols\$Protocol\$side" 'DisabledByDefault' $DisabledByDefault
  }
}

# Audit mot cipher: $Want = 'Disabled' hoac 'Enabled'
function Test-SchannelCipher {
  param([string]$Id, [string]$Cipher, [ValidateSet('Disabled','Enabled')][string]$Want)
  $e = Get-SchannelValue "Ciphers\$Cipher" 'Enabled'
  $ok = if ($Want -eq 'Disabled') { ($null -ne $e) -and ($e -eq 0) } else { ($null -ne $e) -and ($e -ne 0) }
  $detail = "Ciphers\$Cipher Enabled=$e (want $Want)"
  if ($ok) { Add-Result $Id 'PASS' $detail } else { Add-Result $Id 'FAIL' $detail }
}
```

---

## 3. Nhóm 1 — Basic Configurations

### 1.1 (L1, **Manual**) Ensure 'Web content' is on non-system partition

**Mục tiêu:** nội dung web không nằm trên ổ hệ thống, để tránh hết dung lượng ổ hệ thống và hạn chế lỗi file I/O ảnh hưởng file hệ thống.

**Kiểm tra (hỗ trợ):**

```powershell
$sysDrive = $env:SystemDrive
Get-Website | ForEach-Object {
  $p = [Environment]::ExpandEnvironmentVariables($_.physicalPath)
  [pscustomobject]@{
    Site          = $_.Name
    PhysicalPath  = $p
    OnSystemDrive = $p.StartsWith($sysDrive, [StringComparison]::OrdinalIgnoreCase)
  }
} | Format-Table -AutoSize

# Virtual directory (theo PDF)
& "$env:windir\system32\inetsrv\appcmd.exe" list vdir
```

Mục đạt khi **không** có site/vdir nào có `OnSystemDrive = True`.

**Các bước làm (theo PDF):**

1. Mở nội dung web ở `C:\inetpub\wwwroot\`.
2. Copy sang thư mục riêng, hạn chế quyền, trên ổ khác (ví dụ `D:\webroot\`).
3. Đổi mapping của mọi application/virtual directory sang vị trí mới.

Cách làm bằng lệnh (copy kèm ACL rồi đổi đường dẫn):

```powershell
$Site = 'Default Web Site'
$New  = 'D:\wwwroot\default'
New-Item -ItemType Directory -Path $New -Force | Out-Null
robocopy 'C:\inetpub\wwwroot' $New /E /COPYALL /R:1 /W:1
Set-ItemProperty "IIS:\Sites\$Site" -Name physicalPath -Value $New
```

Bằng giao diện (theo PDF): IIS Manager → mở server → Sites → chọn site/app → **Basic Settings** (khung Actions) → sửa **Physical path**.

**Lưu ý:** phải copy cả ACL và thư mục rỗng (PDF ghi rõ ở phần Impact). Sau khi đổi, truy cập lại site để chắc chắn vẫn chạy.

---

### 1.2 (L1, Automated) Ensure 'Host headers' are on all sites

**Mục tiêu:** mỗi binding HTTP phải có host name, giảm nguy cơ DNS rebinding và bị quét theo IP.

**Audit:**

```powershell
foreach ($site in Get-HttpSites) {
  $bad = @($site.bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation.EndsWith(':') })
  if ($bad.Count -eq 0) {
    Add-Result '1.2' 'PASS' "$($site.Name): all http bindings have host header"
  } else {
    Add-Result '1.2' 'FAIL' "$($site.Name): no host header on $($bad.bindingInformation -join ', ')"
  }
}
```

Binding không có host header có dạng `*:80:` (kết thúc bằng dấu `:`).

**Remediate:** điền đúng host name của từng site vào `$HostMap`.

```powershell
$HostMap = @{ 'SiteA' = 'sitea.lab.local'; 'SiteB' = 'siteb.lab.local' }

foreach ($site in Get-HttpSites) {
  $bad = @($site.bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation.EndsWith(':') })
  foreach ($b in $bad) {
    $h = $HostMap[$site.Name]
    if (-not $h) { Write-Warning "No host name mapped for site '$($site.Name)', skipped"; continue }
    Set-WebBinding -Name $site.Name -BindingInformation $b.bindingInformation -PropertyName HostHeader -Value $h
    Write-Host "Set host header '$h' on $($site.Name) ($($b.bindingInformation))"
  }
}
```

**Kiểm chứng:** thêm vào file hosts rồi gọi bằng tên: `Add-Content "$env:windir\System32\drivers\etc\hosts" "127.0.0.1 sitea.lab.local"`, sau đó `curl.exe -I http://sitea.lab.local:8081/`. Gọi bằng IP thuần (`http://127.0.0.1:8081/`) không còn trả nội dung site.

**Lưu ý (theo PDF):** client HTTP/1.0 không gửi Host header có thể không truy cập được site. Nếu dùng wildcard DNS và wildcard host header, site có thể phục vụ nhiều domain hơn mong muốn.

---

### 1.3 (L1, Automated) Ensure 'Directory browsing' is set to Disabled

**Mục tiêu:** không liệt kê nội dung thư mục khi không có default document.

**Audit:**

```powershell
foreach ($p in Get-IisPaths) {
  try {
    $v = Get-Cfg 'system.webServer/directoryBrowse' 'enabled' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '1.3' 'PASS' "$($p.Name): directoryBrowse enabled=False" }
    else                  { Add-Result '1.3' 'FAIL' "$($p.Name): directoryBrowse enabled=$v" }
  } catch { Add-Result '1.3' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-IisPaths) {
  if ("$(Get-Cfg 'system.webServer/directoryBrowse' 'enabled' $p.PSPath)" -ne 'False') {
    Set-Cfg 'system.webServer/directoryBrowse' 'enabled' $false $p.PSPath
    Write-Host "Disabled directory browsing at $($p.Name)"
  }
}
```

**Kiểm chứng:** truy cập một thư mục không có `index.html`; kết quả mong đợi là lỗi 403 thay vì danh sách file.

**Lưu ý:** nếu cần chia sẻ file ở một thư mục cụ thể, chỉ bật riêng ở thư mục đó (ngoại lệ ghi nhận trong báo cáo).

---

### 1.4 (L1, Automated) Ensure 'application pool identity' is configured for all application pools

**Mục tiêu:** app pool chạy bằng danh tính ít quyền (`ApplicationPoolIdentity`), không dùng `NetworkService`/tài khoản quyền cao.

**Audit:**

```powershell
foreach ($pool in Get-ChildItem IIS:\AppPools) {
  $t = "$($pool.processModel.identityType)"
  if ($t -eq 'ApplicationPoolIdentity') { Add-Result '1.4' 'PASS' "$($pool.Name): $t" }
  else                                  { Add-Result '1.4' 'FAIL' "$($pool.Name): identityType=$t" }
}
$def = Get-Cfg 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' 'identityType'
if ("$def" -in 'ApplicationPoolIdentity','4') { Add-Result '1.4' 'PASS' "defaults: $def" }
else { Add-Result '1.4' 'FAIL' "defaults: identityType=$def" }
```

**Remediate:**

```powershell
foreach ($pool in Get-ChildItem IIS:\AppPools) {
  if ("$($pool.processModel.identityType)" -ne 'ApplicationPoolIdentity') {
    Set-ItemProperty "IIS:\AppPools\$($pool.Name)" -Name processModel.identityType -Value ApplicationPoolIdentity
    Write-Host "Set ApplicationPoolIdentity for pool '$($pool.Name)'"
  }
}
Set-Cfg 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' 'identityType' 'ApplicationPoolIdentity'
```

**Lưu ý (theo PDF):** pool đang dùng tài khoản riêng (ví dụ cho Kerberos web farm) là ngoại lệ hợp lệ; tài khoản đó phải thuộc nhóm `IIS_IUSRS`. Nếu ứng dụng cần quyền cụ thể, kiểm tra lại sau khi đổi. Khởi động lại pool/IIS nếu cần.

---

### 1.5 (L1, Automated) Ensure 'unique application pools' is set for sites

**Mục tiêu:** mỗi site một app pool riêng, để lỗi hoặc bị chiếm ở một site không lan sang site khác.

**Audit:**

```powershell
$groups = Get-Website | Group-Object { "$($_.applicationPool)" } | Where-Object { $_.Count -gt 1 }
if (-not $groups) {
  Add-Result '1.5' 'PASS' 'every site has its own application pool'
} else {
  foreach ($g in $groups) {
    Add-Result '1.5' 'FAIL' "pool '$($g.Name)' shared by: $(($g.Group | ForEach-Object Name) -join ', ')"
  }
}
```

**Remediate:** giữ site đầu tiên với pool cũ, các site còn lại được cấp pool riêng đặt tên theo site.

```powershell
$groups = Get-Website | Group-Object { "$($_.applicationPool)" } | Where-Object { $_.Count -gt 1 }
foreach ($g in $groups) {
  foreach ($site in ($g.Group | Select-Object -Skip 1)) {
    if (-not (Test-Path "IIS:\AppPools\$($site.Name)")) { New-WebAppPool -Name $site.Name | Out-Null }
    Set-ItemProperty "IIS:\Sites\$($site.Name)" -Name applicationPool -Value $site.Name
    Write-Host "Site '$($site.Name)' -> pool '$($site.Name)'"
  }
}
```

**Liệt kê (và tùy chọn dừng) pool không dùng** (PDF khuyến nghị dừng pool không dùng hoặc do cài đặt tạo ra, như `.NET v4.5`):

```powershell
$used = @(Get-Website | ForEach-Object { "$($_.applicationPool)" }) + @(Get-WebApplication | ForEach-Object { "$($_.applicationPool)" })
Get-ChildItem IIS:\AppPools | Where-Object { $_.Name -notin $used } | Select-Object Name, State
# Dung thu cong sau khi da xem danh sach:  Stop-WebAppPool -Name 'ten pool'
```

**Lưu ý:** script chỉ đổi pool của *site*, chưa đổi pool của *application* con bên trong site.

---

### 1.6 (L1, Automated) Ensure 'application pool identity' is configured for anonymous user identity

**Mục tiêu:** để `anonymousAuthentication userName=""` thì Anonymous dùng danh tính của app pool, giúp cô lập từng site.

**Audit:**

```powershell
$f = 'system.webServer/security/authentication/anonymousAuthentication'
foreach ($p in Get-IisPaths) {
  try {
    $u = "$(Get-Cfg $f 'userName' $p.PSPath)"
    if ($u -eq '') { Add-Result '1.6' 'PASS' "$($p.Name): userName is empty (app pool identity)" }
    else           { Add-Result '1.6' 'FAIL' "$($p.Name): userName='$u'" }
  } catch { Add-Result '1.6' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

Mặc định IIS dùng tài khoản `IUSR`, nên baseline thường `FAIL`.

**Remediate:** (sửa so với PDF, xem §0.3)

```powershell
$f = 'system.webServer/security/authentication/anonymousAuthentication'
foreach ($p in Get-IisPaths) {
  if ("$(Get-Cfg $f 'userName' $p.PSPath)" -ne '') {
    Set-Cfg $f 'userName' '' $p.PSPath
    Write-Host "Anonymous identity -> app pool identity at $($p.Name)"
  }
}
```

**Lưu ý:** thư mục web cần cấp quyền đọc cho identity của app pool (`IIS AppPool\<tên pool>`) vì Anonymous không còn là `IUSR`. Nếu site trả 401/403 sau khi đổi: `icacls D:\wwwroot\SiteA /grant "IIS AppPool\SiteA:(OI)(CI)RX"`.

---

### 1.7 (L1, Automated) Ensure 'WebDav' feature is disabled

**Mục tiêu:** gỡ WebDAV Publishing để client không thể tạo/sửa/xóa file qua HTTP.

**Audit:** (sửa so với PDF, xem §0.3)

```powershell
$f = Get-WindowsFeature -Name Web-DAV-Publishing
if ($f.Installed) { Add-Result '1.7' 'FAIL' 'Web-DAV-Publishing is installed' }
else              { Add-Result '1.7' 'PASS' "Web-DAV-Publishing not installed (state: $($f.InstallState))" }
```

**Remediate:**

```powershell
if ((Get-WindowsFeature -Name Web-DAV-Publishing).Installed) {
  $r = Uninstall-WindowsFeature -Name Web-DAV-Publishing
  "Success = $($r.Success); RestartNeeded = $($r.RestartNeeded)"
}
```

**Kiểm chứng:** chạy lại audit; trạng thái phải là `Available`.

---

## 4. Nhóm 2 — Authentication & Authorization

> Các mục 2.3–2.8 chỉ có ý nghĩa nếu có site dùng **Forms Authentication** (ASP.NET). Audit trả `N/A` nếu site không dùng Forms.

### 2.1 (L1, **Manual**) Ensure 'global authorization rule' is set to restrict access

**Mục tiêu:** quy tắc URL Authorization ở cấp server chỉ cho nhóm cần thiết, mọi site/thư mục kế thừa.

**Kiểm tra hiện trạng:**

```powershell
$f = 'system.webServer/security/authorization'
(Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name '.').Collection |
  Select-Object accessType, users, roles, verbs
# Hoac:  & "$env:windir\system32\inetsrv\appcmd.exe" list config -section:system.webserver/security/authorization
```

Đạt khi **không** còn rule `Allow` cho `users="*"`, chỉ còn `Allow` cho `Administrators`. Mặc định IIS cho phép mọi người (`Allow users="*"`).

**Các bước làm (theo PDF):**

1. IIS Manager → chọn **server** → **Authorization Rules**.
2. Xóa rule **Allow All Users**.
3. **Add Allow Rule…** → cho phép nhóm được phép trên mọi site (ví dụ `Administrators`).

Hoặc bằng lệnh:

```powershell
Remove-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/authorization' -Name '.' -AtElement @{ users = '*'; roles = ''; verbs = '' }
Add-WebConfigurationProperty    -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/authorization' -Name '.' -Value @{ accessType = 'Allow'; roles = 'Administrators' }
```

**Rủi ro quan trọng:** sau khi xóa rule *Allow All*, **các site công khai có thể bị chặn** (401/403) nếu không có rule cho phép riêng ở cấp site. Cần tạo rule cho site cần công khai (PDF nêu: nếu cấu hình sai có thể chặn truy cập ngoài ý muốn). **Cách cấp quyền site và thứ tự đánh giá rule chưa được tôi kiểm chứng**, nên làm trên VM đã snapshot và test lại từng site; nếu cần, hoàn tác bằng `appcmd restore backup`.

---

### 2.2 (L1, **Manual**) Ensure access to sensitive site features is restricted to authenticated principals only

**Mục tiêu:** site/ứng dụng/thư mục chứa dữ liệu nhạy cảm phải yêu cầu xác thực (không cho Anonymous).

**Kiểm tra: module xác thực nào đang bật ở từng site:**

```powershell
foreach ($s in Get-HttpSites) {
  Write-Host "== $($s.Name)"
  foreach ($m in 'anonymousAuthentication','basicAuthentication','windowsAuthentication','digestAuthentication','clientCertificateMappingAuthentication') {
    $en = Get-Cfg "system.webServer/security/authentication/$m" 'enabled' $AppHostPath $s.Name
    '{0,-45} enabled={1}' -f $m, $en
  }
  "system.web authentication mode = $(Get-Cfg 'system.web/authentication' 'mode' "$AppHostPath/$($s.Name)")"
}
# Theo PDF:
Get-WebConfiguration system.webServer/security/authentication/* -Recurse | Where-Object { $_.enabled -eq $true } | Format-Table
```

**Các bước làm (theo PDF):**

1. IIS Manager → đi tới cấp có nội dung nhạy cảm (site/app/thư mục).
2. **Authentication** → bảo đảm có một module xác thực được **Enable** (Windows/Basic/Forms…). Với Forms Authentication, Anonymous vẫn có thể bật.
3. Nếu cần, chọn module rồi bấm **Enable** ở khung Actions.

Hoặc bằng lệnh (ví dụ tắt Anonymous, bật Windows cho một site):

```powershell
$Site = 'SiteB'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $Site -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $Site -Filter 'system.webServer/security/authentication/windowsAuthentication'   -Name enabled -Value $true
```

**Lưu ý (theo PDF):** các module xác thực dạng *challenge* (Windows, Basic…) không dùng đồng thời với Forms Authentication. Chỉ áp cho phần nhạy cảm, không áp cho site công khai.

---

### 2.3 (L1, Automated) Ensure 'forms authentication' require SSL

**Mục tiêu:** cookie Forms Authentication chỉ gửi qua HTTPS.

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -ne 'Forms') { Add-Result '2.3' 'N/A' "$($p.Name): not using Forms authentication"; continue }
    $v = Get-Cfg 'system.web/authentication/forms' 'requireSSL' $p.PSPath
    if ("$v" -eq 'True') { Add-Result '2.3' 'PASS' "$($p.Name): requireSSL=True" }
    else                 { Add-Result '2.3' 'FAIL' "$($p.Name): requireSSL=$v" }
  } catch { Add-Result '2.3' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -eq 'Forms' -and "$(Get-Cfg 'system.web/authentication/forms' 'requireSSL' $p.PSPath)" -ne 'True') {
    Set-Cfg 'system.web/authentication/forms' 'requireSSL' $true $p.PSPath
    Write-Host "requireSSL=True at $($p.Name)"
  }
}
```

**Lưu ý:** site phải có HTTPS binding (xem §1.2). Truy cập đăng nhập qua `http://` sẽ không giữ được phiên.

---

### 2.4 (L2, tùy chọn, Automated) Ensure 'forms authentication' is set to use cookies

**Mục tiêu:** không đưa session ID vào URL (tránh lộ qua proxy log, lịch sử trình duyệt, `document.location`).

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -ne 'Forms') { Add-Result '2.4' 'N/A' "$($p.Name): not using Forms authentication"; continue }
    $v = Get-Cfg 'system.web/authentication/forms' 'cookieless' $p.PSPath
    if ("$v" -eq 'UseCookies') { Add-Result '2.4' 'PASS' "$($p.Name): cookieless=UseCookies" }
    else                       { Add-Result '2.4' 'FAIL' "$($p.Name): cookieless=$v" }
  } catch { Add-Result '2.4' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -eq 'Forms' -and "$(Get-Cfg 'system.web/authentication/forms' 'cookieless' $p.PSPath)" -ne 'UseCookies') {
    Set-Cfg 'system.web/authentication/forms' 'cookieless' 'UseCookies' $p.PSPath
  }
}
```

Mặc định là `AutoDetect` (chỉ dùng cookie nếu thiết bị hỗ trợ), nên baseline sẽ `FAIL` nếu site dùng Forms.

---

### 2.5 (L1, Automated) Ensure 'cookie protection mode' is configured for forms authentication

**Mục tiêu:** cookie Forms được vừa mã hóa vừa kiểm tra toàn vẹn (`protection="All"`).

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -ne 'Forms') { Add-Result '2.5' 'N/A' "$($p.Name): not using Forms authentication"; continue }
    $v = Get-Cfg 'system.web/authentication/forms' 'protection' $p.PSPath
    if ("$v" -eq 'All') { Add-Result '2.5' 'PASS' "$($p.Name): protection=All" }
    else                { Add-Result '2.5' 'FAIL' "$($p.Name): protection=$v" }
  } catch { Add-Result '2.5' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -eq 'Forms' -and "$(Get-Cfg 'system.web/authentication/forms' 'protection' $p.PSPath)" -ne 'All') {
    Set-Cfg 'system.web/authentication/forms' 'protection' 'All' $p.PSPath
  }
}
```

**Lưu ý (theo PDF):** giá trị mặc định đã là `All`, thuộc tính chỉ hiện trong `web.config` nếu từng bị đổi. Mục này thường `PASS` sẵn.

---

### 2.6 (L1, Automated) Ensure transport layer security for 'basic authentication' is configured

**Mục tiêu:** nếu dùng Basic Authentication thì bắt buộc TLS (Basic gửi thông tin đăng nhập dạng rõ).

**Audit:** site bật Basic mà chưa yêu cầu SSL là `FAIL`.

```powershell
foreach ($s in Get-HttpSites) {
  try {
    $basic = Get-Cfg 'system.webServer/security/authentication/basicAuthentication' 'enabled' $AppHostPath $s.Name
    if ("$basic" -ne 'True') { Add-Result '2.6' 'N/A' "$($s.Name): Basic authentication not enabled"; continue }
    $flags = "$(Get-Cfg 'system.webServer/security/access' 'sslFlags' $AppHostPath $s.Name)"
    if (($flags -split '[,\s]+') -contains 'Ssl') { Add-Result '2.6' 'PASS' "$($s.Name): sslFlags=$flags" }
    else                                          { Add-Result '2.6' 'FAIL' "$($s.Name): Basic enabled but sslFlags='$flags'" }
  } catch { Add-Result '2.6' 'ERROR' "$($s.Name): $($_.Exception.Message)" }
}
```

**Remediate:** site phải có HTTPS binding trước (§1.2).

```powershell
foreach ($s in Get-HttpSites) {
  if ("$(Get-Cfg 'system.webServer/security/authentication/basicAuthentication' 'enabled' $AppHostPath $s.Name)" -eq 'True') {
    if (-not (Get-WebBinding -Name $s.Name -Protocol https)) { Write-Warning "$($s.Name): no HTTPS binding, add one first"; continue }
    Set-Cfg 'system.webServer/security/access' 'sslFlags' 'Ssl' $AppHostPath $s.Name
  }
}
```

**Kiểm chứng (theo PDF):** truy cập bằng `http://` phải lỗi `403.4 - Forbidden`: `curl.exe -I http://localhost:8082/`.

---

### 2.7 (L1, Automated) Ensure 'passwordFormat' is not set to clear

**Mục tiêu:** nếu `<credentials>` có trong cấu hình thì mật khẩu không được lưu dạng rõ.

**Audit:** đọc trực tiếp `web.config` của từng site.

```powershell
foreach ($s in Get-HttpSites) {
  $cfg = Join-Path ([Environment]::ExpandEnvironmentVariables($s.physicalPath)) 'web.config'
  if (-not (Test-Path $cfg)) { Add-Result '2.7' 'N/A' "$($s.Name): no web.config"; continue }
  try {
    [xml]$x = Get-Content -Path $cfg -Raw
    $c = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
    if ($null -eq $c) { Add-Result '2.7' 'PASS' "$($s.Name): no credentials element" }
    elseif ($c.GetAttribute('passwordFormat') -eq 'Clear') { Add-Result '2.7' 'FAIL' "$($s.Name): passwordFormat=Clear" }
    else { Add-Result '2.7' 'PASS' "$($s.Name): passwordFormat='$($c.GetAttribute('passwordFormat'))'" }
  } catch { Add-Result '2.7' 'ERROR' "$($s.Name): $($_.Exception.Message)" }
}
```

Nếu thuộc tính `passwordFormat` không có, mặc định là `SHA1` (không phải `Clear`).

**Remediate:**

```powershell
foreach ($s in Get-HttpSites) {
  $cfg = Join-Path ([Environment]::ExpandEnvironmentVariables($s.physicalPath)) 'web.config'
  if (-not (Test-Path $cfg)) { continue }
  [xml]$x = Get-Content -Path $cfg -Raw
  $c = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
  if ($c -and $c.GetAttribute('passwordFormat') -eq 'Clear') {
    Copy-Item $cfg "$cfg.bak" -Force
    $c.SetAttribute('passwordFormat', 'SHA1')
    $x.Save($cfg)
    Write-Warning "$($s.Name): passwordFormat set to SHA1. Existing clear-text passwords must be replaced with hashed values."
  }
}
```

**Lưu ý (theo PDF):** các mật khẩu dạng rõ phải được thay bằng bản băm tương ứng, nếu không đăng nhập sẽ hỏng. Mục 2.8 (L2) chặt hơn: yêu cầu bỏ hẳn `<credentials>`.

---

### 2.8 (L2, tùy chọn, Automated) Ensure 'credentials' are not stored in configuration files

**Mục tiêu:** không lưu credentials trong file cấu hình IIS, kể cả dạng băm.

**Audit:**

```powershell
foreach ($s in Get-HttpSites) {
  $cfg = Join-Path ([Environment]::ExpandEnvironmentVariables($s.physicalPath)) 'web.config'
  if (-not (Test-Path $cfg)) { Add-Result '2.8' 'N/A' "$($s.Name): no web.config"; continue }
  try {
    [xml]$x = Get-Content -Path $cfg -Raw
    if ($x.SelectSingleNode('//system.web/authentication/forms/credentials')) { Add-Result '2.8' 'FAIL' "$($s.Name): credentials element present" }
    else { Add-Result '2.8' 'PASS' "$($s.Name): no credentials element" }
  } catch { Add-Result '2.8' 'ERROR' "$($s.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($s in Get-HttpSites) {
  $cfg = Join-Path ([Environment]::ExpandEnvironmentVariables($s.physicalPath)) 'web.config'
  if (-not (Test-Path $cfg)) { continue }
  [xml]$x = Get-Content -Path $cfg -Raw
  $c = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
  if ($c) {
    Copy-Item $cfg "$cfg.bak" -Force
    [void]$c.ParentNode.RemoveChild($c)
    $x.Save($cfg)
    Write-Warning "$($s.Name): credentials removed. Users must come from a membership provider / database instead."
  }
}
```

---

## 5. Nhóm 3 — ASP.NET Configuration

> Các mục này đọc/ghi section `system.web`. Cần đã cài **Web-Asp-Net45**; nếu chưa cài, lệnh trả lỗi (audit ghi `ERROR`, coi như `N/A`).

### 3.1 (L1, **Manual**) Ensure 'deployment method retail' is set

**Mục tiêu:** `<deployment retail="true" />` trong `machine.config` tắt trace, debug và hiển thị lỗi chi tiết cho người dùng.

**Kiểm tra:**

```powershell
$files = @(
  "$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config",
  "$env:windir\Microsoft.NET\Framework\v4.0.30319\Config\machine.config"
)
foreach ($f in $files) {
  if (-not (Test-Path $f)) { "$f : not found"; continue }
  [xml]$x = Get-Content -Path $f -Raw
  $d = $x.SelectSingleNode('//system.web/deployment')
  "{0} : retail = {1}" -f $f, $(if ($d) { $d.GetAttribute('retail') } else { '(not set)' })
}
```

Đạt khi cả hai file (64-bit và 32-bit) có `retail="true"`. Mặc định thẻ này **không có** trong `machine.config`.

**Các bước làm (theo PDF):**

1. Mở `machine.config` tại `%systemroot%\Microsoft.NET\Framework64\<phiên bản>\CONFIG` (và `Framework\<phiên bản>\CONFIG` cho 32-bit) bằng Notepad chạy **Administrator**.
2. Thêm dòng `<deployment retail="true" />` vào trong thẻ `<system.web>`.
3. Lưu, khởi động lại IIS (`iisreset`), mở lại file để xác nhận dòng vẫn còn (PDF nói kiểm tra sau lần IIS khởi động lại).

**Tùy chọn (script hóa các bước trên, có sao lưu):**

```powershell
foreach ($f in @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config", "$env:windir\Microsoft.NET\Framework\v4.0.30319\Config\machine.config")) {
  if (-not (Test-Path $f)) { continue }
  Copy-Item $f "$f.bak" -Force
  [xml]$x = Get-Content -Path $f -Raw
  $sw = $x.SelectSingleNode('//system.web')
  if (-not $sw) { $sw = $x.DocumentElement.AppendChild($x.CreateElement('system.web')) }
  $d = $x.SelectSingleNode('//system.web/deployment')
  if (-not $d) { $d = $sw.AppendChild($x.CreateElement('deployment')) }
  $d.SetAttribute('retail', 'true')
  $x.Save($f)
}
iisreset
```

---

### 3.2 (L2, tùy chọn, Automated) Ensure 'debug' is turned off

**Mục tiêu:** `compilation debug=false` để không lộ thông tin biên dịch debug (lớp phòng thủ bổ sung, vì `deployment retail` ghi đè).

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    $v = Get-Cfg 'system.web/compilation' 'debug' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '3.2' 'PASS' "$($p.Name): debug=False" } else { Add-Result '3.2' 'FAIL' "$($p.Name): debug=$v" }
  } catch { Add-Result '3.2' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/compilation' 'debug' $p.PSPath)" -ne 'False') { Set-Cfg 'system.web/compilation' 'debug' $false $p.PSPath }
}
```

---

### 3.3 (L2, tùy chọn, Automated) Ensure custom error messages are not off

**Mục tiêu:** `customErrors` là `On` hoặc `RemoteOnly` (không phải `Off`).

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    $v = "$(Get-Cfg 'system.web/customErrors' 'mode' $p.PSPath)"
    if ($v -in 'On','RemoteOnly') { Add-Result '3.3' 'PASS' "$($p.Name): mode=$v" } else { Add-Result '3.3' 'FAIL' "$($p.Name): mode=$v" }
  } catch { Add-Result '3.3' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/customErrors' 'mode' $p.PSPath)" -notin 'On','RemoteOnly') { Set-Cfg 'system.web/customErrors' 'mode' 'RemoteOnly' $p.PSPath }
}
```

---

### 3.4 (L1, Automated) Ensure IIS HTTP detailed errors are hidden from displaying remotely

**Mục tiêu:** `httpErrors errorMode` là `DetailedLocalOnly` hoặc `Custom`, không hiện lỗi chi tiết cho người dùng từ xa.

**Audit:**

```powershell
foreach ($p in Get-IisPaths) {
  try {
    $v = "$(Get-Cfg 'system.webServer/httpErrors' 'errorMode' $p.PSPath)"
    if ($v -in 'DetailedLocalOnly','Custom') { Add-Result '3.4' 'PASS' "$($p.Name): errorMode=$v" } else { Add-Result '3.4' 'FAIL' "$($p.Name): errorMode=$v" }
  } catch { Add-Result '3.4' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-IisPaths) {
  if ("$(Get-Cfg 'system.webServer/httpErrors' 'errorMode' $p.PSPath)" -notin 'DetailedLocalOnly','Custom') {
    Set-Cfg 'system.webServer/httpErrors' 'errorMode' 'DetailedLocalOnly' $p.PSPath
  }
}
```

---

### 3.5 (L2, tùy chọn, Automated) Ensure ASP.NET stack tracing is not enabled

**Mục tiêu:** tắt `trace` để không hiển thị stack trace và cấu hình chi tiết.

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    $v = Get-Cfg 'system.web/trace' 'enabled' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '3.5' 'PASS' "$($p.Name): trace enabled=False" } else { Add-Result '3.5' 'FAIL' "$($p.Name): trace enabled=$v" }
  } catch { Add-Result '3.5' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/trace' 'enabled' $p.PSPath)" -ne 'False') { Set-Cfg 'system.web/trace' 'enabled' $false $p.PSPath }
}
```

**Lưu ý (theo PDF):** cần bảo đảm `deployment retail` (3.1) đã bật, và loại bỏ `Trace="true"` trong từng trang `.aspx` nếu có.

---

### 3.6 (L2, tùy chọn, Automated) Ensure 'httpcookie' mode is configured for session state

**Mục tiêu:** session state dùng cookie, không đưa session ID vào URL.

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    $v = "$(Get-Cfg 'system.web/sessionState' 'cookieless' $p.PSPath)"
    if ($v -in 'UseCookies','False') { Add-Result '3.6' 'PASS' "$($p.Name): cookieless=$v" } else { Add-Result '3.6' 'FAIL' "$($p.Name): cookieless=$v" }
  } catch { Add-Result '3.6' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:** (sửa so với PDF, xem §0.3)

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/sessionState' 'cookieless' $p.PSPath)" -notin 'UseCookies','False') {
    Set-Cfg 'system.web/sessionState' 'cookieless' 'UseCookies' $p.PSPath
  }
}
```

---

### 3.7 (L1, Automated) Ensure 'cookies' are set with HttpOnly attribute

**Mục tiêu:** cookie có cờ `HttpOnly`, script phía trình duyệt không đọc được `document.cookie` (giảm thiệt hại của XSS).

**Audit:**

```powershell
foreach ($p in Get-AspPaths) {
  try {
    $v = Get-Cfg 'system.web/httpCookies' 'httpOnlyCookies' $p.PSPath
    if ("$v" -eq 'True') { Add-Result '3.7' 'PASS' "$($p.Name): httpOnlyCookies=True" } else { Add-Result '3.7' 'FAIL' "$($p.Name): httpOnlyCookies=$v" }
  } catch { Add-Result '3.7' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:** đặt ở cấp root để áp cho tất cả, rồi xử lý các site ghi đè.

```powershell
foreach ($p in Get-AspPaths) {
  if ("$(Get-Cfg 'system.web/httpCookies' 'httpOnlyCookies' $p.PSPath)" -ne 'True') {
    Set-Cfg 'system.web/httpCookies' 'httpOnlyCookies' $true $p.PSPath
  }
}
```

**Kiểm chứng:** mở ứng dụng có đặt cookie, kiểm tra header `Set-Cookie` có `HttpOnly`: `curl.exe -I http://localhost:8081/`.

---

### 3.8 (L2, tùy chọn, Automated) Ensure 'MachineKey validation method - .Net 3.5' is configured

**Mục tiêu:** `machineKey validation` là `SHA1` hoặc `AES` cho CLR 2.0/3.5. Mục này chỉ có đối tượng khi đã cài **.NET Framework 3.5**.

**Audit:** đọc `web.config` gốc của CLR 2.0.

```powershell
$f = "$env:windir\Microsoft.NET\Framework64\v2.0.50727\CONFIG\web.config"
if (-not (Test-Path $f)) {
  Add-Result '3.8' 'N/A' '.NET 3.5 (CLR 2.0) config not found'
} else {
  [xml]$x = Get-Content -Path $f -Raw
  $mk = $x.SelectSingleNode('//system.web/machineKey')
  $val = if ($mk -and $mk.GetAttribute('validation')) { $mk.GetAttribute('validation') } else { 'SHA1' }   # mac dinh SHA1
  if ($val -in 'SHA1','AES') { Add-Result '3.8' 'PASS' "validation=$val" } else { Add-Result '3.8' 'FAIL' "validation=$val" }
}
```

**Remediate:**

```powershell
$f = "$env:windir\Microsoft.NET\Framework64\v2.0.50727\CONFIG\web.config"
if (Test-Path $f) {
  Copy-Item $f "$f.bak" -Force
  [xml]$x = Get-Content -Path $f -Raw
  $sw = $x.SelectSingleNode('//system.web')
  $mk = $x.SelectSingleNode('//system.web/machineKey')
  if (-not $mk) { $mk = $sw.AppendChild($x.CreateElement('machineKey')) }
  $mk.SetAttribute('validation', 'SHA1')
  $x.Save($f)
}
```

---

### 3.9 (L1, Automated) Ensure 'MachineKey validation method - .Net 4.5' is configured

**Mục tiêu:** dùng SHA-2 (`HMACSHA256` trở lên) cho validation của machineKey .NET 4.5.

**Audit:**

```powershell
try {
  $v = "$(Get-Cfg 'system.web/machineKey' 'validation' $RootWebPath)"
  if ($v -in 'HMACSHA256','HMACSHA384','HMACSHA512') { Add-Result '3.9' 'PASS' "validation=$v" } else { Add-Result '3.9' 'FAIL' "validation=$v" }
} catch { Add-Result '3.9' 'ERROR' $_.Exception.Message }
```

**Remediate:**

```powershell
Set-Cfg 'system.web/machineKey' 'validation' 'HMACSHA256' $RootWebPath
```

**Lưu ý:** PDF ghi giá trị mặc định là SHA256 và audit kiểm tra `HMACSHA256`; thực tế giá trị trả về có thể khác tên. Kết quả đo thật trên VM mới là căn cứ.

---

### 3.10 (L1, Automated) Ensure global .NET trust level is configured

**Mục tiêu:** trust level toàn cục ở `Medium` hoặc thấp hơn (mặc định `Full`).

**Audit:**

```powershell
try {
  $v = "$(Get-Cfg 'system.web/trust' 'level' $RootWebPath)"
  if ($v -in 'Medium','Low','Minimal') { Add-Result '3.10' 'PASS' "trust level=$v" } else { Add-Result '3.10' 'FAIL' "trust level=$v" }
} catch { Add-Result '3.10' 'ERROR' $_.Exception.Message }
```

**Remediate:**

```powershell
Set-Cfg 'system.web/trust' 'level' 'Medium' $RootWebPath
```

**Rủi ro (theo PDF):** ứng dụng cần quyền cao (gọi unmanaged code, đọc file ngoài thư mục app, đọc registry) có thể không chạy. Test lại ứng dụng thật sau khi đổi.

---

### 3.11 (L2, tùy chọn, **Manual**) Ensure X-Powered-By Header is removed

**Mục tiêu:** bỏ header `X-Powered-By` để khó bị dò công nghệ.

**Kiểm tra:**

```powershell
& "$env:windir\system32\inetsrv\appcmd.exe" list config -section:system.webServer/httpProtocol
# Hoac xem truc tiep cac header tuy chinh:
(Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.').Collection | Select-Object name, value
```

Đạt khi không còn `X-Powered-By`.

**Các bước làm (theo PDF):**

```powershell
Remove-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.' -AtElement @{ name = 'X-Powered-By' }
# Hoac: appcmd.exe set config -section:system.webServer/httpProtocol /-"customHeaders.[name='X-Powered-By']" /commit:apphost
```

Bằng giao diện: IIS Manager → server → **HTTP Response Headers** → chọn `X-Powered-By` → **Remove**.

**Kiểm chứng:** `curl.exe -I http://localhost/` không còn dòng `X-Powered-By`.

---

### 3.12 (L2, **chọn**, **Manual**) Ensure Server Header is removed

**Mục tiêu:** bỏ header `Server: Microsoft-IIS/10.0` (tính năng mới của IIS 10).

**Kiểm tra:**

```powershell
Get-WebConfigurationProperty -PSPath 'machine/webroot/apphost' -Filter 'system.webserver/security/requestfiltering' -Name 'removeServerHeader'
```

Đạt khi giá trị là `True`. Mặc định header là `Microsoft-IIS/10.0`.

**Các bước làm (theo PDF):**

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST/' -Filter 'system.webServer/security/requestFiltering' -Name 'removeServerHeader' -Value 'True'
# Hoac: appcmd.exe set config -section:system.webServer/security/requestFiltering /removeServerHeader:"True" /commit:apphost
```

**Kiểm chứng:** `curl.exe -I http://localhost/`; dòng `Server:` phải biến mất. Nếu vẫn còn, chạy `iisreset` rồi thử lại.

---

## 6. Nhóm 4 — Request Filtering và Other Restriction Modules

> Cần role service **Request Filtering** (có sẵn mặc định trong `Web-Server`). Các mục dùng `Get-IisPaths` kiểm tra cả server lẫn từng site, để phát hiện `web.config` ghi đè.

### 4.1 (L2, tùy chọn, **Manual**) Ensure 'maxAllowedContentLength' is configured

**Mục tiêu:** giới hạn kích thước request (byte) phù hợp từng ứng dụng.

**Kiểm tra:**

```powershell
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/requestLimits' -Name 'maxAllowedContentLength'
```

Mặc định `30000000` (khoảng 28.6 MB). Giá trị phải được quyết định *theo ứng dụng* (ví dụ app upload file lớn cần cao hơn), nên mục này để Manual.

**Các bước làm (theo PDF):**

1. IIS Manager → chọn server/site/app → **Request Filtering** → **Edit Feature Settings…**.
2. Mục **Request Limits** → nhập `Maximum allowed content length (Bytes)` phù hợp (ví dụ `30000000`).

Hoặc bằng lệnh:

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/requestLimits' -Name 'maxAllowedContentLength' -Value 30000000
```

**Kiểm chứng (theo PDF):** gửi request vượt giá trị này, IIS trả `404.13`. Ví dụ: `curl.exe -X POST --data-binary "@D:\big.bin" http://localhost/` với file lớn hơn giới hạn.

---

### 4.2 (L2, **chọn**, Automated) Ensure 'maxURL request filter' is configured

**Mục tiêu:** giới hạn độ dài URL (không tính query string), mặc định 4096.

**Audit:**

```powershell
$f = 'system.webServer/security/requestFiltering/requestLimits'
foreach ($p in Get-IisPaths) {
  try {
    $v = [int](Get-Cfg $f 'maxUrl' $p.PSPath)
    if ($v -gt 0 -and $v -le 4096) { Add-Result '4.2' 'PASS' "$($p.Name): maxUrl=$v" } else { Add-Result '4.2' 'FAIL' "$($p.Name): maxUrl=$v" }
  } catch { Add-Result '4.2' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
$f = 'system.webServer/security/requestFiltering/requestLimits'
foreach ($p in Get-IisPaths) {
  $v = [int](Get-Cfg $f 'maxUrl' $p.PSPath)
  if ($v -le 0 -or $v -gt 4096) { Set-Cfg $f 'maxUrl' 4096 $p.PSPath }
}
```

**Kiểm chứng (theo PDF):** URL dài hơn giới hạn bị từ chối, ghi `404.14` trong log:

```powershell
$long = 'a' * 5000
curl.exe -s -o NUL -w "%{http_code}`n" "http://localhost/$long"
# Kiem tra log: Select-String -Path "$env:SystemDrive\inetpub\logs\LogFiles\W3SVC1\*.log" -Pattern ' 404 14 '
```

---

### 4.3 (L2, tùy chọn, Automated) Ensure 'MaxQueryString request filter' is configured

**Mục tiêu:** giới hạn độ dài query string, mặc định 2048.

**Audit:**

```powershell
$f = 'system.webServer/security/requestFiltering/requestLimits'
foreach ($p in Get-IisPaths) {
  try {
    $v = [int](Get-Cfg $f 'maxQueryString' $p.PSPath)
    if ($v -gt 0 -and $v -le 2048) { Add-Result '4.3' 'PASS' "$($p.Name): maxQueryString=$v" } else { Add-Result '4.3' 'FAIL' "$($p.Name): maxQueryString=$v" }
  } catch { Add-Result '4.3' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
$f = 'system.webServer/security/requestFiltering/requestLimits'
foreach ($p in Get-IisPaths) {
  $v = [int](Get-Cfg $f 'maxQueryString' $p.PSPath)
  if ($v -le 0 -or $v -gt 2048) { Set-Cfg $f 'maxQueryString' 2048 $p.PSPath }
}
```

**Kiểm chứng:** query string dài hơn giới hạn bị từ chối (`404.15` trong log): `curl.exe -s -o NUL -w "%{http_code}`n" "http://localhost/?q=$('a'*3000)"`.

---

### 4.4 (L2, tùy chọn, Automated) Ensure non-ASCII characters in URLs are not allowed

**Mục tiêu:** từ chối URL có ký tự non-ASCII (`allowHighBitCharacters=false`) để giảm tấn công canonicalization.

**Audit:**

```powershell
$f = 'system.webServer/security/requestFiltering'
foreach ($p in Get-IisPaths) {
  try {
    $v = Get-Cfg $f 'allowHighBitCharacters' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '4.4' 'PASS' "$($p.Name): allowHighBitCharacters=False" } else { Add-Result '4.4' 'FAIL' "$($p.Name): allowHighBitCharacters=$v" }
  } catch { Add-Result '4.4' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:**

```powershell
$f = 'system.webServer/security/requestFiltering'
foreach ($p in Get-IisPaths) {
  if ("$(Get-Cfg $f 'allowHighBitCharacters' $p.PSPath)" -ne 'False') { Set-Cfg $f 'allowHighBitCharacters' $false $p.PSPath }
}
```

**Lưu ý (theo PDF):** site hỗ trợ đa ngôn ngữ (URL có tiếng Việt, Unicode…) có thể bị ảnh hưởng. Thử bằng `curl.exe -s -o NUL -w "%{http_code}" "http://localhost/%C3%A9"`; log ghi `404.12`.

---

### 4.5 (L1, Automated) Ensure Double-Encoded requests will be rejected

**Mục tiêu:** từ chối request mã hóa kép (`allowDoubleEscaping=false`).

**Audit:**

```powershell
$f = 'system.webServer/security/requestFiltering'
foreach ($p in Get-IisPaths) {
  try {
    $v = Get-Cfg $f 'allowDoubleEscaping' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '4.5' 'PASS' "$($p.Name): allowDoubleEscaping=False" } else { Add-Result '4.5' 'FAIL' "$($p.Name): allowDoubleEscaping=$v" }
  } catch { Add-Result '4.5' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:** (giá trị đúng là `False`; PDF ghi `True` trong lệnh PowerShell, xem §0.3)

```powershell
$f = 'system.webServer/security/requestFiltering'
foreach ($p in Get-IisPaths) {
  if ("$(Get-Cfg $f 'allowDoubleEscaping' $p.PSPath)" -ne 'False') { Set-Cfg $f 'allowDoubleEscaping' $false $p.PSPath }
}
```

**Kiểm chứng:** `curl.exe -s -o NUL -w "%{http_code}`n" "http://localhost/%252e%252e/"`; log ghi `404.11`.

**Lưu ý (theo PDF):** nếu tên file trong URL có dấu `+` thì `allowDoubleEscaping` phải để `true` để chạy được; đây là ngoại lệ ghi nhận.

---

### 4.6 (L1, **Manual**) Ensure 'HTTP Trace Method' is disabled

**Mục tiêu:** chặn phương thức TRACE (phản chiếu header của request, có thể lộ cookie/xác thực).

**Kiểm tra:**

```powershell
(Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs' -Name '.').Collection |
  Select-Object verb, allowed
# Hoac: appcmd.exe list config /section:requestfiltering
```

Đạt khi có dòng `verb = TRACE` và `allowed = False`. Mặc định TRACE không bị lọc.

**Các bước làm (theo PDF):**

1. IIS Manager → chọn site/app → **Request Filtering**.
2. Tab **HTTP Verbs** → **Deny Verb…** (khung Actions).
3. Nhập `TRACE` → **OK**.

Hoặc bằng lệnh:

```powershell
Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs' -Name '.' -Value @{ verb = 'TRACE'; allowed = $false }
```

**Kiểm chứng (theo PDF: IIS trả `404.6` khi verb bị chặn):**

```powershell
curl.exe -i -X TRACE http://localhost/
```

---

### 4.7 (L1, Automated) Ensure Unlisted File Extensions are not allowed

**Mục tiêu:** chỉ phục vụ các đuôi file được liệt kê (`allowUnlisted=false`), tránh tải `.config`, `.bat`, `.exe`…

**Audit:**

```powershell
$f = 'system.webServer/security/requestFiltering/fileExtensions'
foreach ($p in Get-IisPaths) {
  try {
    $v = Get-Cfg $f 'allowUnlisted' $p.PSPath
    if ("$v" -eq 'False') { Add-Result '4.7' 'PASS' "$($p.Name): allowUnlisted=False" } else { Add-Result '4.7' 'FAIL' "$($p.Name): allowUnlisted=$v" }
  } catch { Add-Result '4.7' 'ERROR' "$($p.Name): $($_.Exception.Message)" }
}
```

**Remediate:** liệt kê trước các đuôi cần dùng rồi mới tắt `allowUnlisted`. **Sửa danh sách `$Allow` cho đúng ứng dụng.**

```powershell
$f = 'system.webServer/security/requestFiltering/fileExtensions'
$Allow = '.html','.htm','.css','.js','.png','.jpg','.jpeg','.gif','.ico','.svg','.txt','.woff','.woff2','.aspx','.asp'

foreach ($ext in $Allow) {
  $exists = Get-WebConfiguration -PSPath $AppHostPath -Filter "$f/add[@fileExtension='$ext']"
  if ($exists) { Set-WebConfigurationProperty -PSPath $AppHostPath -Filter "$f/add[@fileExtension='$ext']" -Name allowed -Value $true }
  else { Add-WebConfigurationProperty -PSPath $AppHostPath -Filter $f -Name '.' -Value @{ fileExtension = $ext; allowed = $true } }
}
Set-Cfg $f 'allowUnlisted' $false $AppHostPath
```

**Kiểm chứng (theo PDF: log `404.7`):**

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8081/index.html     # mong doi 200
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8081/web.config     # mong doi 404 (404.7)
```

**Rủi ro:** dễ làm gãy site. Nếu trang gốc `/` hoặc đường dẫn không có đuôi file trả `404.7`, cần thêm quy tắc cho URL không đuôi (dấu `.`); điều này **chưa được tôi kiểm chứng**, hãy test trên VM và ghi lại.

---

### 4.8 (L1, **Manual**) Ensure Handler is not granted Write and Script/Execute

**Mục tiêu:** handler mapping chỉ có `Script/Execute` **hoặc** `Write`, không có cả hai (tránh upload rồi thực thi mã).

**Kiểm tra:**

```powershell
foreach ($p in Get-IisPaths) {
  $v = "$(Get-Cfg 'system.webServer/handlers' 'accessPolicy' $p.PSPath)"
  $bad = ($v -match 'Write') -and ($v -match 'Script|Execute')
  '{0,-12} accessPolicy={1}  =>  {2}' -f $p.Name, $v, $(if ($bad) { 'FAIL' } else { 'OK' })
}
```

Đạt khi `accessPolicy` không chứa `Write` cùng lúc với `Script`/`Execute`. Ví dụ đạt: `Read, Script`. Mặc định là `Read, Script`.

**Các bước làm (theo PDF):** PDF ghi cấu hình này **không sửa được bằng IIS Manager**.

1. Mở Notepad **Administrator**.
2. Mở `%systemroot%\system32\inetsrv\config\ApplicationHost.config`.
3. Trong thẻ `<handlers>`, sửa `accessPolicy` để không có `Write` khi có `Script`/`Execute`.

Hoặc bằng lệnh:

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/handlers' -Name 'accessPolicy' -Value 'Read,Script'
# Hoac: appcmd.exe set config /section:handlers /accessPolicy:Read,Script
```

---

### 4.9 (L1, Automated) Ensure 'notListedIsapisAllowed' is set to false

**Mục tiêu:** không cho chạy ISAPI chưa được liệt kê.

**Audit:**

```powershell
try {
  $v = Get-Cfg 'system.webServer/security/isapiCgiRestriction' 'notListedIsapisAllowed'
  if ("$v" -eq 'False') { Add-Result '4.9' 'PASS' 'notListedIsapisAllowed=False' } else { Add-Result '4.9' 'FAIL' "notListedIsapisAllowed=$v" }
} catch { Add-Result '4.9' 'ERROR' $_.Exception.Message }
```

**Remediate:**

```powershell
Set-Cfg 'system.webServer/security/isapiCgiRestriction' 'notListedIsapisAllowed' $false
```

Mặc định đã là `false`.

---

### 4.10 (L1, Automated) Ensure 'notListedCgisAllowed' is set to false

**Mục tiêu:** không cho chạy CGI chưa được liệt kê.

**Audit:**

```powershell
try {
  $v = Get-Cfg 'system.webServer/security/isapiCgiRestriction' 'notListedCgisAllowed'
  if ("$v" -eq 'False') { Add-Result '4.10' 'PASS' 'notListedCgisAllowed=False' } else { Add-Result '4.10' 'FAIL' "notListedCgisAllowed=$v" }
} catch { Add-Result '4.10' 'ERROR' $_.Exception.Message }
```

**Remediate:**

```powershell
Set-Cfg 'system.webServer/security/isapiCgiRestriction' 'notListedCgisAllowed' $false
```

---

### 4.11 (L1, **Manual**) Ensure 'Dynamic IP Address Restrictions' is enabled

**Mục tiêu:** tự động chặn IP gửi quá nhiều request hoặc request đồng thời (giảm nguy cơ DDoS ở tầng ứng dụng).

**Điều kiện:** cần role service **IP and Domain Restrictions** (`Web-IP-Security`, đã cài ở §1.1).

**Kiểm tra:**

```powershell
(Get-WindowsFeature Web-IP-Security).Installed
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' -Name 'enabled'
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests' -Name 'maxConcurrentRequests'
```

**Các bước làm (theo PDF):**

1. IIS Manager → **IP Address and Domain Restrictions**.
2. **Edit Dynamic Restriction Settings…**
3. Tích **Deny IP Address based on the number of concurrent requests** và **Deny IP Address based on the number of requests over a period of time**. Điều chỉnh số theo môi trường.

Hoặc bằng lệnh:

```powershell
$f = 'system.webServer/security/dynamicIpSecurity'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "$f/denyByConcurrentRequests" -Name 'enabled' -Value $true
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "$f/denyByConcurrentRequests" -Name 'maxConcurrentRequests' -Value 20
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "$f/denyByRequestRate"        -Name 'enabled' -Value $true
```

**Kiểm chứng (theo PDF: truy cập đủ số lần để kích hoạt, phải nhận trang Forbidden):** nên thử **từ máy thật vào IP của VM**, không phải từ chính VM (**chưa kiểm chứng** việc loopback có bị tính hay không). Để dễ kích hoạt khi demo, tạm hạ `maxConcurrentRequests` xuống `2` và `denyByRequestRate`/`maxRequests` thấp, sau đó trả lại giá trị thật.

```powershell
# Chay tu may khac, thay IP cua VM
1..60 | ForEach-Object { Start-Job { curl.exe -s -o NUL -w "%{http_code}`n" http://192.168.56.10:8081/ } } | Wait-Job | Receive-Job
```

---

## 7. Nhóm 5 — IIS Logging

### 5.1 (L1, Automated) Ensure Default IIS web log location is moved

**Mục tiêu:** log IIS không nằm trên ổ hệ thống, có phân quyền chặt (tránh bị sửa/xóa hoặc đầy ổ hệ thống).

**Audit:**

```powershell
$sys = $env:SystemDrive
try {
  $dir = [Environment]::ExpandEnvironmentVariables("$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'directory')")
  if ($dir.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase)) { Add-Result '5.1' 'FAIL' "siteDefaults log dir=$dir (system drive)" }
  else { Add-Result '5.1' 'PASS' "siteDefaults log dir=$dir" }
  foreach ($s in Get-Website) {
    $d = [Environment]::ExpandEnvironmentVariables("$($s.logFile.directory)")
    if ($d.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase)) { Add-Result '5.1' 'FAIL' "$($s.Name): log dir=$d" }
  }
} catch { Add-Result '5.1' 'ERROR' $_.Exception.Message }
```

**Remediate:** (đổi `$NewLogDir` theo ổ của bạn)

```powershell
$NewLogDir = 'D:\IISLogs'
New-Item -ItemType Directory -Path $NewLogDir -Force | Out-Null
# chi Administrators va SYSTEM duoc truy cap (theo PDF)
icacls $NewLogDir /inheritance:r /grant 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' | Out-Null
Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'directory' $NewLogDir
# site nao da co thu muc log rieng tren o he thong thi doi theo
foreach ($s in Get-Website) {
  if ([Environment]::ExpandEnvironmentVariables("$($s.logFile.directory)").StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
    Set-ItemProperty "IIS:\Sites\$($s.Name)" -Name logFile.directory -Value $NewLogDir
  }
}
```

**Kiểm chứng:** truy cập site vài lần rồi xem thư mục `D:\IISLogs\W3SVC<id>\` có file `.log` mới. **Lưu ý (theo PDF):** log của Request Filtering, Advanced Logging, HTTPERR có nơi lưu riêng; `HTTPERR` đổi vị trí bằng registry.

---

### 5.2 (L1, Automated) Ensure Advanced IIS logging is enabled

**Mục tiêu:** ghi log chi tiết (nhiều trường: header, server variable…), phục vụ phát hiện tấn công.

**Điểm cần biết:** *IIS Advanced Logging* là module **tải riêng** (không có sẵn trong `Install-WindowsFeature`). Khả năng cài và chạy trên Windows Server 2022 **tôi chưa kiểm chứng**. Phần Remediation của chính PDF chỉ yêu cầu vào **Logging → Select Fields**, tức là chọn các trường log W3C. Vì vậy tài liệu này làm theo hai tầng:

1. **Audit:** `PASS` nếu W3C logging đang ghi đủ các trường khuyến nghị; đồng thời báo (INFO) xem module Advanced Logging có được cài không.
2. Nếu không cài được module, ghi nhận trong báo cáo là *ngoại lệ có lý do* và dùng cách chọn trường W3C ở dưới.

**Audit:**

```powershell
$need = 'Date','Time','ClientIP','UserName','Method','UriStem','UriQuery','HttpStatus','Win32Status','BytesSent','BytesRecv','TimeTaken','ServerPort','UserAgent','Referer','Host','HttpSubStatus'
try {
  $fmt   = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logFormat')"
  $flags = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logExtFileFlags')"
  $have  = $flags -split '[,\s]+' | Where-Object { $_ }
  $miss  = @($need | Where-Object { $_ -notin $have })
  if ($fmt -eq 'W3C' -and $miss.Count -eq 0) { Add-Result '5.2' 'PASS' 'W3C logging has all recommended fields' }
  else { Add-Result '5.2' 'FAIL' "format=$fmt, missing fields: $($miss -join ', ')" }

  $mod = Get-WebGlobalModule | Where-Object { $_.Name -match 'Advanced.?Logging' }
  if ($mod) { Add-Result '5.2' 'INFO' "Advanced Logging module present: $($mod.Name)" } else { Add-Result '5.2' 'INFO' 'Advanced Logging module not installed (separate download)' }
} catch { Add-Result '5.2' 'ERROR' $_.Exception.Message }
```

**Remediate (chọn trường log W3C, theo bước *Select Fields* của PDF):**

```powershell
$fields = 'Date,Time,ClientIP,UserName,SiteName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,ProtocolVersion,Host,HttpSubStatus'
Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logFormat' 'W3C'
Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logExtFileFlags' $fields
```

**Lưu ý:** nhiều trường hơn nghĩa là log lớn hơn (PDF ghi mục Impact: tốn dung lượng ổ log). Cân nhắc dung lượng ổ `D:`.

---

### 5.3 (L1, **Manual**) Ensure 'ETW Logging' is enabled

**Mục tiêu:** gửi log IIS qua Event Tracing for Windows để xem gần thời gian thực và truy vấn bằng công cụ chuẩn.

**Kiểm tra:**

```powershell
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logTargetW3C'
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logFormat'
```

Đạt khi `logFormat = W3C` và `logTargetW3C` gồm cả `File` và `ETW`.

**Các bước làm (theo PDF):**

1. IIS Manager → chọn server hoặc site cần bật ETW.
2. Mở **Logging**.
3. Bảo đảm **Format** là **W3C**.
4. Chọn **Both log file and ETW event**.
5. **Apply**.

Hoặc bằng lệnh:

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logFormat' -Value 'W3C'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'logTargetW3C' -Value 'File,ETW'
```

**Kiểm chứng:** PDF dùng *Message Analyzer* (truy vấn provider `Microsoft-Windows-IIS-Logging`) để xem dữ liệu live. Công cụ đó đã ngừng phát triển (theo hiểu biết của tôi, chưa kiểm tra lại), nên có thể thay bằng `logman` + `Get-WinEvent`:

```powershell
$etl = 'D:\iis-etw-test.etl'
logman create trace IISLogTest -p Microsoft-Windows-IIS-Logging -o $etl -ets
curl.exe -s -o NUL http://localhost:8081/
logman stop IISLogTest -ets
Get-WinEvent -Path $etl -Oldest -ErrorAction SilentlyContinue | Select-Object -First 5 TimeCreated, Id, Message
```

Có sự kiện xuất hiện sau khi truy cập site là đạt. **Lưu ý (theo PDF Impact):** về lý thuyết cần một máy chủ riêng để thu ETW; trong lab chỉ cần thu cục bộ.

---

## 8. Nhóm 6 — FTP

> Cần đã cài **Web-Ftp-Server** và có site FTP (xem §1.2, site `FtpLab`). Hai mục này đều là **Manual** theo PDF.

### 6.1 (L1, **Manual**) Ensure FTP requests are encrypted

**Mục tiêu:** FTP dùng SSL/TLS (FTPS) để bảo vệ cả lệnh điều khiển, dữ liệu và thông tin đăng nhập.

**Kiểm tra (theo PDF, kết quả phải là `SslRequire` cho cả hai):**

```powershell
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/ssl' -Name 'controlChannelPolicy'
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/ssl' -Name 'dataChannelPolicy'
```

**Các bước làm:**

1. Chuẩn bị một certificate (lab: cert tự ký, §1.2). Lấy thumbprint:
   `Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject, Thumbprint`
2. Gắn cert vào site FTP và bắt buộc SSL:

```powershell
$Site  = 'FtpLab'
$thumb = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like '*sitea.lab.local*' } | Select-Object -First 1).Thumbprint

Set-ItemProperty "IIS:\Sites\$Site" -Name ftpServer.security.ssl.serverCertHash -Value $thumb
Set-ItemProperty "IIS:\Sites\$Site" -Name ftpServer.security.ssl.controlChannelPolicy -Value 'SslRequire'
Set-ItemProperty "IIS:\Sites\$Site" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 'SslRequire'

# Mac dinh cho moi site (theo PDF)
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/ssl' -Name 'controlChannelPolicy' -Value 'SslRequire'
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/ssl' -Name 'dataChannelPolicy'    -Value 'SslRequire'
```

Bằng giao diện: IIS Manager → site FTP → **FTP SSL Settings** → chọn **SSL Certificate** → **Require SSL connections**.

**Kiểm chứng:**

```powershell
curl.exe -v --ssl-reqd --insecure ftp://localhost/ --user user:pass     # co bat tay TLS (AUTH TLS)
curl.exe -v ftp://localhost/ --user user:pass                            # khong TLS => bi tu choi (530/534)
```

(Cần tài khoản FTP hợp lệ và quyền đọc thư mục FTP; nếu chưa cấu hình phân quyền, lỗi 530 có thể do chưa cấp quyền/Authentication.)

---

### 6.2 (L1, **Manual**) Ensure FTP Logon attempt restrictions is enabled

**Mục tiêu:** tự chặn IP thử mật khẩu FTP sai nhiều lần (chống brute-force).

**Kiểm tra (theo PDF, kết quả có `denyByFailure enabled = true`):**

```powershell
& "$env:windir\system32\inetsrv\appcmd.exe" list config -section:system.ftpServer/security/authentication
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.ftpServer/security/authentication/denyByFailure' -Name 'enabled'
```

**Các bước làm:**

```powershell
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.ftpServer/security/authentication/denyByFailure' -Name 'enabled' -Value $true
# Tuy chon: xem/chinh so lan that bai toi da va thoi gian
Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.ftpServer/security/authentication/denyByFailure' -Name '.' | Format-List
```

Bằng giao diện: IIS Manager → server → **FTP Logon Attempt Restrictions** → tích **Deny IP addresses based on the number of failed login attempts** → nhập số lần và khoảng thời gian.

**Kiểm chứng (từ máy thật):** đăng nhập sai nhiều lần liên tiếp, sau đó thử lại (kể cả mật khẩu đúng) sẽ bị từ chối:

```powershell
1..6 | ForEach-Object { curl.exe -s -o NUL -w "%{http_code}`n" ftp://192.168.56.10/ --user nouser:wrongpass }
```

(Thay IP của VM. **Số lần tối đa và thời gian chặn mặc định tôi chưa kiểm chứng**, hãy đọc từ lệnh `Format-List` ở trên rồi chọn số lần thử phù hợp.)

---

## 9. Nhóm 7 — Transport Encryption (TLS/cipher)

> Dùng các hàm `Test-Schannel*`/`Set-Schannel*` ở §2. **Reboot VM sau khi remediate.** Trước khi chạy, **sao lưu registry** (Phụ lục B).
>
> **Cách hiểu hai giá trị** (theo PDF): `Enabled = 0` tắt giao thức một cách chắc chắn (ứng dụng không ghi đè được); `DisabledByDefault = 1` chỉ ngăn gửi Hello qua giao thức đó và có thể bị ứng dụng ghi đè. Vì vậy mục "tắt" cần đặt **cả hai**: `Enabled=0` và `DisabledByDefault=1`.
>
> **Kiểm chứng từ ngoài** (nên làm sau reboot): `nmap --script ssl-enum-ciphers -p 443 <IP_VM>` hoặc `testssl.sh`. Nếu chưa có `nmap`, dùng `Test-NetConnection` chỉ kiểm tra được cổng mở.

### 7.1 (L2, **chọn**, **Manual**) Ensure HSTS Header is set

**Mục tiêu:** buộc trình duyệt luôn dùng HTTPS với site, chặn tấn công hạ cấp (SSL stripping).

**Kiểm tra (theo PDF):** IIS Manager → server (hoặc site) → **HTTP Response Headers** → phải có `Strict-Transport-Security` với giá trị **lớn hơn 0**. Hoặc bằng lệnh:

```powershell
(Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.').Collection |
  Where-Object { $_.name -eq 'Strict-Transport-Security' } | Select-Object name, value
```

**Các bước làm (theo PDF):** PDF dùng `max-age=480` (8 phút, chỉ để thử). Cấp server:

```powershell
$hsts = 'max-age=480; includeSubDomains'
Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.' -Value @{ name = 'Strict-Transport-Security'; value = $hsts }

# Hoac theo appcmd (PDF):
# appcmd.exe set config -section:system.webServer/httpProtocol /+"customHeaders.[name='Strict-Transport-Security',value='max-age=480; includeSubDomains; preload']"
```

Cấp từng site thì thêm `-Location 'TenSite'` hoặc dùng `PSPath = 'MACHINE/WEBROOT/APPHOST/TenSite'`.

**Kiểm chứng:** header chỉ được trình duyệt chấp nhận qua **HTTPS**; kiểm tra bằng `curl.exe -k -I https://localhost/` (cần HTTPS binding, §1.2).

**Lưu ý:** HSTS với `max-age` lớn rất khó gỡ ở phía trình duyệt. Trong báo cáo nên giữ giá trị thử nhỏ, và ghi chú giá trị thực tế khuyến nghị cho production. Cờ `preload` không có nghĩa nếu `max-age` nhỏ hơn mức yêu cầu của danh sách preload (theo hiểu biết của tôi, chưa kiểm tra lại).

---

### 7.2 (L1, Automated) Ensure SSLv2 is Disabled

**Audit:**

```powershell
Test-SchannelProtocol -Id '7.2' -Protocol 'SSL 2.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Remediate:**

```powershell
Set-SchannelProtocol -Protocol 'SSL 2.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Lưu ý:** Windows Server đời mới có thể không hỗ trợ SSLv2 sẵn; nếu khóa registry chưa tồn tại, audit vẫn `FAIL` theo đúng yêu cầu của CIS (phải đặt khóa tường minh).

---

### 7.3 (L1, Automated) Ensure SSLv3 is Disabled

**Audit:**

```powershell
Test-SchannelProtocol -Id '7.3' -Protocol 'SSL 3.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Remediate:**

```powershell
Set-SchannelProtocol -Protocol 'SSL 3.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

SSLv3 có lỗ hổng POODLE (PDF có tham chiếu).

---

### 7.4 (L1, Automated) Ensure TLS 1.0 is Disabled

**Audit:**

```powershell
Test-SchannelProtocol -Id '7.4' -Protocol 'TLS 1.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Remediate:**

```powershell
Set-SchannelProtocol -Protocol 'TLS 1.0' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Rủi ro:** client/ứng dụng cũ chỉ hỗ trợ TLS 1.0 sẽ không kết nối được. Reboot, rồi kiểm chứng bằng `nmap` rằng TLS 1.0 không còn được chấp nhận.

---

### 7.5 (L1, Automated) Ensure TLS 1.1 is Disabled

**Audit:**

```powershell
Test-SchannelProtocol -Id '7.5' -Protocol 'TLS 1.1' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Remediate:**

```powershell
Set-SchannelProtocol -Protocol 'TLS 1.1' -Sides 'Server','Client' -Enabled 0 -DisabledByDefault 1
```

**Lưu ý (theo PDF):** cần test kỹ để chắc không còn nhu cầu tương thích ngược; nếu có, tạo ngoại lệ có ghi chú.

---

### 7.6 (L1, Automated) Ensure TLS 1.2 is Enabled

**Audit:** (chỉ phía Server, theo PDF)

```powershell
Test-SchannelProtocol -Id '7.6' -Protocol 'TLS 1.2' -Sides 'Server' -Enabled 1 -DisabledByDefault 0
```

**Remediate:**

```powershell
Set-SchannelProtocol -Protocol 'TLS 1.2' -Sides 'Server' -Enabled 1 -DisabledByDefault 0
```

---

### 7.7 (L1, Automated) Ensure NULL Cipher Suites is Disabled

**Audit:**

```powershell
Test-SchannelCipher -Id '7.7' -Cipher 'NULL' -Want Disabled
```

**Remediate:**

```powershell
Set-SchannelValue 'Ciphers\NULL' 'Enabled' 0
```

---

### 7.8 (L1, Automated) Ensure DES Cipher Suites is Disabled

**Audit:**

```powershell
Test-SchannelCipher -Id '7.8' -Cipher 'DES 56/56' -Want Disabled
```

**Remediate:**

```powershell
Set-SchannelValue 'Ciphers\DES 56/56' 'Enabled' 0
```

---

### 7.9 (L1, Automated) Ensure RC4 Cipher Suites is Disabled

**Audit:** bốn biến thể RC4.

```powershell
foreach ($c in 'RC4 40/128','RC4 56/128','RC4 64/128','RC4 128/128') {
  Test-SchannelCipher -Id '7.9' -Cipher $c -Want Disabled
}
```

**Remediate:**

```powershell
foreach ($c in 'RC4 40/128','RC4 56/128','RC4 64/128','RC4 128/128') {
  Set-SchannelValue "Ciphers\$c" 'Enabled' 0
}
```

**Lưu ý (theo PDF):** Server 2012/2012 R2 bật sẵn `RC4 128/128`. Tắt RC4 có thể làm client rất cũ không kết nối được.

---

### 7.10 (L1, Automated) Ensure AES 128/128 Cipher Suite is Disabled

**Mục tiêu (theo PDF):** tắt AES 128/128 vì khuyến nghị dùng AES 256/256 (7.11). Chú ý: danh sách ở 7.12 vẫn có các suite AES-128, đây là điểm không nhất quán trong tài liệu gốc.

**Audit:**

```powershell
Test-SchannelCipher -Id '7.10' -Cipher 'AES 128/128' -Want Disabled
```

**Remediate:**

```powershell
Set-SchannelValue 'Ciphers\AES 128/128' 'Enabled' 0
```

**Kiểm chứng:** sau reboot, dùng `nmap --script ssl-enum-ciphers` xem suite AES-128 còn được thương lượng không, rồi ghi nhận kết quả vào báo cáo.

---

### 7.11 (L1, Automated) Ensure AES 256/256 Cipher Suite is Enabled

**Audit:**

```powershell
Test-SchannelCipher -Id '7.11' -Cipher 'AES 256/256' -Want Enabled
```

**Remediate:**

```powershell
Set-SchannelValue 'Ciphers\AES 256/256' 'Enabled' 1
```

AES 256/256 bật sẵn từ Server 2012. Khóa `Enabled` kiểu DWORD có thể là `1` hoặc `0xFFFFFFFF`; audit coi mọi giá trị khác 0 là bật.

---

### 7.12 (L2, **chọn**, Automated) Ensure TLS Cipher Suite ordering is Configured

**Mục tiêu:** sắp xếp cipher suite từ mạnh đến yếu, ưu tiên suite có Perfect Forward Secrecy và hash mạnh.

**Audit:**

```powershell
$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'
$expected = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256'
try {
  $cur = (Get-ItemProperty -Path $path -Name 'Functions' -ErrorAction Stop).Functions
  if ($cur -eq $expected) { Add-Result '7.12' 'PASS' 'cipher suite order matches CIS' }
  else { Add-Result '7.12' 'FAIL' "Functions differs from CIS list: $cur" }
} catch { Add-Result '7.12' 'FAIL' 'Functions value not set' }
```

**Remediate:**

```powershell
$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'
$expected = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256'
New-Item -Path $path -Force | Out-Null
New-ItemProperty -Path $path -Name 'Functions' -Value $expected -PropertyType String -Force | Out-Null
```

Cần **reboot**. **Lưu ý (theo PDF):** bốn suite ECDHE đầu danh sách tương thích HTTP/2. Cách đặt này làm chính sách đè lên mặc định của hệ thống, nên chỉ nhận danh sách đã liệt kê; client không có suite chung sẽ không kết nối được.

---

## Phụ lục A. Chạy toàn bộ audit và xuất báo cáo

Lưu các khối **Audit** đã dùng vào một file `.ps1` (đứng sau §2) hoặc dán lần lượt vào cùng một cửa sổ PowerShell, sau đó chạy khối này để xuất kết quả:

```powershell
$out = 'D:\CIS\out'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'

$script:Results | Export-Csv -Path "$out\audit-$stamp.csv" -NoTypeInformation -Encoding UTF8
$script:Results | ConvertTo-Json | Set-Content -Path "$out\audit-$stamp.json" -Encoding UTF8

# Tong ket nhanh
$script:Results | Group-Object Status | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize

# Bao cao HTML don gian
$script:Results | Sort-Object { [version]($_.Id -replace '(\d+)\.(\d+)','$1.$2') }, Status |
  ConvertTo-Html -Title 'CIS IIS 10 audit' -PreContent "<h2>CIS IIS 10 audit - $env:COMPUTERNAME - $(Get-Date)</h2>" |
  Set-Content -Path "$out\audit-$stamp.html" -Encoding UTF8
```

Chạy khối này **hai lần** (trước và sau khi remediate) rồi so sánh hai file CSV để ra số liệu "trước/sau" cho báo cáo.

## Phụ lục B. Sao lưu và hoàn tác

Làm **trước khi remediate**:

```powershell
# 1) Sao luu cau hinh IIS (applicationHost.config va cac file lien quan)
& "$env:windir\system32\inetsrv\appcmd.exe" add backup 'pre-cis'

# 2) Sao luu registry SCHANNEL va chinh sach cipher suite order (nhom 7)
New-Item -ItemType Directory -Path 'D:\CIS\backup' -Force | Out-Null
reg export 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL' 'D:\CIS\backup\schannel.reg' /y
reg export 'HKLM\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL' 'D:\CIS\backup\ssl-policy.reg' /y   # co the bao loi neu key chua ton tai
```

Hoàn tác khi có sự cố:

```powershell
& "$env:windir\system32\inetsrv\appcmd.exe" list backup
& "$env:windir\system32\inetsrv\appcmd.exe" restore backup 'pre-cis'
# registry: nhap lai file .reg roi reboot
reg import 'D:\CIS\backup\schannel.reg'
```

Khuyến nghị thêm: **snapshot VM** trước mỗi đợt remediate. Với file `web.config` và `machine.config`, các script ở trên tạo bản `.bak` cạnh file gốc trước khi sửa.

## Phụ lục C. Bảng tổng hợp 55 tiêu chí

| ID | Level | Loại | Phạm vi | Ghi chú |
|---|---|---|---|---|
| 1.1 | L1 | Manual | Bắt buộc | |
| 1.2–1.7 | L1 | Automated | Bắt buộc | 1.6, 1.7 đã sửa lỗi lệnh trong PDF |
| 2.1, 2.2 | L1 | Manual | Bắt buộc | 2.1 có rủi ro chặn site |
| 2.3, 2.5, 2.6, 2.7 | L1 | Automated | Bắt buộc | `N/A` nếu không có Forms/Basic |
| 2.4, 2.8 | L2 | Automated | Tùy chọn | |
| 3.1 | L1 | Manual | Bắt buộc | |
| 3.4, 3.7, 3.9, 3.10 | L1 | Automated | Bắt buộc | 3.10 có rủi ro với app cần Full Trust |
| 3.2, 3.3, 3.5, 3.6, 3.8 | L2 | Automated | Tùy chọn | 3.6 đã sửa lệnh trong PDF |
| 3.11 | L2 | Manual | Tùy chọn | |
| 3.12 | L2 | Manual | **Chọn** | |
| 4.1 | L2 | Manual | Tùy chọn | |
| 4.2 | L2 | Automated | **Chọn** | |
| 4.3, 4.4 | L2 | Automated | Tùy chọn | |
| 4.5, 4.7, 4.9, 4.10 | L1 | Automated | Bắt buộc | 4.5 đã sửa lệnh trong PDF; 4.7 dễ gãy site |
| 4.6, 4.8, 4.11 | L1 | Manual | Bắt buộc | |
| 5.1, 5.2 | L1 | Automated | Bắt buộc | 5.2 có ngoại lệ về module Advanced Logging |
| 5.3 | L1 | Manual | Bắt buộc | |
| 6.1, 6.2 | L1 | Manual | Bắt buộc | |
| 7.1 | L2 | Manual | **Chọn** | |
| 7.2–7.11 | L1 | Automated | Bắt buộc | Cần reboot; 7.4/7.5 dễ gãy client cũ |
| 7.12 | L2 | Automated | **Chọn** | |

Tổng: **55 tiêu chí** = 41 Automated + 14 Manual = 40 L1 + 15 L2.
