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

function Get-UninstallRegistryRoots {
  return @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
}

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

  $registryRoots = Get-UninstallRegistryRoots

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

  $registryRoots = Get-UninstallRegistryRoots

  $registryMatches = @()
  foreach ($root in $registryRoots) {
    $entries = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -eq $ProductName }

    foreach ($entry in $entries) {
      $registryMatches += [ordered]@{
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

  return $registryMatches
}

function Get-InstalledBinaryPathCandidates {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProductName
  )

  $installRoots = @()
  $registryMatches = Get-RegistryMatchesForProduct -ProductName $ProductName

  foreach ($match in $registryMatches) {
    if (-not [string]::IsNullOrWhiteSpace($match.install_location)) {
      $installRoots += [string]$match.install_location
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $installRoots += (Join-Path $env:LOCALAPPDATA 'Programs')
    $installRoots += $env:LOCALAPPDATA
  }

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
  $candidatePaths = foreach ($root in $installRoots) {
    if ([string]::IsNullOrWhiteSpace($root)) {
      continue
    }

    $normalizedRoot = $root.TrimEnd('\', '/')

    $directCandidate = Join-Path $normalizedRoot $exeName
    $nestedCandidate = Join-Path (Join-Path $normalizedRoot $ProductName) $exeName

    if ($directCandidate -eq $nestedCandidate) {
      $directCandidate
    }
    else {
      $directCandidate
      $nestedCandidate
    }
  }

  return $candidatePaths | Select-Object -Unique
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

  if ($Summary.msi_table_counts) {
    if ($Summary.msi_table_counts.previous_msi -and $Summary.msi_table_counts.previous_msi.available) {
      $previousTables = $Summary.msi_table_counts.previous_msi.tables
      $lines += "- Previous MSI tables: File=$($previousTables.File), Component=$($previousTables.Component), Directory=$($previousTables.Directory), FeatureComponents=$($previousTables.FeatureComponents)"
    }

    if ($Summary.msi_table_counts.new_msi -and $Summary.msi_table_counts.new_msi.available) {
      $newTables = $Summary.msi_table_counts.new_msi.tables
      $lines += "- New MSI tables: File=$($newTables.File), Component=$($newTables.Component), Directory=$($newTables.Directory), FeatureComponents=$($newTables.FeatureComponents)"
    }
  }

  if ($Summary.msi_log_analysis) {
    foreach ($label in @('previous_install', 'update_install')) {
      $analysis = $Summary.msi_log_analysis.$label
      if ($analysis -and $analysis.available) {
        $keyActions = @()
        foreach ($actionName in @('InstallValidate', 'RemoveExistingProducts', 'RemoveFiles', 'InstallFiles', 'InstallFinalize')) {
          $duration = $analysis.key_action_durations_seconds.$actionName
          if ($null -ne $duration) {
            $keyActions += "${actionName}=${duration}s"
          }
        }

        if ($keyActions.Count -gt 0) {
          $lines += "- $label MSI actions: $($keyActions -join ', ')"
        }
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Summary.msi_action_timeline_artifact)) {
    $lines += "- MSI action timeline artifact: $($Summary.msi_action_timeline_artifact)"
  }

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

function Get-MsiTableRowCount {
  param(
    [Parameter(Mandatory = $true)]
    $Database,

    [Parameter(Mandatory = $true)]
    [string]$TableName
  )

  $view = $null
  $record = $null

  try {
    $query = ('SELECT COUNT(*) FROM `{0}`' -f $TableName)
    $view = $Database.OpenView($query)
    $view.Execute()
    $record = $view.Fetch()
    if ($null -eq $record) {
      return $null
    }

    try {
      return [int]$record.IntegerData(1)
    }
    catch {
      $stringValue = $record.StringData(1)
      if ([string]::IsNullOrWhiteSpace($stringValue)) {
        return $null
      }

      return [int]$stringValue
    }
  }
  catch {
    return $null
  }
  finally {
    if ($record) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($record)
    }
    if ($view) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
    }
  }
}

function Get-MsiTableCounts {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $result = [ordered]@{
    label      = $Label
    path       = $Path
    available  = $false
    error      = $null
    tables     = [ordered]@{
      File              = $null
      Component         = $null
      Directory         = $null
      FeatureComponents = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    $result.error = "MSI path does not exist: $Path"
    return $result
  }

  $installer = $null
  $database = $null

  try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))

    foreach ($tableName in @('File', 'Component', 'Directory', 'FeatureComponents')) {
      $result.tables[$tableName] = Get-MsiTableRowCount -Database $database -TableName $tableName
    }

    $result.available = $true
  }
  catch {
    $result.error = $_.Exception.Message
  }
  finally {
    if ($database) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
    }
    if ($installer) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
    }
  }

  return $result
}

