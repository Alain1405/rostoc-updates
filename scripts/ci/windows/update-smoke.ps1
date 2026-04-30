[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$NewMsiPath,

  [Parameter(Mandatory = $true)]
  [string]$PreviousMsiUrl,

  [Parameter(Mandatory = $true)]
  [string]$ExpectedNewVersion,

  [Parameter(Mandatory = $true)]
  [string]$LogDir
)

# GitHub-hosted windows-latest runners run as runneradmin, which has local admin
# rights. That means `msiexec /quiet /norestart` can install without a UAC
# prompt. If we move this job to self-hosted Windows runners, re-verify that
# assumption before relying on the same flow.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-ProductNameFromMsiPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $fileName = [System.IO.Path]::GetFileName($Path)
  if ([string]::IsNullOrWhiteSpace($fileName)) {
    throw "Unable to infer product name from MSI path '$Path': path is empty"
  }

  $match = [regex]::Match(
    $fileName,
    '^(?<product>Rostoc(?:-staging)?)-(?<version>\d+\.\d+\.\d+)-windows-(?<arch>x64|x86)\.msi$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )

  if (-not $match.Success) {
    throw "Unable to infer product name from MSI path '$Path'. Expected a filename like 'Rostoc-X.Y.Z-windows-x64.msi' or 'Rostoc-staging-X.Y.Z-windows-x64.msi'."
  }

  return $match.Groups['product'].Value
}

function Get-InstalledVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName
  )

  $registryRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  foreach ($root in $registryRoots) {
    $match = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -eq $ProductName } |
      Select-Object -First 1

    if ($match -and -not [string]::IsNullOrWhiteSpace($match.DisplayVersion)) {
      return [string]$match.DisplayVersion
    }
  }

  throw "Unable to find installed version for product '$ProductName' in the uninstall registry keys"
}

function Get-RegistryMatchesForProduct {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName
  )

  $registryRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  $matches = @()
  foreach ($root in $registryRoots) {
    $entries = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -eq $ProductName }

    foreach ($entry in $entries) {
      $matches += [ordered]@{
        registry_root    = $root
        registry_key     = $entry.PSChildName
        display_name     = $entry.DisplayName
        display_version  = $entry.DisplayVersion
        publisher        = $entry.Publisher
        install_location = $entry.InstallLocation
        uninstall_string = $entry.UninstallString
      }
    }
  }

  return $matches
}

function Get-InstalledBinaryPathCandidates {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName
  )

  $installRoots = @()
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $installRoots += $env:ProgramFiles
  }

  $programFilesX86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  if (-not [string]::IsNullOrWhiteSpace($programFilesX86) -and $programFilesX86 -notin $installRoots) {
    $installRoots += $programFilesX86
  }

  if ($installRoots.Count -eq 0) {
    throw "Unable to determine Windows program files directories for product '$ProductName'"
  }

  $exeName = "$ProductName.exe"
  return $installRoots | ForEach-Object {
    Join-Path (Join-Path $_ $ProductName) $exeName
  }
}

function Assert-InstalledBinaryPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName,

    [Parameter(Mandatory = $true)]
    [string]$Stage
  )

  $candidatePaths = Get-InstalledBinaryPathCandidates -ProductName $ProductName
  foreach ($candidatePath in $candidatePaths) {
    if (Test-Path -LiteralPath $candidatePath) {
      return $candidatePath
    }
  }

  $checkedPaths = $candidatePaths -join ', '
  throw "Expected installed binary not found after $Stage install. Checked: $checkedPaths"
}

function Get-PathProbeResults {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName
  )

  $candidatePaths = Get-InstalledBinaryPathCandidates -ProductName $ProductName
  return $candidatePaths | ForEach-Object {
    $candidatePath = $_
    $parentDir = Split-Path -Path $candidatePath -Parent
    [ordered]@{
      path              = $candidatePath
      exists            = Test-Path -LiteralPath $candidatePath
      parent_dir        = $parentDir
      parent_dir_exists = Test-Path -LiteralPath $parentDir
    }
  }
}

function Write-StepSummary {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Summary,

    [Parameter(Mandatory = $true)]
    [string]$DebugStatePath
  )

  if ([string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    return
  }

  $lines = @(
    '## Windows update smoke',
    '',
    "- Status: $($Summary.status)",
    "- Product: $($Summary.product_name)",
    "- Expected version: $($Summary.expected_new_version)",
    "- Previous version: $($Summary.previous_version)",
    "- New version: $($Summary.new_version)",
    "- Previous install seconds: $($Summary.previous_install_seconds)",
    "- Update install seconds: $($Summary.update_install_seconds)",
    "- Installed binary path: $($Summary.installed_binary_path)",
    "- Debug snapshot: $DebugStatePath"
  )

  if (-not [string]::IsNullOrWhiteSpace($Summary.error)) {
    $lines += "- Error: $($Summary.error)"
  }

  Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($lines -join [Environment]::NewLine)
}

function Invoke-MsiInstall {
  param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $script:msiExitCode = $null
  $duration = Measure-Command {
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
      '/i',
      $MsiPath,
      '/quiet',
      '/norestart',
      '/l*v',
      $LogPath
    ) -Wait -PassThru
    $script:msiExitCode = $process.ExitCode
  }

  return [pscustomobject]@{
    ExitCode = $script:msiExitCode
    Seconds  = [math]::Round($duration.TotalSeconds, 3)
  }
}

