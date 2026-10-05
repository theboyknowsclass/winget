<#
.SYNOPSIS
    Configures what setup.ps1 can't: Windows features, CLI tools, settings and models.
    Run it after setup.ps1. Every step is safe to re-run.

.DESCRIPTION
    Steps (settings live in config\post-install.json):
      wsl     Turn on WSL + Virtual Machine Platform (needs an admin terminal)
      claude  Install Claude Code with Anthropic's installer (keeps itself updated)
      git     Apply global git config
      npm     Point npm's global prefix and cache at the configured folders
      uv      Install uv tools
      vscode  Install VS Code extensions from config\vscode-extensions.txt
      ollama  Set Ollama env vars, pull models, recreate custom ones from Modelfiles
      fusion  Fusion 360 MCP bridge: clone, venv, secret, add-in link, Claude MCP registration
      fonts   Install fonts for the current user

.EXAMPLE
    .\post-install.ps1                   # all steps
    .\post-install.ps1 -Only git,vscode  # just these
    .\post-install.ps1 -Skip ollama      # everything except the model downloads
    .\post-install.ps1 -WhatIf           # show what would change
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('wsl', 'claude', 'git', 'npm', 'uv', 'vscode', 'ollama', 'fusion', 'fonts')]
    [string[]]$Only,
    [ValidateSet('wsl', 'claude', 'git', 'npm', 'uv', 'vscode', 'ollama', 'fusion', 'fonts')]
    [string[]]$Skip
)

$ErrorActionPreference = 'Stop'
$cfg = Get-Content (Join-Path $PSScriptRoot 'config\post-install.json') -Raw | ConvertFrom-Json
$results = [ordered]@{}

# Tools installed by setup.ps1 in this session aren't on PATH yet; reload it.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

function Step($name, [scriptblock]$body) {
    if (($Only -and $name -notin $Only) -or $name -in $Skip) { return }
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    try { & $body; if (-not $results.Contains($name)) { $results[$name] = 'ok' } }
    catch { Write-Host "  ! $($_.Exception.Message)" -ForegroundColor Red; $results[$name] = "failed: $($_.Exception.Message)" }
}

function Need($cmd) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { return $true }
    Write-Host "  - '$cmd' not found; run setup.ps1 first" -ForegroundColor Yellow
    $script:results[$script:current] = "skipped: $cmd not installed"
    $false
}

function Add-UserPath($dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($user -split ';') -contains $dir) { return }
    if ($PSCmdlet.ShouldProcess($dir, 'Add to user PATH')) {
        [Environment]::SetEnvironmentVariable('Path', ($user.TrimEnd(';') + ";$dir"), 'User')
        $env:Path += ";$dir"
        Write-Host "  + added $dir to PATH"
    }
}

$script:current = 'wsl'
Step wsl {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
    if (-not $admin) {
        Write-Host '  - needs an admin terminal; re-run with: .\post-install.ps1 -Only wsl' -ForegroundColor Yellow
        $results['wsl'] = 'skipped: not admin'
        return
    }
    $features = 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform'
    $off = $features | Where-Object { (Get-WindowsOptionalFeature -Online -FeatureName $_).State -ne 'Enabled' }
    if (-not $off) { Write-Host '  = WSL features already enabled' -ForegroundColor DarkGray; return }
    if ($PSCmdlet.ShouldProcess(($off -join ', '), 'Enable Windows features')) {
        wsl --install --no-distribution
        Write-Host '  + enabled; restart Windows to finish' -ForegroundColor Green
        $results['wsl'] = 'ok (restart needed)'
    }
}

$script:current = 'claude'
Step claude {
    if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host '  = Claude Code already installed' -ForegroundColor DarkGray; return }
    if ($PSCmdlet.ShouldProcess('Claude Code', 'Install from https://claude.ai/install.ps1')) {
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        Add-UserPath "$env:USERPROFILE\.local\bin"
    }
}

$script:current = 'git'
Step git {
    if (-not (Need git)) { return }
    foreach ($p in $cfg.git.PSObject.Properties) {
        $now = git config --global --get $p.Name
        if ($now -eq $p.Value) { Write-Host "  = $($p.Name) = $($p.Value)" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess("$($p.Name) = $($p.Value)", 'git config --global')) {
            git config --global $p.Name $p.Value
            Write-Host "  + $($p.Name) = $($p.Value)" -ForegroundColor Green
        }
    }
}