function Convert-ClockTextToSeconds {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ClockText
  )

  $parsedTime = [datetime]::ParseExact($ClockText, 'H:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
  return ($parsedTime.Hour * 3600) + ($parsedTime.Minute * 60) + $parsedTime.Second
}

function Get-MsiLogLineClockSeconds {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Line,

    [Parameter(Mandatory = $true)]
    [string]$FallbackClockText
  )

  $lineTimestampMatch = [regex]::Match(
    $Line,
    '\[(?<hour>\d{1,2}):(?<minute>\d{2}):(?<second>\d{2})(?::(?<millisecond>\d{3}))?\]'
  )

  if (-not $lineTimestampMatch.Success) {
    return [double](Convert-ClockTextToSeconds -ClockText $FallbackClockText)
  }

  $hour = [int]$lineTimestampMatch.Groups['hour'].Value
  $minute = [int]$lineTimestampMatch.Groups['minute'].Value
  $second = [int]$lineTimestampMatch.Groups['second'].Value
  $millisecond = 0
  if ($lineTimestampMatch.Groups['millisecond'].Success) {
    $millisecond = [int]$lineTimestampMatch.Groups['millisecond'].Value
  }

  return [double](($hour * 3600) + ($minute * 60) + $second + ($millisecond / 1000.0))
}

