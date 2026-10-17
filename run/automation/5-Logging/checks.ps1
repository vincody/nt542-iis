# checks.ps1 - CIS IIS 10 benchmark, part 5: IIS Logging
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

if (-not $LogDir) { $LogDir = 'D:\IISLogs' }

$PartChecks = @()

$PartChecks += @{
  Id = '5.1'; Title = 'Ensure Default IIS web log location is moved'; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Create -LogDir, restrict ACL to Administrators+SYSTEM, point siteDefaults (and sites on the system drive) to it'
  Test = {
    param($c)
    $sys = $env:SystemDrive
    try {
      $dir = [Environment]::ExpandEnvironmentVariables("$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'directory')")
      if ($dir.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase)) { New-Row 'siteDefaults' 'FAIL' "log dir=$dir (system drive)" } else { New-Row 'siteDefaults' 'PASS' "log dir=$dir" }
      foreach ($s in @(Get-Website)) {
        $d = [Environment]::ExpandEnvironmentVariables("$($s.logFile.directory)")
        if ($d.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase)) { New-Row $s.Name 'FAIL' "log dir=$d (system drive)" } else { New-Row $s.Name 'PASS' "log dir=$d" }
      }
    } catch { New-Row 'logging' 'ERROR' $_.Exception.Message }
  }
  Fix = {
    param($c)
    if ($LogDir.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { throw "-LogDir '$LogDir' is on the system drive" }
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    & icacls.exe $LogDir /inheritance:r /grant 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' | Out-Null
    Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'directory' $LogDir
    foreach ($s in @(Get-Website)) {
      if ([Environment]::ExpandEnvironmentVariables("$($s.logFile.directory)").StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
        Set-ItemProperty "IIS:\Sites\$($s.Name)" -Name logFile.directory -Value $LogDir
      }
    }
  }
}

$AdvFields = 'Date,Time,ClientIP,UserName,SiteName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,ProtocolVersion,Host,HttpSubStatus'
$PartChecks += @{
  Id = '5.2'; Title = 'Ensure Advanced IIS logging is enabled'; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Set W3C format and the recommended log fields (CIS "Select Fields" step). The separate Advanced Logging module is NOT installed by this script'
  Test = {
    param($c)
    $need = 'Date', 'Time', 'ClientIP', 'UserName', 'Method', 'UriStem', 'UriQuery', 'HttpStatus', 'Win32Status', 'BytesSent', 'BytesRecv', 'TimeTaken', 'ServerPort', 'UserAgent', 'Referer', 'Host', 'HttpSubStatus'
    try {
      $fmt = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logFormat')"
      $flags = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logExtFileFlags')"
      $have = @($flags -split '[,\s]+' | Where-Object { $_ })
      $miss = @($need | Where-Object { $_ -notin $have })
      $mod = @(Get-WebGlobalModule | Where-Object { $_.Name -match 'Advanced.?Logging' })
      $note = 'Advanced Logging module not installed'
      if ($mod.Count -gt 0) { $note = 'Advanced Logging module present' }
      if ($fmt -eq 'W3C' -and $miss.Count -eq 0) { New-Row 'siteDefaults' 'PASS' "W3C with all recommended fields; $note" }
      else { New-Row 'siteDefaults' 'FAIL' "format=$fmt, missing: $($miss -join ', '); $note" }
    } catch { New-Row 'siteDefaults' 'ERROR' $_.Exception.Message }
  }
  Fix = {
    param($c)
    Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logFormat' 'W3C'
    Set-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logExtFileFlags' $AdvFields
  }
}

$PartManual = @(
  @{ Id = '5.3'; Level = 1; Title = "Ensure 'ETW Logging' is enabled" }
)
