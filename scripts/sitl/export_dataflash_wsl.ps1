[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [string]$Distro = 'auto'
)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$Distro = Get-ProjectDistro -Requested $Distro
$root = Get-ProjectRoot
$bin = Get-ChildItem -LiteralPath (Join-Path $RunDirectory 'logs') -File -Filter '*.BIN' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bin) { throw "No DataFlash BIN log exists under $RunDirectory\logs." }
$scriptPath = Join-Path $root 'scripts\wsl\export_dataflash.py'
$scriptWsl = ConvertTo-ProjectWslPath -WindowsPath $scriptPath -Distro $Distro
$binWsl = ConvertTo-ProjectWslPath -WindowsPath $bin.FullName -Distro $Distro
$outWsl = ConvertTo-ProjectWslPath -WindowsPath $RunDirectory -Distro $Distro
$script = @"
set -euo pipefail
source "`$HOME/venv-ardupilot/bin/activate"
python $(Quote-ProjectBash $scriptWsl) --input $(Quote-ProjectBash $binWsl) --output $(Quote-ProjectBash $outWsl)
"@
Invoke-ProjectWslBash -Distro $Distro -Script $script
