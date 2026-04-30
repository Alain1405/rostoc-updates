$ErrorActionPreference = 'Stop'

$command = $args[0]
if ([string]::IsNullOrWhiteSpace($command)) {
    throw 'COMMAND is required'
}

function Get-ProductNameForVariant {
    param([string]$Variant)

    switch ($Variant) {
        'staging' { return 'Rostoc-staging' }
        'dev' { return 'Rostoc-dev' }
        default { return 'Rostoc' }
    }
}

switch ($command) {
    'locate-windows' {
        $searchRoots = @('target', 'src-tauri/target')

        $msiCandidates = @()
        foreach ($root in $searchRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $found = Get-ChildItem -Path $root -Recurse -File -Filter '*.msi' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            if ($found) { $msiCandidates += $found }
        }

        $msi = $msiCandidates | Select-Object -First 1
        if (-not $msi) {
            throw 'MSI artifact not found under target/ or src-tauri/target/'
        }

        $msiSigPath = "$($msi.FullName).sig"
        if (-not (Test-Path $msiSigPath)) {
            $sigCandidate = Get-ChildItem -Path $msi.DirectoryName -Filter "$($msi.BaseName)*.sig" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($sigCandidate) {
                $msiSigPath = $sigCandidate.FullName
            } else {
                throw "Signature file not found for $($msi.Name)"
            }
        }

        Write-Host "[INFO] MSI and signature will be used for Tauri auto-updates"
        "artifact=$($msi.FullName)" >> $env:GITHUB_OUTPUT
        "signature=$msiSigPath" >> $env:GITHUB_OUTPUT
        "archive=$($msi.FullName)" >> $env:GITHUB_OUTPUT
        "archive_signature=$msiSigPath" >> $env:GITHUB_OUTPUT
        Write-Host "[INFO] Located MSI installer: $($msi.FullName)"
        Write-Host "[INFO] Located MSI signature: $msiSigPath"
    }

    'prepare-windows' {
        $version = $env:VERSION
        $variant = $env:VARIANT
        $artifact = $env:ARTIFACT
        $signature = $env:SIGNATURE
        $archive = $env:ARCHIVE
        $archiveSignature = $env:ARCHIVE_SIGNATURE
        $arch = $env:ARCH

        if ([string]::IsNullOrWhiteSpace($version)) { throw 'Version missing' }
        if (-not (Test-Path $artifact)) { throw "Artifact missing: $artifact" }
        if (-not (Test-Path $signature)) { throw "Signature missing: $signature" }

        $parent = Split-Path -Parent $PWD
        $updatesRoot = Join-Path $parent 'updates'
        $windowsDir = Join-Path $updatesRoot 'windows'
        New-Item -ItemType Directory -Path $windowsDir -Force | Out-Null

        $productName = Get-ProductNameForVariant $variant
        $archLabel = if ($arch -eq 'i686') { 'x86' } else { 'x64' }

        $extension = [System.IO.Path]::GetExtension($artifact)
        $msiName = "${productName}-${version}-windows-${archLabel}${extension}"
        Copy-Item $artifact (Join-Path $windowsDir $msiName) -Force
        Copy-Item $signature (Join-Path $windowsDir "${msiName}.sig") -Force

        $latestName = "${productName}-windows-${archLabel}${extension}"
        Copy-Item $artifact (Join-Path $windowsDir $latestName) -Force
        Copy-Item $signature (Join-Path $windowsDir "${latestName}.sig") -Force

        Write-Host "[INFO] Windows MSI installer staged: $msiName"
        Write-Host "[INFO] Tauri v2: MSI file will be used directly for auto-updates (no separate .zip needed)"
        Write-Host "[INFO] Variant: $variant, Product name: $productName"
        "msi_name=$msiName" >> $env:GITHUB_OUTPUT
        "archive_name=$msiName" >> $env:GITHUB_OUTPUT
        "product_name=$productName" >> $env:GITHUB_OUTPUT
    }

    default {
        throw "Unknown COMMAND: $command"
    }
}