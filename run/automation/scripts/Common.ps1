<#
  Common.ps1 - shared engine for the CIS Microsoft IIS 10 Benchmark v1.2.1 scripts.
  Not run by itself. It is dot-sourced by every Audit.ps1 / Remediate.ps1 in the part folders
  and by IIS-CIS.ps1 (the one-shot runner). Check definitions live in <part>\checks.ps1.
  File is ASCII only on purpose (no encoding problems on Windows PowerShell 5.1).
#>
$ErrorActionPreference = 'Stop'
$AppHostPath = 'MACHINE/WEBROOT/APPHOST'
$RootWebPath = 'MACHINE/WEBROOT'
$AppCmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
$DefaultL2 = @('3.12', '4.2', '7.1', '7.12')      # L2 items chosen for the project; -AllL2 adds the rest

function Assert-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from a PowerShell window started as Administrator.' }
}

# ---------------------------------------------------------------- helpers
function New-Row {
  param([string]$Target, [string]$Status, [string]$Detail = '')
  [pscustomobject]@{ Target = $Target; Status = $Status; Detail = $Detail }
}

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
  Set-WebConfigurationProperty @p | Out-Null
}

function Get-HttpSites {
  Get-Website | Where-Object { @($_.bindings.Collection | Where-Object { $_.protocol -like 'http*' }).Count -gt 0 }
}

function Get-IisPaths {
  $list = @([pscustomobject]@{ Name = 'SERVER'; PSPath = $AppHostPath })
  foreach ($s in @(Get-HttpSites)) { $list += [pscustomobject]@{ Name = $s.Name; PSPath = "$AppHostPath/$($s.Name)" } }
  $list
}

function Get-AspPaths {
  $list = @([pscustomobject]@{ Name = 'ROOT'; PSPath = $RootWebPath })
  foreach ($s in @(Get-HttpSites)) { $list += [pscustomobject]@{ Name = $s.Name; PSPath = "$AppHostPath/$($s.Name)" } }
  $list
}

function Get-PathsFor {
  param([string]$Scope)
  switch ($Scope) {
    'Iis'  { Get-IisPaths }
    'Asp'  { Get-AspPaths }
    'Root' { [pscustomobject]@{ Name = 'ROOT'; PSPath = $RootWebPath } }
    default { [pscustomobject]@{ Name = 'SERVER'; PSPath = $AppHostPath } }
  }
}

function Get-SiteWebConfig {
  param($Site)
  Join-Path ([Environment]::ExpandEnvironmentVariables($Site.physicalPath)) 'web.config'
}

$SchannelRoot = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'

function Get-SchannelValue {
  param([string]$SubPath, [string]$Name)
  $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$SchannelRoot\$SubPath")
  if ($null -eq $k) { return $null }
  try { $k.GetValue($Name) } finally { $k.Close() }
}

# .NET API on purpose: key names like 'AES 128/128' contain '/', New-Item would split them
function Set-SchannelValue {
  param([string]$SubPath, [string]$Name, [int]$Value)
  $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey("$SchannelRoot\$SubPath")
  try { $k.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() }
}

# ---------------------------------------------------------------- generic check engines

# "property X at path P must satisfy Good, else set it to SetValue"
$TestProp = {
  param($c)
  foreach ($p in @(Get-PathsFor $c.Scope)) {
    try {
      if ($c.Applies -and -not (& $c.Applies $p)) { New-Row $p.Name 'N/A' 'not applicable here'; continue }
      $v = Get-Cfg $c.Filter $c.Name $p.PSPath
      if (& $c.Good $v) { New-Row $p.Name 'PASS' "$($c.Name)=$v" }
      else              { New-Row $p.Name 'FAIL' "$($c.Name)=$v (want $($c.Want))" }
    } catch { New-Row $p.Name 'ERROR' $_.Exception.Message }
  }
}

$FixProp = {
  param($c)
  $errs = @()
  foreach ($p in @(Get-PathsFor $c.Scope)) {
    try {
      if ($c.Applies -and -not (& $c.Applies $p)) { continue }
      $v = Get-Cfg $c.Filter $c.Name $p.PSPath
      if (-not (& $c.Good $v)) { Set-Cfg $c.Filter $c.Name $c.SetValue $p.PSPath }
    } catch { $errs += "$($p.Name): $($_.Exception.Message)" }
  }
  if ($errs.Count -gt 0) { throw ($errs -join '; ') }
}