function Get-MsiLogAnalysis {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $summary = [ordered]@{
    label                                 = $Label
    log_path                              = $LogPath
    available                             = $false
    total_action_span_seconds             = $null
    action_count                          = 0
    incomplete_action_count               = 0
    unmatched_end_count                   = 0
    key_action_durations_seconds          = [ordered]@{
      InstallValidate       = $null
      RemoveExistingProducts = $null
      RemoveFiles           = $null
      InstallFiles          = $null
      InstallFinalize       = $null
    }
    remove_existing_products_occurrences  = 0
    remove_existing_products_nested_actions = @()
    top_actions_by_duration               = @()
    error                                 = $null
  }

  $timeline = @()

  if (-not (Test-Path -LiteralPath $LogPath)) {
    $summary.error = "MSI log not found: $LogPath"
    return [pscustomobject]@{
      Summary  = $summary
      Timeline = $timeline
    }
  }

  $startPattern = [regex]'Action start (?<time>\d{1,2}:\d{2}:\d{2}): (?<name>.+?)\.'
  $endPattern = [regex]'Action ended (?<time>\d{1,2}:\d{2}:\d{2}): (?<name>.+?)\. Return value (?<return>\d+)\.'
  $openActions = New-Object System.Collections.ArrayList
  $completedActions = New-Object System.Collections.ArrayList
  $dayOffset = 0
  $lastClockSeconds = $null
  $unmatchedEndCount = 0

  try {
    $lines = Get-Content -LiteralPath $LogPath
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
      $line = $lines[$lineIndex]
      $startMatch = $startPattern.Match($line)
      $endMatch = $endPattern.Match($line)

      if (-not $startMatch.Success -and -not $endMatch.Success) {
        continue
      }

      $clockText = if ($startMatch.Success) { $startMatch.Groups['time'].Value } else { $endMatch.Groups['time'].Value }
      $clockSeconds = Get-MsiLogLineClockSeconds -Line $line -FallbackClockText $clockText
      if ($null -ne $lastClockSeconds -and $clockSeconds -lt $lastClockSeconds) {
        $dayOffset += 86400
      }
      $absoluteSeconds = $clockSeconds + $dayOffset
      $lastClockSeconds = $clockSeconds

      if ($startMatch.Success) {
        $entry = [pscustomobject][ordered]@{
          name          = $startMatch.Groups['name'].Value
          start_time    = $clockText
          start_seconds = $absoluteSeconds
          start_line    = $lineIndex + 1
          depth         = $openActions.Count
        }
        [void]$openActions.Add($entry)
        continue
      }

      $name = $endMatch.Groups['name'].Value
      $matchIndex = -1
      for ($openIndex = $openActions.Count - 1; $openIndex -ge 0; $openIndex--) {
        if ($openActions[$openIndex].name -eq $name) {
          $matchIndex = $openIndex
          break
        }
      }

      if ($matchIndex -lt 0) {
        $unmatchedEndCount += 1
        continue
      }

      $started = $openActions[$matchIndex]
      $openActions.RemoveAt($matchIndex)
      [void]$completedActions.Add([pscustomobject][ordered]@{
        name             = $name
        start_time       = $started.start_time
        end_time         = $clockText
        start_seconds    = $started.start_seconds
        end_seconds      = $absoluteSeconds
        duration_seconds = [math]::Round(($absoluteSeconds - $started.start_seconds), 3)
        start_line       = $started.start_line
        end_line         = $lineIndex + 1
        depth            = $started.depth
        return_value     = [int]$endMatch.Groups['return'].Value
      })
    }

    if ($completedActions.Count -gt 0) {
      $sortedActions = @($completedActions | Sort-Object start_seconds, end_seconds, name)
      $timeline = $sortedActions | ForEach-Object {
        [ordered]@{
          name             = $_.name
          start_time       = $_.start_time
          end_time         = $_.end_time
          duration_seconds = $_.duration_seconds
          depth            = $_.depth
          start_line       = $_.start_line
          end_line         = $_.end_line
          return_value     = $_.return_value
        }
      }

      $summary.available = $true
      $summary.action_count = $sortedActions.Count
      $summary.incomplete_action_count = $openActions.Count
      $summary.unmatched_end_count = $unmatchedEndCount
      $summary.total_action_span_seconds = [math]::Round(($sortedActions[-1].end_seconds - $sortedActions[0].start_seconds), 3)

      foreach ($actionName in @('InstallValidate', 'RemoveExistingProducts', 'RemoveFiles', 'InstallFiles', 'InstallFinalize')) {
        $matchingActions = @($sortedActions | Where-Object { $_.name -eq $actionName })
        if ($matchingActions.Count -gt 0) {
          $summary.key_action_durations_seconds[$actionName] = [math]::Round((($matchingActions | Measure-Object -Property duration_seconds -Sum).Sum), 3)
        }
      }

      $removeExistingProductsActions = @($sortedActions | Where-Object { $_.name -eq 'RemoveExistingProducts' })
      $summary.remove_existing_products_occurrences = $removeExistingProductsActions.Count

      if ($removeExistingProductsActions.Count -gt 0) {
        $primaryRemoveExistingProducts = $removeExistingProductsActions | Sort-Object duration_seconds -Descending | Select-Object -First 1
        $nestedActions = @(
          $sortedActions | Where-Object {
            $_.name -ne 'RemoveExistingProducts' -and
            $_.start_seconds -ge $primaryRemoveExistingProducts.start_seconds -and
            $_.end_seconds -le $primaryRemoveExistingProducts.end_seconds
          }
        )

        $summary.remove_existing_products_nested_actions = $nestedActions | ForEach-Object {
          [ordered]@{
            name             = $_.name
            start_time       = $_.start_time
            end_time         = $_.end_time
            duration_seconds = $_.duration_seconds
          }
        }
      }

      $summary.top_actions_by_duration = @(
        $sortedActions |
          Sort-Object duration_seconds -Descending |
          Select-Object -First 5 |
          ForEach-Object {
            [ordered]@{
              name             = $_.name
              start_time       = $_.start_time
              end_time         = $_.end_time
              duration_seconds = $_.duration_seconds
            }
          }
      )
    }
    else {
      $summary.incomplete_action_count = $openActions.Count
      $summary.unmatched_end_count = $unmatchedEndCount
      $summary.error = 'No MSI action markers were found in the verbose log'
    }
  }
  catch {
    $summary.error = $_.Exception.Message
  }

  return [pscustomobject]@{
    Summary  = $summary
    Timeline = $timeline
  }
}

