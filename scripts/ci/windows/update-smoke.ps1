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
$previousMsiPath = Join-Path $LogDir 'previous.msi'
$installedBinaryPath = 'C:\Program Files\Rostoc\rostoc.exe'
$productName = Get-ProductNameFromMsiPath -Path $NewMsiPath
$isRelease = $false
if (-not [string]::IsNullOrWhiteSpace($env:IS_RELEASE)) {
  $isRelease = [System.Convert]::ToBoolean($env:IS_RELEASE)
}

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
}

try {
  Write-Host "[INFO] Downloading previous MSI from $PreviousMsiUrl"
  Invoke-WebRequest -Uri $PreviousMsiUrl -OutFile $previousMsiPath
  $summary.previous_msi_size_bytes = (Get-Item -LiteralPath $previousMsiPath).Length

  Write-Host "[INFO] Installing previous MSI: $previousMsiPath"
  $previousInstall = Invoke-MsiInstall -MsiPath $previousMsiPath -LogPath $previousInstallLog
  $summary.previous_install_seconds = $previousInstall.Seconds
  if ($previousInstall.ExitCode -ne 0) {
    throw "Previous MSI install failed with exit code $($previousInstall.ExitCode)"
  }

  if (-not (Test-Path -LiteralPath $installedBinaryPath)) {
    throw "Expected installed binary not found after previous install: $installedBinaryPath"
  }

  $summary.previous_version = Get-InstalledVersion -ProductName $productName

  Write-Host "[INFO] Installing new MSI: $NewMsiPath"
  $updateInstall = Invoke-MsiInstall -MsiPath $NewMsiPath -LogPath $updateInstallLog
  $summary.update_install_seconds = $updateInstall.Seconds
  if ($updateInstall.ExitCode -ne 0) {
    throw "Update MSI install failed with exit code $($updateInstall.ExitCode)"
  }

  if (-not (Test-Path -LiteralPath $installedBinaryPath)) {
    throw "Expected installed binary not found after update install: $installedBinaryPath"
  }

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
  $summaryJson = $summary | ConvertTo-Json -Depth 6 -Compress
  Set-Content -LiteralPath $summaryPath -Value $summaryJson -Encoding UTF8
  Write-Output $summaryJson
}