[CmdletBinding()]
param([string]$Distro = 'auto')

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$cfg = Get-ProjectConfig
$Distro = Get-ProjectDistro -Requested $Distro
$registration = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
    Get-ItemProperty |
    Where-Object { $_.DistributionName -eq $Distro } |
    Select-Object -First 1
$wslVersion = if ($registration) { [int]$registration.Version } else { 0 }
$repoName = [string]$cfg.wsl.repo_name
$binaryRelative = [string]$cfg.ardupilot.binary_relative_path

Write-Output "DISTRO=$Distro"
Write-Output "WSL_VERSION=$wslVersion"
$script = @"
set -euo pipefail
repo="`$HOME/$repoName"
binary="`$repo/$binaryRelative"
. /etc/os-release
printf 'USER=%s\n' "`$USER"
printf 'OS_ID=%s\n' "`$ID"
printf 'OS_VERSION_ID=%s\n' "`$VERSION_ID"
printf 'OS_PRETTY_NAME=%s\n' "`$PRETTY_NAME"
printf 'KERNEL=%s\n' "`$(uname -r)"
printf 'PYTHON=%s\n' "`$(python3 --version 2>&1)"
printf 'GCC=%s\n' "`$(gcc --version | head -n1)"
printf 'GIT=%s\n' "`$(git --version)"
printf 'RELEASE_UPGRADE=%s\n' "`$(awk -F= '/^Prompt=/{print `$2}' /etc/update-manager/release-upgrades)"
printf 'ARDUPILOT_COMMIT=%s\n' "`$(git -C "`$repo" rev-parse HEAD)"
printf 'ARDUPILOT_TAGS=%s\n' "`$(git -C "`$repo" tag --points-at HEAD | paste -sd, -)"
printf 'BUILD_TARGET=sitl/plane\n'
printf 'BINARY=%s\n' "`$binary"
printf 'BINARY_SHA256=%s\n' "`$(sha256sum "`$binary" | awk '{print `$1}')"
printf 'BUILD_TIMESTAMP_UTC=%s\n' "`$(date -u -d "@`$(stat -c %Y "`$binary")" +%Y-%m-%dT%H:%M:%SZ)"
printf 'VENV=%s\n' "`$HOME/venv-ardupilot"
"@
Invoke-ProjectWslBash -Distro $Distro -Script $script
