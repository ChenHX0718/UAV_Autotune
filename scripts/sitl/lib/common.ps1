Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    return (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}

function Get-ProjectConfig {
    $root = Get-ProjectRoot
    return Get-Content -Raw -LiteralPath (Join-Path $root 'config\project.json') | ConvertFrom-Json
}

function Get-ProjectDistro {
    param([string]$Requested = 'auto')
    if ($Requested -and $Requested -ne 'auto') { return $Requested }
    $cfg = Get-ProjectConfig
    $raw = & wsl.exe --list --quiet 2>$null
    $names = @($raw | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) {
        throw 'No WSL Linux distribution is registered. Run scripts/sitl/setup_wsl_ardupilot.ps1 -InstallDistribution from an elevated PowerShell window.'
    }
    $preferred = [string]$cfg.wsl.preferred_distro
    $exact = $names | Where-Object { $_ -eq $preferred } | Select-Object -First 1
    if ($exact) { return $exact }
    $ubuntu = $names | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1
    if ($ubuntu) { return $ubuntu }
    return $names[0]
}

function Get-ProjectWslUser {
    param([Parameter(Mandatory)][string]$Distro)
    $userName = (& wsl.exe -d $Distro -- id -un 2>$null | Select-Object -First 1)
    $userName = (($userName -replace "`0", '').Trim())
    if (-not $userName -or $userName -eq 'root') {
        throw "The default non-root user for WSL distribution '$Distro' could not be discovered."
    }
    return $userName
}

function ConvertTo-ProjectWslPath {
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)][string]$Distro)
    $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    # Native wsl.exe argument conversion can corrupt non-ASCII paths under
    # Windows PowerShell. Carry the path as UTF-8 Base64 and decode in bash.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($resolved)
    $encoded = [System.Convert]::ToBase64String($bytes)
    $script = @"
set -euo pipefail
windows_path="`$(printf %s $(Quote-ProjectBash $encoded) | base64 --decode)"
wslpath -a -u "`$windows_path" | base64 --wrap=0
"@
    $resultBase64 = (Invoke-ProjectWslBash -Distro $Distro -Script $script)
    $resultBase64 = ($resultBase64 -replace "`0", '').Trim()
    try {
        $result = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($resultBase64))
        return $result.Trim()
    } catch {
        throw "Could not convert path for WSL: $resolved"
    }
}

function Quote-ProjectBash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value.Contains("'")) { throw 'A path or value contains an unsupported single quote.' }
    return "'" + $Value + "'"
}

function Invoke-ProjectWslBash {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$Script,
        [string]$User = ''
    )
    # wsl.exe reconstructs native command-line arguments and can strip quotes
    # from multiline scripts. Transport the UTF-8 script as base64 so paths,
    # shell variables and non-ASCII project names arrive unchanged.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Script)
    $encoded = [System.Convert]::ToBase64String($bytes)
    $transport = "printf %s $encoded | base64 --decode | bash -s"
    if ($User) {
        & wsl.exe -d $Distro -u $User -- bash -lc $transport
    } else {
        & wsl.exe -d $Distro -- bash -lc $transport
    }
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed with exit code $LASTEXITCODE." }
}

function Get-ProjectWindowsHostAddress {
    param([Parameter(Mandatory)][string]$Distro)
    $script = "ip route show default 2>/dev/null | awk '{print `$3; exit}'"
    $ip = (Invoke-ProjectWslBash -Distro $Distro -Script $script | Select-Object -First 1)
    $ip = ($ip -replace "`0", '').Trim()
    if (-not $ip) {
        $script = "awk '/^nameserver/{print `$2; exit}' /etc/resolv.conf"
        $ip = (Invoke-ProjectWslBash -Distro $Distro -Script $script | Select-Object -First 1)
        $ip = ($ip -replace "`0", '').Trim()
    }
    $parsed = $null
    if (-not $ip -or -not [System.Net.IPAddress]::TryParse($ip,[ref]$parsed)) {
        throw "Could not discover a valid Windows host address from WSL2: $ip"
    }
    return $ip
}
