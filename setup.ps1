<#
.SYNOPSIS
    Installs the packages listed in packages.json with winget.

.EXAMPLE
    .\setup.ps1                       # install every group
    .\setup.ps1 -Group core,dev       # install only these groups
    .\setup.ps1 -Exclude gaming       # everything except gaming
    .\setup.ps1 -List                 # show groups and packages
    .\setup.ps1 -WhatIf               # show what would be installed
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Group,
    [string[]]$Exclude,
    [switch]$List,
    [string]$Config = (Join-Path $PSScriptRoot 'packages.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
}

$groups = (Get-Content $Config -Raw | ConvertFrom-Json).groups
$names = $groups.PSObject.Properties.Name

foreach ($g in @($Group) + @($Exclude) | Where-Object { $_ }) {
    if ($g -notin $names) { throw "Unknown group '$g'. Available: $($names -join ', ')" }
}

$selected = $names | Where-Object { (-not $Group -or $_ -in $Group) -and $_ -notin $Exclude }

if ($List) {
    foreach ($g in $selected) {
        Write-Host "`n[$g] $($groups.$g.description)" -ForegroundColor Cyan
        foreach ($p in $groups.$g.packages) {
            $label = if ($p.name) { "$($p.id)  ($($p.name))" } else { $p.id }
            Write-Host "  $label"
        }
    }
    return
}

# Snapshot of installed packages. Some packages (e.g. Microsoft.PowerShell) only
# show up here, while Store apps are only found by a per-id query, so check both.
$snapshot = winget list --accept-source-agreements --disable-interactivity 2>$null | Out-String -Width 400

function Test-Installed($p, $source) {
    if ($snapshot -match "\s$([regex]::Escape($p.id))\s") { return $true }
    winget list --id $p.id --exact --source $source --accept-source-agreements --disable-interactivity *> $null
    $LASTEXITCODE -eq 0
}

function Get-InstalledVersion($id) {
    $line = ($snapshot -split "`r?`n") | Where-Object { $_ -match "\s$([regex]::Escape($id))\s" } | Select-Object -First 1
    if ($line -match "\s$([regex]::Escape($id))\s+(\d+(\.\d+){1,3})") { $Matches[1] }
}

function Get-LatestVersion($id, $source) {
    $info = winget show --id $id --exact --source $source --accept-source-agreements --disable-interactivity 2>$null | Out-String
    if ($info -match '(?m)^Version:\s*(\d+(\.\d+){1,3})') { $Matches[1] }
}

$installed = @(); $upgraded = @(); $skipped = @(); $failed = @()

foreach ($g in $selected) {
    Write-Host "`n=== $g - $($groups.$g.description) ===" -ForegroundColor Cyan
    foreach ($p in $groups.$g.packages) {
        $source = if ($p.source) { $p.source } else { 'winget' }
        $label = if ($p.name) { "$($p.name) [$($p.id)]" } else { $p.id }

        # Optional per-package installer settings from packages.json
        $extra = @()
        if ($p.installerType) { $extra += '--installer-type', $p.installerType }
        if ($p.custom) { $extra += '--custom', $p.custom }

        if (Test-Installed $p $source) {
            if (-not $p.alwaysLatest) {
                Write-Host "  = $label (already installed)" -ForegroundColor DarkGray
                $skipped += $label
                continue
            }
            # Compare versions ourselves: `winget upgrade --id` can't find some packages
            # (e.g. Microsoft.PowerShell) even though `winget list` shows them.
            $have = Get-InstalledVersion $p.id
            $latest = Get-LatestVersion $p.id $source
            if ($have -and $latest -and ([version]$have -ge [version]$latest)) {
                Write-Host "  = $label ($have is the latest)" -ForegroundColor DarkGray
                $skipped += $label
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($label, "winget upgrade $have -> $latest")) { continue }
            Write-Host "  ^ $label ($have -> $latest)" -ForegroundColor Yellow
            winget install --id $p.id --exact --source $source --silent @extra `
                --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) { $upgraded += $label } else { $failed += "$label (upgrade exit $LASTEXITCODE)" }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($label, 'winget install')) { continue }

        Write-Host "  + $label" -ForegroundColor Green
        winget install --id $p.id --exact --source $source --silent @extra `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { $installed += $label } else { $failed += "$label (exit $LASTEXITCODE)" }
    }
}

Write-Host "`nInstalled: $($installed.Count)  Upgraded: $($upgraded.Count)  Already current: $($skipped.Count)  Failed: $($failed.Count)" -ForegroundColor Cyan
if ($failed) {
    Write-Host 'Failures:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Next: see MANUAL.md for drivers and apps that winget cannot install.'