function New-PropCheck {
  param(
    [string]$Id, [string]$Title, [int]$Level, [int]$Wave,
    [string]$Filter, [string]$Name, [string]$Scope,
    [scriptblock]$Good, [string]$Want, $SetValue,
    [scriptblock]$Applies, [scriptblock]$Fix
  )
  $fixer = $FixProp
  if ($Fix) { $fixer = $Fix }
  @{
    Id = $Id; Title = $Title; Level = $Level; Wave = $Wave; Reboot = $false
    Filter = $Filter; Name = $Name; Scope = $Scope; Good = $Good; Want = $Want; SetValue = $SetValue; Applies = $Applies
    Test = $TestProp; Fix = $fixer
    FixHint = "Set $Filter / $Name = $SetValue"
  }
}

# registry (SCHANNEL) engine
$TestSch = {
  param($c)
  if ($c.Kind -eq 'Proto') {
    foreach ($side in $c.Sides) {
      $e = Get-SchannelValue "Protocols\$($c.Protocol)\$side" 'Enabled'
      $d = Get-SchannelValue "Protocols\$($c.Protocol)\$side" 'DisabledByDefault'
      if ($c.Enabled -eq 0) { $okE = ($null -ne $e) -and ($e -eq 0) } else { $okE = ($null -ne $e) -and ($e -ne 0) }
      $okD = ($null -ne $d) -and ($d -eq $c.Dis)
      $txt = "$($c.Protocol)\$side Enabled=$e DisabledByDefault=$d"
      if ($okE -and $okD) { New-Row "$($c.Protocol)\$side" 'PASS' $txt } else { New-Row "$($c.Protocol)\$side" 'FAIL' $txt }
    }
  } else {
    foreach ($ci in $c.Ciphers) {
      $e = Get-SchannelValue "Ciphers\$ci" 'Enabled'
      if ($c.Want -eq 'Disabled') { $ok = ($null -ne $e) -and ($e -eq 0) } else { $ok = ($null -ne $e) -and ($e -ne 0) }
      if ($ok) { New-Row $ci 'PASS' "Ciphers\$ci Enabled=$e" } else { New-Row $ci 'FAIL' "Ciphers\$ci Enabled=$e (want $($c.Want))" }
    }
  }
}

$FixSch = {
  param($c)
  if ($c.Kind -eq 'Proto') {
    foreach ($side in $c.Sides) {
      Set-SchannelValue "Protocols\$($c.Protocol)\$side" 'Enabled' $c.Enabled
      Set-SchannelValue "Protocols\$($c.Protocol)\$side" 'DisabledByDefault' $c.Dis
    }
  } else {
    $val = 0
    if ($c.Want -eq 'Enabled') { $val = 1 }
    foreach ($ci in $c.Ciphers) { Set-SchannelValue "Ciphers\$ci" 'Enabled' $val }
  }
}

function New-SchannelCheck {
  param(
    [string]$Id, [string]$Title, [int]$Level, [int]$Wave, [string]$Kind,
    [string]$Protocol, [string[]]$Sides, [int]$Enabled, [int]$Dis,
    [string[]]$Ciphers, [string]$Want
  )
  $what = $Protocol
  if ($Kind -eq 'Cipher') { $what = ($Ciphers -join ', ') }
  @{
    Id = $Id; Title = $Title; Level = $Level; Wave = $Wave; Reboot = $true
    Kind = $Kind; Protocol = $Protocol; Sides = $Sides; Enabled = $Enabled; Dis = $Dis; Ciphers = $Ciphers; Want = $Want
    Test = $TestSch; Fix = $FixSch
    FixHint = "Registry SCHANNEL: $what -> $Want (reboot needed)"
  }
}

# ---------------------------------------------------------------- reporting
function ConvertTo-HtmlText { param($Text) [System.Net.WebUtility]::HtmlEncode("$Text") }