$script:current = 'npm'
Step npm {
    if (-not (Need npm)) { return }
    foreach ($key in 'prefix', 'cache') {
        $dir = $cfg.npm.$key
        $drive = Split-Path $dir -Qualifier
        if (-not (Test-Path "$drive\")) {
            Write-Host "  - $drive doesn't exist on this machine; leaving npm $key at its default" -ForegroundColor Yellow
            continue
        }
        if ((npm config get $key) -eq $dir) { Write-Host "  = $key = $dir" -ForegroundColor DarkGray }
        elseif ($PSCmdlet.ShouldProcess("$key = $dir", 'npm config set')) {
            New-Item -ItemType Directory -Force $dir | Out-Null
            npm config set $key $dir
            Write-Host "  + $key = $dir" -ForegroundColor Green
        }
        if ($key -eq 'prefix') { Add-UserPath $dir }  # global CLI shims live directly in the prefix on Windows
    }
}

$script:current = 'uv'
Step uv {
    if (-not (Need uv)) { return }
    $have = uv tool list 2>$null | Where-Object { $_ -notmatch '^\s*-' } | ForEach-Object { ($_ -split ' ')[0] }
    foreach ($t in $cfg.uvTools) {
        if ($t -in $have) { Write-Host "  = $t" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess($t, 'uv tool install')) { uv tool install $t; Write-Host "  + $t" -ForegroundColor Green }
    }
    uv tool update-shell *> $null
}

$script:current = 'vscode'
Step vscode {
    if (-not (Need code)) { return }
    $want = Get-Content (Join-Path $PSScriptRoot 'config\vscode-extensions.txt') | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }
    $have = code --list-extensions
    $missing = $want | Where-Object { $_ -notin $have }
    Write-Host "  = $($want.Count - $missing.Count) of $($want.Count) already installed" -ForegroundColor DarkGray
    foreach ($e in $missing) {
        if ($PSCmdlet.ShouldProcess($e, 'code --install-extension')) { code --install-extension $e --force | Out-Null; Write-Host "  + $e" -ForegroundColor Green }
    }
}

$script:current = 'ollama'
Step ollama {
    foreach ($v in $cfg.ollama.env.PSObject.Properties) {
        if ([Environment]::GetEnvironmentVariable($v.Name, 'User') -eq $v.Value) { Write-Host "  = $($v.Name)=$($v.Value)" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess("$($v.Name)=$($v.Value)", 'Set user environment variable')) {
            [Environment]::SetEnvironmentVariable($v.Name, $v.Value, 'User')
            Write-Host "  + $($v.Name)=$($v.Value) (restart Ollama to apply)" -ForegroundColor Green
        }
    }
    if (-not (Need ollama)) { return }
    $have =ollama list 2>$null | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] -replace ':latest$', '' }
    foreach ($m in $cfg.ollama.pull) {
        if ($m -in $have) { Write-Host "  = $m" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess($m, 'ollama pull (large download)')) { ollama pull $m }
    }
    foreach ($p in $cfg.ollama.create.PSObject.Properties) {
        if ($p.Name -in $have) { Write-Host "  = $($p.Name)" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess($p.Name, 'ollama create')) { ollama create $p.Name -f (Join-Path $PSScriptRoot $p.Value); Write-Host "  + $($p.Name)" -ForegroundColor Green }
    }
}

