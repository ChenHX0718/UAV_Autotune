[CmdletBinding()]
param(
    [string]$Distro = 'auto',
    [switch]$InstallDistribution,
    [switch]$SkipPackages
)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$cfg = Get-ProjectConfig

if ($InstallDistribution) {
    $existing = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($existing.Count -eq 0) {
        Write-Host 'Requesting the Microsoft WSL installer. A reboot and first Ubuntu launch may be required.'
        & wsl.exe --install -d ([string]$cfg.wsl.preferred_distro)
        if ($LASTEXITCODE -ne 0) { throw 'WSL installation did not complete successfully.' }
        Write-Host 'Complete the Ubuntu first-run user setup, then run this script again without -InstallDistribution.'
        exit 0
    }
}

$Distro = Get-ProjectDistro -Requested $Distro
$wslUser = Get-ProjectWslUser -Distro $Distro
$repoName = [string]$cfg.wsl.repo_name
$repository = [string]$cfg.ardupilot.repository
$commit = [string]$cfg.ardupilot.commit

$script = @"
set -euo pipefail
repo="`$HOME/$repoName"
if [ ! -d "`$repo/.git" ]; then
  git clone --recurse-submodules $(Quote-ProjectBash $repository) "`$repo"
fi
cd "`$repo"
git fetch --tags --prune origin
git checkout --detach $(Quote-ProjectBash $commit)
git submodule sync --recursive
git submodule update --init --recursive
printf 'distro=%s\nubuntu=%s\npython=%s\ngcc=%s\ncommit=%s\n' \
  $(Quote-ProjectBash $Distro) "`$(. /etc/os-release; echo "`$PRETTY_NAME")" \
  "`$(python3 --version 2>&1)" "`$(gcc --version | head -n1)" "`$(git rev-parse HEAD)"
"@

Invoke-ProjectWslBash -Distro $Distro -Script $script

if (-not $SkipPackages) {
    $environmentScript = Join-Path (Get-ProjectRoot) 'scripts\wsl\setup_ardupilot_ubuntu_24_04.sh'
    $environmentWsl = ConvertTo-ProjectWslPath -WindowsPath $environmentScript -Distro $Distro
    $systemScript = "bash $(Quote-ProjectBash $environmentWsl) system $(Quote-ProjectBash $wslUser)"
    Invoke-ProjectWslBash -Distro $Distro -User root -Script $systemScript

    $userScript = @"
set -euo pipefail
repo="`$HOME/$repoName"
bash $(Quote-ProjectBash $environmentWsl) user "`$repo" $(Quote-ProjectBash $commit)
"@
    Invoke-ProjectWslBash -Distro $Distro -Script $userScript
}
Write-Host "ArduPilot source is pinned to $commit in $Distro."