function New-HtmlReport {
  param($Rows, [string]$Path, [string]$Heading)
  $hasAfter = @($Rows | Where-Object { $_.After -ne '' }).Count -gt 0
  $final = { param($r) if ($r.After -ne '') { $r.After } else { $r.Before } }
  $statuses = 'PASS', 'FAIL', 'N/A', 'ERROR', 'MANUAL'
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>CIS IIS 10 report</title><style>')
  [void]$sb.AppendLine('body{font-family:Arial,sans-serif;margin:24px;color:#222}h1{font-size:20px}h2{font-size:16px;margin-top:28px}')
  [void]$sb.AppendLine('table{border-collapse:collapse;font-size:13px}td,th{border:1px solid #bbb;padding:4px 8px;vertical-align:top}th{background:#1f3864;color:#fff}')
  [void]$sb.AppendLine('.PASS{background:#c6efce}.FAIL{background:#ffc7ce;font-weight:bold}.ERROR{background:#ffeb9c}.MANUAL{background:#ddebf7}.NA{background:#e7e6e6}code{background:#f2f2f2;padding:1px 4px}')
  [void]$sb.AppendLine('</style></head><body>')
  [void]$sb.AppendLine("<h1>$(ConvertTo-HtmlText $Heading)</h1>")
  [void]$sb.AppendLine("<p>Host: $(ConvertTo-HtmlText $env:COMPUTERNAME) &middot; Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; Benchmark: CIS Microsoft IIS 10 v1.2.1</p>")

  [void]$sb.AppendLine('<h2>1. Summary</h2><table><tr><th>Status</th><th>Before</th>' + $(if ($hasAfter) { '<th>After</th>' } else { '' }) + '</tr>')
  foreach ($s in $statuses) {
    $b = @($Rows | Where-Object { $_.Before -eq $s }).Count
    $a = @($Rows | Where-Object { (& $final $_) -eq $s }).Count
    $cls = $s.Replace('/', '')
    [void]$sb.AppendLine("<tr><td class=""$cls"">$s</td><td>$b</td>" + $(if ($hasAfter) { "<td>$a</td>" } else { '' }) + '</tr>')
  }
  [void]$sb.AppendLine('</table>')

  $todo = @($Rows | Where-Object { (& $final $_) -in 'FAIL', 'ERROR' } | Sort-Object { [int]$_.Wave }, Id)
  [void]$sb.AppendLine("<h2>2. Needs action now ($($todo.Count))</h2>")
  if ($todo.Count -eq 0) { [void]$sb.AppendLine('<p>Nothing to fix.</p>') }
  else {
    [void]$sb.AppendLine('<table><tr><th>ID</th><th>Check</th><th>Target</th><th>Finding</th><th>Wave</th><th>Suggested fix</th><th>Command</th></tr>')
    foreach ($r in $todo) {
      $cmd = ".\IIS-CIS.ps1 -Mode Remediate -Wave $($r.Wave) -Id $($r.Id) -Label after"
      [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlText $r.Id)</td><td>$(ConvertTo-HtmlText $r.Title)</td><td>$(ConvertTo-HtmlText $r.Target)</td><td class=""$(& $final $r)"">$(ConvertTo-HtmlText $r.Detail)</td><td>$(ConvertTo-HtmlText $r.Wave)</td><td>$(ConvertTo-HtmlText $r.FixHint)</td><td><code>$(ConvertTo-HtmlText $cmd)</code></td></tr>")
    }
    [void]$sb.AppendLine('</table>')
  }

  [void]$sb.AppendLine('<h2>3. All results</h2><table><tr><th>ID</th><th>Lv</th><th>Check</th><th>Target</th><th>Before</th><th>After</th><th>Action</th><th>Detail</th></tr>')
  foreach ($r in $Rows) {
    $bc = $r.Before.Replace('/', ''); $ac = $r.After.Replace('/', '')
    [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlText $r.Id)</td><td>L$(ConvertTo-HtmlText $r.Level)</td><td>$(ConvertTo-HtmlText $r.Title)</td><td>$(ConvertTo-HtmlText $r.Target)</td><td class=""$bc"">$(ConvertTo-HtmlText $r.Before)</td><td class=""$ac"">$(ConvertTo-HtmlText $r.After)</td><td>$(ConvertTo-HtmlText $r.Action)</td><td>$(ConvertTo-HtmlText $r.Detail)</td></tr>")
  }
  [void]$sb.AppendLine('</table></body></html>')
  Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8 -WhatIf:$false
}

function Save-Results {
  param($Rows, [string]$Dir, [string]$Heading)
  New-Item -ItemType Directory -Path $Dir -Force -WhatIf:$false | Out-Null
  $Rows | Export-Csv -Path (Join-Path $Dir 'results.csv') -NoTypeInformation -Encoding UTF8 -WhatIf:$false
  $Rows | ConvertTo-Json | Set-Content -Path (Join-Path $Dir 'results.json') -Encoding UTF8 -WhatIf:$false
  New-HtmlReport -Rows $Rows -Path (Join-Path $Dir 'report.html') -Heading $Heading
}

