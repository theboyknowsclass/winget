<#
.SYNOPSIS
    Audits installed software against packages.json.

.DESCRIPTION
    Groups everything `winget list` sees by source:
      - winget / msstore : manageable by winget
      - ARP              : classic installers winget can't match to a package
      - MSIX             : Store/appx packages winget can't match
    and reports winget-sourced packages that are installed but missing from
    packages.json, so the list can be kept in sync with the machine.

.EXAMPLE
    .\audit.ps1
    .\audit.ps1 -All     # also list the unmatched ARP/MSIX entries
#>
param(
    [switch]$All,
    [string]$Config = (Join-Path $PSScriptRoot 'packages.json')
)

# Runtimes and dependencies that get pulled in by other packages; not worth tracking.
$noise = '^(Microsoft\.(VCRedist|VCLibs|UI\.Xaml|WindowsAppRuntime|DotNet\.(Native|DesktopRuntime)|AppInstaller|Edge)|Nvidia\.PhysX|namazso\.PawnIO|Python\.Launcher|EpicGames\.EpicOnlineServices)'

$lines = winget list --accept-source-agreements --disable-interactivity 2>$null | Out-String -Width 400 -Stream
$h = ($lines | Select-String '^Name\s+Id\s+Version').LineNumber - 1
$hdr = $lines[$h]
$cId = $hdr.IndexOf('Id'); $cVer = $hdr.IndexOf('Version'); $cAv = $hdr.IndexOf('Available'); $cSrc = $hdr.IndexOf('Source')

function Col($l, $a, $b) {
    if ($l.Length -le $a) { return '' }
    if ($b -lt 0 -or $l.Length -lt $b) { return $l.Substring($a).Trim() }
    $l.Substring($a, $b - $a).Trim()
}

$rows = foreach ($l in $lines[($h + 2)..($lines.Count - 1)]) {
    if ($l.Length -lt $cVer) { continue }
    $id = Col $l $cId $cVer
    $src = Col $l $cSrc -1
    [pscustomobject]@{
        Name   = Col $l 0 $cId
        Id     = $id
        Source = if ($src) { $src } elseif ($id -like 'ARP\*') { 'ARP' } elseif ($id -like 'MSIX\*') { 'MSIX' } else { 'other' }
    }
}
$rows = $rows | Sort-Object Id -Unique

Write-Host "`nInstalled software by source:" -ForegroundColor Cyan
$rows | Group-Object Source | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize | Out-Host

$tracked = (Get-Content $Config -Raw | ConvertFrom-Json).groups.PSObject.Properties.Value.packages.id
$untracked = $rows | Where-Object { $_.Source -in 'winget', 'msstore' -and $_.Id -notin $tracked -and $_.Id -notmatch $noise }

Write-Host 'Installed via winget/msstore but not in packages.json:' -ForegroundColor Cyan
if ($untracked) { $untracked | Format-Table Id, Name, Source -AutoSize | Out-Host } else { Write-Host "  (none)`n" }

if ($All) {
    foreach ($s in 'ARP', 'MSIX') {
        Write-Host "Not matched to a winget package ($s) - try 'winget search <name>', else add to MANUAL.md:" -ForegroundColor Cyan
        $rows | Where-Object Source -eq $s | ForEach-Object { "  $($_.Name)" } | Sort-Object -Unique
        ''
    }
}