$script:current = 'fusion'
Step fusion {
    $fb = $cfg.fusionBridge
    if (-not (Need git)) { return }

    # 1. Clone the repo
    if (Test-Path (Join-Path $fb.path '.git')) { Write-Host "  = repo at $($fb.path)" -ForegroundColor DarkGray }
    elseif ($PSCmdlet.ShouldProcess($fb.path, "git clone $($fb.repo)")) {
        git clone $fb.repo $fb.path
        git -C $fb.path remote add upstream $fb.upstream
        Write-Host "  + cloned to $($fb.path)" -ForegroundColor Green
    }

    # 2. Python venv for the MCP server
    $py = Join-Path $fb.path '.venv\Scripts\python.exe'
    if (Test-Path $py) { Write-Host '  = .venv' -ForegroundColor DarkGray }
    elseif ((Test-Path $fb.path) -and $PSCmdlet.ShouldProcess("$($fb.path)\.venv", 'Create venv and install requirements')) {
        py -$($fb.python) -m venv (Join-Path $fb.path '.venv')
        & $py -m pip install --quiet -r (Join-Path $fb.path 'mcp-server\requirements.txt')
        Write-Host '  + .venv with MCP server requirements' -ForegroundColor Green
    }

    # 3. Shared secret between the add-in and the MCP server (never committed anywhere)
    $secret = "$env:USERPROFILE\.fusion-mcp-secret"
    if (Test-Path $secret) { Write-Host '  = ~\.fusion-mcp-secret' -ForegroundColor DarkGray }
    elseif ($PSCmdlet.ShouldProcess($secret, 'Generate shared secret')) {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        Set-Content $secret (($bytes | ForEach-Object { $_.ToString('x2') }) -join '') -NoNewline
        icacls $secret /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null  # owner-only, like chmod 600
        Write-Host '  + ~\.fusion-mcp-secret' -ForegroundColor Green
    }

    # 4. Add-in: a junction into Fusion's AddIns folder, so a git pull updates it
    $addins = "$env:APPDATA\Autodesk\Autodesk Fusion 360\API\AddIns"
    $link = Join-Path $addins 'FusionMCPBridge'
    $src = Join-Path $fb.path 'fusion-addin\FusionMCPBridge'
    if (Test-Path $link) {
        $kind = if ((Get-Item $link).LinkType) { 'linked to the repo' } else { 'a copy; re-copy after pulling updates' }
        Write-Host "  = add-in installed ($kind)" -ForegroundColor DarkGray
    }
    elseif ((Test-Path $src) -and $PSCmdlet.ShouldProcess($link, 'Link add-in into Fusion AddIns')) {
        New-Item -ItemType Directory -Force $addins | Out-Null
        New-Item -ItemType Junction -Path $link -Target $src | Out-Null
        Write-Host '  + add-in linked into Fusion (it runs on startup)' -ForegroundColor Green
    }

    # 5. Register the MCP server with Claude Code
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Host '  - Claude Code not installed; skipping MCP registration' -ForegroundColor Yellow; return }
    claude mcp get fusion360 *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host '  = fusion360 MCP server registered' -ForegroundColor DarkGray }
    elseif ($PSCmdlet.ShouldProcess('fusion360', 'claude mcp add (user scope)')) {
        claude mcp add fusion360 --scope user -- $py (Join-Path $fb.path 'mcp-server\server.py')
        Write-Host '  + fusion360 MCP server registered' -ForegroundColor Green
    }
}

$script:current = 'fonts'
Step fonts {
    $dir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    $reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $registered = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties.Name
    foreach ($f in $cfg.fonts) {
        if ($registered -like "$($f.name)*") { Write-Host "  = $($f.name)" -ForegroundColor DarkGray; continue }
        if (-not $PSCmdlet.ShouldProcess($f.name, 'Download and install font')) { continue }
        New-Item -ItemType Directory -Force $dir | Out-Null
        foreach ($url in $f.urls) {
            $file = [IO.Path]::GetFileName($url)
            $dest = Join-Path $dir $file
            Invoke-WebRequest $url -OutFile $dest -UseBasicParsing
            $style = ([IO.Path]::GetFileNameWithoutExtension($file) -split '-')[-1] -replace 'Regular', '' -replace '(?<=[a-z])(?=[A-Z])', ' '
            New-ItemProperty -Path $reg -Name ("$($f.name) $style".Trim() + ' (TrueType)') -Value $dest -Force | Out-Null
        }
        Write-Host "  + $($f.name) ($($f.urls.Count) styles)" -ForegroundColor Green
    }
}

Write-Host "`nSummary" -ForegroundColor Cyan
$results.GetEnumerator() | ForEach-Object {
    $color = if ($_.Value -like 'failed*') { 'Red' } elseif ($_.Value -like 'skipped*') { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-7} {1}" -f $_.Key, $_.Value) -ForegroundColor $color
}
if ($results.Values -like 'failed*') { exit 1 }
