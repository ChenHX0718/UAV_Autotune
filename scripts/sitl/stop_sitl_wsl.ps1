[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [string]$Distro = 'auto'
)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$Distro = Get-ProjectDistro -Requested $Distro
$runWsl = ConvertTo-ProjectWslPath -WindowsPath $RunDirectory -Distro $Distro
$script = @"
set -euo pipefail
cd $(Quote-ProjectBash $runWsl)
if [ ! -s sitl.pid ]; then
  printf '{"state":"STOPPED","detail":"no_pid"}\n' > sitl_status.json
  exit 0
fi
pid="`$(cat sitl.pid)"
if kill -0 "`$pid" 2>/dev/null; then
  printf '{"state":"STOPPING","pid":%s}\n' "`$pid" > sitl_status.json
  kill "`$pid"
  for attempt in `$(seq 1 50); do
    if ! kill -0 "`$pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if kill -0 "`$pid" 2>/dev/null; then kill -9 "`$pid"; fi
fi
printf '{"state":"STOPPED","pid":%s}\n' "`$pid" > sitl_status.json
echo 'SITL_STOP_PASS'
"@
Invoke-ProjectWslBash -Distro $Distro -Script $script
