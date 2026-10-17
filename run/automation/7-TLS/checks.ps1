# checks.ps1 - CIS IIS 10 benchmark, part 7: Transport Encryption
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

$CipherOrder = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256'
$CipherKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'

$PartChecks = @()

$PartChecks += New-SchannelCheck -Id '7.2' -Title 'Ensure SSLv2 is Disabled' -Level 1 -Wave 1 -Kind Proto -Protocol 'SSL 2.0' -Sides 'Server', 'Client' -Enabled 0 -Dis 1
$PartChecks += New-SchannelCheck -Id '7.3' -Title 'Ensure SSLv3 is Disabled' -Level 1 -Wave 1 -Kind Proto -Protocol 'SSL 3.0' -Sides 'Server', 'Client' -Enabled 0 -Dis 1
$PartChecks += New-SchannelCheck -Id '7.4' -Title 'Ensure TLS 1.0 is Disabled' -Level 1 -Wave 3 -Kind Proto -Protocol 'TLS 1.0' -Sides 'Server', 'Client' -Enabled 0 -Dis 1
$PartChecks += New-SchannelCheck -Id '7.5' -Title 'Ensure TLS 1.1 is Disabled' -Level 1 -Wave 3 -Kind Proto -Protocol 'TLS 1.1' -Sides 'Server', 'Client' -Enabled 0 -Dis 1
$PartChecks += New-SchannelCheck -Id '7.6' -Title 'Ensure TLS 1.2 is Enabled' -Level 1 -Wave 1 -Kind Proto -Protocol 'TLS 1.2' -Sides 'Server' -Enabled 1 -Dis 0
$PartChecks += New-SchannelCheck -Id '7.7' -Title 'Ensure NULL Cipher Suites is Disabled' -Level 1 -Wave 1 -Kind Cipher -Ciphers 'NULL' -Want 'Disabled'
$PartChecks += New-SchannelCheck -Id '7.8' -Title 'Ensure DES Cipher Suites is Disabled' -Level 1 -Wave 1 -Kind Cipher -Ciphers 'DES 56/56' -Want 'Disabled'
$PartChecks += New-SchannelCheck -Id '7.9' -Title 'Ensure RC4 Cipher Suites is Disabled' -Level 1 -Wave 2 -Kind Cipher -Ciphers 'RC4 40/128', 'RC4 56/128', 'RC4 64/128', 'RC4 128/128' -Want 'Disabled'
$PartChecks += New-SchannelCheck -Id '7.10' -Title 'Ensure AES 128/128 Cipher Suite is Disabled' -Level 1 -Wave 2 -Kind Cipher -Ciphers 'AES 128/128' -Want 'Disabled'
$PartChecks += New-SchannelCheck -Id '7.11' -Title 'Ensure AES 256/256 Cipher Suite is Enabled' -Level 1 -Wave 1 -Kind Cipher -Ciphers 'AES 256/256' -Want 'Enabled'

$PartChecks += @{
  Id = '7.12'; Title = 'Ensure TLS Cipher Suite ordering is Configured'; Level = 2; Wave = 2; Reboot = $true
  FixHint = 'Write the CIS cipher suite list to HKLM\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002 (reboot needed)'
  Test = {
    param($c)
    try {
      $cur = (Get-ItemProperty -Path $CipherKey -Name 'Functions' -ErrorAction Stop).Functions
      if ($cur -eq $CipherOrder) { New-Row 'SCHANNEL' 'PASS' 'cipher suite order matches CIS' } else { New-Row 'SCHANNEL' 'FAIL' 'Functions differs from the CIS list' }
    } catch { New-Row 'SCHANNEL' 'FAIL' 'Functions value not set' }
  }
  Fix = {
    param($c)
    New-Item -Path $CipherKey -Force | Out-Null
    New-ItemProperty -Path $CipherKey -Name 'Functions' -Value $CipherOrder -PropertyType String -Force | Out-Null
  }
}

$PartManual = @(
  @{ Id = '7.1'; Level = 2; Title = 'Ensure HSTS Header is set' }
)