function Write-Summary {
  param($Rows)
  Write-Host ''
  Write-Host '--- Summary (Before) ---'
  $Rows | Group-Object Before | Sort-Object Name | ForEach-Object { Write-Host ('{0,-8} {1}' -f $_.Name, $_.Count) }
  if (@($Rows | Where-Object { $_.After -ne '' }).Count -gt 0) {
    Write-Host '--- Summary (After) ---'
    $Rows | Where-Object { $_.After -ne '' } | Group-Object After | Sort-Object Name | ForEach-Object { Write-Host ('{0,-8} {1}' -f $_.Name, $_.Count) }
  }
}

# ---------------------------------------------------------------- Report mode (no IIS needed)
function Invoke-CisReport {
  param([string]$BeforeCsv, [string]$AfterCsv, [string]$OutDir = '.\out')
  if (-not $BeforeCsv) { throw '-Mode Report needs -BeforeCsv (and usually -AfterCsv)' }
  $b = @(Import-Csv -Path $BeforeCsv)
  $a = @()
  if ($AfterCsv) { $a = @(Import-Csv -Path $AfterCsv) }
  $rows = foreach ($r in $b) {
    $after = ''
    $m = @($a | Where-Object { $_.Id -eq $r.Id -and $_.Target -eq $r.Target } | Select-Object -First 1)
    if ($m.Count -gt 0) { $after = $m[0].After; if (-not $after) { $after = $m[0].Before } }
    [pscustomobject]@{ Id = $r.Id; Title = $r.Title; Level = $r.Level; Wave = $r.Wave; Target = $r.Target; Before = $r.Before; After = $after; Action = $r.Action; Detail = $r.Detail; FixHint = $r.FixHint }
  }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dir = Join-Path $OutDir "$stamp-compare"
  Save-Results -Rows @($rows) -Dir $dir -Heading 'CIS IIS 10 - before/after comparison'
  Write-Summary -Rows @($rows)
  Write-Host "Report written to $dir"
}

# ---------------------------------------------------------------- Audit / Remediate engine
function Test-InScope {
  param($Item, [string[]]$Id, [bool]$AllL2)
  if ($Id -and ($Id -notcontains $Item.Id)) { return $false }
  return (($Item.Level -eq 1) -or $AllL2 -or ($DefaultL2 -contains $Item.Id))
}

function Get-IdSortKey { param($Item) $p = $Item.Id.Split('.'); [int]$p[0] * 1000 + [int]$p[1] }

function Invoke-Check {
  param($Check)
  try { @(& $Check.Test $Check) } catch { @(New-Row '-' 'ERROR' $_.Exception.Message) }
}

