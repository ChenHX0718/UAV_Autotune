[CmdletBinding()]
param([string]$Distro = 'auto')

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$cfg = Get-ProjectConfig
$Distro = Get-ProjectDistro -Requested $Distro
$repoName = [string]$cfg.wsl.repo_name
$commit = [string]$cfg.ardupilot.commit
$binaryRelative = [string]$cfg.ardupilot.binary_relative_path

$script = @"
set -euo pipefail
repo="`$HOME/$repoName"
cd "`$repo"
source "`$HOME/venv-ardupilot/bin/activate"
actual="`$(git rev-parse HEAD)"
test "`$actual" = $(Quote-ProjectBash $commit)
./waf configure --board sitl
./waf plane
test -x "`$repo/$binaryRelative"
printf 'ARDUPILOT_BUILD_PASS commit=%s binary=%s\n' "`$actual" "`$repo/$binaryRelative"
"@

Invoke-ProjectWslBash -Distro $Distro -Script $script