if (-not (Test-Path -LiteralPath $NewMsiPath)) {
  throw "New MSI path does not exist: $NewMsiPath"
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$previousInstallLog = Join-Path $LogDir 'previous-install.log'
$updateInstallLog = Join-Path $LogDir 'update-install.log'
$summaryPath = Join-Path $LogDir 'summary.json'
$debugStatePath = Join-Path $LogDir 'debug-state.json'
$previousMsiPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rostoc-update-smoke-previous-{0}.msi" -f [guid]::NewGuid())
$productName = Get-ProductNameFromMsiPath -Path $NewMsiPath
$isRelease = $false
if (-not [string]::IsNullOrWhiteSpace($env:IS_RELEASE)) {
  $isRelease = [System.Convert]::ToBoolean($env:IS_RELEASE)
}

$pathCandidates = Get-InstalledBinaryPathCandidates -ProductName $productName

New-Item -ItemType File -Path $previousInstallLog -Force | Out-Null
New-Item -ItemType File -Path $updateInstallLog -Force | Out-Null

$summary = [ordered]@{
  update_install_seconds   = $null
  previous_install_seconds = $null
  previous_version         = $null
  new_version              = $null
  previous_msi_size_bytes  = $null
  new_msi_size_bytes       = (Get-Item -LiteralPath $NewMsiPath).Length
  run_id                   = $env:GITHUB_RUN_ID
  is_release               = $isRelease
  status                   = 'running'
  product_name             = $productName
  expected_new_version     = $ExpectedNewVersion
  previous_msi_url         = $PreviousMsiUrl
  new_msi_path             = $NewMsiPath
  install_path_candidates  = $pathCandidates
  installed_binary_path    = $null
  previous_install_exit_code = $null
  update_install_exit_code = $null
}

try {
  Write-Host "[INFO] Product name: $productName"
  Write-Host "[INFO] Expected version after update: $ExpectedNewVersion"
  Write-Host "[INFO] Install path candidates: $($pathCandidates -join ', ')"
  Write-Host "[INFO] Downloading previous MSI from $PreviousMsiUrl"
  Invoke-WebRequest -Uri $PreviousMsiUrl -OutFile $previousMsiPath
  $summary.previous_msi_size_bytes = (Get-Item -LiteralPath $previousMsiPath).Length

  Write-Host "[INFO] Installing previous MSI: $previousMsiPath"
  $previousInstall = Invoke-MsiInstall -MsiPath $previousMsiPath -LogPath $previousInstallLog
  $summary.previous_install_seconds = $previousInstall.Seconds
  $summary.previous_install_exit_code = $previousInstall.ExitCode
  if ($previousInstall.ExitCode -ne 0) {
    throw "Previous MSI install failed with exit code $($previousInstall.ExitCode)"
  }

  $summary.installed_binary_path = Assert-InstalledBinaryPresent -ProductName $productName -Stage 'previous'

  $summary.previous_version = Get-InstalledVersion -ProductName $productName

  Write-Host "[INFO] Installing new MSI: $NewMsiPath"
  $updateInstall = Invoke-MsiInstall -MsiPath $NewMsiPath -LogPath $updateInstallLog
  $summary.update_install_seconds = $updateInstall.Seconds
  $summary.update_install_exit_code = $updateInstall.ExitCode
  if ($updateInstall.ExitCode -ne 0) {
    throw "Update MSI install failed with exit code $($updateInstall.ExitCode)"
  }

  $summary.installed_binary_path = Assert-InstalledBinaryPresent -ProductName $productName -Stage 'update'

  $summary.new_version = Get-InstalledVersion -ProductName $productName
  if ($summary.new_version -ne $ExpectedNewVersion) {
    throw "Installed version '$($summary.new_version)' does not match expected '$ExpectedNewVersion'"
  }

  $summary.status = 'success'
}
catch {
  $summary.status = 'failure'
  $summary.error = $_.Exception.Message
  throw
}
finally {
  $debugState = [ordered]@{
    summary          = $summary
    registry_matches = Get-RegistryMatchesForProduct -ProductName $productName
    path_probes      = Get-PathProbeResults -ProductName $productName
    log_files        = [ordered]@{
      previous_install_log = $previousInstallLog
      update_install_log   = $updateInstallLog
      summary_json         = $summaryPath
    }
    host             = [ordered]@{
      computer_name    = $env:COMPUTERNAME
      program_files    = $env:ProgramFiles
      program_files_x86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    }
  }

  $summaryJson = $summary | ConvertTo-Json -Depth 6 -Compress
  $debugJson = $debugState | ConvertTo-Json -Depth 8
  Set-Content -LiteralPath $summaryPath -Value $summaryJson -Encoding UTF8
  Set-Content -LiteralPath $debugStatePath -Value $debugJson -Encoding UTF8
  Write-StepSummary -Summary $summary -DebugStatePath $debugStatePath
  Write-Output $summaryJson

  if (Test-Path -LiteralPath $previousMsiPath) {
    Remove-Item -LiteralPath $previousMsiPath -Force -ErrorAction SilentlyContinue
  }
}