function Invoke-CisRun {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Checks,
    [AllowEmptyCollection()]$Manual = @(),
    [Parameter(Mandatory = $true)][ValidateSet('Audit', 'Remediate')][string]$Mode,
    [int[]]$Wave,
    [string[]]$Id,
    [switch]$AllL2,
    [switch]$Force,
    [switch]$ForceHighRisk,
    [string]$Label = '',
    [string]$OutDir = '.\out',
    [string]$Heading = 'CIS IIS 10'
  )
  Assert-Admin
  Import-Module WebAdministration -Global
  if ($Mode -eq 'Remediate' -and -not $Wave) { throw 'Remediate needs -Wave, e.g. -Wave 1  or  -Wave 1,2  (3 = high risk, asks to confirm)' }

  $all = @($Checks)
  $manualAll = @($Manual)
  if ($Id) {
    $known = @($all | ForEach-Object { $_.Id }) + @($manualAll | ForEach-Object { $_.Id })
    foreach ($x in $Id) { if ($known -notcontains $x) { Write-Warning "Id '$x' is not part of this run." } }
  }
  $selected = @($all | Where-Object { Test-InScope $_ $Id $AllL2.IsPresent } | Sort-Object { Get-IdSortKey $_ })
  Write-Host ('Checks selected (' + $selected.Count + '): ' + (($selected | ForEach-Object { $_.Id }) -join ', ')) -ForegroundColor Cyan
  if ($Id) { Write-Host "Ids you passed: $($Id -join ', ')  (PowerShell turns an unquoted 3.10 into 3.1: write -Id '3.10')" -ForegroundColor DarkGray }

  if ($selected.Count -eq 0 -and $Mode -eq 'Remediate') {
    Write-Host 'Nothing to remediate automatically in this selection (Manual items are done by hand, see HuongDan_CIS_IIS10.md).' -ForegroundColor Yellow
    return
  }

  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $name = $stamp
  if ($Label) { $name = "$stamp-$Label" }
  $dir = Join-Path $OutDir $name

  # backup before the first change
  if ($Mode -eq 'Remediate' -and $WhatIfPreference -eq $false) {
    $willFix = @($selected | Where-Object { $Wave -contains $_.Wave })
    if ($willFix.Count -gt 0) {
      try {
        New-Item -ItemType Directory -Path (Join-Path $OutDir 'backup') -Force -WhatIf:$false | Out-Null
        $bk = "cis-$stamp"
        & $AppCmd add backup $bk | Out-Null
        try { & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL' (Join-Path $OutDir "backup\schannel-$stamp.reg") /y 2>$null | Out-Null } catch { }
        Write-Host "Backup created: appcmd backup '$bk' and $OutDir\backup\schannel-$stamp.reg" -ForegroundColor Cyan
        Write-Host "Restore with:   appcmd restore backup $bk" -ForegroundColor Cyan
      } catch {
        throw "Backup failed, nothing was changed: $($_.Exception.Message)"
      }
    }
  }

  $rows = New-Object System.Collections.Generic.List[object]
  $rebootNeeded = $false

  foreach ($c in $selected) {
    $before = @(Invoke-Check $c)
    $after = @()
    $action = ''
    $hasFail = @($before | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0

    if ($Mode -eq 'Remediate' -and ($Wave -contains $c.Wave) -and $hasFail) {
      $go = $true
      $needConfirm = ((($c.Wave -eq 3) -and (-not $ForceHighRisk)) -or (($c.Wave -lt 3) -and (-not $Force)))
      if ($needConfirm) {
        $ans = Read-Host "[$($c.Id)] $($c.Title) (wave $($c.Wave)) - apply fix? (y/N)"
        if ($ans -notmatch '^(y|yes)$') { $go = $false; $action = 'Declined' }
      }
      if ($go) {
        if ($PSCmdlet.ShouldProcess("$($c.Id) $($c.Title)", 'Apply remediation')) {
          try { & $c.Fix $c | Out-Null; $action = 'Fixed'; if ($c.Reboot) { $rebootNeeded = $true } }
          catch { $action = 'FixError: ' + $_.Exception.Message }
          $after = @(Invoke-Check $c)
        } else { $action = 'WhatIf' }
      }
    }

    foreach ($r in $before) {
      $a = ''
      $m = @($after | Where-Object { $_.Target -eq $r.Target } | Select-Object -First 1)
      if ($m.Count -gt 0) { $a = $m[0].Status }
      $rowAction = ''
      if ($r.Status -eq 'FAIL') { $rowAction = $action }
      $rows.Add([pscustomobject]@{
          Id = $c.Id; Title = $c.Title; Level = $c.Level; Wave = $c.Wave; Target = $r.Target
          Before = $r.Status; After = $a; Action = $rowAction; Detail = $r.Detail; FixHint = $c.FixHint
        })
      $line = '[{0}] {1,-5} {2}  {3}' -f $r.Status, $c.Id, $r.Target, $r.Detail
      if ($a) { $line += "  -> after: $a" }
      if ($rowAction) { $line += "  ($rowAction)" }
      $color = 'Gray'
      switch ($r.Status) { 'PASS' { $color = 'Green' } 'FAIL' { $color = 'Red' } 'ERROR' { $color = 'Yellow' } }
      Write-Host $line -ForegroundColor $color
    }
  }

  # manual items: listed so the report covers every check of the part
  foreach ($m in $manualAll) {
    if (-not (Test-InScope $m $Id $AllL2.IsPresent)) { continue }
    $rows.Add([pscustomobject]@{
        Id = $m.Id; Title = $m.Title; Level = $m.Level; Wave = 0; Target = '-'
        Before = 'MANUAL'; After = ''; Action = ''; Detail = 'Manual item: follow HuongDan_CIS_IIS10.md'; FixHint = 'Manual steps in HuongDan_CIS_IIS10.md'
      })
    Write-Host ('[MANUAL] {0,-5} {1}' -f $m.Id, $m.Title) -ForegroundColor DarkCyan
  }

  if ($rows.Count -eq 0) { Write-Warning 'No check matched your selection, nothing was written.'; return }
  $sorted = @($rows | Sort-Object { [int]($_.Id.Split('.')[0]) * 1000 + [int]($_.Id.Split('.')[1]) }, Target)
  Save-Results -Rows $sorted -Dir $dir -Heading "$Heading $Label"
  Write-Summary -Rows $sorted
  Write-Host ''
  Write-Host "Results written to $dir  (results.csv, results.json, report.html)" -ForegroundColor Cyan
  if ($rebootNeeded) { Write-Host 'REBOOT REQUIRED for the SCHANNEL changes to take effect.' -ForegroundColor Yellow }
}