function Write-MsiInstrumentationSummary {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Summary
  )

  if ($Summary.msi_table_counts) {
    foreach ($label in @('previous_msi', 'new_msi')) {
      $counts = $Summary.msi_table_counts.$label
      if ($counts -and $counts.available) {
        Write-Host "[INFO] $label table counts: File=$($counts.tables.File), Component=$($counts.tables.Component), Directory=$($counts.tables.Directory), FeatureComponents=$($counts.tables.FeatureComponents)"
      }
    }
  }

  if ($Summary.msi_log_analysis) {
    foreach ($label in @('previous_install', 'update_install')) {
      $analysis = $Summary.msi_log_analysis.$label
      if (-not $analysis -or -not $analysis.available) {
        continue
      }

      $parts = @()
      foreach ($actionName in @('InstallValidate', 'RemoveExistingProducts', 'RemoveFiles', 'InstallFiles', 'InstallFinalize')) {
        $duration = $analysis.key_action_durations_seconds.$actionName
        if ($null -ne $duration) {
          $parts += "${actionName}=${duration}s"
        }
      }

      if ($parts.Count -gt 0) {
        Write-Host "[INFO] $label action durations: $($parts -join ', ')"
      }
    }
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
$actionTimelinePath = Join-Path $LogDir 'msi-action-timeline.json'
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
  msi_table_counts         = [ordered]@{
    previous_msi = $null
    new_msi      = $null
  }
  msi_log_analysis         = [ordered]@{
    previous_install = $null
    update_install   = $null
  }
  msi_action_timeline_artifact = $null
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
  $summary.msi_table_counts.new_msi = Get-MsiTableCounts -Path $NewMsiPath -Label 'new_msi'

  if (Test-Path -LiteralPath $previousMsiPath) {
    $summary.msi_table_counts.previous_msi = Get-MsiTableCounts -Path $previousMsiPath -Label 'previous_msi'
  }

  $previousInstallAnalysis = Get-MsiLogAnalysis -LogPath $previousInstallLog -Label 'previous_install'
  $updateInstallAnalysis = Get-MsiLogAnalysis -LogPath $updateInstallLog -Label 'update_install'
  $summary.msi_log_analysis.previous_install = $previousInstallAnalysis.Summary
  $summary.msi_log_analysis.update_install = $updateInstallAnalysis.Summary

  $timelinePayload = [ordered]@{
    previous_install = $previousInstallAnalysis.Timeline
    update_install   = $updateInstallAnalysis.Timeline
  }

  if (($previousInstallAnalysis.Timeline.Count + $updateInstallAnalysis.Timeline.Count) -gt 0) {
    $timelineJson = $timelinePayload | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $actionTimelinePath -Value $timelineJson -Encoding UTF8
    $summary.msi_action_timeline_artifact = [System.IO.Path]::GetFileName($actionTimelinePath)
  }

  $debugState = [ordered]@{
    summary          = $summary
    registry_matches = Get-RegistryMatchesForProduct -ProductName $productName
    path_probes      = Get-PathProbeResults -ProductName $productName
    log_files        = [ordered]@{
      previous_install_log = $previousInstallLog
      update_install_log   = $updateInstallLog
      summary_json         = $summaryPath
      msi_action_timeline  = $actionTimelinePath
    }
    host             = [ordered]@{
      computer_name    = $env:COMPUTERNAME
      program_files    = $env:ProgramFiles
      local_app_data   = $env:LOCALAPPDATA
      program_files_x86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    }
  }

  Write-MsiInstrumentationSummary -Summary $summary

  $summaryJson = $summary | ConvertTo-Json -Depth 8 -Compress
  $debugJson = $debugState | ConvertTo-Json -Depth 8
  Set-Content -LiteralPath $summaryPath -Value $summaryJson -Encoding UTF8
  Set-Content -LiteralPath $debugStatePath -Value $debugJson -Encoding UTF8
  Write-StepSummary -Summary $summary -DebugStatePath $debugStatePath
  Write-Output $summaryJson

  if (Test-Path -LiteralPath $previousMsiPath) {
    Remove-Item -LiteralPath $previousMsiPath -Force -ErrorAction SilentlyContinue
  }
}