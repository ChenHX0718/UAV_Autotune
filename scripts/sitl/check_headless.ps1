[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunDirectory)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$root = Get-ProjectRoot
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$resultFile = Join-Path $RunDirectory 'result.json'
if (-not (Test-Path -LiteralPath $resultFile)) {
    throw "Missing result.json in $RunDirectory"
}
$result = Get-Content -Raw -LiteralPath $resultFile | ConvertFrom-Json
$missionPlannerRunning = [bool](Get-Process -Name MissionPlanner -ErrorAction SilentlyContinue)
$snapshot = Get-Content -Raw -LiteralPath (Join-Path $RunDirectory 'configuration_snapshot.json') | ConvertFrom-Json
$sourceBuilt = $snapshot.backend -eq 'wsl' -and $snapshot.firmware_source -eq 'wsl_source_build'
$pass = -not $missionPlannerRunning -and $result.interface_overall -eq 'PASS' -and $sourceBuilt
$evidence = [ordered]@{
    verdict = $(if ($pass) { 'PASS' } else { 'FAIL' })
    mission_planner_running = $missionPlannerRunning
    run_directory = $RunDirectory
    run_verdict = $result.interface_overall
    backend = $snapshot.backend
    firmware_source = $snapshot.firmware_source
    commit = $snapshot.ardupilot_commit
    checked_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$evidence | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $root 'results\headless_verdict.json') -Encoding UTF8
if (-not $pass) { throw 'Headless acceptance failed.' }
Write-Output "HEADLESS_PASS run=$RunDirectory"
