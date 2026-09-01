[CmdletBinding()]
param([string]$Distro = 'auto')

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$cfg = Get-ProjectConfig
$Distro = Get-ProjectDistro -Requested $Distro
$root = Get-ProjectRoot
$outFile = Join-Path $root 'config\ardupilot\apm.pdef.xml'
if (-not (Test-Path -LiteralPath $outFile)) { New-Item -ItemType File -Path $outFile | Out-Null }
$outWsl = ConvertTo-ProjectWslPath -WindowsPath $outFile -Distro $Distro
$repoName = [string]$cfg.wsl.repo_name
$commit = [string]$cfg.ardupilot.commit
$script = @"
set -euo pipefail
repo="`$HOME/$repoName"
cd "`$repo/Tools/autotest/param_metadata"
source "`$HOME/venv-ardupilot/bin/activate"
test "`$(git -C "`$repo" rev-parse HEAD)" = $(Quote-ProjectBash $commit)
python3 param_parse.py --vehicle Plane
test -s apm.pdef.xml
cp apm.pdef.xml $(Quote-ProjectBash $outWsl)
echo PARAMETER_METADATA_EXPORT_PASS
"@
Invoke-ProjectWslBash -Distro $Distro -Script $script
